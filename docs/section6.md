# Section 6: CI/CD 파이프라인 구성

---

## 학습 목표

- CI/CD 기본 개념과 자동화의 필요성
- GitHub Actions 워크플로우 구조 이해
- Git 브랜치 전략과 환경별(dev/staging/prod) 분리 배포
- 3단계 배포 전략: Registry → 이미지 빌드/푸시 → 서비스 배포
- AWS ECS와 GCP Cloud Run 멀티 클라우드 자동 배포

---

## 📖 CI/CD 개념

**CI (Continuous Integration)**: 코드 변경 시 자동 테스트/빌드/검증 → 버그 조기 발견

**CD (Continuous Deployment)**: 테스트 통과한 코드를 자동으로 프로덕션 배포 → 빠른 배포, 수동 오류 제거

**파이프라인**: 코드 푸시 → 테스트 → 이미지 빌드 → 레지스트리 푸시 → 클라우드 배포

---

## 🛠️ GitHub Actions 기초

```yaml
name: Deploy Workflow
on:
  push:
    branches: [main, develop]  # 트리거: 브랜치 푸시 시
  workflow_dispatch:  # 수동 실행 가능

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production  # GitHub Environment 사용
    steps:
      - uses: actions/checkout@v4  # 코드 체크아웃
      - name: Deploy
        run: ./deploy.sh
        env:
          API_KEY: ${{ secrets.API_KEY }}  # Secrets 사용
```

**구조**: on (트리거) → jobs (작업) → steps (단계) → Secrets (민감정보)

**핵심 개념**:
- **Workflow**: 자동화 작업의 전체 흐름
- **Jobs**: 병렬 실행 가능한 작업 단위
- **Steps**: 순차적으로 실행되는 개별 명령
- **Environments**: 환경별 변수와 시크릿 분리 관리

---

## 🌳 협업을 위한 Git 전략

### Git Flow vs GitHub Flow

실무에서 많이 사용하는 두 가지 브랜치 전략:

**Git Flow** (복잡한 릴리즈 관리):
```
main (production)
├── develop (개발 통합)
│   ├── feature/user-auth
│   └── feature/payment
└── hotfix/critical-bug
```
- 장점: 릴리즈 버전 관리 명확
- 단점: 브랜치 구조 복잡, 빠른 배포에 불리

**GitHub Flow** (빠른 배포 중심):
```
main (항상 배포 가능 상태)
├── feature/user-auth → PR → main
└── feature/payment → PR → main
```
- 장점: 단순, 빠른 배포
- 단점: 릴리즈 관리 어려움

### 이 강의의 브랜치 전략

**3-tier 환경 분리** (Git Flow 변형):
```
develop → development 환경 (개발/테스트)
staging → staging 환경 (QA/검증)
main → production 환경 (실서비스)
```

**배포 흐름**:
1. `feature/*` 브랜치에서 개발
2. `develop`에 PR → development 환경 자동 배포
3. `staging`에 머지 → staging 환경 자동 배포
4. `main`에 머지 → production 환경 배포 (승인 필요)

### 이미지 버전 관리 전략

**Semantic Versioning** 체계: **MAJOR.MINOR.PATCH** (예: v1.2.3)

- **MAJOR**: 호환성 깨지는 변경 (v1.0.0 → v2.0.0)
- **MINOR**: 기능 추가 (v1.0.0 → v1.1.0)
- **PATCH**: 버그 수정 (v1.0.0 → v1.0.1)

**환경별 동일 버전 태그 전략**:

각 환경(dev/staging/prod)에서 **독립적으로 빌드**하되, **동일한 버전 태그**를 사용해 배포 추적:

```bash
# development 환경
backend-dev:v1.2.3 → dev registry에 푸시

# staging 환경
backend-stag:v1.2.3 → staging registry에 푸시

# production 환경
backend-prod:v1.2.3 → prod registry에 푸시
```

**장점**:
- 환경별 독립적인 빌드 및 레지스트리 관리
- 동일한 버전 태그로 배포 상태 추적 용이
- 각 환경마다 어떤 버전이 배포되었는지 명확하게 파악 가능

**GitHub Actions에서 IMAGE_TAG 변수 사용**:

```yaml
# GitHub Environments Variables에 IMAGE_TAG 설정
IMAGE_TAG = "v1.2.3"

# 워크플로우에서 사용
BACKEND_IMAGE: backend-${{ vars.ENVIRONMENT }}:${{ vars.IMAGE_TAG }}
FRONTEND_IMAGE: frontend-${{ vars.ENVIRONMENT }}:${{ vars.IMAGE_TAG }}
```

---

## 🌍 환경별 인프라 분리 개념

실무에서는 개발(dev), 스테이징(staging), 프로덕션(prod) 환경을 분리하여 관리합니다.

### 환경 분리가 필요한 이유

| 이유 | 설명 |
|------|------|
| **안전성** | 프로덕션 영향 없이 개발/테스트 가능 |
| **독립성** | 각 환경이 독립적으로 동작 (데이터, 리소스 분리) |
| **비용 관리** | dev 환경은 소형 인스턴스, prod는 고성능 인스턴스 |
| **배포 검증** | dev → staging → prod 단계별 검증 |

### 브랜치별 환경 매핑

```
develop 브랜치 → dev 환경
  - backend-dev, frontend-dev
  - agent-cluster-dev (AWS) / agent-dev (GCP)

staging 브랜치 → staging 환경
  - backend-stag, frontend-stag
  - agent-cluster-stag / agent-stag

main 브랜치 → prod 환경
  - backend-prod, frontend-prod
  - agent-cluster-prod / agent-prod
```

### 환경별 설정 차이

| 설정 | dev | staging | prod |
|------|-----|---------|------|
| **CPU/Memory** | 작음 (512/1024) | 중간 (1024/2048) | 큼 (2048/4096) |
| **인스턴스 수** | 1 | 2 | 3+ |
| **Auto Scaling** | 비활성화 | 활성화 | 활성화 |
| **로그 보관** | 7일 | 30일 | 90일 |
| **백업** | 없음 | 일간 | 실시간 |
| **비용** | 최소 | 중간 | 최대 |

---

