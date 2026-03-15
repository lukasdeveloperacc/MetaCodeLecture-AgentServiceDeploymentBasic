# Section 5: Terraform 기반 Infrastructure as Code (IaC)

## 학습 목표
- **Section 3/4 수동 배포를 Terraform 코드로 전환**하여 IaC의 실용성 체험
- Terraform 기초 개념 완전 이해 (Provider, Resource, Variable, State)
- `terraform apply` 한 번으로 전체 인프라 자동 생성
- 코드로 인프라를 관리하는 실무 패턴 습득
- **AWS와 GCP 멀티 클라우드 배포** 경험을 통한 클라우드 중립적 사고 배양
- 각 클라우드의 장단점 비교 및 프로젝트 상황별 선택 능력 배양

## 📊 Section 3 vs Section 5: 왜 Terraform인가?

| 작업 | Section 3 (수동 배포) | Section 5 (Terraform) |
|------|----------------------|----------------------|
| **ECR 생성** | Console 클릭 → 이름 입력 → 생성 | `resource "aws_ecr_repository"` (5줄) |
| **Task Definition** | JSON 작성 → CLI 등록 → 버전 관리 복잡 | `resource "aws_ecs_task_definition"` (30줄) |
| **ALB 생성** | Console 10단계 클릭 → 15분 소요 | `resource "aws_lb"` (10줄) |
| **Security Group** | 규칙 하나씩 클릭 추가 | 코드로 명확히 정의 |
| **재현성** | ❌ 문서 보고 다시 클릭 (휴먼 에러 발생) | ✅ `terraform apply` (100% 동일) |
| **롤백** | ❌ 수동으로 하나씩 삭제 | ✅ `terraform destroy` (10초) |
| **변경 추적** | ❌ "누가 언제 뭘 바꿨지?" | ✅ Git 커밋 이력으로 추적 |
| **협업** | ❌ 문서화 어려움 | ✅ 코드 리뷰, PR |
| **속도** | ⏱️ 30-60분 (클릭 반복) | ⚡ 5-10분 (자동화) |

### 실무에서는?
- **개발 환경**: Terraform으로 생성/삭제 반복 → 비용 절감
- **스테이징/프로덕션**: Terraform으로 동일한 구성 재현 → 환경 일관성 보장
- **인프라 변경**: PR 리뷰 → 승인 → terraform apply → 안전한 배포

---

# Part 1: AWS Terraform 배포

이 섹션에서는 **AWS ECS/Fargate + ALB**를 Terraform으로 배포합니다.
Section 3에서 수동으로 구축했던 인프라를 코드로 자동화하는 과정을 배웁니다.

## 🗂️ Terraform 파일 구조

Section 5에서 새로 추가된 파일들:

```
terraform/aws/
  ├── main.tf                   # Provider 설정 (10줄)
  ├── data.tf                   # Data Sources - Secret ARN 자동 조회 (40줄)
  ├── iam.tf                    # IAM Roles (80줄)
  ├── ecr.tf                    # ECR Repositories (30줄)
  ├── cloudwatch.tf             # Log Groups (20줄)
  ├── network.tf                # Security Groups, Dual ALB, Target Groups (350줄)
  ├── ecs.tf                    # Cluster, Task Definitions, Services (200줄)
  ├── variables.tf              # 변수 정의
  ├── outputs.tf                # 출력 정의
  └── terraform.tfvars.example  # 변수 값 예시

aws/scripts/
  └── get_vpc_info.sh           # VPC 자동 확인 스크립트
```

**파일 분리 이유**:
- **가독성**: 각 파일이 명확한 역할 (iam.tf = IAM만, network.tf = 네트워크만)
- **유지보수**: 수정 시 해당 파일만 편집
- **실무 패턴**: 팀 협업 시 파일별로 책임 분담

## 🎯 Terraform이 생성할 리소스

### ✅ Terraform으로 생성
- **ECR Repository**: backend-tf, frontend-tf
- **IAM Roles**: ecsTaskExecutionRole-tf, ecsTaskRole-tf
- **CloudWatch Log Groups**: /ecs/backend-tf, /ecs/frontend-tf
- **Security Groups**: frontend-alb-sg-tf, backend-alb-sg-tf, backend-sg-tf, frontend-sg-tf
- **ALB**: frontend-alb-tf, backend-alb-tf (Dual ALB 아키텍처, Section 3와 동일)
- **Target Groups**: frontend-tg-tf, backend-tg-tf
- **Listeners**: frontend-http, backend-http
- **ECS Cluster**: agent-cluster-tf
- **ECS Task Definitions**: backend-tf, frontend-tf
- **ECS Services**: backend-tf-service, frontend-tf-service

### ♻️ Section 3 리소스 재사용
- **VPC/Subnets만 재사용** (기본 VPC)
- 이유: VPC는 한번 설정 후 거의 변경 안 함 + 네트워크 기초 개념 불필요

**리소스 충돌 방지**:
- Section 3: `backend`, `frontend`, `agent-cluster`
- Section 5: `backend-tf`, `frontend-tf`, `agent-cluster-tf`
→ 이름이 달라서 공존 가능!

## 📚 Terraform 핵심 개념

### 1. Provider
클라우드 제공자 (AWS, GCP, Azure 등)와 통신하는 플러그인

```hcl
# main.tf
provider "aws" {
  region = "ap-northeast-2"
}
```

### 2. Resource
생성할 인프라 리소스

```hcl
# ecr.tf
resource "aws_ecr_repository" "backend" {
  name = "backend-tf"
  # ...
}
```

### 3. Variable
재사용 가능한 변수

```hcl
# variables.tf
variable "aws_region" {
  default = "ap-northeast-2"
}

# 사용: var.aws_region
```

### 4. Output
terraform apply 후 출력할 정보

