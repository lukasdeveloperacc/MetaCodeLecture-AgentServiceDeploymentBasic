# Section 5: Terraform 기반 Infrastructure as Code (IaC)

## 학습 목표
- IaC의 핵심 개념과 Terraform 기초 이해
- **Terraform으로 인프라를 코드로 관리하는 방법** 학습
- Section 3-4 수동 배포와 Terraform 비교 경험
- Terraform State 관리 및 협업 전략
- 실무에서 적용 가능한 IaC 접근법

## ✅ Section 5의 접근 방식

### 비교 학습 전략

**Section 3-4에서 학습한 내용:**
- AWS: Console과 CLI로 ECS/Fargate 수동 배포
- GCP: gcloud 명령으로 Cloud Run 수동 배포
- 직접 클릭하고 명령어 입력하며 리소스 생성

**Section 5에서 학습할 내용:**
- **Section 3-4 리소스는 그대로 유지** (삭제하지 않음)
- **별도 이름**의 리소스를 Terraform으로 생성
- 수동 배포 vs IaC 비교하며 장단점 체험
- 학습 완료 후 선택적으로 리소스 정리

### 리소스 충돌 방지 전략

**Section 3-4 리소스 (수동 생성):**
- AWS: `backend`, `frontend`, `agent-cluster`
- GCP: `backend-dev`, `frontend-dev`

**Section 5 리소스 (Terraform 생성):**
- AWS: `backend-tf`, `frontend-tf`, `agent-cluster-tf`
- GCP: `backend-terraform`, `frontend-terraform`

→ **서로 다른 이름**으로 충돌 없이 공존 가능!

### Terraform으로 생성할 리소스

**AWS:**
- ✅ ECR Repository (컨테이너 레지스트리)
- ✅ ALB (Application Load Balancer)
- ✅ Target Groups (로드밸런서 타겟)
- ✅ Security Groups (방화벽 규칙)
- ✅ IAM Roles/Policies (권한 관리)
- ✅ ECS Cluster (컨테이너 클러스터)
- ✅ ECS Task Definition (컨테이너 설정)
- ✅ ECS Service (컨테이너 실행)
- ⚠️ VPC, Subnets만 Section 3 기존 것 재사용 (네트워크 기본 인프라)

**GCP:**
- ✅ Artifact Registry (컨테이너 레지스트리)
- ✅ Cloud Run Service (서버리스 컨테이너)
- ⚠️ VPC만 기존 것 재사용

**VPC만 재사용하는 이유:**
1. VPC는 AWS 계정의 기본 네트워크 인프라 (재생성 불필요)
2. 나머지 리소스는 모두 Terraform으로 생성하여 완전한 IaC 경험 제공
3. `terraform apply` 한 번으로 전체 인프라 자동 생성

## 새로 추가된 파일
```
terraform/
  ├── aws/
  │   ├── main.tf                    # AWS 리소스 정의
  │   ├── variables.tf               # 변수 정의
  │   ├── outputs.tf                 # 출력 변수
  │   └── terraform.tfvars.example   # 변수 예시
  │
  └── gcp/
      ├── main.tf                    # GCP 리소스 정의
      ├── variables.tf               # 변수 정의
      ├── outputs.tf                 # 출력 변수
      └── terraform.tfvars.example   # 변수 예시
```

## Infrastructure as Code (IaC)란?

### 기존 방식 vs IaC
```
기존 방식 (ClickOps):
1. AWS Console 접속
2. ECR 생성 클릭
3. Task Definition 수정...
4. Service 업데이트...
❌ 재현 불가능, 문서화 어려움, 휴먼 에러 발생

IaC (Terraform):
1. .tf 파일 작성
2. terraform apply
✅ 재현 가능, 버전 관리, 자동화, 협업 용이
```

### Terraform 핵심 개념
- **Provider**: 클라우드 제공자 (AWS, GCP, Azure 등)
- **Resource**: 생성할 인프라 리소스 (ECR, ECS Task 등)
- **State**: 현재 인프라 상태 추적 파일
- **Plan**: 변경 사항 미리보기 (실행 전 검증)
- **Apply**: 실제 인프라 변경 적용

## Terraform 설치

### macOS
```bash
# Homebrew 이용
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 설치 확인
terraform version
```

