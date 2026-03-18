# Section 7: 실전 운영 노하우

---

## 학습 목표

- **구조화된 로깅**으로 프로덕션 디버깅 시간 대폭 단축
- **클라우드 비용을 절감**하는 실전 최적화 전략 (일반적으로 20-40% 범위)
- **Circuit Breaker**로 배포 실패 자동 감지 및 롤백 (AWS re:Invent 2024에서 권장)
- **보안 체크리스트**로 프로덕션 배포 전 필수 항목 검증
- **장애 대응 플레이북**으로 긴급 상황 빠른 복구

---

## 🎯 왜 운영 노하우가 중요한가?

### 개발 vs 운영의 차이

| 단계 | 개발 환경 | 프로덕션 환경 |
|------|-----------|--------------|
| **에러 발생** | 즉시 확인 가능 | 사용자 신고 후 알게 됨 |
| **디버깅** | print문으로 확인 | 로그를 통해서만 추적 가능 |
| **장애 영향** | 영향 범위가 제한적 | 다수 사용자에게 직접 영향 |
| **비용** | 무시 가능 | 월 수백만 원 |
| **복구 시간** | 비교적 자유롭게 재시작 가능 | 서비스에 따라 짧은 장애도 매출·신뢰도에 직접 영향 |

### 실무에서 중요한 포인트 (2024년 기준)
- 많은 기업이 클라우드 비용 최적화를 최우선 과제로 선정
- 구조화된 로깅으로 **디버깅 시간 대폭 단축** 가능
- Circuit Breaker 사용 시 **배포 실패 자동 복구** 가능
- 적절한 운영 전략으로 **상당한 비용 절감** 달성 가능 (일반적으로 20-40% 범위)

---

## 1. 효과적인 로깅과 디버깅 (10분)

### 1-1. 구조화된 로깅의 위력 (3분)

#### 일반 텍스트 로깅의 문제점

```python
# ❌ 나쁜 예: 검색/필터링 불가능
print("User 123 requested /api/chat at 2024-03-17 14:30:00")
print("Error: API rate limit exceeded")
```

**문제**:
- 로그 검색 어려움 (어떻게 "User 123"의 모든 요청을 찾을까?)
- 에러 집계 불가능 (같은 에러가 몇 번 발생했는지?)
- 분산 추적 불가능 (하나의 요청이 여러 서비스를 거칠 때)

#### 구조화된 JSON 로깅

프로젝트의 `backend/app.py:25-46` 구현:

```python
class TraceIdFormatter(logging.Formatter):
    """trace_id가 없는 로그 레코드에 기본값을 제공"""
    def format(self, record):
        if not hasattr(record, 'trace_id'):
            record.trace_id = 'N/A'
        return super().format(record)

# JSON 포맷 로깅 설정
handler = logging.StreamHandler()
handler.setFormatter(TraceIdFormatter(
    '{"time": "%(asctime)s", "level": "%(levelname)s", "trace_id": "%(trace_id)s", "message": "%(message)s"}'
))
logger.addHandler(handler)
```

**실행 결과**:
```json
{"time": "2024-03-17 14:30:00", "level": "INFO", "trace_id": "abc-123", "message": "User 123 requested /api/chat"}
{"time": "2024-03-17 14:30:01", "level": "ERROR", "trace_id": "abc-123", "message": "API rate limit exceeded"}
```

**장점**:
- ✅ trace_id로 하나의 요청 전체 흐름 추적
- ✅ level별 필터링 (ERROR만 모아보기)
- ✅ 자동 집계 가능 (같은 에러 발생 횟수)
- ✅ CloudWatch/GCP Logging에서 쿼리 가능

#### trace_id의 중요성

**MSA 환경**에서 하나의 사용자 요청이 여러 서비스를 거칠 때:

```
사용자 요청 (trace_id: abc-123)
  → Frontend (로그: trace_id=abc-123)
  → Backend API (로그: trace_id=abc-123)
  → Vector DB (로그: trace_id=abc-123)
  → LLM API (로그: trace_id=abc-123)
```

trace_id로 검색하면 **전체 흐름을 한눈에** 볼 수 있습니다!

---

### 1-2. CloudWatch/GCP Logging 실전 활용 (4분)

#### AWS CloudWatch Logs Insights

**기본 로그 확인**:
```bash
# 실시간 로그 스트리밍 (Ctrl+C로 종료)
aws logs tail /ecs/backend-dev --follow --region ap-northeast-2
```

**CloudWatch Insights 쿼리** (Console에서 실행):

```
# 1. 특정 trace_id의 모든 로그 추적
fields @timestamp, trace_id, level, message
| filter trace_id = "abc-123"
| sort @timestamp asc
| limit 1000
```

