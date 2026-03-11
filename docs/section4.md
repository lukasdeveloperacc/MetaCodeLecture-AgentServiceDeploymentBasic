# Section 4: GCP Cloud Run 배포

## 학습 목표
- AWS와 GCP 컨테이너 서비스 비교 이해
- Artifact Registry에 이미지 업로드
- Cloud Run으로 서버리스 컨테이너 배포
- Secret Manager로 시크릿 관리
- Cloud Logging 모니터링

## AWS ↔ GCP 서비스 비교

| AWS Service | GCP Service | 용도 | 주요 차이점 |
|-------------|-------------|------|------------|
| ECR | Artifact Registry | 컨테이너 이미지 저장소 | 유사한 기능 |
| ECS/Fargate | Cloud Run | 컨테이너 실행 | Cloud Run이 더 간단 (완전 서버리스) |
| Secrets Manager | Secret Manager | 시크릿 관리 | 유사한 기능 |
| CloudWatch Logs | Cloud Logging | 로그 수집/분석 | 유사한 기능 |
| CloudWatch Metrics | Cloud Monitoring | 메트릭 모니터링 | 유사한 기능 |
| ALB | Cloud Load Balancing | 로드 밸런싱 | Cloud Run이 자동 제공 |

**Cloud Run의 장점:**
- **완전 서버리스**: ALB, Target Group, Task Definition 등 인프라 관리 불필요
- **자동 스케일링**: 트래픽에 따라 0 ↔ N으로 자동 확장/축소
- **간단한 배포**: 단일 명령어로 배포 완료
- **비용 효율**: 요청이 없으면 자동으로 0으로 축소 → 비용 0원

## 배포 단계

### 1. gcloud CLI 설정

```bash
# gcloud CLI 설치 확인
gcloud version

# 인증
gcloud auth login

# 프로젝트 설정 (본인의 GCP 프로젝트 ID 입력)
gcloud config set project YOUR_PROJECT_ID

# 기본 리전 설정 (서울)
gcloud config set run/region asia-northeast3

# 현재 설정 확인
gcloud config list
```

### 2. 필요한 API 활성화

```bash
# 1. GCP Console 접속
# https://console.cloud.google.com/billing

# 2. 결제 계정 생성 또는 기존 계정 선택
# - "결제 계정 만들기" 클릭
# - 신용카드 정보 입력 (무료 크레딧 $300 제공)

# 3. 프로젝트에 결제 계정 연결
# - Billing > Account Management
# - "프로젝트 연결" 선택
# - 현재 프로젝트 (831546666724) 선택

# gcloud CLI로 결제 계정 확인 및 연결

# 현재 프로젝트 확인
gcloud config get-value project

# 사용 가능한 결제 계정 목록 확인
gcloud billing accounts list

# 결제 계정을 프로젝트에 연결
gcloud billing projects link PROJECT_ID \
--billing-account=BILLING_ACCOUNT_ID

# 결제 계정 연결 확인
gcloud billing projects describe PROJECT_ID

# Cloud Run API
gcloud services enable run.googleapis.com

# Artifact Registry API
gcloud services enable artifactregistry.googleapis.com

# Secret Manager API
gcloud services enable secretmanager.googleapis.com

# 활성화 확인
gcloud services list --enabled
```

### 3. Artifact Registry 생성

```bash
# Repository 생성
gcloud artifacts repositories create agent \
  --repository-format=docker \
  --location=asia-northeast3 \
  --description="Agent Service Container Images"

# 생성 확인
gcloud artifacts repositories list --location=asia-northeast3

# Docker 인증 설정
gcloud auth configure-docker asia-northeast3-docker.pkg.dev
```

### 4. Secret Manager에 API Key 저장

```bash
# OpenAI API Key 저장
echo -n "your-openai-api-key" | gcloud secrets create openai-api-key \
  --data-file=- \
  --replication-policy="automatic"

# Pinecone API Key 저장
echo -n "your-pinecone-api-key" | gcloud secrets create pinecone-api-key \
  --data-file=- \
  --replication-policy="automatic"

# Secret 생성 확인
gcloud secrets list

# Secret 내용 확인 (필요시)
gcloud secrets versions access latest --secret="openai-api-key"
```

