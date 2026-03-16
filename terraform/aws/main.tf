# ==============================================================================
# Terraform 설정 및 Provider
# ==============================================================================
#
# 이 파일은 Terraform 기본 설정과 AWS Provider를 정의합니다.
# Section 3에서 AWS Console/CLI로 했던 작업을 이제 코드로 관리합니다!

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 원격 State 관리 (팀 협업용)
  # GitHub Actions에서 -backend-config로 동적 설정
  backend "s3" {
    # bucket, key, region은 terraform init 시 주입됨
    # 예: terraform init \
    #   -backend-config="bucket=my-state-bucket" \
    #   -backend-config="key=agent-service/dev/terraform.tfstate" \
    #   -backend-config="region=ap-northeast-2"
    encrypt = true
  }
}

# AWS Provider 설정
provider "aws" {
  region = var.aws_region

  # 모든 리소스에 자동으로 태그 추가
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Section     = "Section5"
    }
  }
}