```
# 2. 최근 1시간 ERROR 로그만 모아보기
fields @timestamp, level, message, trace_id
| filter level = "ERROR"
| filter @timestamp > ago(1h)
| sort @timestamp desc
| limit 100
```

```
# 3. 에러 발생 빈도 집계 (어떤 에러가 가장 많이 발생하는가?)
fields message
| filter level = "ERROR"
| stats count() by message
| sort count desc
```

```
# 4. 특정 사용자의 요청 패턴 분석
fields @timestamp, trace_id, message
| filter message like /User 123/
| sort @timestamp asc
```

**주요 함수**:
- `filter`: 조건 필터링
- `fields`: 출력할 필드 선택
- `stats`: 집계 (count, avg, sum 등)
- `sort`: 정렬
- `limit`: 결과 개수 제한

#### GCP Cloud Logging

**기본 로그 확인**:
```bash
# 실시간 로그 스트리밍 (alpha 명령어 사용)
gcloud alpha logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=backend-dev" --format=json
```

**Cloud Logging 고급 필터** (Console에서):

```
# 1. 특정 trace_id 추적
resource.type="cloud_run_revision"
resource.labels.service_name="backend-dev"
jsonPayload.trace_id="abc-123"
```

```
# 2. ERROR 레벨 로그만
resource.type="cloud_run_revision"
severity="ERROR"
timestamp>="2024-03-17T00:00:00Z"
```

```
# 3. 특정 메시지 패턴 검색 (정규표현식)
resource.type="cloud_run_revision"
jsonPayload.message=~"API.*failed"
```

#### 로그 보관 기간 설정

프로젝트의 CloudWatch 설정 (`terraform/aws/cloudwatch.tf:23`):

```hcl
resource "aws_cloudwatch_log_group" "backend" {
  name = "/ecs/backend-${var.environment}"

  # 로그 보관 기간 (일) - 비용 절감을 위해 7일로 설정
  retention_in_days = 7

  tags = {
    Name = "backend-${var.environment}-logs"
  }
}
```

**환경별 권장 보관 기간**:
- Dev: 3일 (테스트용, 최소 비용)
- Staging: 7일 (QA 검증용)
- Production: 30-90일 (규정 준수, 장기 분석)

**비용 영향** (CloudWatch Logs 기준):
- **로그 수집(Ingestion)**: $0.50/GB
- **로그 저장(Storage)**: $0.03/GB/월
- 예시: 1GB 로그를 약 1개월 보관하면 대략 $0.50(수집) + $0.03(저장) 수준이며, 실제 비용은 리전·로그 클래스·조회량에 따라 달라질 수 있습니다
- 무제한 보관: 저장 비용이 지속적으로 누적 (비용 폭발 위험!)

---

### 1-3. 프로덕션 디버깅 시나리오 (3분)

#### 실전 예시: "사용자가 API 호출 실패 신고"

**상황**: 고객이 "채팅 API가 동작하지 않는다"고 신고

**Step 1: trace_id 확인**
```bash
# Frontend 로그에서 해당 요청의 trace_id 찾기
aws logs tail /ecs/frontend-prod --follow | grep "User 123"
# → trace_id: xyz-789 발견
```

**Step 2: trace_id로 전체 흐름 추적**
```
# CloudWatch Insights
fields @timestamp, trace_id, level, message
| filter trace_id = "xyz-789"
| sort @timestamp asc
```

**발견된 로그 흐름**:
```json
{"time": "14:30:00", "level": "INFO", "trace_id": "xyz-789", "message": "Request received"}
{"time": "14:30:01", "level": "INFO", "trace_id": "xyz-789", "message": "Calling OpenAI API"}
{"time": "14:30:15", "level": "ERROR", "trace_id": "xyz-789", "message": "OpenAI API timeout after 15s"}
{"time": "14:30:15", "level": "ERROR", "trace_id": "xyz-789", "message": "Request failed: 504 Gateway Timeout"}
```

**원인 파악**: OpenAI API 응답 시간 초과 (15초)

**Step 3: 동일 에러 빈도 확인** (1회 오류 vs 대규모 장애?)
```
# 최근 1시간 동안 동일 에러 발생 횟수 확인
fields message
| filter level = "ERROR"
| filter message like /OpenAI API timeout/
| filter @timestamp > ago(1h)
| stats count()
```

**결과**:
- count = 1 → 일시적 네트워크 오류 (재시도 안내)
- count = 1000 → OpenAI API 장애 (긴급 대응 필요)

**Step 4: 해결 방안**
- 단기: 타임아웃 시간 늘리기 (15s → 30s)
- 중기: Retry 로직 추가 (3회 재시도)
- 장기: Circuit Breaker로 외부 API 장애 격리

---

