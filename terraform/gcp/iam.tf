# ==============================================================================
# IAM (Identity and Access Management)
# ==============================================================================
#
# Cloud Run 서비스가 Secret Manager의 시크릿에 접근할 수 있도록 권한 부여
#
# Section 4에서 수동으로 설정했던 것:
#   gcloud projects add-iam-policy-binding PROJECT_ID \
#     --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
#     --role="roles/secretmanager.secretAccessor"
#
# Terraform으로 자동화:
#   - 프로젝트 정보 자동 조회
#   - Compute Engine 기본 서비스 계정에 권한 자동 부여
#   - Secret Manager Secret Accessor 역할 할당

# ------------------------------------------------------------------------------
# 프로젝트 정보 조회
# ------------------------------------------------------------------------------

# 현재 프로젝트 정보를 조회합니다 (프로젝트 번호 필요)
data "google_project" "project" {}

# ------------------------------------------------------------------------------
# Secret Manager 접근 권한 부여
# ------------------------------------------------------------------------------

# Compute Engine 기본 서비스 계정에 Secret Manager 접근 권한 부여
# Cloud Run은 기본적으로 이 서비스 계정을 사용합니다
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"

  # Compute Engine 기본 서비스 계정
  # 형식: PROJECT_NUMBER-compute@developer.gserviceaccount.com
  member = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# ------------------------------------------------------------------------------
# 참고: AWS와 GCP IAM 비교
# ------------------------------------------------------------------------------
#
# AWS ECS:
#   - Task Execution Role: ECR pull, CloudWatch, Secrets Manager 접근
#   - Task Role: 애플리케이션 AWS API 호출
#   - 두 개의 별도 역할 필요
#
# GCP Cloud Run:
#   - Compute Engine 기본 서비스 계정 사용
#   - Secret Manager 접근 권한만 추가로 부여
#   - 훨씬 간단한 IAM 구조
#
# 왜 GCP가 더 간단한가?
#   - Cloud Run이 완전 관리형 서비스이기 때문
#   - 대부분의 인프라 권한이 자동으로 처리됨
#   - 개발자는 Secret 접근 권한만 신경 쓰면 됨
