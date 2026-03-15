# ==============================================================================
# Terraform Variables (GCP)
# ==============================================================================
#
# 변수를 사용하면:
# - 환경별로 다른 값 적용 가능 (dev/staging/prod)
# - 재사용 가능한 모듈 작성 가능
# - terraform.tfvars 파일로 값 주입
#
# 사용 예시:
# - 코드: var.project_id
# - 값 주입: terraform.tfvars에서 project_id = "my-project"

# ------------------------------------------------------------------------------
# GCP 프로젝트 및 리전
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "GCP Project ID"
  type        = string

  # 예시: "my-gcp-project-123456"
  # gcloud config get-value project 명령으로 확인 가능
}

variable "region" {
  description = "GCP Region (서울 리전)"
  type        = string
  default     = "asia-northeast3" # 서울

  # 다른 리전 사용 시:
  # - asia-northeast1 (도쿄)
  # - us-central1 (아이오와)
  # - europe-west1 (벨기에)
}

# ------------------------------------------------------------------------------
# 프로젝트 정보
# ------------------------------------------------------------------------------

variable "project_name" {
  description = "Project name (레이블에 사용)"
  type        = string
  default     = "agent-service"
}

variable "environment" {
  description = "Environment suffix for resource names (충돌 방지)"
  type        = string
  default     = "tf" # 리소스 이름: backend-tf, frontend-tf, agent-tf

  validation {
    condition     = length(var.environment) <= 10
    error_message = "Environment name must be 10 characters or less."
  }
}

# ------------------------------------------------------------------------------
# Secret Manager 시크릿 이름
# ------------------------------------------------------------------------------

variable "openai_secret_name" {
  description = "OpenAI API Key Secret 이름 (Secret Manager)"
  type        = string
  default     = "openai-api-key"

  # Section 4에서 생성한 Secret 이름
  # gcloud secrets list 명령으로 확인 가능
}

variable "pinecone_secret_name" {
  description = "Pinecone API Key Secret 이름 (Secret Manager)"
  type        = string
  default     = "pinecone-api-key"
}

variable "pinecone_index_name" {
  description = "Pinecone Index 이름"
  type        = string
  default     = "ai-service-docs-dev"
}

# ------------------------------------------------------------------------------
# Backend 리소스 설정
# ------------------------------------------------------------------------------

variable "backend_cpu" {
  description = "Backend CPU 할당 (1, 2, 4 등)"
  type        = string
  default     = "2"

  validation {
    condition     = contains(["1", "2", "4", "8"], var.backend_cpu)
    error_message = "Valid CPU values: 1, 2, 4, 8"
  }
}

variable "backend_memory" {
  description = "Backend Memory 할당 (예: 512Mi, 1Gi, 2Gi)"
  type        = string
  default     = "2Gi"

  # CPU:Memory 호환성
  # 1 CPU: 최대 2Gi
  # 2 CPU: 최대 4Gi
  # 4 CPU: 최대 8Gi
  # 8 CPU: 최대 16Gi
}

variable "backend_min_instances" {
  description = "Backend 최소 인스턴스 수 (0 = 자동 축소)"
  type        = number
  default     = 0

  validation {
    condition     = var.backend_min_instances >= 0 && var.backend_min_instances <= 10
    error_message = "Min instances must be between 0 and 10."
  }
}

variable "backend_max_instances" {
  description = "Backend 최대 인스턴스 수"
  type        = number
  default     = 10

  validation {
    condition     = var.backend_max_instances >= 1 && var.backend_max_instances <= 100
    error_message = "Max instances must be between 1 and 100."
  }
}

# ------------------------------------------------------------------------------
# Frontend 리소스 설정
# ------------------------------------------------------------------------------

variable "frontend_cpu" {
  description = "Frontend CPU 할당"
  type        = string
  default     = "1"

  validation {
    condition     = contains(["1", "2", "4"], var.frontend_cpu)
    error_message = "Valid CPU values for frontend: 1, 2, 4"
  }
}

variable "frontend_memory" {
  description = "Frontend Memory 할당"
  type        = string
  default     = "512Mi"
}

variable "frontend_min_instances" {
  description = "Frontend 최소 인스턴스 수"
  type        = number
  default     = 0

  validation {
    condition     = var.frontend_min_instances >= 0 && var.frontend_min_instances <= 10
    error_message = "Min instances must be between 0 and 10."
  }
}

variable "frontend_max_instances" {
  description = "Frontend 최대 인스턴스 수"
  type        = number
  default     = 5

  validation {
    condition     = var.frontend_max_instances >= 1 && var.frontend_max_instances <= 100
    error_message = "Max instances must be between 1 and 100."
  }
}

# ------------------------------------------------------------------------------
# 참고: AWS vs GCP 변수 비교
# ------------------------------------------------------------------------------
#
# AWS (Section 5):
#   - vpc_id, subnet_ids (VPC 정보 필요)
#   - secret ARN (전체 ARN 필요)
#   - CPU/Memory는 문자열 (예: "512", "1024")
#   - desired_count (고정된 Task 수)
#
# GCP (Section 5):
#   - project_id만 필요 (VPC 불필요)
#   - secret 이름만 필요 (ARN 불필요)
#   - CPU/Memory는 더 직관적 (예: "2", "2Gi")
#   - min/max instances (자동 스케일링)
#
# 왜 GCP가 더 간단한가?
#   - Cloud Run이 완전 관리형이기 때문
#   - 네트워크 인프라 관리 불필요
#   - 자동 스케일링 기본 제공