```hcl
# outputs.tf
output "alb_dns_name" {
  value = aws_lb.main.dns_name
}
```

### 5. State
현재 인프라 상태를 추적하는 파일 (`terraform.tfstate`)

- **매우 중요**: 이 파일이 없으면 Terraform이 리소스를 관리할 수 없음
- **로컬 저장** (학습용): terraform.tfstate 파일
- **원격 저장** (팀 협업 시): S3 + DynamoDB (State Lock)

## 🚀 실습: 3단계로 완성하는 Terraform 배포

### Step 1: 사전 준비 및 VPC 정보 확인

#### 1-1. Terraform 설치

**macOS**:
- https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli

```bash
# Homebrew 이용
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 설치 확인
terraform version
```

#### 1-2. VPC 정보 자동 확인 (간편 방법)

**자동 스크립트 실행**:
```bash
bash aws/scripts/get_vpc_info.sh
```

**스크립트가 하는 일**:
1. 기본 VPC ID 자동 확인
2. Public Subnet IDs 자동 확인 (최소 2개 AZ)
3. `terraform/aws/terraform.tfvars` 파일 자동 생성
4. 다음 단계 안내

**출력 예시**:
```
🔍 AWS 기본 VPC 정보를 확인합니다...
📍 리전: ap-northeast-2

1️⃣  기본 VPC 확인 중...
✅ VPC ID: vpc-0123456789abcdef0

2️⃣  Public Subnet 확인 중 (ALB는 최소 2개 AZ 필요)...
  - subnet-0123456789abcdef0 (ap-northeast-2a, 10.0.1.0/24)
  - subnet-0123456789abcdef1 (ap-northeast-2c, 10.0.2.0/24)

✅ Subnet 수: 2 (충분함)

3️⃣  terraform.tfvars 파일 생성 중...
✅ 생성 완료: /path/to/project/terraform/aws/terraform.tfvars
```

#### 1-3. terraform.tfvars 파일 확인

스크립트가 생성한 `terraform/aws/terraform.tfvars` 파일을 열어서 **Secret 이름 확인**:

```bash
vi terraform/aws/terraform.tfvars
```

**확인할 부분**:
```hcl
# Section 3에서 생성한 Secret 이름 (기본값: dev/openai-api-key, dev/pinecone-api-key)
# 💡 Terraform이 자동으로 ARN을 조회하므로 이름만 확인하면 됩니다!
openai_secret_name   = "dev/openai-api-key"
pinecone_secret_name = "dev/pinecone-api-key"
```

**Secret 이름이 다르다면 확인 후 수정**:
```bash
# Section 3에서 생성한 Secret 이름 확인
aws secretsmanager list-secrets \
  --region ap-northeast-2 \
  --query 'SecretList[*].Name' \
  --output table

# 출력 예시:
# ---------------------
# |   ListSecrets     |
# +-------------------+
# | dev/openai-api-key|
# | dev/pinecone-api-key|
# +-------------------+
```

**💡 장점**:
- ARN 대신 이름만 입력하면 됨 (더 간단!)
- Terraform이 자동으로 ARN 조회 (Data Source 활용)
- Secret 이름만 맞으면 어떤 리전/계정에서도 동작

---

### Step 2: Terraform 실행

#### 2-1. 초기화 (Provider 다운로드)

```bash
cd terraform/aws
terraform init
```

**출력 예시**:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.75.0...
✅ Terraform has been successfully initialized!
```

#### 2-2. 포맷팅 (코드 정리)

```bash
terraform fmt
```

코드 스타일을 자동으로 정리합니다.

#### 2-3. 유효성 검사

```bash
terraform validate
```

**출력**:
```
✅ Success! The configuration is valid.
```

#### 2-4. 실행 계획 확인 (Dry-Run)

```bash
terraform plan
```

**출력 예시**:
```
Terraform will perform the following actions:

  # aws_cloudwatch_log_group.backend will be created
  + resource "aws_cloudwatch_log_group" "backend" {
      + name = "/ecs/backend-tf"
      ...
    }

  # aws_ecr_repository.backend will be created
  + resource "aws_ecr_repository" "backend" {
      + name = "backend-tf"
      ...
    }

  # ... (총 21개 리소스 - Dual ALB 아키텍처)

Plan: 21 to add, 0 to change, 0 to destroy.
```

**확인 사항**:
- 생성될 리소스 수 (약 21개 - Dual ALB 아키텍처)
- 리소스 이름이 `-tf` suffix가 붙어 있는지 확인
- `0 to change, 0 to destroy` 확인 (기존 리소스 영향 없음)

#### 2-5. 인프라 생성!

```bash
terraform apply
```

**출력**:
```
Plan: 19 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

**`yes` 입력** → ⏱️ 약 3-5분 대기

**완료 출력**:
```
Apply complete! Resources: 21 added, 0 changed, 0 destroyed.

Outputs:

backend_alb_dns_name = "backend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com"
backend_ecr_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend-tf"
frontend_alb_dns_name = "frontend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com"
frontend_ecr_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/frontend-tf"
...
```

#### 2-6. 생성된 리소스 확인

**Terraform 출력 확인**:
```bash
terraform output
```

**AWS Console 확인**:
1. **ECR**: Console > ECR > Repositories > `backend-tf`, `frontend-tf` 확인
2. **ECS**: Console > ECS > Clusters > `agent-cluster-tf` 확인
3. **ALB**: Console > EC2 > Load Balancers > `frontend-alb-tf`, `backend-alb-tf` 확인 (Dual ALB)
4. **CloudWatch**: Console > CloudWatch > Log Groups > `/ecs/backend-tf` 확인

---

### Step 3: 이미지 빌드/푸시 및 배포

#### 3-1. ECR 로그인

```bash
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com
```

**출력**: `Login Succeeded`

#### 3-2. docker-compose로 이미지 빌드 및 푸시

