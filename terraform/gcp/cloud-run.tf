# ==============================================================================
# Cloud Run Services
# ==============================================================================
#
# Cloud Run은 AWS ECS/Fargate + ALB를 하나로 합친 완전 관리형 서비스입니다.
#
# Section 4에서 수동으로 배포했던 것:
#   gcloud run deploy backend-dev \
#     --image asia-northeast3-docker.pkg.dev/.../backend:v1 \
#     --set-env-vars "..." \
#     --set-secrets "..." \
#     --cpu 2 --memory 2Gi
#
# Terraform으로 자동화:
#   - Backend 및 Frontend 서비스 정의
#   - 환경 변수 및 시크릿 참조 설정
#   - 리소스(CPU/Memory) 및 스케일링 설정
#   - 트래픽 설정 (100% latest revision)

# ------------------------------------------------------------------------------
# Backend Cloud Run Service
# ------------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "backend" {
  # 서비스 이름
  name     = "backend-${var.environment}"
  location = var.region

  # Cloud Run 서비스 템플릿 정의
  template {
    # 스케일링 설정
    scaling {
      min_instance_count = var.backend_min_instances # 최소 인스턴스 (0 = 자동 축소)
      max_instance_count = var.backend_max_instances # 최대 인스턴스
    }

    # 컨테이너 정의
    containers {
      # 컨테이너 이미지
      # 초기 배포 시에는 이미지가 없어도 됩니다 (placeholder 사용)
      # 실제 이미지는 terraform apply 후 docker push로 업로드
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}/backend:latest"

      # 포트 설정
      ports {
        container_port = 8000 # FastAPI는 8000 포트 사용
      }

      # 리소스 제한
      resources {
        limits = {
          cpu    = var.backend_cpu    # CPU (예: "2" = 2 vCPU)
          memory = var.backend_memory # Memory (예: "2Gi" = 2GB)
        }
      }

      # 환경 변수 설정
      # Section 3/4와 동일한 환경 변수
      env {
        name  = "ENVIRONMENT"
        value = "development"
      }
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
      env {
        name  = "PINECONE_INDEX_NAME"
        value = var.pinecone_index_name
      }
      env {
        name  = "LLM_MODEL"
        value = "gpt-4o-mini"
      }
      env {
        name  = "LLM_TEMPERATURE"
        value = "0.7"
      }
      env {
        name  = "LLM_MAX_TOKENS"
        value = "1000"
      }
      env {
        name  = "RAG_TOP_K"
        value = "3"
      }
      env {
        name  = "EMBEDDING_MODEL"
        value = "text-embedding-3-small"
      }

      # Secret Manager 시크릿 참조
      # Section 4에서 생성한 시크릿을 참조합니다
      env {
        name = "OPENAI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.openai_secret_name # Secret 이름 (예: "openai-api-key")
            version = "latest"               # 최신 버전 사용
          }
        }
      }
      env {
        name = "PINECONE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.pinecone_secret_name
            version = "latest"
          }
        }
      }

      # 시작 프로브 (컨테이너 시작 확인)
      startup_probe {
        http_get {
          path = "/health" # 헬스 체크 엔드포인트
          port = 8000
        }
        initial_delay_seconds = 10
        timeout_seconds       = 3
        period_seconds        = 10
        failure_threshold     = 3
      }

      # 라이브니스 프로브 (컨테이너 정상 동작 확인)
      liveness_probe {
        http_get {
          path = "/health"
          port = 8000
        }
        timeout_seconds   = 3
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    # 타임아웃 설정 (최대 요청 처리 시간)
    timeout = "300s" # 5분

    # 서비스 계정 (IAM에서 생성한 권한 사용)
    service_account = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
  }

  # 트래픽 설정: 100% 최신 리비전으로 라우팅
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # iam.tf의 권한 부여가 완료된 후 실행되도록 의존성 설정
  depends_on = [
    google_project_iam_member.secret_accessor
  ]
}

# ------------------------------------------------------------------------------
# Frontend Cloud Run Service
# ------------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "frontend" {
  name     = "frontend-${var.environment}"
  location = var.region

  template {
    scaling {
      min_instance_count = var.frontend_min_instances
      max_instance_count = var.frontend_max_instances
    }

    containers {
      # Frontend 이미지
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}/frontend:latest"

      # Nginx는 80 포트 사용
      ports {
        container_port = 80
      }

      # Frontend는 Backend보다 리소스 적게 사용
      resources {
        limits = {
          cpu    = var.frontend_cpu
          memory = var.frontend_memory
        }
      }

      # 헬스 체크
      startup_probe {
        http_get {
          path = "/"
          port = 80
        }
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 80
        }
        timeout_seconds   = 3
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    timeout = "60s" # Frontend는 짧은 타임아웃

    service_account = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# ------------------------------------------------------------------------------
# Cloud Run 서비스 IAM 정책 (Public 접근 허용)
# ------------------------------------------------------------------------------

# Backend를 인터넷에서 접근 가능하도록 설정
resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  name     = google_cloud_run_v2_service.backend.name
  location = google_cloud_run_v2_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers" # 모든 사용자 접근 허용
}

# Frontend를 인터넷에서 접근 가능하도록 설정
resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  name     = google_cloud_run_v2_service.frontend.name
  location = google_cloud_run_v2_service.frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ------------------------------------------------------------------------------
# 참고: AWS ECS vs GCP Cloud Run 비교
# ------------------------------------------------------------------------------
#
# AWS ECS (Section 3):
#   ✓ ECS Cluster 생성
#   ✓ Task Definition (CPU, Memory, 환경변수, 시크릿)
#   ✓ ECS Service (Desired Count, 네트워크 설정)
#   ✓ Security Group (인바운드/아웃바운드 규칙)
#   ✓ ALB (로드 밸런서)
#   ✓ Target Group (헬스 체크, 라우팅)
#   ✓ Listener (포트 80 → Target Group)
#   ✓ VPC 및 Subnet 설정
#   → 총 8개 이상의 리소스 관리 필요!
#
# GCP Cloud Run (Section 5):
#   ✓ Cloud Run Service (컨테이너, 환경변수, 시크릿, 리소스, 스케일링)
#   → 단 1개의 리소스로 모든 기능 제공!
#   → VPC, ALB, Target Group 등 인프라 관리 불필요
#   → 완전 서버리스, 자동 스케일링 (0 ↔ N)
#
# 왜 이렇게 다른가?
#   - AWS ECS: 세밀한 제어 가능, 복잡한 인프라
#   - GCP Cloud Run: 간단한 설정, 완전 관리형
#   - 프로젝트 요구사항에 따라 선택