**주의:** Secret은 한 번 생성하면 수정할 수 없으므로 처음부터 정확하게 입력하세요.

#### 4-1. Cloud Run 서비스 계정에 Secret 접근 권한 부여

**중요!** Cloud Run이 Secret Manager의 시크릿에 접근하려면 서비스 계정에 권한을 부여해야 합니다.

```bash
# 프로젝트 번호 확인
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) \
  --format="value(projectNumber)")

echo "Project Number: $PROJECT_NUMBER"

# Compute Engine 기본 서비스 계정에 Secret Manager Secret Accessor 역할 부여
gcloud projects add-iam-policy-binding $PROJECT_NUMBER \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 권한 부여 확인
gcloud projects get-iam-policy $PROJECT_NUMBER \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/secretmanager.secretAccessor"
```

**대안: 특정 Secret에만 권한 부여 (세밀한 제어)**

```bash
# OpenAI API Key에 대한 권한
gcloud secrets add-iam-policy-binding openai-api-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Pinecone API Key에 대한 권한
gcloud secrets add-iam-policy-binding pinecone-api-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 권한 확인
gcloud secrets get-iam-policy openai-api-key
gcloud secrets get-iam-policy pinecone-api-key
```

### 5. 컨테이너 이미지 빌드 및 푸시

#### 5-1. Backend 이미지 빌드 및 푸시

```bash
# 프로젝트 ID 확인
PROJECT_ID=$(gcloud config get-value project)
echo $PROJECT_ID

# Backend 이미지 빌드
docker build -t backend:v1 ./backend

# Artifact Registry 형식으로 태깅
docker tag backend:v1 \
  asia-northeast3-docker.pkg.dev/$PROJECT_NAME/agent/backend:v1

# Artifact Registry에 푸시
docker push asia-northeast3-docker.pkg.dev/$PROJECT_NAME/agent/backend:v1
```

#### 5-2. Frontend 이미지 빌드 및 푸시

```bash
# Frontend 이미지 빌드
docker build -t frontend:v1 ./frontend

# Artifact Registry 형식으로 태깅
docker tag frontend:v1 \
  asia-northeast3-docker.pkg.dev/$PROJECT_NAME/agent/frontend:v1

# Artifact Registry에 푸시
docker push asia-northeast3-docker.pkg.dev/$PROJECT_NAME/agent/frontend:v1
```

**참고:** AWS ECR과 다르게 태깅 형식이 `region-docker.pkg.dev/PROJECT_ID/REPO_NAME/IMAGE_NAME` 입니다.

#### 5-3. docker-compose를 이용한 통합 워크플로우

**docker-compose.yml을 활용하면 빌드, 태깅, 푸시를 더 효율적으로 관리할 수 있습니다.**

##### 5-3-1. 환경 변수 설정

프로젝트 루트에 `.env` 파일을 생성하여 GCP 프로젝트 ID를 설정합니다:

```bash
# .env 파일 생성
cat > .env << EOF
PROJECT_ID=$(gcloud config get-value project)
EOF

# 생성 확인
cat .env
# 출력: PROJECT_ID=your-project-id
```

##### 5-3-2. docker-compose.yml 확인

현재 프로젝트의 `docker-compose.yml`이 GCP Artifact Registry를 사용하도록 설정되어 있는지 확인:

```yaml
services:
  backend:
    image: asia-northeast3-docker.pkg.dev/${PROJECT_NAME}/agent/backend:v1
    build:
      context: ./backend
      dockerfile: Dockerfile
    # ...

  frontend:
    image: asia-northeast3-docker.pkg.dev/${PROJECT_NAME}/agent/frontend:v1
    build:
      context: ./frontend
      dockerfile: Dockerfile
    # ...
```

##### 5-3-3. docker-compose로 빌드 및 푸시