**환경 변수 설정**:
```bash
# 프로젝트 루트로 이동
cd ../..

# AWS 계정 ID 및 리전 설정
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-northeast-2

# docker-compose를 위한 이미지 URL 설정
export BACKEND_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/backend-tf:latest"
export FRONTEND_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/frontend-tf:latest"

# 설정 확인
echo "Backend Image: $BACKEND_IMAGE"
echo "Frontend Image: $FRONTEND_IMAGE"
```

**docker-compose로 빌드 및 푸시**:
```bash
# Backend와 Frontend 동시 빌드
docker-compose build

# Backend와 Frontend 동시 푸시
docker-compose push
```

**💡 작동 원리**:
- `docker-compose.yml`은 `${BACKEND_IMAGE}`, `${FRONTEND_IMAGE}` 환경 변수 사용
- AWS/GCP 환경에 따라 다른 레지스트리 URL 설정 가능
- 로컬 개발 시에는 기본값(`backend:latest`, `frontend:latest`) 사용

**💡 장점**:
- 한 번의 명령으로 모든 서비스 빌드/푸시
- docker-compose.yml에서 이미지 URL 중앙 관리
- Section 2에서 배운 docker-compose 지식 활용

**개별 서비스만 빌드/푸시하려면**:
```bash
# Backend만
docker-compose build backend
docker-compose push backend

# Frontend만
docker-compose build frontend
docker-compose push frontend
```

**💡 Tip**: `terraform output backend_ecr_url`로 ECR URL 확인 가능

#### 3-3. ECS Service 강제 재배포

이미지를 푸시한 후, ECS가 새 이미지를 사용하도록 강제 재배포:

```bash
# Backend Service 재배포
aws ecs update-service \
  --cluster agent-cluster-tf \
  --service backend-tf-service \
  --force-new-deployment \
  --region ap-northeast-2

# Frontend Service 재배포
aws ecs update-service \
  --cluster agent-cluster-tf \
  --service frontend-tf-service \
  --force-new-deployment \
  --region ap-northeast-2
```

#### 3-4. 배포 상태 확인

```bash
# Service 상태 확인
aws ecs describe-services \
  --cluster agent-cluster-tf \
  --services backend-tf-service frontend-tf-service \
  --region ap-northeast-2 \
  --query 'services[*].[serviceName,status,runningCount,desiredCount]' \
  --output table
```

**출력 예시**:
```
-------------------------------------------
|          DescribeServices             |
+----------------------+--------+---+----+
| backend-tf-service   | ACTIVE | 2 | 2  |
| frontend-tf-service  | ACTIVE | 2 | 2  |
+----------------------+--------+---+----+
```

#### 3-5. Dual ALB로 서비스 접속

```bash
# Frontend ALB DNS Name 확인
terraform output frontend_alb_dns_name
# 출력: frontend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com

# Backend ALB DNS Name 확인
terraform output backend_alb_dns_name
# 출력: backend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com

# 브라우저 접속
# Frontend 접속
open http://frontend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com

# Backend API 접속
curl http://backend-alb-tf-1234567890.ap-northeast-2.elb.amazonaws.com/health
```

**확인 사항**:
- Frontend ALB로 Frontend 페이지가 로드되는지
- Backend ALB로 `/health` 엔드포인트가 `{"status": "healthy"}` 응답하는지
- **Section 3와 동일한 Dual ALB 아키텍처**로 서비스가 완전히 분리되어 있는지

---

## 📊 Terraform 주요 명령어

### 기본 워크플로우
```bash
terraform init      # Provider 다운로드 (최초 1회)
terraform fmt       # 코드 포맷팅
terraform validate  # 문법 검사
terraform plan      # 실행 계획 확인 (dry-run)
terraform apply     # 변경 적용
terraform destroy   # 모든 리소스 삭제
```

### 유용한 명령어
```bash
# 특정 리소스만 적용
terraform apply -target=aws_ecs_service.backend

# 변경 사항 미리보기 (파일로 저장)
terraform plan -out=tfplan

# 저장된 플랜 적용
terraform apply tfplan

# State 목록 보기
terraform state list

# 특정 리소스 상태 보기
terraform state show aws_ecr_repository.backend

# 출력 값 확인
terraform output
terraform output backend_ecr_url
```

## 🔄 Terraform State 관리

### State란?
- 현재 인프라 상태를 추적하는 JSON 파일 (`terraform.tfstate`)
- **매우 중요**: 이 파일이 없으면 Terraform이 리소스를 관리할 수 없음!
- **민감 정보 포함**: Resource IDs, Secret ARNs (자동 조회된 값) 등

### 로컬 State (학습용)
```bash
# 기본값: terraform.tfstate 파일로 로컬 저장
# ✅ 간편함
# ❌ 협업 불가능
# ❌ 백업 필요
```

**백업 방법**:
```bash
cp terraform.tfstate terraform.tfstate.backup
```

### 원격 State (팀 협업 시 권장)
```hcl
# main.tf에 추가
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "agent-service/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"  # State Lock (동시 수정 방지)
    encrypt        = true
  }
}
```

**장점**:
- ✅ 팀원 모두 같은 State 공유
- ✅ 동시 수정 방지 (State Lock)
- ✅ 자동 백업 (S3 버전 관리)

## 🛠️ 트러블슈팅

### 1. VPC를 찾을 수 없음
**증상**: `Error: No default VPC found`

**해결**:
```bash
# VPC 확인
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true"

# 없으면 새로 생성하거나 기존 VPC ID를 terraform.tfvars에 직접 입력
```

### 2. Subnet 수 부족
**증상**: `Error: At least 2 subnets in different AZs are required`

**해결**:
```bash
# Subnet 확인
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output table

# terraform.tfvars에 서로 다른 AZ의 Subnet 2개 이상 입력
```

