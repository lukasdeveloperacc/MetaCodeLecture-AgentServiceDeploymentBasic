# ==============================================================================
# CloudWatch Log Groups
# ==============================================================================
#
# 🎯 왜 필요한가?
# ECS Task가 로그를 전송하려면 Log Group이 사전에 존재해야 합니다.
# Section 3에서는 AWS CLI로 수동 생성했지만,
# Terraform으로 관리하면 자동 생성 및 Retention 정책까지 코드로 관리 가능합니다.
#
# Section 3 비교:
# - Section 3: aws logs create-log-group --log-group-name /ecs/backend
# - Terraform: resource "aws_cloudwatch_log_group" "backend" { ... }

# ------------------------------------------------------------------------------
# Backend Log Group
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "backend" {
  name = "/ecs/backend-${var.environment}" # 예: /ecs/backend-tf

  # 로그 보관 기간 (일) - 비용 절감을 위해 7일로 설정
  # 0 = 무제한, 1/3/5/7/14/30/60/90/120/150/180/365/400/545/731/1827/3653
  retention_in_days = 7

  tags = {
    Name = "backend-${var.environment}-logs"
  }
}

# ------------------------------------------------------------------------------
# Frontend Log Group
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "frontend" {
  name = "/ecs/frontend-${var.environment}" # 예: /ecs/frontend-tf

  retention_in_days = 7

  tags = {
    Name = "frontend-${var.environment}-logs"
  }
}