```bash
# 1. 프로젝트 ID 환경 변수 로드
export PROJECT_ID=$(gcloud config get-value project)

# 2. 이미지 빌드 (두 서비스 동시 빌드)
docker-compose build

# 3. 빌드된 이미지 확인
docker images | grep $PROJECT_ID

# 4. Artifact Registry에 푸시
docker-compose push

# 또는 빌드와 푸시를 한 번에
docker-compose build && docker-compose push
```

**장점:**
- 한 번의 명령으로 모든 서비스 빌드/푸시
- 일관된 이미지 태깅 관리
- 환경 변수로 프로젝트 ID 자동 적용
- 로컬 테스트와 배포 환경 통일

##### 5-3-4. 개별 서비스만 빌드/푸시

```bash
# Backend만 빌드 및 푸시
docker-compose build backend
docker-compose push backend

# Frontend만 빌드 및 푸시
docker-compose build frontend
docker-compose push frontend
```

##### 5-3-5. 빌드 캐시 없이 재빌드

코드 변경 사항을 확실히 반영하려면:

```bash
# 캐시 없이 전체 재빌드
docker-compose build --no-cache

# 특정 서비스만 캐시 없이 재빌드
docker-compose build --no-cache backend
```

#### 5-4. 이미지 업로드 확인

```bash
# Artifact Registry에 업로드된 이미지 확인
gcloud artifacts docker images list \
  asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent

# 특정 이미지의 태그 확인
gcloud artifacts docker images list \
  asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/backend \
  --include-tags
```

### 6. Cloud Run 서비스 배포

#### 6-1. Backend 배포

```bash
# Backend Cloud Run 배포
gcloud run deploy backend-dev \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/backend:v1 \
  --region asia-northeast3 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "ENVIRONMENT=development,LOG_LEVEL=INFO,PINECONE_INDEX_NAME=ai-service-docs-dev,LLM_MODEL=gpt-4o-mini,LLM_TEMPERATURE=0.7,LLM_MAX_TOKENS=1000,RAG_TOP_K=3,EMBEDDING_MODEL=text-embedding-3-small" \
  --set-secrets "OPENAI_API_KEY=openai-api-key:latest,PINECONE_API_KEY=pinecone-api-key:latest" \
  --cpu 2 \
  --memory 2Gi \
  --min-instances 0 \
  --max-instances 10 \
  --timeout 300 \
  --port 8000

# 배포 완료 후 서비스 URL 확인
gcloud run services describe backend-dev \
  --region asia-northeast3 \
  --format="value(status.url)"
```

#### 6-2. Frontend 배포

```bash
# Frontend Cloud Run 배포
gcloud run deploy frontend-dev \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/frontend:v1 \
  --region asia-northeast3 \
  --platform managed \
  --allow-unauthenticated \
  --cpu 1 \
  --memory 512Mi \
  --min-instances 0 \
  --max-instances 5 \
  --port 80

# 배포 완료 후 서비스 URL 확인
gcloud run services describe frontend-dev \
  --region asia-northeast3 \
  --format="value(status.url)"
```

#### 6-3. 배포 상태 확인

```bash
# 모든 Cloud Run 서비스 목록
gcloud run services list --region asia-northeast3

# Backend 서비스 상세 정보
gcloud run services describe backend-dev --region asia-northeast3

# Frontend 서비스 상세 정보
gcloud run services describe frontend-dev --region asia-northeast3
```

### 7. Frontend 프록시 설정 업데이트

**중요!** Cloud Run은 각 서비스마다 고유한 URL을 제공합니다. Frontend가 Backend를 호출하려면 Backend의 Cloud Run URL을 사용해야 합니다.

#### 7-1. Backend URL 확인

```bash
# Backend Cloud Run URL 확인
BACKEND_URL=$(gcloud run services describe backend-dev \
  --region asia-northeast3 \
  --format="value(status.url)")

echo "Backend URL: $BACKEND_URL"
# 출력 예시: https://backend-dev-xxxxx-an.a.run.app
```

#### 7-2. Frontend nginx.conf 수정

**중요:** Backend가 SSE(Server-Sent Events) 스트리밍을 사용하므로 nginx에서 버퍼링을 완전히 비활성화해야 합니다.