### 3. Secret을 찾을 수 없음
**증상**: `Error: no matching Secrets Manager secret found`

**원인**: Secret 이름이 잘못되었거나 Section 3에서 Secret을 생성하지 않음

**해결**:
```bash
# 1. Secret 이름 확인
aws secretsmanager list-secrets \
  --region ap-northeast-2 \
  --query 'SecretList[*].Name'

# 2. Secret이 없다면 Section 3 문서를 참고하여 생성
aws secretsmanager create-secret \
  --name dev/openai-api-key \
  --secret-string "your-openai-api-key"

# 3. terraform.tfvars에 정확한 Secret 이름 입력
openai_secret_name = "dev/openai-api-key"
```

### 4. ECR 이미지가 없음
**증상**: `Error: CannotPullContainerError: pull image manifest has been retried`

**원인**: Terraform이 Task Definition을 생성했지만, ECR에 이미지가 아직 없음

**해결**:
```bash
# 1. 이미지 푸시 (Step 3-2, 3-3)
docker push <ECR_URL>:latest

# 2. Service 강제 재배포
aws ecs update-service --cluster agent-cluster-tf \
  --service backend-tf-service \
  --force-new-deployment
```

### 5. State Lock 에러
**증상**: `Error: Error acquiring the state lock`

**원인**: 다른 사람이 terraform apply 중이거나, 이전 실행이 비정상 종료됨

**해결**:
```bash
# 다른 사람이 실행 중인지 확인 후, 안전하면 Lock 강제 해제
terraform force-unlock <LOCK_ID>
```

### 6. 리소스 이미 존재
**증상**: `Error: Resource already exists`

**원인**: Section 3에서 만든 리소스와 이름 충돌

**해결**:
- `terraform.tfvars`에서 `environment = "tf"` 확인
- 리소스 이름이 `-tf` suffix가 붙는지 확인 (`backend-tf`, not `backend`)

## 🧹 리소스 정리

### 전체 삭제
```bash
cd terraform/aws
terraform destroy
```

**출력**:
```
Plan: 0 to add, 0 to change, 19 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes
```

**⏱️ 약 5-10분 소요**

### 특정 리소스만 삭제
```bash
terraform destroy -target=aws_ecs_service.backend
```

### 삭제 확인
```bash
# State에 리소스가 없는지 확인
terraform state list
# 출력: (비어 있음)

# AWS Console에서도 확인
```

## 💰 비용 관리

### Terraform으로 생성한 리소스 비용 (서울 리전)

| 리소스 | 비용 | 설명 |
|--------|------|------|
| ECR | $0.10/GB/월 | 이미지 스토리지 |
| ECS Fargate (Backend) | ~$35/월 | 2 tasks × 0.5 vCPU × 1 GB × 24h × 30d |
| ECS Fargate (Frontend) | ~$9/월 | 2 tasks × 0.25 vCPU × 512 MB × 24h × 30d |
| ALB | ~$27/월 | ALB 운영 비용 + 데이터 처리 |
| CloudWatch Logs | ~$1/월 | 로그 저장 (7일 보관) |
| **Total** | **~$72/월** | 상시 운영 시 |

### 비용 절감 팁

**1. 개발 환경은 사용 시에만 생성**:
```bash
# 작업 시작
terraform apply

# 작업 종료
terraform destroy  # ← 비용 0원!
```

**2. Desired Count 조정**:
```hcl
# terraform.tfvars
backend_desired_count  = 1  # 2 → 1 (50% 절감)
frontend_desired_count = 1
```

**3. Auto Scaling 비활성화** (개발 환경):
- 고정 Task 수로 운영 → 예측 가능한 비용

---

# Part 2: GCP Terraform 배포

이 섹션에서는 **GCP Cloud Run**을 Terraform으로 배포합니다.
Section 4에서 수동으로 구축했던 서버리스 인프라를 코드로 자동화하는 과정을 배웁니다.

## 🌟 왜 GCP도 배우는가?

### AWS vs GCP 아키텍처 차이

**AWS (ECS/Fargate + ALB)**:
- VPC, Subnet, Security Group 설정 필요
- ALB + Target Group + Listener 구성
- ECS Cluster + Task Definition + Service 생성
- 총 **8개 이상의 리소스** 관리 필요

**GCP (Cloud Run)**:
- **단 하나의 리소스**로 모든 기능 제공
- VPC, Load Balancer 등 인프라 관리 불필요
- 완전 서버리스, 자동 스케일링 (0 ↔ N)
- HTTPS 자동 제공

### 핵심 차이점

| 항목 | AWS (ECS/Fargate) | GCP (Cloud Run) |
|------|-------------------|-----------------|
| **인프라 복잡도** | 높음 (VPC, ALB, SG 등) | 낮음 (서비스 1개) |
| **네트워크 관리** | 수동 (Subnet, SG) | 자동 (완전 관리형) |
| **로드 밸런서** | ALB 필수 | 자동 제공 |
| **HTTPS** | Certificate Manager 설정 | 자동 제공 |
| **스케일링** | 고정 Task 수 (desired_count) | 자동 (0↔N, min/max) |
| **비용** | 상시 운영 (~$72/월) | 사용량 기반 (~$10/월) |
| **설정 변수** | 10개+ (VPC, Subnet 등) | 4개 (project_id만 필수) |
| **리소스 수** | 21개 (Dual ALB) | 4개 |

### Cloud Run의 특징

1. **완전 서버리스**: 요청 없을 때 0으로 축소 → 비용 0원
2. **자동 스케일링**: 트래픽 증가 시 자동 확장 (최대 100개)
3. **자동 HTTPS**: Let's Encrypt 인증서 자동 발급
4. **자동 로드밸런싱**: 여러 인스턴스 간 트래픽 자동 분산
5. **간단한 배포**: 이미지 푸시 시 자동 감지 및 재배포

