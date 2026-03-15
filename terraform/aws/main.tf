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

  # 원격 State 관리 (선택사항, 팀 협업 시 사용)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "agent-service/terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
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