```nginx
# frontend/nginx.conf 파일 수정

# 기존 설정 (docker-compose 용)
location /api/ {
    proxy_pass http://backend:8000/;  # docker-compose 서비스 이름
    ...
}

# Cloud Run용으로 변경 (SSE 스트리밍 지원)
location /api/ {
    # Backend Cloud Run URL로 프록시
    proxy_pass https://backend-xxxxx-an.a.run.app/;

    proxy_http_version 1.1;

    # SSE(Streaming)를 위한 설정 - 버퍼링 완전히 비활성화
    proxy_set_header Connection '';
    proxy_buffering off;
    proxy_cache off;
    chunked_transfer_encoding on;
    proxy_read_timeout 300s;

    # 백엔드 호스트로 요청 전달
    proxy_set_header Host backend-xxxxx-an.a.run.app;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # nginx 버퍼링 완전히 비활성화
    add_header X-Accel-Buffering no;
}
```

**주요 설정 설명:**
- `proxy_pass`: HTTPS URL 사용 (Cloud Run은 HTTPS 제공)
- `proxy_set_header Host`: Backend의 실제 도메인 설정 (Cloud Run은 Host 헤더 검증)
- `proxy_buffering off`: nginx 프록시 버퍼링 비활성화
- `proxy_cache off`: 캐싱 비활성화
- `chunked_transfer_encoding on`: 청크 전송 인코딩 활성화 (스트리밍 필수)
- `proxy_read_timeout 300s`: 타임아웃 5분 설정 (긴 스트리밍 응답 처리)
- `add_header X-Accel-Buffering no`: nginx 버퍼링 완전히 비활성화 (응답 헤더에 추가)

#### 7-3. Backend CORS 설정 업데이트

```python
# backend/app/main.py (또는 해당 파일)
from fastapi.middleware.cors import CORSMiddleware

# Frontend Cloud Run URL을 CORS 허용 목록에 추가
ALLOWED_ORIGINS = [
    "http://localhost:1235",  # 로컬 개발용
    "https://frontend-xxxxx-an.a.run.app",  # Frontend Cloud Run URL
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

#### 7-4. 재빌드 및 재배포

```bash
# 프로젝트 ID 확인
PROJECT_ID=$(gcloud config get-value project)

# Frontend 재빌드 (nginx.conf 변경 반영)
docker compose build --no-cache frontend
docker compose push frontend

# Backend 재빌드 (CORS 설정 변경 반영)
docker compose build --no-cache backend
docker compose push backend

# Cloud Run 재배포
gcloud run deploy frontend-dev  \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/frontend:v1 \
  --region asia-northeast3

gcloud run deploy backend-dev \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/backend:v1 \
  --region asia-northeast3
```

**참고:** `gcloud run deploy` 명령에 최소한의 옵션만 주면 기존 설정을 유지하며 이미지만 업데이트됩니다.

#### 7-5. 동작 확인

```bash
# Frontend URL 접속 테스트
FRONTEND_URL=$(gcloud run services describe frontend-dev \
  --region asia-northeast3 \
  --format="value(status.url)")

curl $FRONTEND_URL
# → Frontend HTML 응답 확인

# Backend URL 직접 테스트
BACKEND_URL=$(gcloud run services describe backend-dev \
  --region asia-northeast3 \
  --format="value(status.url)")

curl $BACKEND_URL/health
# → {"status": "healthy"}

# 브라우저에서 Frontend URL 접속 후 API 호출 테스트
echo "Frontend: $FRONTEND_URL"
echo "Backend: $BACKEND_URL"
```

## Cloud Logging 모니터링

### 로그 확인

```bash
# Backend 실시간 로그 스트리밍
gcloud logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=backend" \
  --format=json

# 최근 1시간 로그 조회
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=backend" \
  --limit 50 \
  --format json \
  --freshness 1h

# 에러 로그만 조회
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=backend AND severity>=ERROR" \
  --limit 20 \
  --format json
```

### GCP Console에서 로그 확인

```
GCP Console > Logging > Logs Explorer