## 📋 파이프라인 상세 설명

### 1. AWS 배포 파이프라인 (3단계 전략)

**파일:** `.github/workflows/deploy-aws.yml`

#### 목적

**Section 5의 이미지 순서 문제를 해결**하는 3단계 워크플로우:
1. **Stage 1**: ECR Repository 생성 (Terraform -target)
2. **Stage 2**: Docker 이미지 빌드 및 ECR 푸시
3. **Stage 3**: ECS 전체 인프라 배포 (Terraform apply)

#### 실행 조건

```yaml
on:
  push:
    branches:
      - develop  # development 환경
      - staging  # staging 환경
      - main     # production 환경
  workflow_dispatch:  # 수동 실행
```

#### 브랜치별 환경 자동 선택

```yaml
# develop 브랜치 → development 환경
# staging 브랜치 → staging 환경
# main 브랜치 → production 환경

environment: ${{ github.ref_name == 'main' && 'production' || (github.ref_name == 'staging' && 'staging' || 'development') }}
```

#### 3단계 워크플로우 상세

**Step 1: terraform.tfvars 동적 생성**

```yaml
- name: Generate terraform.tfvars
  working-directory: terraform/aws
  run: |
    cat > terraform.tfvars <<EOF
    environment = "${{ vars.ENVIRONMENT }}"
    vpc_id = "${{ secrets.AWS_VPC_ID }}"
    public_subnet_ids = ${{ secrets.AWS_PUBLIC_SUBNET_IDS }}
    openai_secret_name = "${{ vars.AWS_OPENAI_SECRET_NAME }}"
    pinecone_secret_name = "${{ vars.AWS_PINECONE_SECRET_NAME }}"
    backend_cpu = "${{ vars.BACKEND_CPU }}"
    backend_memory = "${{ vars.BACKEND_MEMORY }}"
    backend_desired_count = ${{ vars.BACKEND_DESIRED_COUNT }}
    frontend_cpu = "${{ vars.FRONTEND_CPU }}"
    frontend_memory = "${{ vars.FRONTEND_MEMORY }}"
    frontend_desired_count = ${{ vars.FRONTEND_DESIRED_COUNT }}
    EOF
```

**핵심:**
- GitHub Environments에서 변수와 시크릿 읽어서 terraform.tfvars 생성
- 환경별로 다른 값 자동 적용 (dev/staging/prod)

**Step 2: ECR Repository 생성 (Registry만)**

```yaml
- name: Terraform Init
  working-directory: terraform/aws
  run: terraform init \
    -backend-config="bucket=metacode-terraform-state" \
    -backend-config="key=agent-service/${{ vars.ENVIRONMENT }}/terraform.tfstate" \
    -backend-config="region=${{ vars.AWS_REGION }}"

- name: Create ECR Repositories
  working-directory: terraform/aws
  run: |
    terraform apply -auto-approve \
      -target=aws_ecr_repository.backend \
      -target=aws_ecr_repository.frontend

    echo "✅ ECR Repository 생성 완료: backend-${{ vars.ENVIRONMENT }}, frontend-${{ vars.ENVIRONMENT }}"
```

**핵심:**
- `-target` 옵션으로 ECR만 선택적으로 생성
- ECS Task Definition, Service는 아직 생성하지 않음
- 이미지를 푸시할 저장소가 먼저 준비됨

**Step 3: Docker 이미지 빌드 및 푸시**

```yaml
- name: Login to Amazon ECR
  uses: aws-actions/amazon-ecr-login@v2

- name: Build and push images
  env:
    BACKEND_IMAGE: ${{ steps.account.outputs.id }}.dkr.ecr.${{ vars.AWS_REGION }}.amazonaws.com/backend-${{ vars.ENVIRONMENT }}:${{ vars.IMAGE_TAG }}
    FRONTEND_IMAGE: ${{ steps.account.outputs.id }}.dkr.ecr.${{ vars.AWS_REGION }}.amazonaws.com/frontend-${{ vars.ENVIRONMENT }}:${{ vars.IMAGE_TAG }}
  run: |
    echo "🐳 Building images for ${{ vars.ENVIRONMENT }} environment"
    echo "Backend: $BACKEND_IMAGE"
    echo "Frontend: $FRONTEND_IMAGE"

    docker-compose build
    docker-compose push

    echo "✅ Images pushed to ECR"
```

**핵심:**
- 환경별 이미지 URL (backend-dev:v1.0.0, backend-stag:v1.0.0, backend-prod:v1.0.0)
- docker-compose.yml의 `BACKEND_IMAGE`, `FRONTEND_IMAGE` 환경 변수 사용
- 이제 ECR에 이미지가 존재 ✅

**Step 4: 전체 인프라 배포**

```yaml
- name: Deploy with Terraform
  working-directory: terraform/aws
  run: |
    echo "🚀 Deploying infrastructure for ${{ vars.ENVIRONMENT }} environment"

    terraform apply -auto-approve

    echo "✅ Terraform apply 완료"
```

**핵심:**
- 이미지가 존재하므로 ECS Task Definition이 성공적으로 생성
- ECS Service가 Task를 정상적으로 시작
- Section 5의 Pending 문제 해결! ✅
- Terraform outputs로 배포 결과 확인

#### 전체 워크플로우 다이어그램

```
[develop/staging/main 브랜치에 푸시]
        ↓
[환경 자동 선택: development/staging/production]
        ↓
[Step 1: terraform.tfvars 생성]
  - GitHub Environments Variables/Secrets → terraform.tfvars
        ↓
[Step 2: ECR Repository 생성]
  - terraform apply -target=aws_ecr_repository.*
  - ECR: backend-{env}, frontend-{env} 생성 ✅
        ↓
[Step 3: Docker 이미지 빌드/푸시]
  - docker-compose build
  - docker-compose push
  - 이미지가 ECR에 존재 ✅
        ↓
[Step 4: 전체 인프라 배포]
  - terraform apply (전체)
  - ECS Task Definition 생성 (이미지 참조 성공)
  - ECS Service 생성 (Task 정상 시작)
  - Terraform outputs로 결과 확인
        ↓
[배포 완료] 🎉
```

#### 환경별 배포 예시