## 🗂️ Terraform 파일 구조

GCP Terraform 파일들 (`terraform/gcp/`):

```
terraform/gcp/
├── main.tf                     # GCP Provider 설정
├── variables.tf                # 변수 정의
├── artifact-registry.tf        # Container Registry (AWS ECR과 유사)
├── cloud-run.tf                # Backend/Frontend 서비스
├── iam.tf                      # Secret Manager 권한
├── outputs.tf                  # 출력 정의
└── terraform.tfvars.example    # 변수 값 예시
```

### AWS vs GCP 파일 비교

| AWS 파일 | GCP 파일 | 설명 |
|----------|----------|------|
| `ecr.tf` | `artifact-registry.tf` | 컨테이너 레지스트리 |
| `ecs.tf` + `network.tf` | `cloud-run.tf` | 컴퓨트 + 네트워크 통합 |
| `iam.tf` | `iam.tf` | IAM 권한 |
| `cloudwatch.tf` | ❌ 불필요 | Cloud Run이 자동 로깅 |
| `network.tf` (ALB, SG) | ❌ 불필요 | Cloud Run이 자동 제공 |

GCP가 **3개 파일 적음** → 더 간단한 인프라!

## 🎯 Terraform이 생성할 GCP 리소스

### ✅ Terraform으로 생성

1. **Artifact Registry Repository** (`agent-tf`)
   - Docker 이미지 저장소 (AWS ECR과 동일)

2. **Cloud Run Services** (2개)
   - `backend-tf`: FastAPI 백엔드 서비스
   - `frontend-tf`: Nginx 프론트엔드 서비스

3. **IAM Policy Bindings** (2개)
   - Secret Manager 접근 권한
   - Public 접근 허용 (allUsers)

**총 4개 리소스** (AWS 19개 vs GCP 4개)

### ♻️ Section 4 리소스 재사용

- **Secret Manager Secrets**: Section 4에서 생성한 `openai-api-key`, `pinecone-api-key` 재사용
- 이유: Secret은 한번 생성 후 여러 서비스에서 공유

## 📚 GCP Terraform 핵심 개념

### 1. Provider

```hcl
# main.tf
provider "google" {
  project = var.project_id
  region  = var.region
}
```

AWS와 달리 **Project ID**가 필수입니다.

### 2. Resource - Artifact Registry

```hcl
# artifact-registry.tf
resource "google_artifact_registry_repository" "agent" {
  repository_id = "agent-tf"
  location      = var.region
  format        = "DOCKER"
}
```

AWS ECR과 동일한 역할의 컨테이너 레지스트리

### 3. Resource - Cloud Run

```hcl
# cloud-run.tf
resource "google_cloud_run_v2_service" "backend" {
  name     = "backend-tf"
  location = var.region

  template {
    scaling {
      min_instance_count = 0  # 완전 서버리스!
      max_instance_count = 10
    }

    containers {
      image = "..."

      env {
        name  = "ENVIRONMENT"
        value = "development"
      }

      env {
        name = "OPENAI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "openai-api-key"  # Secret 이름만 참조
            version = "latest"
          }
        }
      }
    }
  }
}
```

AWS ECS + ALB + Auto Scaling을 **하나의 리소스**로!

### 4. Variable

```hcl
# variables.tf
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "backend_min_instances" {
  description = "최소 인스턴스 (0 = 완전 서버리스)"
  type        = number
  default     = 0
}
```

### 5. Output

```hcl
# outputs.tf
output "backend_url" {
  description = "Backend Service URL"
  value       = google_cloud_run_v2_service.backend.uri
  # 예시: https://backend-tf-xxxxx-an.a.run.app
}
```

HTTPS URL이 자동으로 제공됩니다!

## 🚀 실습: 3단계로 완성하는 GCP Terraform 배포

### Step 1: 사전 준비 및 Project 정보 확인

#### 1-1. gcloud CLI 설치 확인

**macOS/Linux**:
```bash
# 설치 확인
gcloud version

# 설치 안 되어 있다면: https://cloud.google.com/sdk/docs/install
```

**인증 및 프로젝트 설정**:
```bash
# 로그인
gcloud auth login

# 프로젝트 설정
gcloud config set project YOUR_PROJECT_ID

# 현재 프로젝트 확인
gcloud config get-value project

# Application Default Credentials 설정 (Terraform용 - 필수!)
gcloud auth application-default login

# 브라우저 인증 문제 발생 시:
# gcloud auth application-default login --no-browser
# → 출력된 URL을 브라우저에 복사 → 인증 코드 복사 → 터미널에 붙여넣기

# 인증 성공 확인
gcloud auth application-default print-access-token
```

**💡 중요**:
- `gcloud auth login`: gcloud 명령어용 인증
- `gcloud auth application-default login`: **Terraform/SDK용 인증 (필수!)**

#### 1-1-1. 필수 API 활성화

**⚠️ 중요**: GCP는 보안상 모든 API가 기본적으로 비활성화되어 있습니다.
Terraform 실행 전에 필요한 API를 **반드시** 활성화해야 합니다!

**명령어 한 번에 활성화**:
```bash
# 필요한 모든 API 활성화
gcloud services enable \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com

# API 활성화 완료 대기 (약 1-2분)
echo "⏳ API 활성화 중... 잠시 대기해주세요 (1-2분)"
sleep 120

# 활성화 확인
gcloud services list --enabled | grep -E "compute|artifact|run|secret"
```

**출력 예시**:
```
compute.googleapis.com              Compute Engine API
artifactregistry.googleapis.com     Artifact Registry API
run.googleapis.com                  Cloud Run Admin API
secretmanager.googleapis.com        Secret Manager API
cloudresourcemanager.googleapis.com Cloud Resource Manager API
iam.googleapis.com                  Identity and Access Management (IAM) API
```