필터 예시:
resource.type="cloud_run_revision"
resource.labels.service_name="backend"
severity="ERROR"
```

### 주요 메트릭 (Cloud Console)

Cloud Run 서비스를 선택하면 자동으로 다음 메트릭을 확인할 수 있습니다:
- **Request Count**: 요청 수
- **Request Latency**: 응답 시간
- **Container Instance Count**: 실행 중인 인스턴스 수
- **Billable Instance Time**: 과금 시간
- **CPU Utilization**: CPU 사용률
- **Memory Utilization**: 메모리 사용률

## Cloud Run 주요 기능

### Auto Scaling (자동 확장)

```bash
# min-instances=0: 트래픽 없으면 완전히 종료 (비용 0원)
# max-instances=10: 최대 10개까지 자동 확장

# 설정 확인
gcloud run services describe backend \
  --region asia-northeast3 \
  --format="value(spec.template.metadata.annotations)"
```

**작동 방식:**
- 요청 증가 → 자동으로 인스턴스 추가
- 요청 감소 → 자동으로 인스턴스 제거
- 트래픽 0 → min-instances=0이면 모든 인스턴스 종료

### Cold Start (콜드 스타트)

**콜드 스타트란?**
- 모든 인스턴스가 종료된 상태에서 첫 요청이 들어올 때
- 컨테이너를 시작하는 데 걸리는 시간 (2-5초)

**최적화 방법:**
```bash
# 방법 1: min-instances 설정 (비용 증가)
gcloud run services update backend \
  --min-instances 1 \
  --region asia-northeast3

# 방법 2: Startup CPU Boost (Cold Start 시 CPU 증가)
gcloud run services update backend \
  --cpu-boost \
  --region asia-northeast3

# 방법 3: 이미지 경량화 (Dockerfile 최적화)
# - 불필요한 패키지 제거
# - Multi-stage build 사용
```

### 트래픽 분할 (Canary Deployment)

```bash
# 1. 새 버전 배포 (트래픽 0%)
gcloud run deploy backend \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/backend:v2 \
  --region asia-northeast3 \
  --no-traffic

# 2. 트래픽 10%만 새 버전으로
gcloud run services update-traffic backend \
  --to-revisions LATEST=10 \
  --region asia-northeast3

# 3. 문제 없으면 100% 전환
gcloud run services update-traffic backend \
  --to-latest \
  --region asia-northeast3

# 4. Revision 목록 확인
gcloud run revisions list --service backend --region asia-northeast3
```

## 비용 최적화

### Cloud Run 비용 구조

```
비용 = (vCPU 시간 × vCPU 가격) + (Memory 시간 × Memory 가격) + (Request 수 × Request 가격)
```

**서울 리전 (asia-northeast3) 가격:**
- vCPU: $0.00002400/vCPU-second
- Memory: $0.00000250/GiB-second
- Requests: $0.40/million requests
- **무료 할당량**: 월 200만 요청, 36만 vCPU-second, 10만 GiB-second

### 최적화 전략

#### 1. min-instances=0 설정
```bash
# 트래픽 없을 때 완전 종료 → 비용 0원
gcloud run services update backend \
  --min-instances 0 \
  --region asia-northeast3
```

#### 2. 적절한 리소스 할당
```bash
# CPU/Memory를 필요한 만큼만 할당
# 과도한 할당 = 비용 낭비

# 현재 리소스 확인
gcloud run services describe backend \
  --region asia-northeast3 \
  --format="value(spec.template.spec.containers[0].resources.limits)"
```

#### 3. Request Timeout 최적화
```bash
# 불필요하게 긴 timeout은 과금 시간 증가
gcloud run services update backend \
  --timeout 60 \
  --region asia-northeast3
```

#### 4. 비용 모니터링
```bash
# 비용 확인 (GCP Console)
# Billing > Reports > Cloud Run 필터
```

### 예상 비용 계산 예시

```
시나리오: 하루 1,000 요청, 평균 응답 시간 2초, 2 vCPU, 2 GiB Memory