## 2. 클라우드 비용 최적화 전략 (8분)

### 2-1. 환경별 Right-Sizing 전략 (3분)

#### 프로젝트의 환경별 리소스 설정

**현재 설정 분석**:

프로젝트는 환경별로 다른 리소스를 할당합니다 (`terraform/aws/terraform.tfvars.example`):

```hcl
# Development 환경
environment = "dev"
backend_cpu = "512"      # 0.5 vCPU
backend_memory = "1024"  # 1GB
backend_desired_count = 1

# Staging 환경
environment = "stag"
backend_cpu = "1024"     # 1 vCPU
backend_memory = "2048"  # 2GB
backend_desired_count = 2

# Production 환경
environment = "prod"
backend_cpu = "2048"     # 2 vCPU
backend_memory = "4096"  # 4GB
backend_desired_count = 3
```

#### 환경별 설정 철학

| 환경 | 목적 | 리소스 전략 | 비용 |
|------|------|------------|------|
| **Development** | 기능 테스트 | 최소 리소스, 단일 인스턴스 | 최소 |
| **Staging** | QA 검증, 부하 테스트 | 중간 리소스, 2개 인스턴스 | 중간 |
| **Production** | 실 서비스 | 충분한 여유, 3개 이상 인스턴스 | 최대 |

**핵심 원칙**:
1. **Dev는 "동작 여부"만 확인** → 최소 리소스로 비용 절감
2. **Staging은 "실제와 유사한 환경"** → Prod의 70% 수준
3. **Prod는 "트래픽 급증 대비"** → 평소 사용량의 2배 여유

#### GCP Cloud Run의 비용 장점

```hcl
# terraform/gcp/variables.tf
backend_min_instances = 0  # 트래픽 없을 때 인스턴스 0개
backend_max_instances = 5  # 트래픽 많을 때 자동 확장
```

**Request-based Billing**:
- **min instances=0**이고 request-based billing을 사용하는 일반적인 서비스에서는 유휴 시 비용을 크게 줄일 수 있습니다
- 요청이 들어올 때만 과금 (Cold Start 발생)
- Dev/Staging 환경에 최적 (업무시간에만 사용)

**AWS ECS vs GCP Cloud Run 비용 비교** (예시 시나리오, 실제 비용은 리소스 및 사용 패턴에 따라 변동):

| 시나리오 | AWS ECS Fargate | GCP Cloud Run |
|---------|-----------------|---------------|
| **24시간 가동** (Dev) | 지속적 과금 | 요청 기반 과금 |
| **트래픽 급증** | 고정 인스턴스 수 | 자동 확장 (max 제한) |
| **야간/주말** | 동일 비용 | 트래픽 없으면 비용 최소화 |

---

### 2-2. 즉시 적용 가능한 비용 절감 팁 (3분)

#### 🎯 실전 팁 Top 5

**1. Spot/Preemptible 인스턴스 활용**

Spot을 활용하면 일반 Fargate 대비 비용을 크게 절감할 수 있습니다.

AWS Fargate Spot:
```hcl
# terraform/aws/ecs.tf 서비스 설정에 추가
capacity_provider_strategy {
  capacity_provider = "FARGATE_SPOT"
  weight            = 70  # 70%는 Spot 사용
  base              = 0
}

capacity_provider_strategy {
  capacity_provider = "FARGATE"
  weight            = 30  # 30%는 일반 Fargate (안정성)
  base              = 1   # 최소 1개는 일반 Fargate
}
```

**주의사항**:
- Spot은 언제든 중단될 수 있음 (2분 전 경고)
- 중요한 작업은 일반 인스턴스 사용
- Dev/Staging은 100% Spot 가능

**2. 로그 보관 기간 최적화**

현재 설정 (`terraform/aws/cloudwatch.tf:23`):
```hcl
retention_in_days = 7  # 모든 환경 동일
```

**개선안**:
```hcl
# 환경별 차등 적용
retention_in_days = var.environment == "prod" ? 30 : (var.environment == "stag" ? 7 : 3)
```

**비용 절감 효과**:
- Dev: 7일 → 3일 (비용 60% 절감)
- Staging: 7일 유지
- Prod: 7일 → 30일 (규정 준수)

**3. ECR/Artifact Registry 이미지 라이프사이클 정책**

**현재 문제**: 이미지가 무한히 누적 → 스토리지 비용 증가

```bash
# 현재 이미지 개수 확인
aws ecr list-images --repository-name backend-dev --query 'imageIds[*]' --output text | wc -l
# → 100개 이상?
```

**해결책**: 오래된 이미지 자동 삭제

```hcl
# terraform/aws/ecr.tf에 추가
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
```

**효과**: 이미지 10개만 유지 → 스토리지 비용 90% 절감

