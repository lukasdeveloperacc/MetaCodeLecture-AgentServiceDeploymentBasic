# ==============================================================================
# ECS (Elastic Container Service) Resources
# ==============================================================================
#
# 🎯 왜 필요한가?
# Section 3에서는 AWS Console에서 다음 작업을 수동으로 했습니다:
# 1. ECS Cluster 생성
# 2. Task Definition JSON 작성 → CLI로 등록
# 3. Service 생성 → ALB 연결
#
# Terraform으로 관리하면:
# - 모든 설정을 코드로 명확히 정의
# - Task Definition 변경 시 자동 배포
# - terraform apply 한 번으로 전체 인프라 생성
#
# Section 3 비교:
# - Section 3: Task Definition JSON 파일 → aws ecs register-task-definition
# - Terraform: resource "aws_ecs_task_definition" { ... }
#
# 참고: Secrets Manager Data Sources는 data.tf에 정의되어 있습니다.

# ==============================================================================
# ECS Cluster
# ==============================================================================

resource "aws_ecs_cluster" "main" {
  name = "agent-cluster-${var.environment}" # 예: agent-cluster-tf

  # Container Insights 활성화 (모니터링 강화, 비용 추가)
  setting {
    name  = "containerInsights"
    value = "disabled" # 학습용으로 비활성화 (비용 절감)
  }

  tags = {
    Name = "agent-cluster-${var.environment}"
  }
}

# ==============================================================================
# ECS Task Definitions
# ==============================================================================
#
# Task Definition은 컨테이너 실행 설정을 정의합니다.
# Section 3에서는 JSON 파일로 작성했지만, Terraform에서는 HCL로 작성합니다.

# ------------------------------------------------------------------------------
# Backend Task Definition
# ------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "backend" {
  family                   = "backend-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_cpu    # 예: "512" (0.5 vCPU)
  memory                   = var.backend_memory # 예: "1024" (1 GB)
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  # 컨테이너 정의
  container_definitions = jsonencode([{
    name  = "backend"
    image = "${aws_ecr_repository.backend.repository_url}:latest"

    # 포트 매핑
    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    # 환경 변수
    environment = [
      {
        name  = "ENVIRONMENT"
        value = var.environment
      }
    ]

    # Secrets Manager에서 시크릿 주입
    # Data Source로 조회한 Secret ARN 사용
    secrets = [
      {
        name      = "OPENAI_API_KEY"
        valueFrom = data.aws_secretsmanager_secret.openai.arn
      },
      {
        name      = "PINECONE_API_KEY"
        valueFrom = data.aws_secretsmanager_secret.pinecone.arn
      }
    ]

    # CloudWatch Logs 설정
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    # 컨테이너 Health Check (선택사항)
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name = "backend-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Frontend Task Definition
# ------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_cpu    # 예: "256" (0.25 vCPU)
  memory                   = var.frontend_memory # 예: "512" (512 MB)
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "frontend"
    image = "${aws_ecr_repository.frontend.repository_url}:latest"

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    # CloudWatch Logs 설정
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = {
    Name = "frontend-${var.environment}"
  }
}

# ==============================================================================
# ECS Services
# ==============================================================================
#
# Service는 Task Definition을 실행하고 유지합니다.
# Section 3에서는 Console에서 생성했지만, Terraform으로 자동화합니다.

# ------------------------------------------------------------------------------
# Backend Service
# ------------------------------------------------------------------------------

resource "aws_ecs_service" "backend" {
  name            = "backend-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count # 예: 2
  launch_type     = "FARGATE"

  # 네트워크 설정
  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true # Public Subnet 사용 시 필요
  }

  # ALB 연결
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  # Service가 안정화될 때까지 대기
  depends_on = [
    aws_lb_listener.backend_http
  ]

  # Deployment 설정 (롤링 업데이트 제어)
  deployment_maximum_percent         = 200 # 롤링 배포 시 최대 200%
  deployment_minimum_healthy_percent = 50  # 최소 50% 유지

  # Service Auto Scaling 활성화 (선택사항)
  # enable_ecs_managed_tags = true
  # propagate_tags          = "SERVICE"

  tags = {
    Name = "backend-${var.environment}-service"
  }
}

# ------------------------------------------------------------------------------
# Frontend Service
# ------------------------------------------------------------------------------

resource "aws_ecs_service" "frontend" {
  name            = "frontend-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count # 예: 2
  launch_type     = "FARGATE"

  # 네트워크 설정
  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.frontend.id]
    assign_public_ip = true
  }

  # ALB 연결
  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.frontend_http]

  # Deployment 설정 (롤링 업데이트 제어)
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  tags = {
    Name = "frontend-${var.environment}-service"
  }
}

# ==============================================================================
# Auto Scaling (선택사항)
# ==============================================================================
#
# CPU 사용률에 따라 Task 수를 자동으로 조정합니다.

# Backend Auto Scaling Target
# resource "aws_appautoscaling_target" "backend" {
#   max_capacity       = 10
#   min_capacity       = 2
#   resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}"
#   scalable_dimension = "ecs:service:DesiredCount"
#   service_namespace  = "ecs"
# }

# Backend Auto Scaling Policy (CPU 70% 기준)
# resource "aws_appautoscaling_policy" "backend_cpu" {
#   name               = "backend-cpu-autoscaling"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.backend.resource_id
#   scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.backend.service_namespace
#
#   target_tracking_scaling_policy_configuration {
#     target_value = 70.0
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }
#   }
# }