**왜 필요한가?**
- **Compute Engine API** → 기본 서비스 계정 생성 (`PROJECT_NUMBER-compute@...`)
- **Artifact Registry API** → Docker 이미지 저장소 생성
- **Cloud Run API** → 서비스 배포
- **Secret Manager API** → API 키 안전 관리

**⚠️ 주의**: API 활성화 없이 `terraform apply`를 실행하면 에러 발생!

#### 1-2. terraform.tfvars 파일 생성

**자동 생성 (권장)**:
```bash
cd terraform/gcp

# 예시 파일 복사
cp terraform.tfvars.example terraform.tfvars

# 편집
vi terraform.tfvars
```

**terraform.tfvars 내용 수정**:
```hcl
# GCP Project ID (필수! 실제 프로젝트 ID로 교체)
project_id = "your-gcp-project-id"  # gcloud config get-value project로 확인

# 리전 (서울 = asia-northeast3)
region = "asia-northeast3"

# 프로젝트 정보
project_name = "agent-service"
environment  = "tf"

# Secret Manager 시크릿 이름 (Section 4에서 생성한 이름)
openai_secret_name   = "openai-api-key"
pinecone_secret_name = "pinecone-api-key"
pinecone_index_name  = "ai-service-docs-dev"

# Backend 리소스 (기본값 사용 가능)
backend_cpu            = "2"
backend_memory         = "2Gi"
backend_min_instances  = 0    # 완전 서버리스
backend_max_instances  = 10

# Frontend 리소스
frontend_cpu           = "1"
frontend_memory        = "512Mi"
frontend_min_instances = 0
frontend_max_instances = 5
```

#### 1-3. Secret 존재 확인

Section 4에서 생성한 Secret이 있는지 확인:

```bash
# Secret 목록 확인
gcloud secrets list

# 출력 예시:
# NAME                CREATE_TIME          REPLICATION_POLICY  LOCATIONS
# openai-api-key      2024-03-01T...       automatic           -
# pinecone-api-key    2024-03-01T...       automatic           -
```

**Secret이 없다면 생성**:
```bash
# OpenAI API Key
echo -n "your-openai-api-key" | gcloud secrets create openai-api-key --data-file=-

# Pinecone API Key
echo -n "your-pinecone-api-key" | gcloud secrets create pinecone-api-key --data-file=-
```

---

### Step 2: Terraform 실행

#### 2-1. 초기화 (Provider 다운로드)

```bash
cd terraform/gcp
terraform init
```

**출력 예시**:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 5.0"...
- Installing hashicorp/google v5.75.0...
✅ Terraform has been successfully initialized!
```

#### 2-2. 유효성 검사

```bash
terraform validate
```

**출력**:
```
✅ Success! The configuration is valid.
```

#### 2-3. 실행 계획 확인 (Dry-Run)

```bash
terraform plan
```

**출력 예시**:
```
Terraform will perform the following actions:

  # google_artifact_registry_repository.agent will be created
  + resource "google_artifact_registry_repository" "agent" {
      + repository_id = "agent-tf"
      + location      = "asia-northeast3"
      + format        = "DOCKER"
      ...
    }

  # google_cloud_run_v2_service.backend will be created
  + resource "google_cloud_run_v2_service" "backend" {
      + name     = "backend-tf"
      + location = "asia-northeast3"
      ...
    }

  # ... (총 4개 리소스)

Plan: 4 to add, 0 to change, 0 to destroy.
```

**확인 사항**:
- 생성될 리소스 수: **4개** (AWS 21개 대비 훨씬 적음!)
- `0 to change, 0 to destroy` 확인 (기존 리소스 영향 없음)

#### 2-4. 인프라 생성!

```bash
terraform apply
```

**출력**:
```
Plan: 4 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

**`yes` 입력** → ⏱️ 약 2-3분 대기

**완료 출력**:
```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

artifact_registry_url = "asia-northeast3-docker.pkg.dev/your-project/agent-tf"
backend_image_url = "asia-northeast3-docker.pkg.dev/your-project/agent-tf/backend:latest"
backend_url = "https://backend-tf-xxxxx-an.a.run.app"
frontend_url = "https://frontend-tf-xxxxx-an.a.run.app"
next_steps = <<EOT
✅ Terraform 배포 완료!

📋 다음 단계:
... (배포 가이드)
EOT
```

#### 2-5. 생성된 리소스 확인

**Terraform 출력 확인**:
```bash
terraform output
terraform output backend_url
```

**GCP Console 확인**:
1. **Artifact Registry**: Console > Artifact Registry > `agent-tf` 확인
2. **Cloud Run**: Console > Cloud Run > `backend-tf`, `frontend-tf` 확인
3. **IAM**: Console > IAM & Admin > `secretmanager.secretAccessor` 권한 확인

---

### Step 3: 이미지 빌드/푸시 및 배포

#### 3-1. Artifact Registry 인증 설정

```bash
# 인증 설정 (서울 리전)
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 출력: Adding credentials for: asia-northeast3-docker.pkg.dev
```

#### 3-2. docker-compose로 이미지 빌드 및 푸시

**환경 변수 설정**:
```bash
# 프로젝트 루트로 이동
cd ../..

# GCP 프로젝트 정보 설정
export PROJECT_ID=$(gcloud config get-value project)
export REGION=asia-northeast3

# docker-compose를 위한 이미지 URL 설정
export BACKEND_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-tf/backend:latest"
export FRONTEND_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-tf/frontend:latest"

# 설정 확인
echo "Backend Image: $BACKEND_IMAGE"
echo "Frontend Image: $FRONTEND_IMAGE"
```

**docker-compose로 빌드 및 푸시**:
```bash
# Backend와 Frontend 동시 빌드
docker-compose build

# Backend와 Frontend 동시 푸시
docker-compose push
```