**4. Container Insights 선택적 활성화**

현재 설정 (`terraform/aws/ecs.tf:32`):
```hcl
setting {
  name  = "containerInsights"
  value = "disabled"  # 모든 환경 비활성화
}
```

**Container Insights란?**:
- ECS Task/Service의 상세 메트릭 수집
- CPU, Memory, Network 사용량을 세밀하게 모니터링
- **비용**: Container Insights는 추가 메트릭과 로그 수집 비용이 발생하므로, 프로덕션처럼 상세 관측이 필요한 환경에 선택적으로 활성화하는 것이 일반적입니다

**권장 설정**:
- Dev/Staging: disabled (기본 메트릭만 사용)
- Production: enabled (상세 모니터링 필요)

```hcl
value = var.environment == "prod" ? "enabled" : "disabled"
```

**5. 개발 환경 자동 삭제 전략**

**전략**: 업무 시간에만 Dev 환경 가동

```bash
# 퇴근 시 (18:00)
terraform destroy -auto-approve  # Dev 환경 삭제 → 비용 0원

# 출근 시 (09:00)
terraform apply -auto-approve    # Dev 환경 재생성 (5분 소요)
```

**자동화 방법**:
- GitHub Actions Scheduled Workflow (Cron)
- AWS Lambda + EventBridge (시간 트리거)

**비용 절감 효과**:
- Dev 환경: $30/월 → $10/월 (약 67% 절감)
- 업무 시간 (9-18시, 9시간) = 하루의 37%만 가동

---

### 2-3. 비용 모니터링 설정 (2분)

#### AWS Cost Management

**1. Cost Explorer 활성화**
- AWS Console → Cost Explorer
- 환경별 비용 확인 (태그 기반)
- 월별/일별 트렌드 분석

**2. Budget Alerts 설정**
```bash
# AWS CLI로 Budget 생성 (예시 - 실제 사용 시 account-id와 JSON 구조 확인 필요)
aws budgets create-budget \
  --account-id 123456789012 \  # 본인의 AWS Account ID로 변경
  --budget '{
    "BudgetName": "dev-monthly-budget",
    "BudgetLimit": {
      "Amount": "50",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80
      },
      "Subscribers": [{
        "SubscriptionType": "EMAIL",
        "Address": "team@example.com"
      }]
    }
  ]'
```

**알림 시나리오**:
- 예산의 80% 도달 → 경고 이메일
- 예산의 100% 도달 → 긴급 알림
- 예산의 120% 도달 → 자동 리소스 축소 (Lambda)

#### GCP Billing Budget

**Console에서 설정**:
1. Billing → Budgets & alerts
2. Create budget
3. 프로젝트별/서비스별 한도 설정
4. 50%, 80%, 100% 초과 시 알림

**프로그래매틱 알림**:
```bash
# Pub/Sub으로 예산 초과 시 자동 대응
gcloud pubsub topics create billing-alert
gcloud functions deploy budget-alert-handler \
  --trigger-topic=billing-alert \
  --runtime=python310
```

#### 리소스 태깅 전략

**모든 리소스에 태그 추가**:

```hcl
# terraform/aws/ecs.tf
tags = {
  Name        = "backend-${var.environment}"
  Environment = var.environment
  Team        = "backend"
  CostCenter  = "engineering"
  Project     = "ai-service"
}
```

**태그 기반 비용 분리**:
- 환경별: dev, staging, prod
- 팀별: backend, frontend, data
- 프로젝트별: ai-service, analytics

**Cost Allocation Tags**:
- AWS Console → Billing → Cost Allocation Tags
- 태그 활성화 → Cost Explorer에서 필터링 가능

---

## 3. 배포 안전성과 Circuit Breaker (5분)

### 3-1. Circuit Breaker란? (2분)

#### 배포 실패의 일반적인 시나리오

**문제 상황**:
```
1. 새 버전 배포 시작
2. Task가 시작되지만 즉시 Health Check 실패
3. ECS가 Task를 종료하고 다시 시작
4. 또 실패 → 무한 재시작 루프
5. 결국 모든 Task가 실패 상태
6. 서비스 완전 중단! 💥
```

**수동 개입 필요**:
- 개발자가 로그 확인 → 원인 파악
- 이전 버전으로 수동 롤백
- 소요 시간: 10-30분 (서비스 중단 시간)

#### Circuit Breaker의 자동 보호

**AWS re:Invent 2024에서 프로덕션 환경에서 권장되는 중요한 기능으로 소개**