일일 비용:
- vCPU: 1,000 요청 × 2초 × 2 vCPU × $0.000024 = $0.096
- Memory: 1,000 요청 × 2초 × 2 GiB × $0.0000025 = $0.010
- Requests: 1,000 / 1,000,000 × $0.40 = $0.0004

일일 총 비용: $0.1064
월 비용: $3.19 (30일 기준)

무료 할당량 고려 시: 거의 무료!
```

## 트러블슈팅

### 1. Cold Start 지연

**증상:** 첫 요청이 느림 (2-5초)

**해결 방법:**

```bash
# 방법 1: min-instances 설정 (비용 증가)
gcloud run services update backend \
  --min-instances 1 \
  --region asia-northeast3

# 방법 2: CPU Boost 활성화
gcloud run services update backend \
  --cpu-boost \
  --region asia-northeast3

# 방법 3: 이미지 경량화
# Dockerfile에서 불필요한 패키지 제거
```

### 2. Secret 접근 실패

**증상:** `Permission denied on secret` 오류

**원인:** Cloud Run 서비스 계정에 Secret Manager Secret Accessor 역할이 없음

**해결 방법:**

```bash
# 1. Secret Manager API 활성화 확인
gcloud services list --enabled | grep secretmanager

# 2. Secret 존재 확인
gcloud secrets list

# 3. Secret 이름 정확한지 확인 (대소문자 구분)
gcloud secrets describe openai-api-key

# 4. 프로젝트 번호 확인
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) \
  --format="value(projectNumber)")

# 5. 서비스 계정에 Secret Manager Secret Accessor 역할 부여
gcloud projects add-iam-policy-binding $PROJECT_NUMBER \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 6. 권한 부여 확인
gcloud projects get-iam-policy $PROJECT_NUMBER \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/secretmanager.secretAccessor"

# 7. 권한 부여 후 Cloud Run 재배포
gcloud run deploy backend-dev \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/backend:v1 \
  --region asia-northeast3
```

**참고:** Section 4-1에서 미리 권한을 부여했다면 이 오류는 발생하지 않습니다.

### 3. 503 Service Unavailable

**증상:** 서비스 접속 불가

**해결 방법:**

```bash
# 1. 로그 확인
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=backend" \
  --limit 20 \
  --format json

# 2. 배포 상태 확인
gcloud run services describe backend --region asia-northeast3

# 3. 컨테이너 포트 확인
# Cloud Run에 지정한 포트와 컨테이너의 EXPOSE 포트가 일치하는지 확인

# 4. 재배포 시도
gcloud run deploy backend \
  --image asia-northeast3-docker.pkg.dev/$PROJECT_ID/agent/backend:v1 \
  --region asia-northeast3
```

### 4. Frontend에서 Backend API 호출 실패

**증상:** CORS 오류 또는 연결 실패

**해결 방법:**

```bash
# 1. Backend URL 확인
gcloud run services describe backend \
  --region asia-northeast3 \
  --format="value(status.url)"

# 2. Frontend nginx.conf 확인
# proxy_pass에 정확한 Backend URL이 설정되었는지 확인

# 3. Backend CORS 설정 확인
# Frontend Cloud Run URL이 ALLOWED_ORIGINS에 추가되었는지 확인

# 4. 브라우저 개발자 도구 Network 탭 확인
# 실제 요청 URL과 응답 상태 코드 확인
```

### 5. 이미지 푸시 실패

**증상:** `denied: Permission "artifactregistry.repositories.uploadArtifacts" denied`

**해결 방법:**

```bash
# 1. Docker 인증 재설정
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 2. Artifact Registry API 활성화 확인
gcloud services list --enabled | grep artifactregistry

# 3. Repository 존재 확인
gcloud artifacts repositories list --location=asia-northeast3

# 4. 권한 확인 (본인 계정이 Artifact Registry Writer 권한 보유)
gcloud projects get-iam-policy $(gcloud config get-value project)
```

### 6. 배포 후 환경 변수/시크릿이 반영되지 않음

**증상:** 애플리케이션에서 환경 변수를 읽을 수 없음

**해결 방법:**

```bash
# 1. 현재 설정 확인
gcloud run services describe backend \
  --region asia-northeast3 \
  --format="value(spec.template.spec.containers[0].env)"