### Linux
```bash
# Ubuntu/Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

## AWS 인프라 관리

### 1. 사전 준비 - VPC 정보 확인

**Terraform은 VPC/Subnets만 재사용하고, 나머지는 모두 자동 생성합니다.**

기본 VPC와 Subnet ID만 확인하면 됩니다:

```bash
# 1. VPC ID 확인 (기본 VPC 사용)
aws ec2 describe-vpcs \
  --query 'Vpcs[?IsDefault==`true`].VpcId' \
  --output text

# 출력 예시: vpc-0123456789abcdef0

# 2. Subnet IDs 확인 (최소 2개의 AZ 필요)
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-0123456789abcdef0" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table

# 출력 예시:
# subnet-0123456789abcdef0  ap-northeast-2a  True
# subnet-0123456789abcdef1  ap-northeast-2c  True
```

**이 정보만 메모해두세요** - terraform.tfvars 파일에 입력합니다.

**나머지 리소스는 모두 Terraform이 자동 생성:**
- ALB (Application Load Balancer)
- Target Groups
- Security Groups
- IAM Roles/Policies
- ECR Repository
- ECS Cluster
- Task Definition
- ECS Service

### 2. AWS 자격증명 설정

```bash
# AWS 자격증명 설정
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-northeast-2"
```

### 3. Terraform 디렉토리 구조 생성

```bash
mkdir -p terraform/aws
cd terraform/aws
```

### 4. main.tf 작성

`terraform/aws/main.tf` 파일을 생성합니다:

```hcl
# Provider 설정
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================
# IAM Roles and Policies
# ============================================

# ECS Task Execution Role (ECR pull, CloudWatch logs)
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "ecsTaskExecutionRole-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_execution_secrets_policy" {
  name = "ecs-execution-secrets-policy-${var.environment}"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ]
      Resource = [
        var.openai_secret_arn,
        var.pinecone_secret_arn
      ]
    }]
  })
}

# ECS Task Role (application runtime permissions)
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "ecsTaskRole-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ============================================
# ECR Repositories
# ============================================