```hcl
# terraform/aws/ecs.tf 서비스 설정에 추가
resource "aws_ecs_service" "backend" {
  # ... 기존 설정 ...

  # 🔥 Circuit Breaker (배포 안전 장치)
  deployment_circuit_breaker {
    enable   = true
    rollback = true  # 실패 시 자동 롤백
  }

  deployment_configuration {
    maximum_percent         = 200  # 새 Task를 먼저 시작 (여유 확보)
    minimum_healthy_percent = 100  # 기존 Task 유지 (서비스 중단 방지)
  }
}
```

**동작 원리**:
1. 새 버전 배포 시작
2. Circuit Breaker가 Task 상태 모니터링
3. 일정 횟수 이상 연속 실패하여 서비스가 **steady state에 도달하지 못하면** 배포를 실패로 판단
4. **자동으로 배포 중단**
5. **이전 버전으로 자동 롤백**
6. CloudWatch 알람 발송

**효과**:
- 서비스 중단 시간: 10-30분 → **2-3분**
- 수동 개입 불필요
- 사용자 영향 최소화

---

### 3-2. Health Check 설정 리뷰 (2분)

#### 프로젝트의 Health Check 구현

**3단계 Health Check**:

**1. 컨테이너 레벨** (`terraform/aws/ecs.tf:103-109`):
```hcl
healthCheck = {
  command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
  interval    = 30  # 30초마다 체크
  timeout     = 5   # 5초 이내 응답
  retries     = 3   # 3회 실패 시 unhealthy
  startPeriod = 60  # 시작 후 60초는 유예기간
}
```

**2. ALB Target Group** (`terraform/aws/network.tf:238`):
```hcl
health_check {
  enabled             = true
  path                = "/health"
  protocol            = "HTTP"
  port                = "traffic-port"
  healthy_threshold   = 2   # 2회 성공 → healthy
  unhealthy_threshold = 3   # 3회 실패 → unhealthy
  timeout             = 5
  interval            = 30
  matcher             = "200"  # HTTP 200 응답 기대
}
```

**3. Backend 엔드포인트** (`backend/app.py:157`):
```python
@app.get("/health")
async def health_check():
    """Health check endpoint for ALB and ECS"""
    return {
        "status": "healthy",
        "service": "rag-agent-backend",
        "timestamp": "2024-03-17T14:30:00Z"
    }
```

#### Health Check 개선 포인트

**현재 구현**: 단순 HTTP 200 응답만 확인

**개선안**: 실제 의존성 확인

```python
@app.get("/health")
async def health_check():
    """Enhanced health check with dependencies"""
    health_status = {
        "status": "healthy",
        "service": "rag-agent-backend",
        "timestamp": datetime.utcnow().isoformat(),
        "dependencies": {}
    }

    # 1. Vector DB 연결 확인
    try:
        if vectorstore:
            # Pinecone ping
            vectorstore._index.describe_index_stats()
            health_status["dependencies"]["pinecone"] = "healthy"
        else:
            health_status["dependencies"]["pinecone"] = "not_initialized"
    except Exception as e:
        health_status["dependencies"]["pinecone"] = "unhealthy"
        health_status["status"] = "degraded"

    # 2. OpenAI API 연결 확인 (선택적)
    try:
        if llm:
            # 간단한 테스트 호출 (비용 최소화)
            llm.invoke("test", max_tokens=1)
            health_status["dependencies"]["openai"] = "healthy"
    except Exception as e:
        health_status["dependencies"]["openai"] = "unhealthy"
        health_status["status"] = "degraded"

    # 전체 상태가 unhealthy면 503 반환
    if health_status["status"] == "unhealthy":
        raise HTTPException(status_code=503, detail=health_status)

    return health_status
```

**degraded vs unhealthy**:
- **degraded**: 일부 기능만 동작 (서비스는 유지, 200 반환)
- **unhealthy**: 핵심 기능 불가 (서비스 중단, 503 반환)

**주의사항**:
- Health check는 **빠르게 응답**해야 함 (< 5초)
- 외부 API 호출 시 타임아웃 설정 필수
- 과도한 체크는 비용 증가 (OpenAI API 호출 등)

#### Degraded State 처리 전략

**언제 degraded를 사용하는가?**:
- **시나리오 1**: Vector DB 장애 시 캐시된 응답 제공 가능
- **시나리오 2**: LLM API 일시 장애 시 미리 준비된 fallback 응답 제공
- **시나리오 3**: 부가 기능(예: 로깅, 분석) 장애 시 핵심 기능은 유지

**Degraded 상태에서의 ALB 동작**:

ALB는 HTTP status code 기준으로 healthy 여부를 판단하므로, degraded를 200으로 반환하면 트래픽은 계속 유입됩니다.

```python
# HTTP 200 반환 → ALB는 트래픽 계속 전달
# 하지만 status: "degraded"로 모니터링 가능
{
  "status": "degraded",
  "dependencies": {
    "pinecone": "unhealthy",  # 실패한 의존성 표시
    "openai": "healthy"
  }
}
```

