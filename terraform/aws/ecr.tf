# ==============================================================================
# ECR (Elastic Container Registry) Repositories
# ==============================================================================
#
# 🎯 왜 필요한가?
# Section 3에서는 AWS Console로 ECR Repository를 만들었습니다.
# Terraform으로 관리하면:
# - 환경별(dev/staging/prod) 자동 생성 가능
# - 이미지 스캔, 수명 주기 정책 등 설정을 코드로 관리
# - 실수로 삭제하더라도 terraform apply로 즉시 복구
#
# Section 3 비교:
# - Section 3: aws ecr create-repository --repository-name backend
# - Terraform: resource "aws_ecr_repository" "backend" { ... }

# ------------------------------------------------------------------------------
# Backend ECR Repository
# ------------------------------------------------------------------------------

resource "aws_ecr_repository" "backend" {
  name                 = "backend-${var.environment}" # 예: backend-tf
  image_tag_mutability = "MUTABLE"                    # 이미지 태그 수정 허용
  force_delete         = true                         # 이미지가 있어도 삭제 허용 (학습용)

  # 이미지 푸시 시 자동 취약점 스캔
  image_scanning_configuration {
    scan_on_push = true
  }

  # Lifecycle Policy: 오래된 이미지 자동 삭제 (비용 절감)
  # 최근 10개 이미지만 유지
  # lifecycle_policy {
  #   policy = jsonencode({
  #     rules = [{
  #       rulePriority = 1
  #       description  = "Keep last 10 images"
  #       selection = {
  #         tagStatus     = "any"
  #         countType     = "imageCountMoreThan"
  #         countNumber   = 10
  #       }
  #       action = {
  #         type = "expire"
  #       }
  #     }]
  #   })
  # }

  tags = {
    Name = "backend-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Frontend ECR Repository
# ------------------------------------------------------------------------------

resource "aws_ecr_repository" "frontend" {
  name                 = "frontend-${var.environment}" # 예: frontend-tf
  image_tag_mutability = "MUTABLE"
  force_delete         = true # 이미지가 있어도 삭제 허용 (학습용)

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "frontend-${var.environment}"
  }
}