**Development 배포 (develop 브랜치)**:
```bash
git checkout develop
git add .
git commit -m "Update backend API"
git push origin develop

→ ENVIRONMENT=dev
→ IMAGE_TAG=v1.0.0
→ ECR: backend-dev:v1.0.0, frontend-dev:v1.0.0
→ ECS: agent-cluster-dev, backend-dev-service, frontend-dev-service
→ ALB: backend-dev-alb, frontend-dev-alb
```

**Staging 배포 (staging 브랜치)**:
```bash
git checkout staging
git merge develop
git push origin staging

→ ENVIRONMENT=stag
→ IMAGE_TAG=v1.0.0 (동일한 버전)
→ ECR: backend-stag:v1.0.0, frontend-stag:v1.0.0
→ ECS: agent-cluster-stag, backend-stag-service, frontend-stag-service
```

**Production 배포 (main 브랜치)**:
```bash
git checkout main
git merge staging
git push origin main

→ ENVIRONMENT=prod
→ IMAGE_TAG=v1.0.0 (동일한 버전)
→ ECR: backend-prod:v1.0.0, frontend-prod:v1.0.0
→ ECS: agent-cluster-prod, backend-prod-service, frontend-prod-service
```

#### 배포 검증

```bash
# 1. ECS 서비스 상태 확인
aws ecs describe-services \
  --cluster agent-cluster-$ENVIRONMENT \
  --services backend-$ENVIRONMENT-service frontend-$ENVIRONMENT-service \
  --region ap-northeast-2

# 2. ALB DNS로 접속 테스트
BACKEND_ALB=$(aws elbv2 describe-load-balancers \
  --names backend-$ENVIRONMENT-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)
curl http://$BACKEND_ALB/health

# 3. CloudWatch 로그 확인
aws logs tail /ecs/backend-$ENVIRONMENT --follow --region ap-northeast-2
```

---

### 2. GCP 배포 파이프라인 (3단계 전략)

**파일:** `.github/workflows/deploy-gcp.yml`

#### 목적

**Section 5의 이미지 순서 문제를 해결**하는 3단계 워크플로우 (AWS와 동일한 패턴):
1. **Stage 1**: Artifact Registry 생성 (Terraform -target)
2. **Stage 2**: Docker 이미지 빌드 및 Artifact Registry 푸시
3. **Stage 3**: Cloud Run 전체 인프라 배포 (Terraform apply)

#### GCP의 특별한 점

Cloud Run은 서비스 생성 시 **이미지 존재 여부를 엄격하게 검증**합니다:
- AWS: 이미지 없어도 Service 생성 성공 → 나중에 Pending
- **GCP: 이미지 없으면 Service 생성 실패** ❌

→ **3단계 전략이 필수!**

#### 실행 조건

```yaml
on:
  push:
    branches:
      - develop  # development 환경
      - staging  # staging 환경
      - main     # production 환경
  workflow_dispatch:  # 수동 실행
```

#### 3단계 워크플로우 상세

**Step 1: terraform.tfvars 동적 생성**

```yaml
- name: Generate terraform.tfvars
  working-directory: terraform/gcp
  run: |
    cat > terraform.tfvars <<EOF
    project_id = "${{ vars.GCP_PROJECT_ID }}"
    region = "${{ vars.GCP_REGION }}"
    environment = "${{ vars.ENVIRONMENT }}"
    image_tag = "${{ vars.IMAGE_TAG }}"
    openai_secret_name = "${{ vars.GCP_OPENAI_SECRET_NAME }}"
    pinecone_secret_name = "${{ vars.GCP_PINECONE_SECRET_NAME }}"
    pinecone_index_name = "${{ vars.PINECONE_INDEX_NAME }}"
    backend_cpu = "${{ vars.BACKEND_CPU }}"
    backend_memory = "${{ vars.BACKEND_MEMORY }}"
    backend_min_instances = ${{ vars.BACKEND_MIN_INSTANCES }}
    backend_max_instances = ${{ vars.BACKEND_MAX_INSTANCES }}
    frontend_cpu = "${{ vars.FRONTEND_CPU }}"
    frontend_memory = "${{ vars.FRONTEND_MEMORY }}"
    frontend_min_instances = ${{ vars.FRONTEND_MIN_INSTANCES }}
    frontend_max_instances = ${{ vars.FRONTEND_MAX_INSTANCES }}
    EOF
```

**핵심:**
- GitHub Environments에서 GCP 관련 변수 읽어서 terraform.tfvars 생성
- 환경별로 다른 CPU/Memory 설정 적용 (dev/staging/prod)

**Step 2: Artifact Registry 생성 (Registry만)**

```yaml
- name: Terraform Init
  working-directory: terraform/gcp
  run: terraform init \
    -backend-config="bucket=metacode-terraform-state" \
    -backend-config="prefix=agent-service/${{ vars.ENVIRONMENT }}"

- name: Create Artifact Registry
  working-directory: terraform/gcp
  run: |
    terraform apply -auto-approve \
      -target=google_artifact_registry_repository.agent

    echo "✅ Artifact Registry 생성 완료: agent-${{ vars.ENVIRONMENT }}"
```

**핵심:**
- `-target` 옵션으로 Artifact Registry만 선택적으로 생성
- Cloud Run Service는 아직 생성하지 않음
- 이미지를 푸시할 저장소가 먼저 준비됨

**Step 3: Docker 이미지 빌드 및 푸시**

```yaml
- name: Configure Docker for Artifact Registry
  run: |
    gcloud auth configure-docker ${{ vars.GCP_REGION }}-docker.pkg.dev

- name: Build and push images
  env:
    BACKEND_IMAGE: ${{ vars.GCP_REGION }}-docker.pkg.dev/${{ vars.GCP_PROJECT_ID }}/agent-${{ vars.ENVIRONMENT }}/backend:${{ vars.IMAGE_TAG }}
    FRONTEND_IMAGE: ${{ vars.GCP_REGION }}-docker.pkg.dev/${{ vars.GCP_PROJECT_ID }}/agent-${{ vars.ENVIRONMENT }}/frontend:${{ vars.IMAGE_TAG }}
  run: |
    echo "🐳 Building images for ${{ vars.ENVIRONMENT }} environment"
    echo "Backend: $BACKEND_IMAGE"
    echo "Frontend: $FRONTEND_IMAGE"

    docker-compose build
    docker-compose push

    echo "✅ Images pushed to Artifact Registry"
```