**💡 작동 원리** (AWS와 동일):
- `docker-compose.yml`은 `${BACKEND_IMAGE}`, `${FRONTEND_IMAGE}` 환경 변수 사용
- AWS/GCP 환경에 따라 다른 레지스트리 URL 설정 가능

**💡 장점**:
- 한 번의 명령으로 모든 서비스 빌드/푸시
- Section 2에서 배운 docker-compose 지식 재사용

#### 3-3. Cloud Run 자동 재배포

**Cloud Run의 특별한 기능**:
- **이미지 푸시 시 자동 감지**
- 새 리비전 자동 생성
- 트래픽 자동 전환

**수동 재배포 (필요 시)**:
```bash
# Backend 재배포
gcloud run services update backend-dev \
  --region asia-northeast3 \
  --image asia-northeast3-docker.pkg.dev/agent-service-terraform/agent-dev/backend:latest

# Frontend 재배포
gcloud run services update frontend-dev \
  --region asia-northeast3 \
  --image asia-northeast3-docker.pkg.dev/agent-service-terraform/agent-dev/frontend:latest
```

#### 3-4. 배포 상태 확인

```bash
# Service 목록 확인
gcloud run services list --region asia-northeast3
```

**출력 예시**:
```
SERVICE       REGION              URL                                        LAST DEPLOYED BY
backend-tf    asia-northeast3     https://backend-tf-xxx-an.a.run.app        you@example.com
frontend-tf   asia-northeast3     https://frontend-tf-xxx-an.a.run.app       you@example.com
```

#### 3-5. Cloud Run 서비스 접속

```bash
# Backend URL 확인
terraform output backend_url
# 출력: https://backend-tf-xxxxx-an.a.run.app

# Frontend URL 확인
terraform output frontend_url
# 출력: https://frontend-tf-xxxxx-an.a.run.app

# 브라우저 접속
open $(terraform output -raw frontend_url)
```

