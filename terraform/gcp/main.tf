# ==============================================================================
# Terraform Provider 설정 (GCP)
# ==============================================================================
#
# Terraform 기본 설정 및 GCP Provider 구성
# - GCP Project ID와 Region 설정
# - 기본 태그를 통한 리소스 관리
#
# 사용 예시:
# - terraform init    : Provider 플러그인 다운로드
# - terraform plan    : 생성될 리소스 미리보기
# - terraform apply   : 실제 리소스 생성

# ------------------------------------------------------------------------------
# Terraform 버전 및 Provider 요구사항
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# GCP Provider 설정
# ------------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region

  # 모든 리소스에 자동으로 적용될 기본 레이블 (AWS의 태그와 동일)
  # GCP에서는 labels라고 부릅니다
  default_labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    section     = "section5"
  }
}