**핵심:**
- 환경별 Artifact Registry (agent-dev, agent-stag, agent-prod)
- 환경별 이미지 (backend:v1.0.0, frontend:v1.0.0 in each registry)
- docker-compose.yml의 `BACKEND_IMAGE`, `FRONTEND_IMAGE` 환경 변수 사용
- 이제 Artifact Registry에 이미지가 존재 ✅

**Step 4: 전체 인프라 배포**

```yaml
- name: Deploy with Terraform
  working-directory: terraform/gcp
  run: |
    echo "🚀 Deploying infrastructure for ${{ vars.ENVIRONMENT }} environment"

    terraform apply -auto-approve

    echo "✅ Terraform apply 완료"
```

**핵심:**
- 이미지가 존재하므로 Cloud Run Service가 성공적으로 생성
- GCP의 엄격한 이미지 검증 통과 ✅
- Section 5의 "Error 400: Container image not found" 문제 해결! ✅
- Terraform outputs로 배포 결과 확인

#### 전체 워크플로우 다이어그램

```
[develop/staging/main 브랜치에 푸시]
        ↓
[환경 자동 선택: development/staging/production]
        ↓
[Step 1: terraform.tfvars 생성]
  - GitHub Environments Variables/Secrets → terraform.tfvars
        ↓
[Step 2: Artifact Registry 생성]
  - terraform apply -target=google_artifact_registry_repository.agent
  - Artifact Registry: agent-{env} 생성 ✅
        ↓
[Step 3: Docker 이미지 빌드/푸시]
  - gcloud auth configure-docker
  - docker-compose build && push
  - 이미지가 Artifact Registry에 존재 ✅
        ↓
[Step 4: 전체 인프라 배포]
  - terraform apply (전체)
  - Cloud Run Service 생성 (이미지 검증 통과)
  - 서비스가 정상 시작
  - Terraform outputs로 결과 확인
        ↓
[배포 완료] 🎉
```

#### 환경별 배포 예시

**Development 배포 (develop 브랜치)**:
```bash
git checkout develop
git add .
git commit -m "Update backend API"
git push origin develop

→ ENVIRONMENT=dev
→ IMAGE_TAG=v1.0.0
→ Artifact Registry: agent-dev (backend:v1.0.0, frontend:v1.0.0)
→ Cloud Run: backend-dev, frontend-dev
→ URL: https://backend-dev-xxxxx-an.a.run.app
```

**Staging 배포 (staging 브랜치)**:
```bash
git checkout staging
git merge develop
git push origin staging

→ ENVIRONMENT=stag
→ IMAGE_TAG=v1.0.0 (동일한 버전)
→ Artifact Registry: agent-stag (backend:v1.0.0, frontend:v1.0.0)
→ Cloud Run: backend-stag, frontend-stag
```

**Production 배포 (main 브랜치)**:
```bash
git checkout main
git merge staging
git push origin main

→ ENVIRONMENT=prod
→ IMAGE_TAG=v1.0.0 (동일한 버전)
→ Artifact Registry: agent-prod (backend:v1.0.0, frontend:v1.0.0)
→ Cloud Run: backend-prod, frontend-prod
```

#### 배포 검증

```bash
# 1. Cloud Run 서비스 상태 확인
gcloud run services list --region $GCP_REGION

# 2. Health check
BACKEND_URL=$(gcloud run services describe backend-$ENVIRONMENT \
  --region $GCP_REGION \
  --format="value(status.url)")
curl $BACKEND_URL/health

# 3. 로그 확인
gcloud logging read "resource.type=cloud_run_revision AND \
  resource.labels.service_name=backend-$ENVIRONMENT" \
  --limit 50 \
  --format json
```

---

## 🚀 실습 환경 구성

이제 파이프라인이 어떻게 동작하는지 이해했으니, 실제로 실습 환경을 구성해봅시다.

### 1. Branch 생성

**브랜치 전략**:
- `develop` → development 환경 자동 배포
- `staging` → staging 환경 자동 배포
- `main` → production 환경 자동 배포

```bash
# 로컬 저장소에서 브랜치 생성
git checkout -b develop
git push -u origin develop

git checkout -b staging
git push -u origin staging

git checkout -b main
git push -u origin main

# 현재 상태 확인
git branch -a
# → develop, staging, main 브랜치 확인
```

### 2. GitHub Environments 생성

**GitHub Environments란?**

환경별(development, staging, production) 변수와 시크릿을 분리 관리하고, 배포 승인 프로세스를 추가할 수 있는 기능입니다.

**주요 이점:**
- 환경별 Variables와 Secrets 분리 관리
- 배포 이력 추적 및 시각화
- Production 환경에 배포 승인 프로세스 추가 가능
- 브랜치 기반 자동 환경 선택

**환경 생성 방법:**

1. GitHub 저장소 → **Settings** → **Environments**
2. **New environment** 클릭
3. 3개의 환경 생성:
   - `development` (develop 브랜치용)
   - `staging` (staging 브랜치용)
   - `production` (main 브랜치용)

**Protection Rules** (production만 설정):
```
Settings → Environments → production → Protection rules
✅ Required reviewers (배포 승인 필요)
✅ Wait timer: 5 minutes
```

### 3. Environment Variables 설정

**Variables vs Secrets**:

| 구분 | Variables | Secrets |
|------|-----------|---------|
| **용도** | 비민감 설정값 (리전, 환경 이름 등) | 민감 정보 (API 키, 액세스 키 등) |
| **암호화** | 암호화 안 됨 | 암호화됨 |
| **로그 출력** | 로그에 표시 | `***`로 마스킹됨 |
| **접근 방법** | `${{ vars.변수명 }}` | `${{ secrets.변수명 }}` |

각 환경마다 아래 변수들을 설정합니다.

#### development 환경

**Settings → Environments → development → Add variable**

**공통 Variables**:

