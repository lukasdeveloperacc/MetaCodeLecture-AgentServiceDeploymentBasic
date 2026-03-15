# ==============================================================================
# Terraform Variables
# ==============================================================================
#
# 변수를 사용하면:
# - 환경별로 다른 값 적용 가능 (dev/staging/prod)
# - 재사용 가능한 모듈 작성 가능
# - terraform.tfvars 파일로 값 주입
#
# 사용 예시:
# - 코드: var.aws_region
# - 값 주입: terraform.tfvars에서 aws_region = "ap-northeast-2"

# ------------------------------------------------------------------------------
# AWS 리전
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

# ------------------------------------------------------------------------------
# 프로젝트 정보
# ------------------------------------------------------------------------------

variable "project_name" {
  description = "Project name (태그에 사용)"
  type        = string
  default     = "agent-service"
}

variable "environment" {
  description = "Environment suffix for resource names (충돌 방지)"
  type        = string
  default     = "dev" # 리소스 이름: backend-dev, frontend-dev, agent-cluster-dev

  validation {
    condition     = length(var.environment) <= 10
    error_message = "Environment name must be 10 characters or less."
  }
}

# ------------------------------------------------------------------------------
# VPC 정보 (기존 VPC 재사용)
# ------------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID (기본 VPC 사용)"
  type        = string

  # 예시: vpc-0123456789abcdef0
  # aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId'
}

variable "public_subnet_ids" {
  description = "Public Subnet IDs (ALB용, 최소 2개의 AZ 필요)"
  type        = list(string)

  # 예시: ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  # aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets in different AZs are required for ALB."
  }
}

# ------------------------------------------------------------------------------
# Secrets Manager 시크릿 이름 (ARN은 자동 조회)
# ------------------------------------------------------------------------------

variable "openai_secret_name" {
  description = "OpenAI API Key Secret 이름 (Secrets Manager)"
  type        = string
  default     = "dev/openai-api-key"

  # Section 3에서 생성한 Secret 이름
  # Terraform이 자동으로 ARN을 조회합니다
  # aws secretsmanager list-secrets --query 'SecretList[*].Name'
}

variable "pinecone_secret_name" {
  description = "Pinecone API Key Secret 이름 (Secrets Manager)"
  type        = string
  default     = "dev/pinecone-api-key"

  # Section 3에서 생성한 Secret 이름
  # Terraform이 자동으로 ARN을 조회합니다
}

# ------------------------------------------------------------------------------
# ECS Task 설정
# ------------------------------------------------------------------------------

variable "backend_cpu" {
  description = "Backend task CPU units (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1 vCPU)"
  type        = string
  default     = "512"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096"], var.backend_cpu)
    error_message = "Valid CPU values: 256, 512, 1024, 2048, 4096"
  }
}

variable "backend_memory" {
  description = "Backend task memory (MiB) - Must be compatible with CPU"
  type        = string
  default     = "1024"

  # CPU:Memory 호환성
  # 256 CPU: 512, 1024, 2048
  # 512 CPU: 1024-4096
  # 1024 CPU: 2048-8192
  # 2048 CPU: 4096-16384
  # 4096 CPU: 8192-30720
}

variable "frontend_cpu" {
  description = "Frontend task CPU units"
  type        = string
  default     = "256"

  validation {
    condition     = contains(["256", "512", "1024"], var.frontend_cpu)
    error_message = "Valid CPU values for frontend: 256, 512, 1024"
  }
}

variable "frontend_memory" {
  description = "Frontend task memory (MiB)"
  type        = string
  default     = "512"
}

# ------------------------------------------------------------------------------
# ECS Service 설정
# ------------------------------------------------------------------------------

variable "backend_desired_count" {
  description = "Backend desired task count (최소 2개 권장)"
  type        = number
  default     = 2

  validation {
    condition     = var.backend_desired_count >= 1 && var.backend_desired_count <= 10
    error_message = "Desired count must be between 1 and 10."
  }
}

variable "frontend_desired_count" {
  description = "Frontend desired task count (최소 2개 권장)"
  type        = number
  default     = 2

  validation {
    condition     = var.frontend_desired_count >= 1 && var.frontend_desired_count <= 10
    error_message = "Desired count must be between 1 and 10."
  }
}