# 2. 환경 변수 업데이트
gcloud run services update backend \
  --set-env-vars "KEY1=value1,KEY2=value2" \
  --region asia-northeast3

# 3. Secret 재설정
gcloud run services update backend \
  --set-secrets "API_KEY=secret-name:latest" \
  --region asia-northeast3

# 4. 로그에서 환경 변수 확인 (애플리케이션 로그)
gcloud logging read "resource.labels.service_name=backend" --limit 10
```

## 완료 체크리스트

### 기본 설정
- [ ] gcloud CLI가 설정되었는가?
- [ ] 필요한 GCP API가 모두 활성화되었는가?
- [ ] Artifact Registry Repository가 생성되었는가?
- [ ] Secret Manager에 API Key가 저장되었는가?
- [ ] Docker 인증이 설정되었는가 (configure-docker)?

### 이미지 빌드 및 배포
- [ ] Backend 이미지가 빌드되고 Artifact Registry에 푸시되었는가?
- [ ] Frontend 이미지가 빌드되고 Artifact Registry에 푸시되었는가?
- [ ] Artifact Registry에서 이미지를 확인할 수 있는가?

### Cloud Run 배포
- [ ] Backend Cloud Run 서비스가 배포되었는가?
- [ ] Frontend Cloud Run 서비스가 배포되었는가?
- [ ] 각 서비스의 URL을 확인했는가?
- [ ] 환경 변수와 시크릿이 올바르게 설정되었는가?

### 프록시 및 CORS 설정
- [ ] Frontend nginx.conf에 Backend Cloud Run URL이 설정되었는가?
- [ ] Backend CORS 설정에 Frontend Cloud Run URL이 추가되었는가?
- [ ] 재빌드 및 재배포가 완료되었는가?

### 동작 확인
- [ ] Frontend URL로 접속이 가능한가?
- [ ] Backend URL로 직접 API 호출이 가능한가? (/health 엔드포인트)
- [ ] Frontend에서 Backend API 호출이 정상 작동하는가?
- [ ] Cloud Logging에서 로그가 확인되는가?

### 최적화 및 모니터링
- [ ] Auto Scaling 설정이 적절한가? (min-instances, max-instances)
- [ ] Cold Start 시간이 허용 범위 내인가?
- [ ] 비용 모니터링을 설정했는가?
- [ ] 알림 설정을 고려했는가? (선택 사항)

## 참고: AWS와 GCP 배포 비교

| 항목 | AWS (ECS/Fargate) | GCP (Cloud Run) |
|------|-------------------|-----------------|
| **인프라 관리** | Task Definition, Service, ALB, Target Group | 단일 명령어 배포 |
| **네트워크 설정** | VPC, Subnet, Security Group 설정 필요 | 자동 관리 (설정 불필요) |
| **로드 밸런싱** | ALB 별도 생성 및 설정 | 자동 제공 |
| **스케일링** | Service Auto Scaling 설정 | 기본 제공 (0 ↔ N) |
| **로그 관리** | CloudWatch Log Group 사전 생성 필요 | 자동 생성 |
| **배포 복잡도** | 높음 (여러 단계) | 낮음 (간단) |
| **비용 구조** | 항상 최소 인스턴스 실행 | 요청 없으면 0원 |
| **Cold Start** | 없음 (항상 실행) | 있음 (2-5초) |

**선택 기준:**
- **GCP Cloud Run**: 간단한 배포, 서버리스, 비용 최적화 우선
- **AWS ECS/Fargate**: 세밀한 제어, 복잡한 네트워크 구성 필요, Cold Start 없어야 함

## 다음 단계

Section 4를 완료했다면 다음 내용을 학습하세요:
- **Section 5**: Terraform을 사용한 Infrastructure as Code (IaC)
- **Section 6**: GitHub Actions를 사용한 CI/CD 파이프라인
- **Section 7**: 프로덕션 운영 및 모니터링