# ECR Repository - Backend
resource "aws_ecr_repository" "backend" {
  name                 = "backend-${var.environment}"  # backend-tf
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "backend-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ECR Repository - Frontend
resource "aws_ecr_repository" "frontend" {
  name                 = "frontend-${var.environment}"  # frontend-tf
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "frontend-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ECS Cluster - Terraform 전용
resource "aws_ecs_cluster" "main" {
  name = "agent-cluster-${var.environment}"  # agent-cluster-tf

  tags = {
    Name        = "agent-cluster-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ============================================
# Security Groups
# ============================================

# ALB Security Group (인터넷에서 80/443 허용)
resource "aws_security_group" "alb" {
  name        = "alb-sg-${var.environment}"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "alb-sg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Backend Security Group (ALB에서만 8000 포트 허용)
resource "aws_security_group" "backend" {
  name        = "backend-sg-${var.environment}"
  description = "Security group for backend ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend port from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "backend-sg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Frontend Security Group (ALB에서만 80 포트 허용)
resource "aws_security_group" "frontend" {
  name        = "frontend-sg-${var.environment}"
  description = "Security group for frontend ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Frontend port from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "frontend-sg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ============================================
# Application Load Balancer
# ============================================

# ALB
resource "aws_lb" "main" {
  name               = "agent-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "agent-alb-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Target Group - Backend
resource "aws_lb_target_group" "backend" {
  name        = "backend-tg-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name        = "backend-tg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Target Group - Frontend
resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = {
    Name        = "frontend-tg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ALB Listener (HTTP:80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ALB Listener Rule - Backend (경로 기반 라우팅)
resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ============================================
# ECS Cluster
# ============================================

# ECS Task Definition - Backend
resource "aws_ecs_task_definition" "backend" {
  family                   = "backend-${var.environment}"  # backend-tf
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = var.backend_cpu
  memory                  = var.backend_memory
  execution_role_arn      = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "backend"
    image = "${aws_ecr_repository.backend.repository_url}:latest"

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "ENVIRONMENT"
        value = var.environment
      }
    ]

    secrets = [
      {
        name      = "OPENAI_API_KEY"
        valueFrom = var.openai_secret_arn
      },
      {
        name      = "PINECONE_API_KEY"
        valueFrom = var.pinecone_secret_arn
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/backend-${var.environment}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name        = "backend-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ECS Task Definition - Frontend
resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-${var.environment}"  # frontend-tf
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = var.frontend_cpu
  memory                  = var.frontend_memory
  execution_role_arn      = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "frontend"
    image = "${aws_ecr_repository.frontend.repository_url}:latest"

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/frontend-${var.environment}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = {
    Name        = "frontend-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ECS Service - Backend
resource "aws_ecs_service" "backend" {
  name            = "backend-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids  # Public subnet 사용
    security_groups  = [aws_security_group.backend.id]  # 새로 생성한 SG
    assign_public_ip = true  # Public IP 할당
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn  # 새로 생성한 TG
    container_name   = "backend"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener_rule.backend
  ]

  tags = {
    Name        = "backend-${var.environment}-service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ECS Service - Frontend
resource "aws_ecs_service" "frontend" {
  name            = "frontend-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids  # Public subnet 사용
    security_groups  = [aws_security_group.frontend.id]  # 새로 생성한 SG
    assign_public_ip = true  # Public IP 할당
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn  # 새로 생성한 TG
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name        = "frontend-${var.environment}-service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

### 5. variables.tf 작성

`terraform/aws/variables.tf` 파일을 생성합니다:

```hcl
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name (not used in resource names, kept for compatibility)"
  type        = string
  default     = "agent-service"
}

variable "environment" {
  description = "Environment suffix for resource names (충돌 방지)"
  type        = string
  default     = "tf"  # backend-tf, frontend-tf, agent-cluster-tf
}

# VPC 정보 (기존 VPC 재사용)
variable "vpc_id" {
  description = "VPC ID (기본 VPC 사용)"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public Subnet IDs (ALB용, 최소 2개의 AZ)"
  type        = list(string)
}

# Secrets Manager ARNs
variable "openai_secret_arn" {
  description = "OpenAI API Key Secret ARN"
  type        = string
}

variable "pinecone_secret_arn" {
  description = "Pinecone API Key Secret ARN"
  type        = string
}

# Task Definition 설정
variable "backend_cpu" {
  description = "Backend task CPU units"
  type        = string
  default     = "512"
}

variable "backend_memory" {
  description = "Backend task memory (MiB)"
  type        = string
  default     = "1024"
}

variable "frontend_cpu" {
  description = "Frontend task CPU units"
  type        = string
  default     = "256"
}

variable "frontend_memory" {
  description = "Frontend task memory (MiB)"
  type        = string
  default     = "512"
}

# Service 설정
variable "backend_desired_count" {
  description = "Backend desired task count"
  type        = number
  default     = 2
}

variable "frontend_desired_count" {
  description = "Frontend desired task count"
  type        = number
  default     = 2
}
```

### 6. outputs.tf 작성

`terraform/aws/outputs.tf` 파일을 생성합니다:

```hcl
output "backend_ecr_url" {
  description = "Backend ECR Repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_url" {
  description = "Frontend ECR Repository URL"
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_task_definition_arn" {
  description = "Backend Task Definition ARN"
  value       = aws_ecs_task_definition.backend.arn
}

output "frontend_task_definition_arn" {
  description = "Frontend Task Definition ARN"
  value       = aws_ecs_task_definition.frontend.arn
}
```

### 7. terraform.tfvars 작성

`terraform/aws/terraform.tfvars` 파일을 생성하고, 1단계에서 확인한 VPC 정보를 입력합니다:

```hcl
aws_region   = "ap-northeast-2"
project_name = "agent-service"
environment  = "tf"  # 리소스 이름: backend-tf, frontend-tf, agent-cluster-tf

# VPC 정보 (사전 준비 섹션에서 확인한 값 입력)
vpc_id             = "vpc-0123456789abcdef0"  # 기본 VPC ID
public_subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]  # Public Subnet IDs (최소 2개 AZ)

# Secrets Manager ARNs (Section 3에서 생성한 것)
openai_secret_arn   = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:prod/openai-api-key-xxxxx"
pinecone_secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:prod/pinecone-api-key-xxxxx"

# Task 설정 (필요시 수정)
backend_cpu    = "512"
backend_memory = "1024"

frontend_cpu    = "256"
frontend_memory = "512"

# Service 설정
backend_desired_count  = 2
frontend_desired_count = 2
```

**간단합니다!** VPC/Subnet ID만 입력하면 나머지는 Terraform이 자동 생성합니다.

### 8. Terraform 실행

```bash
# 1. 초기화 (Provider 다운로드)
terraform init

# 2. 포맷팅 (코드 정리)
terraform fmt

# 3. 유효성 검사
terraform validate

# 4. 실행 계획 확인 (dry-run)
terraform plan

# 출력 예시:
# Terraform will perform the following actions:
#
#   # aws_iam_role.ecs_execution_role will be created
#   # aws_iam_role.ecs_task_role will be created
#   # aws_security_group.alb will be created
#   # aws_security_group.backend will be created
#   # aws_security_group.frontend will be created
#   # aws_lb.main will be created
#   # aws_lb_target_group.backend will be created
#   # aws_lb_target_group.frontend will be created
#   # aws_lb_listener.http will be created
#   # aws_lb_listener_rule.backend will be created
#   # aws_ecr_repository.backend will be created
#   # aws_ecr_repository.frontend will be created
#   # aws_ecs_cluster.main will be created
#   # aws_ecs_task_definition.backend will be created
#   # aws_ecs_task_definition.frontend will be created
#   # aws_ecs_service.backend will be created
#   # aws_ecs_service.frontend will be created
#   ...
#
# Plan: 19 to add, 0 to change, 0 to destroy.

# 5. 인프라 생성
terraform apply

# 확인 프롬프트에서 'yes' 입력
```

### 9. 출력 확인

```bash
# 생성된 리소스 출력
terraform output

# 예시 출력:
# backend_ecr_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend-tf"
# frontend_ecr_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/frontend-tf"
# backend_task_definition_arn = "arn:aws:ecs:ap-northeast-2:123456789012:task-definition/backend-tf:1"
```

### 10. 이미지 빌드 및 푸시

이제 ECR URL을 알았으니, 이미지를 빌드하고 푸시합니다:

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com

# Backend 이미지 빌드
docker build -t backend:latest ./backend

# Backend 이미지 태그
docker tag backend:latest 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend-tf:latest

# Backend 이미지 푸시
docker push 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend-tf:latest

# Frontend도 동일하게 수행
docker build -t frontend:latest ./frontend
docker tag frontend:latest 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/frontend-tf:latest
docker push 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/frontend-tf:latest
```

### 11. 서비스 확인

```bash
# ECS 서비스 상태 확인 (새로 만든 Cluster 사용)
aws ecs describe-services \
  --cluster agent-cluster-tf \
  --services backend-tf-service frontend-tf-service \
  --region ap-northeast-2

# Task 실행 상태 확인
aws ecs list-tasks \
  --cluster agent-cluster-tf \
  --service-name backend-tf-service \
  --region ap-northeast-2

# ALB를 통해 접속 테스트
curl http://agent-service-alb-xxxx.ap-northeast-2.elb.amazonaws.com/health
```

## GCP 인프라 관리

### 1. 사전 준비

**GCP는 모든 리소스를 Terraform으로 생성합니다.** 프로젝트 ID만 있으면 됩니다!

```bash
# 1. gcloud 인증
gcloud auth application-default login

# 2. 프로젝트 ID 확인
gcloud projects list

# 출력 예시:
# PROJECT_ID          NAME                PROJECT_NUMBER
# my-project-12345    My Project          123456789012

# 3. 프로젝트 설정
export GCP_PROJECT_ID="my-project-12345"
gcloud config set project $GCP_PROJECT_ID
```

**Terraform이 자동 생성할 리소스:**
- Artifact Registry (컨테이너 이미지 저장소)
- Cloud Run Services (Backend, Frontend)
- Secret Manager Secrets (API Keys 저장)
- IAM Service Accounts (Cloud Run 실행 권한)
- IAM Policy Bindings (권한 연결)

**간단합니다!** 프로젝트 ID만 있으면 `terraform apply` 한 번으로 전체 인프라가 생성됩니다.

### 2. Terraform 디렉토리 구조 생성

```bash
mkdir -p terraform/gcp
cd terraform/gcp
```

### 3. main.tf 작성

`terraform/gcp/main.tf` 파일을 생성합니다:

```hcl
# Provider 설정
terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ============================================
# Secret Manager
# ============================================

# Secret Manager Secret - OpenAI API Key
resource "google_secret_manager_secret" "openai_api_key" {
  secret_id = "openai-api-key"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Secret Manager Secret Version - OpenAI
resource "google_secret_manager_secret_version" "openai_api_key" {
  secret      = google_secret_manager_secret.openai_api_key.id
  secret_data = var.openai_api_key  # terraform.tfvars에서 입력
}

# Secret Manager Secret - Pinecone API Key
resource "google_secret_manager_secret" "pinecone_api_key" {
  secret_id = "pinecone-api-key"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Secret Manager Secret Version - Pinecone
resource "google_secret_manager_secret_version" "pinecone_api_key" {
  secret      = google_secret_manager_secret.pinecone_api_key.id
  secret_data = var.pinecone_api_key  # terraform.tfvars에서 입력
}

# ============================================
# IAM Service Account
# ============================================

# Service Account for Cloud Run
resource "google_service_account" "cloudrun" {
  account_id   = "cloudrun-sa-${var.environment}"
  display_name = "Cloud Run Service Account (${var.environment})"
  description  = "Service account for Cloud Run services"
}

# Grant Secret Manager access to Service Account
resource "google_secret_manager_secret_iam_member" "openai_access" {
  secret_id = google_secret_manager_secret.openai_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloudrun.email}"
}

resource "google_secret_manager_secret_iam_member" "pinecone_access" {
  secret_id = google_secret_manager_secret.pinecone_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloudrun.email}"
}

# ============================================
# Artifact Registry
# ============================================

# Artifact Registry Repository
resource "google_artifact_registry_repository" "main" {
  location      = var.gcp_region
  repository_id = "${var.project_name}-${var.environment}"
  description   = "Docker repository for ${var.project_name}"
  format        = "DOCKER"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ============================================
# Cloud Run Services
# ============================================

# Cloud Run Service - Backend
resource "google_cloud_run_service" "backend" {
  name     = "${var.project_name}-${var.environment}-backend"
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.cloudrun.email  # Service Account 연결

      containers {
        image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.main.repository_id}/backend:latest"

        ports {
          container_port = 8000
        }

        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }

        env {
          name = "OPENAI_API_KEY"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.openai_api_key.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "PINECONE_API_KEY"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.pinecone_api_key.secret_id
              key  = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = var.backend_cpu
            memory = var.backend_memory
          }
        }
      }

      container_concurrency = 80
      timeout_seconds       = 300
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = var.backend_min_instances
        "autoscaling.knative.dev/maxScale" = var.backend_max_instances
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  metadata {
    labels = {
      environment = var.environment
      managed_by  = "terraform"
    }
  }
}

# Cloud Run Service - Frontend
resource "google_cloud_run_service" "frontend" {
  name     = "${var.project_name}-${var.environment}-frontend"
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.cloudrun.email  # Service Account 연결

      containers {
        image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.main.repository_id}/frontend:latest"

        ports {
          container_port = 80
        }

        resources {
          limits = {
            cpu    = var.frontend_cpu
            memory = var.frontend_memory
          }
        }
      }

      container_concurrency = 80
      timeout_seconds       = 300
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = var.frontend_min_instances
        "autoscaling.knative.dev/maxScale" = var.frontend_max_instances
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  metadata {
    labels = {
      environment = var.environment
      managed_by  = "terraform"
    }
  }
}

# IAM Policy - Backend (공개 접근)
resource "google_cloud_run_service_iam_member" "backend_public" {
  service  = google_cloud_run_service.backend.name
  location = google_cloud_run_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# IAM Policy - Frontend (공개 접근)
resource "google_cloud_run_service_iam_member" "frontend_public" {
  service  = google_cloud_run_service.frontend.name
  location = google_cloud_run_service.frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

### 4. variables.tf 작성

`terraform/gcp/variables.tf` 파일을 생성합니다:

```hcl
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast3"
}

variable "project_name" {
  description = "Project name (not used in resource names, kept for compatibility)"
  type        = string
  default     = "agent-service"
}

variable "environment" {
  description = "Environment suffix for resource names (충돌 방지)"
  type        = string
  default     = "terraform"  # backend-terraform, frontend-terraform
}

# Backend 설정
variable "backend_cpu" {
  description = "Backend CPU limit"
  type        = string
  default     = "2"
}

variable "backend_memory" {
  description = "Backend memory limit"
  type        = string
  default     = "2Gi"
}

variable "backend_min_instances" {
  description = "Backend minimum instances"
  type        = string
  default     = "0"
}

variable "backend_max_instances" {
  description = "Backend maximum instances"
  type        = string
  default     = "10"
}

# Frontend 설정
variable "frontend_cpu" {
  description = "Frontend CPU limit"
  type        = string
  default     = "1"
}

variable "frontend_memory" {
  description = "Frontend memory limit"
  type        = string
  default     = "512Mi"
}

variable "frontend_min_instances" {
  description = "Frontend minimum instances"
  type        = string
  default     = "0"
}

variable "frontend_max_instances" {
  description = "Frontend maximum instances"
  type        = string
  default     = "10"
}

# API Keys (Secret Manager에 저장할 값)
variable "openai_api_key" {
  description = "OpenAI API Key (will be stored in Secret Manager)"
  type        = string
  sensitive   = true
}

variable "pinecone_api_key" {
  description = "Pinecone API Key (will be stored in Secret Manager)"
  type        = string
  sensitive   = true
}
```

### 5. outputs.tf 작성

`terraform/gcp/outputs.tf` 파일을 생성합니다:

```hcl
output "artifact_registry_url" {
  description = "Artifact Registry URL"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.main.repository_id}"
}

output "backend_url" {
  description = "Backend Cloud Run Service URL"
  value       = google_cloud_run_service.backend.status[0].url
}

output "frontend_url" {
  description = "Frontend Cloud Run Service URL"
  value       = google_cloud_run_service.frontend.status[0].url
}
```

### 6. terraform.tfvars 작성

`terraform/gcp/terraform.tfvars` 파일을 생성합니다:

```hcl
gcp_project_id = "your-gcp-project-id"
gcp_region     = "asia-northeast3"
project_name   = "agent-service"
environment    = "terraform"  # 리소스 이름: agent-service-terraform-backend

# API Keys (Secret Manager에 저장됨)
openai_api_key   = "sk-xxxxxxxxxxxxxxxxxxxx"  # 실제 OpenAI API Key
pinecone_api_key = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # 실제 Pinecone API Key

# Backend 설정 (필요시 수정)
backend_cpu           = "2"
backend_memory        = "2Gi"
backend_min_instances = "0"
backend_max_instances = "10"

# Frontend 설정
frontend_cpu           = "1"
frontend_memory        = "512Mi"
frontend_min_instances = "0"
frontend_max_instances = "10"
```

**간단합니다!** 프로젝트 ID와 API Keys만 입력하면 Terraform이 모든 리소스를 자동 생성합니다!

### 7. Terraform 실행

```bash
# 1. 초기화
terraform init

# 2. 포맷팅
terraform fmt

# 3. 유효성 검사
terraform validate

# 4. 실행 계획 확인
terraform plan

# 5. 인프라 생성
terraform apply

# 확인 프롬프트에서 'yes' 입력
```

### 8. 출력 확인

```bash
# 생성된 리소스 출력
terraform output

# 예시 출력:
# artifact_registry_url = "asia-northeast3-docker.pkg.dev/your-project-id/agent-service-terraform"
# backend_url = "https://agent-service-terraform-backend-abc123-an.a.run.app"
# frontend_url = "https://agent-service-terraform-frontend-def456-an.a.run.app"
```

### 9. 이미지 빌드 및 푸시

```bash
# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경변수 설정
export GCP_PROJECT_ID="your-project-id"
export ARTIFACT_REGISTRY="asia-northeast3-docker.pkg.dev/$GCP_PROJECT_ID/agent-service-terraform"

# Backend 이미지 빌드
docker build --platform linux/amd64 -t backend:latest ./backend

# Backend 이미지 태그
docker tag backend:latest $ARTIFACT_REGISTRY/backend:latest

# Backend 이미지 푸시
docker push $ARTIFACT_REGISTRY/backend:latest

# Frontend도 동일하게 수행
docker build --platform linux/amd64 -t frontend:latest ./frontend
docker tag frontend:latest $ARTIFACT_REGISTRY/frontend:latest
docker push $ARTIFACT_REGISTRY/frontend:latest
```

### 10. Cloud Run 서비스 업데이트

이미지를 푸시한 후, Cloud Run 서비스가 자동으로 업데이트됩니다. 강제로 재배포하려면:

```bash
# Backend 재배포 (Terraform으로 만든 서비스)
gcloud run services update agent-service-terraform-backend \
  --region asia-northeast3

# Frontend 재배포
gcloud run services update agent-service-terraform-frontend \
  --region asia-northeast3
```

### 11. 서비스 확인

```bash
# 서비스 상태 확인 (Terraform으로 만든 서비스)
gcloud run services describe agent-service-terraform-backend \
  --region asia-northeast3

gcloud run services describe agent-service-terraform-frontend \
  --region asia-northeast3

# Health check
BACKEND_URL=$(terraform output -raw backend_url)
curl $BACKEND_URL/health
```

## Terraform 주요 명령어

### 기본 워크플로우
```bash
# 1. 초기화 (최초 1회, Provider 설치)
terraform init

# 2. 포맷팅 (코드 정리)
terraform fmt

# 3. 유효성 검사
terraform validate

# 4. 실행 계획 확인 (dry-run)
terraform plan

# 5. 변경 적용
terraform apply

# 6. 특정 리소스만 적용
terraform apply -target=aws_ecs_service.backend

# 7. 리소스 삭제
terraform destroy
```

### State 관리
```bash
# State 목록 보기
terraform state list

# 특정 리소스 상태 보기
terraform state show aws_ecr_repository.backend

# State에서 리소스 제거 (실제 리소스는 유지)
terraform state rm aws_ecr_repository.backend

# State 백업
cp terraform.tfstate terraform.tfstate.backup
```

### 출력 관리
```bash
# 모든 출력 보기
terraform output

# 특정 출력만 보기
terraform output backend_ecr_url

# JSON 포맷으로 출력
terraform output -json
```

## Terraform State 관리

### State란?
- Terraform이 관리하는 인프라의 현재 상태
- `terraform.tfstate` 파일에 JSON 형식으로 저장
- **매우 중요**: 이 파일이 없으면 인프라 관리 불가능

### State 저장 위치

#### 로컬 State (기본, 학습용)
```hcl
# 별도 설정 없음 → terraform.tfstate 파일로 로컬 저장
# ⚠️ 협업 불가능, 동기화 문제, 백업 필요
```

**학습용으로는 충분하지만, 프로덕션에서는 원격 State 사용 권장**

#### 원격 State (프로덕션 권장)
```hcl
# AWS S3 Backend
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "agent-service/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"  # Lock 방지
    encrypt        = true
  }
}

# GCP GCS Backend
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "agent-service/terraform.tfstate"
  }
}
```

### State Lock
- 여러 사람이 동시에 `terraform apply` 실행 방지
- AWS: DynamoDB 테이블 사용
- GCP: 자동 Lock 지원

## 변수 관리 전략

### 1. 환경별 변수 분리
```bash
# 디렉토리 구조
terraform/aws/
├── environments/
│   ├── dev/
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── terraform.tfvars
│   └── prod/
│       └── terraform.tfvars
```

### 2. Sensitive 변수 보호
```hcl
variable "openai_api_key" {
  type      = string
  sensitive = true  # Plan/Apply 출력에서 마스킹
}
```

### 3. 환경변수 사용
```bash
# TF_VAR_ 접두사로 변수 주입
export TF_VAR_gcp_project_id="your-project-id"
terraform apply
```

## 비용 관리

### AWS 비용 추정 (Terraform으로 관리하는 리소스)
```
ECR: $0.10/GB/month (스토리지)
ECS Fargate: 사용량 기반
  - vCPU: $0.04856/vCPU/hour
  - Memory: $0.00532/GB/hour

예시) Backend 2 tasks * 0.5 vCPU * 24h * 30d = ~$35/month
```

### GCP 비용 추정 (Terraform으로 관리하는 리소스)
```
Artifact Registry: $0.10/GB/month (스토리지)
Cloud Run:
  - vCPU: $0.00002400/vCPU-second
  - Memory: $0.00000250/GiB-second
  - Requests: $0.40/million requests
무료 할당량: 월 200만 요청, 36만 vCPU-second
```

### 비용 최적화 팁
1. **개발 환경**: 필요 시에만 인프라 생성
   ```bash
   # 작업 시작
   terraform apply

   # 작업 완료 후 삭제
   terraform destroy
   ```

2. **Auto Scaling 활용**: 트래픽에 따라 자동 조절
3. **리소스 크기 최적화**: 필요한 만큼만 할당

## 트러블슈팅

### State Lock 에러
```
Error: Error acquiring the state lock
```
**해결**:
```bash
# Lock 강제 해제 (주의: 다른 사람이 실행 중이 아닌지 확인!)
terraform force-unlock LOCK_ID
```

### Provider 버전 충돌
```
Error: Incompatible provider version
```
**해결**:
```bash
# .terraform 디렉토리 삭제 후 재초기화
rm -rf .terraform
terraform init
```

### 변수 누락 에러
```
Error: No value for required variable
```
**해결**:
```bash
# terraform.tfvars 파일 확인
cat terraform.tfvars

# 또는 명령줄에서 직접 전달
terraform apply -var="gcp_project_id=your-project-id"
```

### ECR/Artifact Registry에 이미지가 없음
```
Error: The specified image does not exist
```
**해결**:
```bash
# 먼저 이미지를 푸시한 후 Terraform apply
docker push $ECR_URL/backend:latest
terraform apply
```

### 기존 리소스 충돌
```
Error: Resource already exists
```
**본 강의에서는 발생하지 않음** (environment 변수로 다른 이름 사용: backend-tf)

**만약 발생한다면**:
```bash
# 옵션 1: 다른 이름 사용 (권장 - 본 강의 방식)
# terraform.tfvars에서 environment 변경

# 옵션 2: 기존 리소스를 Terraform State로 import (고급)
terraform import aws_ecr_repository.backend agent-service-backend
```

## 모범 사례

### 1. 점진적 IaC 도입
- **시작**: 간단한 리소스부터 (ECR, Task Definition)
- **확장**: 안정화 후 더 많은 리소스 추가
- **완성**: 전체 인프라를 Terraform으로 관리

### 2. 변수 검증
```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

### 3. 리소스 태깅
```hcl
tags = {
  Project     = "RAG-Demo"
  Environment = var.environment
  ManagedBy   = "Terraform"
  Team        = "Platform"
}
```

### 4. 코드 리뷰
```bash
# 포맷 자동 수정
terraform fmt -recursive

# 유효성 검사
terraform validate

# Plan 결과 공유
terraform plan -out=tfplan
```

### 5. 문서화
```hcl
# 변수에 설명 추가
variable "backend_cpu" {
  description = "Backend task CPU units. 512 = 0.5 vCPU, 1024 = 1 vCPU."
  type        = string
  default     = "512"
}
```

## Terraform vs 수동 배포 비교

| 항목 | 수동 배포 (Section 3-4) | Terraform (Section 5) |
|------|-------------------------|------------------------|
| 재현성 | ❌ 매번 다를 수 있음 | ✅ 100% 재현 가능 |
| 협업 | ❌ 문서화 어려움 | ✅ 코드로 공유 |
| 롤백 | ❌ 수동으로 되돌리기 | ✅ 이전 버전 적용 |
| 변경 추적 | ❌ 어려움 | ✅ Git으로 추적 |
| 리소스 정리 | ❌ 수동으로 하나씩 | ✅ `terraform destroy` |
| 테스트 | ❌ 프로덕션에서만 | ✅ 격리된 환경 생성 |
| 속도 | ⚠️ 느림 (많은 클릭) | ✅ 빠름 (자동화) |
| 학습 곡선 | ✅ 쉬움 | ⚠️ 중간 |

## 실무 적용 전략

### 1단계: 간단한 리소스부터 시작
- ✅ ECR, Artifact Registry
- ✅ Task Definition, Cloud Run Service

### 2단계: 애플리케이션 설정 추가
- ✅ 환경 변수 관리
- ✅ Secret 참조
- ✅ Auto Scaling 설정

### 3단계: 네트워크 인프라 추가 (선택)
- ⚠️ VPC, Subnet (필요한 경우에만)
- ⚠️ Load Balancer
- ⚠️ Security Groups

### 4단계: 고급 기능
- 📊 모니터링 (CloudWatch, Cloud Monitoring)
- 🔔 알림 (SNS, Cloud Pub/Sub)
- 🔐 보안 감사 (AWS Config, Cloud Security)

## 다음 단계

Section 5를 완료했다면:
- ✅ Terraform으로 간단한 리소스를 코드로 관리하는 방법 습득
- ✅ 기존 인프라를 재사용하면서 점진적으로 IaC 도입
- ✅ State 관리 및 협업 전략 이해
- ✅ 실무에서 적용 가능한 실용적 접근법 학습

**Section 6 예고**: GitHub Actions를 이용한 CI/CD 파이프라인
- 코드 푸시 → 자동 테스트 → 자동 빌드 → 자동 배포
- Terraform과 CI/CD 통합
- 안전한 배포 전략

## 완료 체크리스트
- [ ] Terraform이 설치되었는가?
- [ ] 기존 AWS 리소스를 확인하고 변수 파일에 입력했는가?
- [ ] AWS 인프라가 Terraform으로 관리되는가?
- [ ] GCP 인프라가 Terraform으로 관리되는가?
- [ ] Terraform State 파일의 중요성을 이해했는가?
- [ ] 환경별 변수 관리 전략을 적용했는가?
- [ ] `terraform plan`과 `terraform apply`의 차이를 이해했는가?
- [ ] 비용 관리 전략을 수립했는가?
- [ ] 인프라 변경 사항을 Git으로 추적하고 있는가?
- [ ] `terraform destroy`로 리소스를 정리할 수 있는가?
- [ ] 점진적 IaC 도입 전략을 이해했는가?
