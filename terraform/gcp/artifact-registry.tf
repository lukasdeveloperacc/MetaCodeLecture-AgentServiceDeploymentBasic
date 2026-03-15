# ==============================================================================
# Artifact Registry (GCP Container Registry)
# ==============================================================================
#
# Artifact Registry는 AWS ECR과 동일한 역할의 컨테이너 이미지 저장소입니다.
#
# Section 4에서 수동으로 생성했던 것:
#   gcloud artifacts repositories create agent \
#     --repository-format=docker \
#     --location=asia-northeast3 \
#     --description="Agent Service Container Images"
#
# Terraform으로 자동화:
#   - Repository 생성
#   - Docker 형식 지정
#   - 리전 설정

# ------------------------------------------------------------------------------
# Artifact Registry Repository
# ------------------------------------------------------------------------------

resource "google_artifact_registry_repository" "agent" {
  # Repository 이름 (Section 4와 동일하게 "agent" 사용)
  # Terraform 관리 구분을 위해 -tf suffix는 사용하지 않습니다
  # (GCP는 프로젝트 내에서 Repository 이름이 고유하므로 충돌 가능성 낮음)
  repository_id = "agent-${var.environment}"

  # Repository 위치 (서울 리전)
  location = var.region

  # 형식: Docker 이미지 저장소
  format = "DOCKER"

  # 설명
  description = "Agent Service Container Images (Managed by Terraform)"

  # 레이블 (리소스 관리용)
  labels = {
    service = "agent-service"
    type    = "container-registry"
  }
}

# ------------------------------------------------------------------------------
# 참고: Artifact Registry 이미지 URL 형식
# ------------------------------------------------------------------------------
#
# AWS ECR:
#   123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend-tf:latest
#
# GCP Artifact Registry:
#   asia-northeast3-docker.pkg.dev/PROJECT_ID/agent-tf/backend:latest
#
# 차이점:
# - GCP는 region-docker.pkg.dev 형식 사용
# - PROJECT_ID가 URL에 포함됨
# - Repository 이름 (agent-tf) 포함