**Degraded 상태 모니터링**:
```bash
# CloudWatch Logs Insights로 degraded 상태 추적
fields @timestamp, status, dependencies
| filter status = "degraded"
| stats count() by bin(5m)
```

**운영 원칙**:
- **일시적 장애**: degraded (200 반환, 서비스 유지)
- **핵심 기능 불가**: unhealthy (503 반환, 트래픽 차단)
- **명확한 기준 수립**: 어떤 의존성 실패가 unhealthy인지 사전 정의

---

### 3-3. 배포 전략 선택 가이드 (1분)

#### 3가지 주요 배포 전략

**1. Rolling Deployment (기본값)**

```
Before: [v1] [v1] [v1]
Step 1: [v1] [v1] [v2]  ← 1개씩 교체
Step 2: [v1] [v2] [v2]
Step 3: [v2] [v2] [v2]  ← 완료
```

- 장점: 추가 리소스 불필요
- 단점: 배포 중 v1과 v2 혼재 (호환성 문제 가능)
- 적합: 일반적인 상황

**2. Blue-Green Deployment**

```
Blue (v1):  [v1] [v1] [v1]  ← 기존 환경
Green (v2): [v2] [v2] [v2]  ← 새 환경 (별도 생성)

ALB 트래픽 전환: Blue → Green (즉시 전환)

롤백 필요 시: Green → Blue (즉시 복구)
```

- 장점: 즉시 전환/롤백 가능, 버전 혼재 없음
- 단점: 2배의 리소스 필요 (비용 증가)
- 적합: 중요한 프로덕션 배포, 롤백 가능성 높을 때

**3. Canary Deployment (단계적 출시)**

```
Step 1: 90% v1, 10% v2  ← 일부 트래픽만 v2로
Step 2: 50% v1, 50% v2  ← 메트릭 확인 후 확대
Step 3: 0% v1, 100% v2  ← 완전 전환
```

- 장점: 점진적 검증, 위험 최소화
- 단점: 복잡한 설정, 긴 배포 시간
- 적합: 대규모 사용자, 위험 회피 중시

**프로젝트에 적용**:
- Dev/Staging: Rolling (빠른 배포)
- Production: Blue-Green or Canary (안전성 우선)

---

## 4. 보안 체크리스트 (4분)

### 4-1. Secrets 관리 Best Practice (2분)

#### ✅ 프로젝트의 올바른 Secrets 관리

**1. AWS Secrets Manager 사용** (`terraform/aws/ecs.tf:81-90`):

```hcl
# Secrets Manager에서 시크릿 주입
secrets = [
  {
    name      = "OPENAI_API_KEY"
    valueFrom = data.aws_secretsmanager_secret.openai.arn
  },
  {
    name      = "PINECONE_API_KEY"
    valueFrom = data.aws_secretsmanager_secret.pinecone.arn
  }
]
```

**장점**:
- ✅ 코드에 시크릿 노출 안 됨
- ✅ 중앙 집중 관리
- ✅ 버전 관리 및 로테이션 가능
- ✅ 접근 로그 추적

**2. GitHub Secrets + WIF (GCP)**:

```yaml
# .github/workflows/deploy-gcp.yml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
    service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}
```

**WIF (Workload Identity Federation) 장점**:
- ✅ JSON Key 파일 불필요 (키 유출 위험 제거)
- ✅ 단기 토큰 사용 (자동 만료)
- ✅ GitHub Actions에서 안전한 인증

#### ⚠️ 절대 하면 안 되는 것

```bash
# ❌ 절대 금지!
git add .env
git commit -m "Add API keys"
git push

# ❌ 절대 금지!
export OPENAI_API_KEY="sk-abc123..."  # 코드에 하드코딩

# ❌ 절대 금지!
docker run -e OPENAI_API_KEY="sk-abc123..." backend  # 로그에 노출
```

**실수로 커밋한 경우**:
```bash
# 1. 즉시 API 키 무효화 (OpenAI/Pinecone Console)
# 2. Git 히스토리에서 완전 삭제
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch .env' \
  --prune-empty --tag-name-filter cat -- --all

# 3. 강제 푸시
git push origin --force --all
```

#### Secrets 로테이션 정책

**권장 주기**:
- API Keys: 90일마다 교체
- Database Passwords: 60일마다 교체
- 의심되는 유출: 즉시 교체

**자동 로테이션** (AWS Secrets Manager):
```hcl
resource "aws_secretsmanager_secret_rotation" "openai" {
  secret_id           = aws_secretsmanager_secret.openai.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn

  rotation_rules {
    automatically_after_days = 90
  }
}
```

---