| Name | Value | 설명 |
|------|-------|------|
| `ENVIRONMENT` | `dev` | 환경 식별자 |
| `IMAGE_TAG` | `v1.0.0` | 이미지 버전 태그 |

**AWS Variables** (AWS 배포 시):

| Name | Value | 설명 |
|------|-------|------|
| `AWS_REGION` | `ap-northeast-2` | AWS 리전 |
| `AWS_OPENAI_SECRET_NAME` | `dev/openai-api-key` | Secret Manager 시크릿 이름 |
| `AWS_PINECONE_SECRET_NAME` | `dev/pinecone-api-key` | Secret Manager 시크릿 이름 |
| `BACKEND_CPU` | `512` | Backend ECS CPU (단위: vCPU * 1024) |
| `BACKEND_MEMORY` | `1024` | Backend ECS Memory (단위: MB) |
| `BACKEND_DESIRED_COUNT` | `1` | Backend Task 개수 |
| `FRONTEND_CPU` | `256` | Frontend ECS CPU |
| `FRONTEND_MEMORY` | `512` | Frontend ECS Memory |
| `FRONTEND_DESIRED_COUNT` | `1` | Frontend Task 개수 |

**GCP Variables** (GCP 배포 시):

| Name | Value | 설명 |
|------|-------|------|
| `GCP_PROJECT_ID` | `<YOUR_GCP_PROJECT_ID>` | GCP 프로젝트 ID |
| `GCP_REGION` | `asia-northeast3` | GCP 리전 |
| `GCP_OPENAI_SECRET_NAME` | `openai-api-key` | Secret Manager 시크릿 이름 |
| `GCP_PINECONE_SECRET_NAME` | `pinecone-api-key` | Secret Manager 시크릿 이름 |
| `PINECONE_INDEX_NAME` | `ai-service-docs-dev` | Pinecone Index 이름 |
| `GCP_BACKEND_CPU` | `2` | Backend Cloud Run CPU (코어 수: 1, 2, 4, 8) |
| `GCP_BACKEND_MEMORY` | `2Gi` | Backend Cloud Run Memory (Mi/Gi 접미사 필수) |
| `BACKEND_MIN_INSTANCES` | `0` | Backend 최소 인스턴스 |
| `BACKEND_MAX_INSTANCES` | `5` | Backend 최대 인스턴스 |
| `GCP_FRONTEND_CPU` | `1` | Frontend Cloud Run CPU (코어 수: 1, 2, 4, 8) |
| `GCP_FRONTEND_MEMORY` | `512Mi` | Frontend Cloud Run Memory (Mi/Gi 접미사 필수) |
| `FRONTEND_MIN_INSTANCES` | `0` | Frontend 최소 인스턴스 |
| `FRONTEND_MAX_INSTANCES` | `3` | Frontend 최대 인스턴스 |

**⚠️ 중요**: GCP와 AWS는 CPU/Memory 형식이 다릅니다!
- AWS: `AWS_BACKEND_CPU="1024"` (밀리코어), `AWS_BACKEND_MEMORY="2048"` (MB)
- GCP: `GCP_BACKEND_CPU="2"` (코어 수), `GCP_BACKEND_MEMORY="2Gi"` (Mi/Gi 접미사)

#### staging 환경

development 설정을 복사하고 아래 값만 변경:

| Variable | Value |
|----------|-------|
| `ENVIRONMENT` | `stag` |
| `AWS_OPENAI_SECRET_NAME` | `stag/openai-api-key` |
| `AWS_PINECONE_SECRET_NAME` | `stag/pinecone-api-key` |
| `PINECONE_INDEX_NAME` | `ai-service-docs-stag` |
| `BACKEND_CPU` | `1024` (AWS) / `4` (GCP) |
| `BACKEND_MEMORY` | `2048` (AWS) / `4Gi` (GCP) |
| `BACKEND_DESIRED_COUNT` | `2` (AWS) |
| `BACKEND_MIN_INSTANCES` | `1` (GCP) |
| `BACKEND_MAX_INSTANCES` | `10` (GCP) |
| `FRONTEND_CPU` | `512` (AWS) / `2` (GCP) |
| `FRONTEND_MEMORY` | `1024` (AWS) / `1Gi` (GCP) |
| `FRONTEND_DESIRED_COUNT` | `2` (AWS) |
| `FRONTEND_MIN_INSTANCES` | `1` (GCP) |
| `FRONTEND_MAX_INSTANCES` | `5` (GCP) |

#### production 환경

staging 설정을 복사하고 아래 값만 변경:

| Variable | Value |
|----------|-------|
| `ENVIRONMENT` | `prod` |
| `AWS_OPENAI_SECRET_NAME` | `prod/openai-api-key` |
| `AWS_PINECONE_SECRET_NAME` | `prod/pinecone-api-key` |
| `PINECONE_INDEX_NAME` | `ai-service-docs-prod` |
| `BACKEND_CPU` | `2048` (AWS) / `8` (GCP) |
| `BACKEND_MEMORY` | `4096` (AWS) / `8Gi` (GCP) |
| `BACKEND_DESIRED_COUNT` | `3` (AWS) |
| `BACKEND_MIN_INSTANCES` | `2` (GCP) |
| `BACKEND_MAX_INSTANCES` | `20` (GCP) |
| `FRONTEND_CPU` | `1024` (AWS) / `4` (GCP) |
| `FRONTEND_MEMORY` | `2048` (AWS) / `2Gi` (GCP) |
| `FRONTEND_DESIRED_COUNT` | `3` (AWS) |
| `FRONTEND_MIN_INSTANCES` | `2` (GCP) |
| `FRONTEND_MAX_INSTANCES` | `10` (GCP) |

### 4. Environment Secrets 설정

각 환경마다 아래 시크릿들을 설정합니다.

**Settings → Environments → development → Add secret**

#### AWS Secrets

시크릿 값 확인 방법:

```bash
# AWS Access Key 확인
cat ~/.aws/credentials

# VPC ID 확인
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text

# Subnet IDs 확인 (최소 2개 필요)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query 'Subnets[*].SubnetId' --output json
```

