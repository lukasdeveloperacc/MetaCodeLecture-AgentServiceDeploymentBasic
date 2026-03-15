# ==============================================================================
# IAM Roles and Policies
# ==============================================================================
#
# 🎯 왜 필요한가?
# ECS Task가 AWS 서비스에 접근하려면 두 가지 IAM Role이 필요합니다:
# 1. Task Execution Role: ECS 인프라가 ECR 이미지를 가져오고 로그를 전송
# 2. Task Role: 애플리케이션 코드가 AWS API를 호출
#
# Section 3에서는 AWS Console에서 클릭으로 생성했지만,
# Terraform으로 관리하면 권한을 코드로 명확히 정의하고 버전 관리할 수 있습니다.

# ------------------------------------------------------------------------------
# ECS Task Execution Role
# ------------------------------------------------------------------------------
# ECS 인프라가 사용하는 Role (ECR pull, CloudWatch logs, Secrets Manager)

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-${var.environment}"

  # Trust Relationship: ECS Tasks 서비스가 이 Role을 사용할 수 있도록 허용
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "ecsTaskExecutionRole-${var.environment}"
  }
}

# AWS 관리형 정책 연결: ECR 및 CloudWatch Logs 접근 권한
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager 접근 권한 (API Keys 읽기)
resource "aws_iam_role_policy" "ecs_execution_secrets_policy" {
  name = "ecs-execution-secrets-policy-${var.environment}"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ]
      # Data Source로 조회한 Secret ARN 사용
      Resource = [
        data.aws_secretsmanager_secret.openai.arn,
        data.aws_secretsmanager_secret.pinecone.arn
      ]
    }]
  })
}

# ------------------------------------------------------------------------------
# ECS Task Role
# ------------------------------------------------------------------------------
# 애플리케이션 코드가 사용하는 Role (필요한 AWS API 호출)

resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole-${var.environment}"

  # Trust Relationship: ECS Tasks 서비스가 이 Role을 사용할 수 있도록 허용
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "ecsTaskRole-${var.environment}"
  }
}

# CloudWatch Logs 접근 권한 (애플리케이션 로그 작성)
resource "aws_iam_role_policy_attachment" "ecs_task_logs_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# 필요 시 추가 권한 부여
# 예: S3 접근, DynamoDB 접근 등
# resource "aws_iam_role_policy" "ecs_task_custom_policy" {
#   name = "ecs-task-custom-policy-${var.environment}"
#   role = aws_iam_role.ecs_task_role.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "s3:GetObject",
#         "s3:PutObject"
#       ]
#       Resource = "arn:aws:s3:::your-bucket/*"
#     }]
#   })
# }