### 4-2. IAM 최소 권한 원칙 (1분)

#### 프로젝트의 IAM 역할 분리

**1. ECS Task Execution Role** (`terraform/aws/iam.tf`):

```hcl
# ECR에서 이미지 pull, Secrets Manager 읽기만
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-${var.environment}"

  # 최소 권한
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
}
```

**권한 범위**:
- ✅ ECR 이미지 pull
- ✅ CloudWatch Logs 쓰기
- ✅ Secrets Manager 읽기 (특정 ARN만)
- ❌ ECS API 호출 불가
- ❌ S3 접근 불가

**2. ECS Task Role**:

```hcl
# 애플리케이션 실행 중 필요한 권한만
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole-${var.environment}"

  # 커스텀 정책 (필요한 것만)
  inline_policy {
    name = "task-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = ["secretsmanager:GetSecretValue"]
          Resource = [
            data.aws_secretsmanager_secret.openai.arn,
            data.aws_secretsmanager_secret.pinecone.arn
          ]
        }
      ]
    })
  }
}
```

**최소 권한 체크리스트**:
- [ ] 역할마다 명확한 목적 정의
- [ ] 와일드카드(*) 사용 최소화
- [ ] 특정 리소스 ARN 지정
- [ ] 정기적으로 사용하지 않는 권한 제거

---

### 4-3. 네트워크 보안 Quick Check (1분)

#### Security Group 검토

프로젝트의 Security Group 구조:

```
Internet
  ↓ (HTTPS 443)
[Frontend ALB SG]
  ↓ (HTTP 80)
[Frontend Container SG]

  ↓ (HTTP 80)
[Backend ALB SG]
  ↓ (HTTP 8000)
[Backend Container SG]
  ↓ (HTTPS 443)
External APIs (OpenAI, Pinecone)
```

**보안 원칙**:
1. **ALB만 인터넷 노출**: 컨테이너는 직접 노출 금지
2. **최소 포트만 오픈**: 필요한 포트만 허용
3. **Source 제한**: 특정 Security Group에서만 접근

**프로덕션 필수 설정**:

```hcl
# Frontend ALB: HTTPS만 허용
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # 전체 공개
}

# Backend ALB: Frontend에서만 접근
ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [aws_security_group.frontend.id]  # Frontend만
}
```

#### HTTPS 적용 (프로덕션 필수)

**현재 프로젝트**: HTTP만 사용 (학습용)

**프로덕션 체크리스트**:
- [ ] ACM (AWS Certificate Manager)에서 SSL 인증서 발급
- [ ] ALB에 HTTPS Listener 추가
- [ ] HTTP → HTTPS 리다이렉트 설정
- [ ] 도메인 연결 (Route 53)

```hcl
# HTTPS Listener 추가
resource "aws_lb_listener" "frontend_https" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = "arn:aws:acm:region:account:certificate/xxx"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}
```

---

## 5. 장애 발생 시 대응 방법 (3분)

### 5-1. 일반적인 장애 패턴 Top 3 (2분)

#### 장애 1: Task 재시작 루프

**증상**:
```
ECS Task 상태: PENDING → RUNNING → STOPPED → PENDING (반복)
```

**확인 방법**:
```bash
# Task 상태 확인
aws ecs describe-tasks \
  --cluster agent-cluster-prod \
  --tasks <task-id> \
  --region ap-northeast-2 \
  --query 'tasks[0].stoppedReason' \
  --output text
```

**주요 원인과 해결**:

| stoppedReason | 원인 | 해결 방법 |
|--------------|------|----------|
| `Essential container exited` | 컨테이너 시작 실패 | 로그 확인 → 코드/설정 오류 수정 |
| `OutOfMemory` | 메모리 부족 | Task Definition memory 증가 |
| `CannotPullContainerError` | 이미지 pull 실패 | ECR 권한, 이미지 태그 확인 |
| `HealthCheckFailed` | Health check 3회 실패 | `/health` 엔드포인트 확인 |

**디버깅 순서**:
1. CloudWatch Logs 확인 (에러 로그)
2. Task Definition 설정 확인 (CPU/Memory)
3. Security Group 규칙 확인 (네트워크)
4. Health Check 엔드포인트 테스트

---

#### 장애 2: 503 Service Unavailable

**증상**:
```
curl https://backend-alb-prod.elb.amazonaws.com/api
→ 503 Service Unavailable
```

**확인 방법**:
```bash
# Target Group 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-northeast-2
```

**주요 원인과 해결**:

| Target State | 원인 | 해결 방법 |
|-------------|------|----------|
| `unhealthy` | Health check 실패 | 로그 확인, `/health` 테스트 |
| `draining` | Task 종료 중 | 잠시 대기 (새 Task 시작 확인) |
| `initial` | Task 시작 중 | Health check 통과 대기 |
| `unused` | Target Group에 Task 없음 | ECS Service desired count 확인 |

