# ==============================================================================
# Terraform Outputs
# ==============================================================================
#
# Output은 terraform apply 완료 후 중요한 정보를 출력합니다.
# - ECR URL: 이미지 푸시 시 필요
# - ALB DNS: 서비스 접속 주소
# - Task Definition ARN: 배포 확인용
#
# 사용 예시:
# - terraform output backend_ecr_url
# - terraform output -json | jq '.alb_dns_name.value'

# ------------------------------------------------------------------------------
# ECR Repositories
# ------------------------------------------------------------------------------

output "backend_ecr_url" {
  description = "Backend ECR Repository URL (docker push 시 사용)"
  value       = aws_ecr_repository.backend.repository_url

  # 예시 출력: 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend-tf
}

output "frontend_ecr_url" {
  description = "Frontend ECR Repository URL"
  value       = aws_ecr_repository.frontend.repository_url
}

# ------------------------------------------------------------------------------
# Application Load Balancers
# ------------------------------------------------------------------------------

output "frontend_alb_dns_name" {
  description = "Frontend ALB DNS Name (Frontend 서비스 접속 주소)"
  value       = aws_lb.frontend.dns_name

  # 예시 출력: frontend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com
  # 브라우저 접속: http://<Frontend_ALB_DNS>/
}

output "backend_alb_dns_name" {
  description = "Backend ALB DNS Name (Backend API 접속 주소)"
  value       = aws_lb.backend.dns_name

  # 예시 출력: backend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com
  # API 접속: http://<Backend_ALB_DNS>/health
}

output "frontend_alb_zone_id" {
  description = "Frontend ALB Hosted Zone ID (Route 53 연결 시 사용)"
  value       = aws_lb.frontend.zone_id
}

output "backend_alb_zone_id" {
  description = "Backend ALB Hosted Zone ID (Route 53 연결 시 사용)"
  value       = aws_lb.backend.zone_id
}

# ------------------------------------------------------------------------------
# ECS Cluster
# ------------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

# ------------------------------------------------------------------------------
# ECS Task Definitions
# ------------------------------------------------------------------------------

output "backend_task_definition_arn" {
  description = "Backend Task Definition ARN (최신 버전)"
  value       = aws_ecs_task_definition.backend.arn

  # 예시 출력: arn:aws:ecs:ap-northeast-2:123456789012:task-definition/backend-tf:5
}

output "frontend_task_definition_arn" {
  description = "Frontend Task Definition ARN (최신 버전)"
  value       = aws_ecs_task_definition.frontend.arn
}

# ------------------------------------------------------------------------------
# ECS Services
# ------------------------------------------------------------------------------

output "backend_service_name" {
  description = "Backend Service Name"
  value       = aws_ecs_service.backend.name
}

output "frontend_service_name" {
  description = "Frontend Service Name"
  value       = aws_ecs_service.frontend.name
}

# ------------------------------------------------------------------------------
# CloudWatch Log Groups
# ------------------------------------------------------------------------------

output "backend_log_group" {
  description = "Backend CloudWatch Log Group Name"
  value       = aws_cloudwatch_log_group.backend.name

  # 로그 확인: aws logs tail /ecs/backend-tf --follow
}

output "frontend_log_group" {
  description = "Frontend CloudWatch Log Group Name"
  value       = aws_cloudwatch_log_group.frontend.name
}

# ------------------------------------------------------------------------------
# 배포 후 다음 단계 안내
# ------------------------------------------------------------------------------

output "next_steps" {
  description = "배포 후 다음 단계"
  value       = <<-EOT
    ✅ Terraform 배포 완료!

    📋 다음 단계:

    1. ECR 로그인:
       aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.backend.repository_url}

    2. 이미지 빌드 및 푸시 (docker-compose 사용):
       # 환경 변수 설정
       export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
       export AWS_REGION=${var.aws_region}
       export BACKEND_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/backend-${var.environment}:${var.image_tag}"
       export FRONTEND_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/frontend-${var.environment}:${var.image_tag}"

       # docker-compose로 빌드 및 푸시 (두 서비스 동시)
       docker-compose build
       docker-compose push

       # 또는 개별 서비스만 빌드/푸시:
       # docker-compose build backend && docker-compose push backend
       # docker-compose build frontend && docker-compose push frontend

    3. ECS Service 강제 재배포 (이미지 반영):
       aws ecs update-service --cluster ${aws_ecs_cluster.main.name} --service ${aws_ecs_service.backend.name} --force-new-deployment --region ${var.aws_region}
       aws ecs update-service --cluster ${aws_ecs_cluster.main.name} --service ${aws_ecs_service.frontend.name} --force-new-deployment --region ${var.aws_region}

    4. 서비스 접속:
       Frontend: http://${aws_lb.frontend.dns_name}/
       Backend:  http://${aws_lb.backend.dns_name}/health

    5. 로그 확인:
       aws logs tail ${aws_cloudwatch_log_group.backend.name} --follow --region ${var.aws_region}
  EOT
}
