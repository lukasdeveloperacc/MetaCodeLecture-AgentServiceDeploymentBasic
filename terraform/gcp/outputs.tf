# ==============================================================================
# Terraform Outputs (GCP)
# ==============================================================================
#
# Output은 terraform apply 완료 후 중요한 정보를 출력합니다.
# - Artifact Registry URL: 이미지 푸시 시 필요
# - Cloud Run Service URLs: 서비스 접속 주소
#
# 사용 예시:
# - terraform output backend_url
# - terraform output -json | jq '.backend_url.value'

# ------------------------------------------------------------------------------
# Artifact Registry
# ------------------------------------------------------------------------------

output "artifact_registry_url" {
  description = "Artifact Registry URL (docker push 시 사용)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}"

  # 예시 출력: asia-northeast3-docker.pkg.dev/my-project-123/agent-tf
}

output "backend_image_url" {
  description = "Backend 이미지 전체 URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}/backend:latest"
}

output "frontend_image_url" {
  description = "Frontend 이미지 전체 URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}/frontend:latest"
}

# ------------------------------------------------------------------------------
# Cloud Run Services
# ------------------------------------------------------------------------------

output "backend_url" {
  description = "Backend Cloud Run Service URL (API 접속 주소)"
  value       = google_cloud_run_v2_service.backend.uri

  # 예시 출력: https://backend-tf-xxxxx-an.a.run.app
}

output "frontend_url" {
  description = "Frontend Cloud Run Service URL (웹 접속 주소)"
  value       = google_cloud_run_v2_service.frontend.uri

  # 예시 출력: https://frontend-tf-xxxxx-an.a.run.app
}

output "backend_service_name" {
  description = "Backend Service 이름"
  value       = google_cloud_run_v2_service.backend.name
}

output "frontend_service_name" {
  description = "Frontend Service 이름"
  value       = google_cloud_run_v2_service.frontend.name
}

# ------------------------------------------------------------------------------
# 배포 후 다음 단계 안내
# ------------------------------------------------------------------------------

output "next_steps" {
  description = "배포 후 다음 단계"
  value       = <<-EOT
    ✅ Terraform 배포 완료!

    📋 다음 단계:

    1. Artifact Registry 인증 설정:
       gcloud auth configure-docker ${var.region}-docker.pkg.dev

    2. 이미지 빌드 및 푸시 (docker-compose 사용):
       # 환경 변수 설정
       export PROJECT_ID=${var.project_id}
       export REGION=${var.region}
       export BACKEND_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/${google_artifact_registry_repository.agent.repository_id}/backend:latest"
       export FRONTEND_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/${google_artifact_registry_repository.agent.repository_id}/frontend:latest"

       # docker-compose로 빌드 및 푸시 (두 서비스 동시)
       docker-compose build
       docker-compose push

       # 또는 개별 서비스만 빌드/푸시:
       # docker-compose build backend && docker-compose push backend
       # docker-compose build frontend && docker-compose push frontend

    3. Cloud Run 서비스 자동 재배포:
       # 이미지를 푸시하면 Cloud Run이 자동으로 감지하여 재배포합니다
       # 또는 수동으로 새 리비전 배포:
       gcloud run services update-traffic ${google_cloud_run_v2_service.backend.name} --to-latest --region ${var.region}
       gcloud run services update-traffic ${google_cloud_run_v2_service.frontend.name} --to-latest --region ${var.region}

    4. 서비스 접속:
       Backend:  ${google_cloud_run_v2_service.backend.uri}
       Frontend: ${google_cloud_run_v2_service.frontend.uri}

    5. 로그 확인:
       # Backend 로그
       gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_service.backend.name}" --limit 50 --format json

       # Frontend 로그
       gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_service.frontend.name}" --limit 50 --format json

    💡 Cloud Run의 장점:
    - 자동 스케일링: 트래픽에 따라 0 ↔ N 자동 조절
    - 자동 HTTPS: 별도 설정 없이 HTTPS 제공
    - 자동 로드밸런싱: ALB 없이도 자동 분산
    - 비용 효율: 요청 없으면 0원 (완전 서버리스)
  EOT
}

# ------------------------------------------------------------------------------
# 참고: AWS vs GCP Output 비교
# ------------------------------------------------------------------------------
#
# AWS Outputs:
#   - ALB DNS: agent-alb-tf-xxx.elb.amazonaws.com (http only)
#   - ECR URLs: 123456789012.dkr.ecr.region.amazonaws.com/...
#   - Task Definition ARNs: 긴 ARN 문자열
#   - Service Names: backend-tf-service, frontend-tf-service
#   - 다음 단계: ECR 로그인 → 이미지 푸시 → ECS 강제 재배포
#
# GCP Outputs:
#   - Service URLs: https://backend-tf-xxx.a.run.app (https 기본)
#   - Image URLs: region-docker.pkg.dev/project/repo/image
#   - Service Names: backend-tf, frontend-tf
#   - 다음 단계: 인증 설정 → 이미지 푸시 → 자동 재배포
#
# 왜 GCP가 더 간단한가?
#   - HTTPS 자동 제공 (인증서 불필요)
#   - 자동 재배포 (force-new-deployment 불필요)
#   - 짧고 직관적인 URL