**빠른 해결**:
```bash
# 1. Security Group 확인 (ALB → Container 통신 가능?)
# ALB SG: 0.0.0.0/0 → 80
# Container SG: ALB SG → 8000 (허용 필요!)

# 2. Health check 경로 확인
curl http://<container-ip>:8000/health
# → 200 OK 반환 확인

# 3. Security Group 규칙 추가 (필요 시)
aws ec2 authorize-security-group-ingress \
  --group-id <container-sg-id> \
  --protocol tcp --port 8000 \
  --source-group <alb-sg-id>
```

---

#### 장애 3: 컨테이너 OOM (Out of Memory)

**증상**:
```
Task가 갑자기 종료 (STOPPED)
stoppedReason: "OutOfMemoryError: Container killed due to memory usage"
```

**확인 방법**:
```bash
# CloudWatch Logs에서 확인
aws logs filter-log-events \
  --log-group-name /ecs/backend-prod \
  --filter-pattern "OOMKilled" \
  --region ap-northeast-2
```

**원인**:
- Task Definition의 `memory`보다 실제 사용량 초과
- 메모리 누수 (memory leak)
- 대용량 데이터 처리

**해결 방법**:

**단기 (긴급)**:
```hcl
# Task Definition memory 증가
memory = "2048"  # 1024 → 2048 (2배)
```

**중기 (모니터링)**:
```bash
# Container Insights 활성화 (메모리 사용량 추적)
aws ecs update-cluster-settings \
  --cluster agent-cluster-prod \
  --settings name=containerInsights,value=enabled
```

**장기 (최적화)**:
- 코드 프로파일링으로 메모리 누수 찾기
- 대용량 데이터는 스트리밍 처리
- 주기적 메모리 정리 (Python: `gc.collect()`)

---

### 5-2. 긴급 롤백 명령어 (1분)

#### AWS ECS 롤백

**이전 Task Definition으로 즉시 롤백**:

```bash
# 1. 현재 Task Definition 버전 확인
aws ecs describe-services \
  --cluster agent-cluster-prod \
  --services backend-prod-service \
  --query 'services[0].taskDefinition' \
  --output text
# → backend-prod:45 (현재 버전)

# 2. 이전 버전으로 롤백
aws ecs update-service \
  --cluster agent-cluster-prod \
  --service backend-prod-service \
  --task-definition backend-prod:44 \
  --force-new-deployment
# → :44 (이전 버전)로 즉시 롤백

# 3. 롤백 진행 상황 확인
aws ecs describe-services \
  --cluster agent-cluster-prod \
  --services backend-prod-service \
  --query 'services[0].deployments'
```

**롤백 시간**: 약 2-5분 (Task 교체 시간)

---

#### GCP Cloud Run 롤백

**이전 Revision으로 트래픽 전환**:

```bash
# 1. 현재 Revision 목록 확인
gcloud run revisions list \
  --service backend-prod \
  --region asia-northeast3
# → backend-prod-00045-abc (현재)
# → backend-prod-00044-xyz (이전)

# 2. 이전 Revision으로 100% 트래픽 전환
gcloud run services update-traffic backend-prod \
  --to-revisions=backend-prod-00044-xyz=100 \
  --region asia-northeast3

# 3. 롤백 확인
gcloud run services describe backend-prod \
  --region asia-northeast3 \
  --format="value(status.traffic)"
```

**롤백 시간**: 약 30초-1분 (즉시 전환)

---

## 📚 참고 자료

### AWS
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-best-practices.html)
- [AWS re:Invent 2024 - Deployment Best Practices](https://reinvent.awsevents.com/)
- [AWS Cost Optimization Guide](https://aws.amazon.com/aws-cost-management/)

### GCP
- [Cloud Run Best Practices](https://cloud.google.com/run/docs/tips/general)
- [GCP Cost Optimization](https://cloud.google.com/cost-management)
- [Cloud Logging Guide](https://cloud.google.com/logging/docs)

### 일반
- [12-Factor App](https://12factor.net/) - 클라우드 네이티브 애플리케이션 원칙
- [Site Reliability Engineering (SRE)](https://sre.google/) - Google의 운영 철학
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

---

**🎉 축하합니다! Section 7을 완료했습니다!**

이제 여러분은 **실전 운영 노하우**를 갖춘 엔지니어입니다. 배포뿐만 아니라 **안정적으로 운영하고, 비용을 최적화하고, 장애에 대응하는** 능력을 갖추었습니다.

다음 단계는 **여러분의 AI 서비스를 실제로 배포하고 운영**하는 것입니다! 💪