**확인 사항**:
- ✅ Frontend 페이지 로드 (HTTPS 자동 제공!)
- ✅ `/api/health` 엔드포인트 응답: `{"status": "healthy"}`
- ✅ 인증서 유효성 (Let's Encrypt 자동 발급)

#### 3-6. 로그 확인

```bash
# Backend 로그 (최근 50줄)
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=backend-tf" \
  --limit 50 \
  --format json

# Frontend 로그
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=frontend-tf" \
  --limit 50 \
  --format json
```

---

## 📊 Terraform 주요 명령어 (GCP)

### 기본 워크플로우
```bash
terraform init      # Provider 다운로드 (최초 1회)
terraform validate  # 문법 검사
terraform plan      # 실행 계획 확인
terraform apply     # 변경 적용
terraform destroy   # 모든 리소스 삭제
```

### 유용한 명령어
```bash
# 출력 값 확인
terraform output
terraform output backend_url

# State 목록 보기
terraform state list

# 특정 리소스 상태 보기
terraform state show google_cloud_run_v2_service.backend
```

## 💰 GCP 비용 관리

### Terraform으로 생성한 리소스 비용 (서울 리전)

| 리소스 | 비용 | 설명 |
|--------|------|------|
| Artifact Registry | $0.10/GB/월 | 이미지 스토리지 (AWS ECR과 동일) |
| Cloud Run (Backend) | ~$8/월 | 2 vCPU × 2GB, min_instances=0 |
| Cloud Run (Frontend) | ~$2/월 | 1 vCPU × 512MB, min_instances=0 |
| Cloud Logging | ~$1/월 | 로그 저장 (기본 보관 기간) |
| **Total (상시 운영)** | **~$11/월** | |
| **Total (요청 없을 때)** | **~$0/월** | 완전 서버리스! |

**AWS 대비 비용 절감**: ~$72/월 → ~$11/월 = **85% 절감!**

### 비용 절감 팁

**1. 완전 서버리스 모드 (권장)**:
```hcl
# terraform.tfvars
backend_min_instances  = 0  # 요청 없으면 0원!
frontend_min_instances = 0
```
→ 개발 환경에서 사용하지 않을 때 **완전히 0원**

**2. 개발 환경은 사용 시에만 생성**:
```bash
# 작업 시작
cd terraform/gcp
terraform apply

# 작업 종료
terraform destroy  # ← 비용 0원!
```

**3. Max Instances 제한**:
```hcl
backend_max_instances  = 5   # 10 → 5로 제한
frontend_max_instances = 3
```

**4. 리소스 최적화**:
```hcl
# 리소스를 줄여서 비용 절감
backend_cpu    = "1"     # 2 → 1 (50% 절감)
backend_memory = "1Gi"   # 2Gi → 1Gi
```

### AWS vs GCP 비용 비교

| 항목 | AWS (24/7 운영) | GCP (min=0) | 절감율 |
|------|----------------|-------------|--------|
| **개발 환경 (사용 중)** | $72/월 | $11/월 | 85% |
| **개발 환경 (미사용)** | $72/월 | $0/월 | 100% |
| **개발 환경 (8시간/일)** | $72/월 | $3/월 | 96% |

**GCP의 압도적 비용 우위!**

## 🛠️ 트러블슈팅 (GCP)

### 0. 브라우저 인증 실패
**증상**:
```
ERROR: There was a problem with web authentication. Try running again with --no-browser.
ERROR: (gcloud.auth.application-default.login) https://www.googleapis.com/auth/cloud-platform scope is required but not consented.
```

**원인**:
- 브라우저가 제대로 열리지 않음
- localhost 리다이렉트 실패
- 권한 동의 누락 (cloud-platform scope)
- 방화벽/네트워크 차단

**해결**:
```bash
# --no-browser 옵션 사용 (권장)
gcloud auth application-default login --no-browser
```

**실행 과정**:
1. 터미널에 출력된 **인증 URL을 복사**
2. 브라우저에서 **URL을 직접 열기**
3. Google 계정으로 **로그인**
4. **모든 권한 요청에 "허용" 클릭** (중요! cloud-platform 포함)
5. 표시된 **인증 코드를 복사**
6. 터미널로 돌아와서 **인증 코드 붙여넣기**

**인증 성공 확인**:
```bash
gcloud auth application-default print-access-token
# 토큰이 출력되면 성공!
```

---

### 1. Project ID를 찾을 수 없음
**증상**: `Error: google: could not find default credentials`

**해결**:
```bash
# 1. gcloud 인증
gcloud auth login
gcloud auth application-default login

# 2. 프로젝트 설정
gcloud config set project YOUR_PROJECT_ID

# 3. terraform.tfvars에 정확한 프로젝트 ID 입력
project_id = "your-project-id"  # 프로젝트 이름이 아님!
```

### 2. Secret을 찾을 수 없음
**증상**: `Error: Secret not found: openai-api-key`

**원인**: Secret이 생성되지 않았거나 이름이 틀림

**해결**:
```bash
# 1. Secret 목록 확인
gcloud secrets list

# 2. Secret이 없다면 생성
echo -n "your-api-key" | gcloud secrets create openai-api-key --data-file=-

# 3. terraform.tfvars에 정확한 이름 입력
openai_secret_name = "openai-api-key"
```

### 3. API가 활성화되지 않음
**증상**:
```
Error: Error 403: Artifact Registry API has not been used in project before or it is disabled.
Error: Service account XXX-compute@developer.gserviceaccount.com does not exist.
```

**원인**: GCP 프로젝트에서 필요한 API들이 활성화되지 않음 (신규 프로젝트의 경우 흔함)

**해결**: **Step 1-1-1. 필수 API 활성화** 참조

```bash
# 필요한 모든 API 한 번에 활성화
gcloud services enable \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com

# 활성화 완료 대기 (1-2분)
sleep 120

# 확인
gcloud services list --enabled | grep -E "compute|artifact|run|secret"
```

**⚠️ 중요**: 특히 **Compute Engine API**를 활성화해야 기본 서비스 계정이 자동 생성됩니다!

### 4. Artifact Registry 인증 실패
**증상**: `Error: denied: Permission "artifactregistry.repositories.uploadArtifacts" denied`

**해결**:
```bash
# 1. 인증 재설정
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 2. 권한 확인
gcloud projects get-iam-policy $(gcloud config get-value project)

# 3. 필요 시 권한 추가
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="user:your-email@example.com" \
  --role="roles/artifactregistry.writer"
```

### 5. Cloud Run 배포 실패
**증상**: `Error: Error creating Service: googleapi: Error 400: Container image not found`

**원인**: Artifact Registry에 이미지가 없음

**해결**:
```bash
# 1. 이미지 푸시 (Step 3-2)
docker-compose push

# 2. 이미지 확인
gcloud artifacts docker images list asia-northeast3-docker.pkg.dev/PROJECT_ID/agent-tf

# 3. Terraform 재실행
terraform apply
```

### 6. 비용 청구 계정 미설정
**증상**: `Error: Cannot create ... Cloud Run without an active billing account`

**해결**:
1. GCP Console > Billing 이동
2. Billing Account 생성 또는 연결
3. 프로젝트에 Billing Account 연결

## 🧹 리소스 정리

### 전체 삭제
```bash
cd terraform/gcp
terraform destroy
```

**출력**:
```
Plan: 0 to add, 0 to change, 4 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes
```

**⏱️ 약 2-3분 소요** (AWS 5-10분 대비 빠름!)

### 삭제 확인
```bash
# State에 리소스가 없는지 확인
terraform state list
# 출력: (비어 있음)

# GCP Console에서도 확인
gcloud run services list
gcloud artifacts repositories list
```

## 완료 체크리스트

### 사전 준비
- [ ] Terraform이 설치되었는가?
- [ ] AWS CLI가 설정되었는가?
- [ ] VPC 정보가 확인되었는가? (`bash aws/scripts/get_vpc_info.sh`)
- [ ] terraform.tfvars 파일에 Secret 이름이 올바른가? (기본값: dev/openai-api-key, dev/pinecone-api-key)

### Terraform 실행
- [ ] `terraform init` 성공했는가?
- [ ] `terraform validate` 통과했는가?
- [ ] `terraform plan`에서 19개 리소스 생성 확인했는가?
- [ ] `terraform apply` 성공했는가?
- [ ] 출력값 (alb_dns_name, ecr_url 등)이 표시되는가?

### 배포 확인
- [ ] ECR에 이미지가 푸시되었는가?
- [ ] ECS Service가 ACTIVE 상태인가?
- [ ] Running Count = Desired Count인가?
- [ ] ALB URL로 접속이 가능한가?
- [ ] `/api/health` 엔드포인트가 응답하는가?
- [ ] CloudWatch Logs에 로그가 기록되는가?

### 이해도 확인
- [ ] Terraform의 기본 워크플로우를 이해했는가?
- [ ] Resource, Variable, Output의 개념을 이해했는가?
- [ ] State 파일의 중요성을 이해했는가?
- [ ] terraform plan과 terraform apply의 차이를 이해했는가?
- [ ] Section 3 수동 배포와 Terraform의 장단점을 이해했는가?

---

## 🎓 다음 단계

Section 5를 완료했다면:
- ✅ Terraform 기초 개념 습득
- ✅ IaC의 실용성 체험
- ✅ 코드로 인프라를 관리하는 실무 패턴 이해

**Section 6 예고**: GitHub Actions를 이용한 CI/CD 파이프라인
- 코드 푸시 → 자동 테스트 → 자동 빌드 → Terraform 자동 배포
- GitOps 워크플로우
- 안전한 배포 전략 (Blue-Green, Canary)