| Name | Value | 설명 |
|------|-------|------|
| `AWS_ACCESS_KEY_ID` | `~/.aws/credentials`의 `aws_access_key_id` | AWS 인증 키 |
| `AWS_SECRET_ACCESS_KEY` | `~/.aws/credentials`의 `aws_secret_access_key` | AWS 시크릿 키 |
| `AWS_VPC_ID` | `vpc-xxxxx` | VPC ID |
| `AWS_PUBLIC_SUBNET_IDS` | `["subnet-xxxxx", "subnet-yyyyy"]` | Subnet IDs (JSON 배열) |

#### GCP 사전 준비 (필수)

**⚠️ 중요**: WIF 설정 전에 다음 사항들을 먼저 확인하세요.

**1. GCS Terraform State 버킷 및 권한 설정**

```bash
# 1단계: GCS 버킷 생성 (이미 생성되어 있다면 skip)
gcloud storage buckets create gs://metacode-terraform-state \
  --location=asia-northeast3 \
  --project=$GCP_PROJECT_ID

# 2단계: 버킷 버저닝 활성화 (State 파일 보호)
gcloud storage buckets update gs://metacode-terraform-state \
  --versioning

# 3단계: github-actions 서비스 계정에 Storage 권한 부여
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
```

**2. 서비스 계정 전체 권한 목록 (필수)**

GitHub Actions에서 배포하려면 다음 **모든 권한**이 필요합니다:

```bash
export GCP_PROJECT_ID="your-gcp-project-id"

# Artifact Registry 관리 (이미지 업로드)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

# Cloud Run 관리 (서비스 생성/업데이트)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

# 서비스 계정 사용 권한
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Secret Manager 접근 (시크릿 읽기)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Storage 관리 (Terraform State 파일)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# ⚠️ 중요: IAM 정책 관리 (Terraform에서 IAM 바인딩 생성 시 필요)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/resourcemanager.projectIamAdmin"
```

**왜 이렇게 많은 권한이 필요한가?**
- `artifactregistry.admin`: Docker 이미지 업로드
- `run.admin`: Cloud Run 서비스 생성/수정
- `iam.serviceAccountUser`: Cloud Run이 다른 서비스 계정 사용
- `secretmanager.secretAccessor`: Terraform이 시크릿 참조
- `storage.admin`: Terraform State 파일 읽기/쓰기
- `resourcemanager.projectIamAdmin`: **Terraform이 IAM 바인딩 생성** (Cloud Run → Secret Manager 접근 권한)

**3. AWS vs GCP 리소스 형식 차이 (매우 중요)**

| 항목 | AWS ECS | GCP Cloud Run |
|------|---------|---------------|
| **CPU** | 밀리코어 (256, 512, 1024, 2048, 4096) | 코어 수 (1, 2, 4, 8) |
| **Memory** | MB 단위 (512, 1024, 2048, 4096) | Mi/Gi 접미사 (512Mi, 1Gi, 2Gi, 4Gi) |
| **예시** | BACKEND_CPU="1024" | BACKEND_CPU="2" |
| **예시** | BACKEND_MEMORY="2048" | BACKEND_MEMORY="2Gi" |

**❌ 잘못된 설정 (GCP에서 에러 발생)**:
```yaml
BACKEND_CPU: "1024"        # ❌ GCP는 밀리코어 사용 안 함
BACKEND_MEMORY: "2048"     # ❌ Mi/Gi 접미사 필요
```

**✅ 올바른 설정**:
```yaml
# GCP Variables (development 환경 예시)
GCP_BACKEND_CPU: "2"        # 2 vCPU
GCP_BACKEND_MEMORY: "2Gi"   # 2GB
GCP_FRONTEND_CPU: "1"       # 1 vCPU
GCP_FRONTEND_MEMORY: "512Mi" # 512MB
```

**4. Service Account Impersonation 설정**

Terraform과 Docker 명령이 github-actions 서비스 계정 권한으로 실행되도록 설정:

Workflow 파일에서 다음과 같이 사용:
```yaml
# .github/workflows/deploy-gcp.yml

- name: Terraform Init
  working-directory: terraform/gcp
  env:
    GOOGLE_IMPERSONATE_SERVICE_ACCOUNT: github-actions@${{ vars.GCP_PROJECT_ID }}.iam.gserviceaccount.com
  run: terraform init ...

- name: Configure Docker for Artifact Registry
  run: |
    gcloud auth print-access-token \
      --impersonate-service-account=github-actions@${{ vars.GCP_PROJECT_ID }}.iam.gserviceaccount.com | \
    docker login -u oauth2accesstoken --password-stdin https://${{ vars.GCP_REGION }}-docker.pkg.dev
```

**왜 Impersonation이 필요한가?**
- WIF로 인증한 후에도 실제 작업은 `github-actions` 서비스 계정 권한으로 수행
- Terraform backend GCS 접근, Artifact Registry 업로드 모두 이 계정 권한 사용
- 명시적으로 impersonate해야 권한 오류 방지

---

#### GCP Secrets (GCP 배포 시)

**WIF (Workload Identity Federation) 설정:**

> 💡 **WIF란?** JSON 키 없이 GitHub Actions가 GCP에 안전하게 인증하는 Google 권장 방식입니다.

```bash
# 1단계: 환경 변수 설정
export GCP_PROJECT_ID="your-gcp-project-id"
export PROJECT_NUMBER=$(gcloud projects describe $GCP_PROJECT_ID --format="value(projectNumber)")

# 2단계: WIF Pool 생성
gcloud iam workload-identity-pools create github-pool \
  --project=$GCP_PROJECT_ID --location=global --display-name="GitHub Actions Pool"

# 3단계: WIF Provider 생성 (GitHub 연결)
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=$GCP_PROJECT_ID --location=global --workload-identity-pool=github-pool \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository_owner=='YOUR_GITHUB_USERNAME'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# 4단계: 서비스 계정 생성 및 역할 부여
gcloud iam service-accounts create github-actions \
  --project=$GCP_PROJECT_ID --display-name="GitHub Actions Deployment"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 5단계: WIF-서비스 계정 바인딩
gcloud iam service-accounts add-iam-policy-binding \
  github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com \
  --project=$GCP_PROJECT_ID --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME"

# 6단계: GitHub Secrets에 등록할 값 확인
echo "WIF_PROVIDER: projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
echo "WIF_SERVICE_ACCOUNT: github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com"
```

**⚠️ 주의**: `YOUR_GITHUB_USERNAME`, `YOUR_REPO_NAME`을 실제 값으로 변경하세요.

| Name | Value | 설명 |
|------|-------|------|
| `WIF_PROVIDER` | `projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider` | WIF Provider 전체 경로 |
| `WIF_SERVICE_ACCOUNT` | `github-actions@PROJECT_ID.iam.gserviceaccount.com` | 서비스 계정 이메일 |

**staging, production 환경도 동일한 Secrets 설정**

### 5. Terraform State 버킷 설정

**왜 필요한가?**

팀 협업 시 State 파일을 공유해야 인프라 변경사항을 안전하게 관리할 수 있습니다.

**환경별 State 파일 분리**

```
S3/GCS 버킷 구조:
├── agent-service/
│   ├── dev/
│   │   └── terraform.tfstate          # dev 환경 State
│   ├── staging/
│   │   └── terraform.tfstate          # staging 환경 State
│   └── prod/
│       └── terraform.tfstate          # prod 환경 State
```

**사전 준비 (수동 생성)**

```bash
# AWS: S3 버킷 생성
aws s3 mb s3://metacode-terraform-state --region ap-northeast-2

# GCP: GCS 버킷 생성
gcloud storage buckets create gs://metacode-terraform-state \
  --location=asia-northeast3
```

**자동 적용 방식**

GitHub Actions에서 환경 변수(`ENVIRONMENT`)에 따라 자동으로 다른 State 파일을 사용합니다. 워크플로우 파일들은 이미 `metacode-terraform-state` 버킷을 사용하도록 설정되어 있습니다.

```yaml
# .github/workflows/deploy-aws.yml
terraform init \
  -backend-config="bucket=metacode-terraform-state" \
  -backend-config="key=agent-service/${{ vars.ENVIRONMENT }}/terraform.tfstate"

# 결과:
# dev → agent-service/dev/terraform.tfstate
# staging → agent-service/staging/terraform.tfstate
# prod → agent-service/prod/terraform.tfstate
```

### 6. 첫 배포 테스트

```bash
# develop 브랜치에 코드 푸시
git checkout develop
git add .
git commit -m "Setup CI/CD"
git push origin develop

# GitHub Actions 확인
# → Actions 탭에서 "Deploy to AWS/GCP" 워크플로우 자동 실행 확인
```

**배포 흐름**:
1. `develop` 브랜치 푸시
2. GitHub Actions 자동 트리거
3. `development` 환경 사용
4. Terraform으로 인프라 생성
5. Docker 이미지 빌드 & 푸시
6. ECS/Cloud Run 배포

**배포 확인**:

```
GitHub 저장소 → Actions 탭
→ "Deploy to AWS" / "Deploy to GCP" 워크플로우 실행 확인
→ 각 Step별 로그 확인
→ Terraform outputs로 배포된 리소스 확인
```

---

## 🎯 실습 시나리오

### 시나리오 1: Dev 환경 배포

```bash
git checkout -b feature/new-api
git commit -m "Add new API"
git checkout develop
git merge feature/new-api
git push origin develop
# → AWS/GCP 모두 development 환경에 자동 배포
```

### 시나리오 2: Staging → Production 배포

```bash
# Staging 배포
git checkout staging
git merge develop
git push origin staging
# → staging 환경 배포

# Production 배포 (승인 필요)
git checkout main
git merge staging
git push origin main
# → GitHub에서 Reviewer 승인 후 배포
```

### 시나리오 3: 롤백

```bash
# 방법 1: Git Revert (권장)
git revert <problem-commit>
git push origin main

# 방법 2: 수동 이미지 롤백 (빠른 임시 조치)
# AWS: aws ecs update-service --task-definition backend-prod:42
# GCP: gcloud run services update-traffic --to-revisions=...
```

**실습 체크리스트**:
- [ ] Dev 환경 배포 (develop 브랜치)
- [ ] Staging 배포 (staging 브랜치)
- [ ] Production 배포 및 승인 프로세스
- [ ] 롤백 시나리오 테스트

---

## 🔧 트러블슈팅

### AWS 자격증명 오류

```bash
# aws configure 설정 확인
aws sts get-caller-identity

# 필요한 권한: ECR, ECS, VPC, Secrets Manager 접근 권한
```

### GCP 인증 오류 (WIF)

```bash
# WIF_PROVIDER 및 WIF_SERVICE_ACCOUNT 값 확인
gcloud iam workload-identity-pools providers describe github-provider \
  --project=PROJECT_ID --location=global --workload-identity-pool=github-pool

# GitHub Environments Secrets 업데이트 필요
```

### GCP IAM Permission 오류

**증상**: `Error 403: The caller does not have permission, forbidden`

**원인**: github-actions 서비스 계정에 필요한 권한이 없음

**해결**:
```bash
# 1. 현재 권한 확인
gcloud projects get-iam-policy $GCP_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com"

# 2. 누락된 권한 추가 (위 "GCP 사전 준비" 섹션 참고)
# 특히 중요한 권한:
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/resourcemanager.projectIamAdmin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
```

### GCP CPU/Memory Validation 오류

**증상 1**: `Valid CPU values: 1, 2, 4, 8`
```
Error: Invalid value for variable
backend_cpu = "1024"  # ❌ AWS 형식 사용
Valid CPU values: 1, 2, 4, 8
```

**증상 2**: `Invalid value specified for container memory. For 1.0 CPU, memory must be between 128Mi and 4Gi`
```
Error: Invalid value for variable
backend_memory = "2048"  # ❌ Mi/Gi 접미사 없음
Memory must have Mi or Gi suffix
```

**해결**:
```yaml
# GitHub Environments Variables 수정
# development 환경 예시

# ❌ 잘못된 값 (AWS 형식)
GCP_BACKEND_CPU: "1024"
GCP_BACKEND_MEMORY: "2048"

# ✅ 올바른 값 (GCP 형식)
GCP_BACKEND_CPU: "2"        # 코어 수 (1, 2, 4, 8)
GCP_BACKEND_MEMORY: "2Gi"   # Mi/Gi 접미사 필수
```

**CPU/Memory 유효한 조합**:
| CPU | Memory 범위 |
|-----|-------------|
| 1 | 128Mi - 4Gi |
| 2 | 256Mi - 8Gi |
| 4 | 512Mi - 16Gi |
| 8 | 1Gi - 32Gi |

### Terraform Backend Storage 접근 오류

**증상**: `Error 403: Caller does not have storage.objects.list access to the Google Cloud Storage bucket`

**원인**: github-actions 서비스 계정이 GCS bucket에 접근 권한 없음

**해결**:
```bash
# Storage Admin 권한 부여
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Workflow에서 Impersonation 설정 확인
# .github/workflows/deploy-gcp.yml
env:
  GOOGLE_IMPERSONATE_SERVICE_ACCOUNT: github-actions@PROJECT_ID.iam.gserviceaccount.com
```

### Artifact Registry 인증 오류

**증상**: `denied: Permission 'artifactregistry.repositories.uploadArtifacts' denied`

**원인**: Docker가 github-actions 서비스 계정 권한으로 인증하지 못함

**해결**:
```yaml
# Workflow 파일에서 명시적 impersonation 사용
- name: Configure Docker for Artifact Registry
  run: |
    gcloud auth print-access-token \
      --impersonate-service-account=github-actions@${{ vars.GCP_PROJECT_ID }}.iam.gserviceaccount.com | \
    docker login -u oauth2accesstoken --password-stdin https://${{ vars.GCP_REGION }}-docker.pkg.dev

# ❌ 잘못된 방법 (WIF 권한만으로는 부족)
- name: Configure Docker for Artifact Registry
  run: gcloud auth configure-docker ${{ vars.GCP_REGION }}-docker.pkg.dev
```

### Docker Build .env 파일 오류

**증상**: `env file .../backend/.env not found: no such file or directory`

**원인**: docker-compose.yml이 backend/.env 파일 존재를 확인함

**해결**:
```yaml
# Workflow에 .env 파일 생성 단계 추가
- name: Create dummy .env file
  run: |
    touch backend/.env

- name: Build and push images
  run: |
    docker compose build
    docker compose push
```

### 이미지 Pull 실패

```bash
# AWS ECR 로그인 확인
aws ecr get-login-password | docker login --username AWS --password-stdin

# GCP Artifact Registry 로그인 확인
gcloud auth configure-docker <REGION>-docker.pkg.dev
```

### 인프라 삭제

**GitHub Actions에서 수동 실행**:

1. GitHub 저장소 → **Actions** 탭
2. **"Destroy AWS Infrastructure"** 또는 **"Destroy GCP Infrastructure"** 선택
3. **"Run workflow"** 클릭
4. **Environment** 선택: dev / staging (prod는 선택 불가)

```bash
# 실행 결과
→ ECS Cluster, Services, Task Definitions 삭제 (AWS)
→ Cloud Run Services 삭제 (GCP)
→ ALB, Target Groups, Listeners 삭제 (AWS)
→ Security Groups 삭제 (AWS)
→ CloudWatch Log Groups 삭제 (AWS)
→ ECR Repositories 삭제 (이미지 포함) (AWS)
→ Artifact Registry 삭제 (이미지 포함) (GCP)
```

**⚠️ 권장사항**:

- **ECR/Artifact Registry**: 이미지 저장소는 별도로 관리하는 것을 권장합니다.
- **Production**: prod 환경은 destroy workflow를 제공하지 않습니다.
- **State 파일**: Terraform State는 S3/GCS에 보존됩니다.

---

## 🎯 Best Practices

**브랜치 전략**: feature → develop → staging → main 순차 배포

**환경 분리**: GitHub Environments로 dev/staging/prod 분리, 배포 승인 프로세스

**캐싱**: 의존성 및 Docker 레이어 캐싱으로 빌드 시간 단축

**병렬 실행**: 독립적인 Job은 병렬로 실행 (test-backend, test-frontend 등)

**보안**: Secrets 사용, CODEOWNERS 설정, 민감 정보 노출 방지

**알림**: 배포 실패 시 Slack/Email 알림 설정

---

## ✅ 완료 체크리스트

Section 6를 완료하기 전에 다음 항목을 확인하세요:

### GitHub 설정
- [ ] 3개의 브랜치 생성 (develop, staging, main)
- [ ] 3개의 Environments 생성 (development, staging, production)
- [ ] Environment Variables 설정 (각 환경별)
- [ ] Environment Secrets 설정 (각 환경별)

### AWS 설정
- [ ] `AWS_ACCESS_KEY_ID` 등록
- [ ] `AWS_SECRET_ACCESS_KEY` 등록
- [ ] `AWS_VPC_ID` 등록
- [ ] `AWS_PUBLIC_SUBNET_IDS` 등록
- [ ] S3 버킷 `metacode-terraform-state` 생성

### GCP 설정
- [ ] `GCP_PROJECT_ID` 등록
- [ ] `WIF_PROVIDER` 등록
- [ ] `WIF_SERVICE_ACCOUNT` 등록
- [ ] WIF Pool 및 Provider 생성
- [ ] 서비스 계정 생성 및 역할 부여
- [ ] GCS 버킷 `metacode-terraform-state` 생성

### 워크플로우 테스트
- [ ] develop 브랜치 푸시 → AWS/GCP development 환경 배포 확인
- [ ] staging 브랜치 푸시 → AWS/GCP staging 환경 배포 확인
- [ ] main 브랜치 푸시 → AWS/GCP production 환경 배포 확인 (승인 프로세스)

### 배포 검증
- [ ] AWS ECS 서비스 정상 동작 확인
- [ ] GCP Cloud Run 서비스 정상 동작 확인
- [ ] Health check 엔드포인트 응답 확인
- [ ] 로그 정상 출력 확인

### 문서화
- [ ] 팀원들에게 Secrets 설정 방법 공유
- [ ] 배포 프로세스 문서화
- [ ] 트러블슈팅 가이드 작성
- [ ] 롤백 절차 문서화
