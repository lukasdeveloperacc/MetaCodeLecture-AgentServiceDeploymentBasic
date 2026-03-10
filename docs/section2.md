# Section 3: AWS ECS/Fargate 배포

## 학습 목표
- AWS 컨테이너 서비스 핵심 개념 이해 (ECR, ECS, Fargate, ALB)
- 프로덕션 배포 아키텍처 설계
- ECR에 컨테이너 이미지 업로드
- ECS/Fargate로 실제 서비스 배포
- CloudWatch 모니터링 및 장애 대응

## 새로 추가된 파일
```
aws/scripts/
  └── cli_commands.sh                           # AWS CLI 명령어 모음 스크립트

aws/ecs/task_definition/
  ├── task-definition-backend.json              # Backend ECS Task Definition
  └── task-definition-frontend.json             # Frontend ECS Task Definition

aws/iam/
  ├── ecs-task-execution-trust-policy.json      # ECS Task Execution Role Trust Policy
  └── ecs-task-trust-policy.json                # ECS Task Role Trust Policy
```

## AWS 서비스 구성도 (Dual ALB 아키텍처)

```
┌─────────────────────────────────────────────────┐
│                   Internet                      │
└───────────┬───────────────────┬─────────────────┘
            │                   │
    ┌───────▼────────┐  ┌───────▼────────┐
    │  Frontend ALB  │  │  Backend ALB   │
    │  (Port 80)     │  │  (Port 80)     │
    └───────┬────────┘  └───────┬────────┘
            │                   │
    ┌───────▼────────┐  ┌───────▼────────┐
    │ frontend-tg    │  │ backend-tg     │
    │ (Port 80)      │  │ (Port 8000)    │
    └───────┬────────┘  └───────┬────────┘
            │                   │
    ┌───────▼────────┐  ┌───────▼────────┐
    │ Frontend       │  │ Backend        │
    │ Service        │  │ Service        │
    └───────┬────────┘  └───────┬────────┘
            │                   │
    ┌───────▼────────┐  ┌───────▼────────┐
    │ Frontend       │  │ Backend        │
    │ Fargate Task   │  │ Fargate Task   │
    │                │  │                │
    │ nginx:80       │  │ FastAPI:8000   │
    └────────────────┘  └────────────────┘
            │                   ▲
            └───────────────────┘
               프록시 연결:
         backend-alb-xxx.elb.amazonaws.com
```

**Dual ALB 구조의 장점:**
- **독립적인 서비스 관리**: Frontend와 Backend를 독립적으로 스케일링, 배포, 모니터링
- **명확한 서비스 분리**: 각 ALB가 하나의 서비스만 담당하여 구조가 단순
- **보안 그룹 세밀 제어**: 서비스별로 독립적인 보안 그룹 설정 가능
- **장애 격리**: 한 서비스의 ALB 장애가 다른 서비스에 영향 없음
- **유연한 확장**: 향후 추가 서비스를 위한 ALB 추가가 용이

## 배포 단계

### 1. AWS CLI 설정
```bash
# AWS CLI 설치 확인
aws --version

# AWS 자격증명 설정
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: ap-northeast-2
# Default output format: json
```

### 2. ECR에 이미지 푸시
```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com

# 이미지 빌드 및 태깅
docker build -t backend:latest ./backend
docker tag backend:latest {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/backend:latest

# ECR 푸시
docker push {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/backend:latest

# Frontend도 동일하게 진행
docker build -t frontend:latest ./frontend
docker tag frontend:latest {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/frontend:latest
docker push {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/frontend:latest
```

**참고:** `aws/scripts/cli_commands.sh` 파일에 유용한 AWS CLI 명령어 모음이 있습니다.

### 2.5. IAM Role 설정

**중요!** ECS Task가 AWS 서비스에 접근하려면 두 가지 IAM Role이 필요합니다:
- **ecsTaskExecutionRole**: ECS 인프라가 ECR 이미지 다운로드, CloudWatch 로그 전송, Secrets Manager 접근에 사용
- **ecsTaskRole**: 애플리케이션 코드가 AWS API를 호출할 때 사용

#### Trust Relationship 정책 파일 생성
```bash
# ECS Task Execution Trust Policy
cat > aws/iam/ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# ECS Task Trust Policy
cat > aws/iam/ecs-task-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

#### ecsTaskExecutionRole 생성
```bash
# Role 생성
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://aws/iam/ecs-task-execution-trust-policy.json \
  --description "ECS Task Execution Role" \
  --region ap-northeast-2

# 기본 권한 연결 (ECR, CloudWatch Logs 접근)
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Secrets Manager 접근 권한 추가
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

#### ecsTaskRole 생성
```bash
# Role 생성
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://aws/iam/ecs-task-trust-policy.json \
  --description "ECS Task Role for application AWS API access" \
  --region ap-northeast-2

# CloudWatch Logs 접근 권한
aws iam attach-role-policy \
  --role-name ecsTaskRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

#### Role 생성 확인
```bash
# 생성된 Role 확인
aws iam get-role --role-name ecsTaskExecutionRole
aws iam get-role --role-name ecsTaskRole

# 연결된 정책 확인
aws iam list-attached-role-policies --role-name ecsTaskExecutionRole
aws iam list-attached-role-policies --role-name ecsTaskRole
```

### 3. Secrets Manager에 API Key 저장
```bash
# OpenAI API Key 저장
aws secretsmanager create-secret \
  --name dev/openai-api-key \
  --secret-string "your-openai-api-key" \
  --region ap-northeast-2

# Pinecone API Key 저장
aws secretsmanager create-secret \
  --name dev/pinecone-api-key \
  --secret-string "your-pinecone-api-key" \
  --region ap-northeast-2
```

**참고:** Task Definition에서 이 시크릿 이름을 참조하므로 정확하게 입력하세요.

### 4. ECS Cluster 생성
```bash
# AWS Console > ECS > Clusters > Create Cluster
# - Cluster name: agent-cluster (또는 agent-cluster-dev)
# - Infrastructure: AWS Fargate (serverless)
```

**참고:** 클러스터 이름은 환경에 따라 `agent-cluster` 또는 `agent-cluster-dev`로 설정할 수 있습니다. 이후 Service 생성 시 동일한 이름을 사용하세요.

### 4.5. CloudWatch Log Group 생성

**중요!** Task가 로그를 전송하려면 Log Group이 사전에 존재해야 합니다.

```bash
# Backend Log Group 생성
aws logs create-log-group \
  --log-group-name /ecs/backend \
  --region ap-northeast-2

# Frontend Log Group 생성
aws logs create-log-group \
  --log-group-name /ecs/frontend \
  --region ap-northeast-2

# Log Group 확인
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/ \
  --region ap-northeast-2
```

#### Retention 정책 설정 (선택사항, 비용 절감)
```bash
# Backend 로그 7일 보관
aws logs put-retention-policy \
  --log-group-name /ecs/backend \
  --retention-in-days 7 \
  --region ap-northeast-2

# Frontend 로그 7일 보관
aws logs put-retention-policy \
  --log-group-name /ecs/frontend \
  --retention-in-days 7 \
  --region ap-northeast-2
```

### 5. Task Definition 등록
```bash
# Task Definition 파일 수정 ({ACCOUNT_ID} 교체) - 필요한 경우
# sed -i "s/{ACCOUNT_ID}/$(aws sts get-caller-identity --query Account --output text)/g" aws/ecs/task_definition/task-definition-backend.json

# Task Definition 등록
aws ecs register-task-definition \
  --cli-input-json file://aws/ecs/task_definition/task-definition-backend.json

aws ecs register-task-definition \
  --cli-input-json file://aws/ecs/task_definition/task-definition-frontend.json
```

**참고:** 실제 파일에는 이미 Account ID가 반영되어 있으므로 sed 명령은 생략 가능합니다.

### 6. ALB 및 Target Group 생성 (Dual ALB)

#### 6-1. Backend ALB 생성
```bash
# AWS Console > EC2 > Load Balancers > Create Load Balancer
# - Type: Application Load Balancer
# - Name: backend-alb
# - Scheme: internet-facing
# - VPC: default VPC
# - Subnets: ap-northeast-2a, ap-northeast-2c (최소 2개)
# - Security Group: backend-alb-sg (Port 80 허용)
# - Listener: HTTP:80 → backend-tg
```

#### 6-2. Frontend ALB 생성
```bash
# AWS Console > EC2 > Load Balancers > Create Load Balancer
# - Type: Application Load Balancer
# - Name: frontend-alb
# - Scheme: internet-facing
# - VPC: default VPC
# - Subnets: ap-northeast-2a, ap-northeast-2c (최소 2개)
# - Security Group: frontend-alb-sg (Port 80 허용)
# - Listener: HTTP:80 → frontend-tg
```

#### 6-3. Target Groups 확인
- **backend-tg**: IP 타입, Port 8000
- **frontend-tg**: IP 타입, Port 80

**주의:** Dual ALB 구조에서는 각 ALB가 단일 Target Group에만 연결되므로 Listener Rules가 필요 없습니다.

### 7. ECS Service 생성 (Dual ALB)

#### 7-1. Backend Service 생성
```bash
# AWS Console > ECS > Cluster > Create Service
# - Launch type: Fargate
# - Task Definition: backend-task
# - Service name: backend-service
# - Desired tasks: 2
# - Load balancer: backend-alb
# - Target group: backend-tg
```

#### 7-2. Frontend Service 생성
```bash
# AWS Console > ECS > Cluster > Create Service
# - Launch type: Fargate
# - Task Definition: frontend-task
# - Service name: frontend-service
# - Desired tasks: 2
# - Load balancer: frontend-alb
# - Target group: frontend-tg
```

**각 서비스가 독립적인 ALB에 연결됩니다:**
- Backend Service → backend-alb → backend-tg
- Frontend Service → frontend-alb → frontend-tg

### 8. Frontend 프록시 설정 업데이트 (Dual ALB)

**중요!** Dual ALB 구조에서는 Frontend가 **Backend ALB DNS**를 통해 Backend API를 호출합니다.

#### 8-1. Backend ALB DNS 확인
```bash
aws elbv2 describe-load-balancers \
  --names backend-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ap-northeast-2

# 출력 예시: backend-alb-1234567890.ap-northeast-2.elb.amazonaws.com
```

#### 8-2. Frontend nginx.conf 수정
```nginx
# frontend/nginx.conf - 기존 설정 (docker-compose)
location /api/ {
    proxy_pass http://backend:8000/;  # docker-compose 서비스 이름
    ...
}

# Dual ALB용으로 변경
location /api/ {
    proxy_pass http://backend-alb-1234567890.ap-northeast-2.elb.amazonaws.com/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_cache_bypass $http_upgrade;
}
```

#### 8-3. Backend CORS 설정 업데이트
```python
# backend/app/main.py
from fastapi.middleware.cors import CORSMiddleware

# Frontend ALB DNS를 CORS 허용 목록에 추가
ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "http://frontend-alb-1234567890.ap-northeast-2.elb.amazonaws.com",  # Frontend ALB DNS
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**주의:** Backend는 Frontend ALB DNS를 CORS 허용 목록에 추가해야 합니다.

#### 8-4. 재빌드 및 배포
```bash
# 계정 ID 확인
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Frontend 재빌드 및 푸시
docker build -t frontend:latest ./frontend
docker tag frontend:latest $ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/frontend:latest
docker push $ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/frontend:latest

# Backend 재빌드 및 푸시 (CORS 설정 변경)
docker build -t backend:latest ./backend
docker tag backend:latest $ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/backend:latest
docker push $ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/backend:latest

# ECS Service 강제 재배포
aws ecs update-service \
  --cluster agent-cluster \
  --service frontend-service \
  --force-new-deployment \
  --region ap-northeast-2

aws ecs update-service \
  --cluster agent-cluster \
  --service backend-service \
  --force-new-deployment \
  --region ap-northeast-2
```

#### 8-5. 동작 확인 (Dual ALB)
```bash
# 1. Frontend ALB 접속
curl http://frontend-alb-1234567890.ap-northeast-2.elb.amazonaws.com
→ Frontend 페이지 표시

# 2. Backend ALB 직접 테스트
curl http://backend-alb-1234567890.ap-northeast-2.elb.amazonaws.com/health
→ {"status": "healthy"}

# 3. Frontend를 통한 Backend API 호출 테스트
# 브라우저에서 Frontend ALB 접속 후 API 버튼 클릭
# F12 → Network 탭에서 Backend ALB로 요청이 전송되는지 확인
```

**Dual ALB 구조 확인:**
- Frontend ALB → Frontend 서비스
- Backend ALB → Backend 서비스
- Frontend nginx가 Backend ALB DNS로 프록시
- 각 서비스가 독립적으로 동작

## CloudWatch 모니터링

### 로그 확인
```bash
# CloudWatch Logs로 이동
aws logs tail /ecs/backend --follow

# 특정 기간 로그 조회
aws logs filter-log-events \
  --log-group-name /ecs/backend \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

### 메트릭 확인
- CPU 사용률
- 메모리 사용률
- 네트워크 In/Out
- 헬스체크 상태

### 알람 설정
```bash
# CPU 사용률 80% 초과 시 알람
aws cloudwatch put-metric-alarm \
  --alarm-name backend-high-cpu \
  --alarm-description "Backend CPU > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

## 트러블슈팅

### IAM Role 권한 오류
**증상**: `ECS was unable to assume the role ... that was provided for this task`

**해결방법**:
1. **Role 존재 확인**
   ```bash
   aws iam get-role --role-name ecsTaskExecutionRole
   aws iam get-role --role-name ecsTaskRole
   ```

2. **Trust Relationship 확인**
   ```bash
   aws iam get-role --role-name ecsTaskExecutionRole --query 'Role.AssumeRolePolicyDocument'
   # "Service": "ecs-tasks.amazonaws.com" 확인
   ```

3. **필수 정책 연결 확인**
   ```bash
   # ecsTaskExecutionRole에 필요한 정책
   aws iam list-attached-role-policies --role-name ecsTaskExecutionRole
   # AmazonECSTaskExecutionRolePolicy와 SecretsManagerReadWrite 확인
   ```

4. **Account ID 일치 확인**
   ```bash
   # Task Definition의 Account ID가 실제 계정 ID와 일치하는지 확인
   cat aws/ecs/task_definition/task-definition-backend.json | grep "arn:aws:iam"
   ```

5. **IAM 권한 전파 대기**
   - Role 생성 후 약 60초 대기 (AWS IAM 권한 전파 시간)
   - 재시도 전에 충분한 시간 대기

### CloudWatch Log Group 누락 에러
**증상**: `ResourceInitializationError: failed to validate logger args: The specified log group does not exist`

**해결방법**:
1. **Log Group 존재 확인**
   ```bash
   aws logs describe-log-groups \
     --log-group-name-prefix /ecs/ \
     --region ap-northeast-2
   ```

2. **누락된 Log Group 생성**
   ```bash
   # Backend Log Group
   aws logs create-log-group \
     --log-group-name /ecs/backend \
     --region ap-northeast-2

   # Frontend Log Group
   aws logs create-log-group \
     --log-group-name /ecs/frontend \
     --region ap-northeast-2
   ```

3. **Task Definition과 이름 일치 확인**
   ```bash
   # Task Definition 파일의 logConfiguration 확인
   cat aws/ecs/task_definition/task-definition-backend.json | grep "awslogs-group"
   # 출력: "awslogs-group": "/ecs/backend"
   ```

4. **Service 재시작**
   ```bash
   aws ecs update-service \
     --cluster agent-cluster \
     --service backend-service \
     --force-new-deployment \
     --region ap-northeast-2
   ```

### Task가 계속 재시작되는 경우
1. CloudWatch Logs 확인
2. 헬스체크 설정 확인
3. 환경변수/시크릿 주입 확인
4. 리소스(CPU/Memory) 부족 확인

### API Key 관련 오류
1. Secrets Manager 시크릿 이름 확인
2. Task Role IAM 권한 확인
3. 시크릿 ARN이 정확한지 확인

### 네트워크 연결 실패
1. Security Group 설정 확인
2. Subnet이 Public인지 확인
3. NAT Gateway 설정 확인 (Private Subnet 사용 시)

## 비용 최적화

### Fargate Spot 사용
- On-Demand 대비 최대 70% 할인
- 중단 가능한 워크로드에 적합

### Auto Scaling 설정
```bash
# Target Tracking Scaling Policy
# - Target: CPU 70%
# - Min tasks: 2
# - Max tasks: 10
```

## 완료 체크리스트 (Dual ALB)

### 기본 설정
- [ ] AWS CLI가 설정되었는가?
- [ ] ECR에 이미지가 푸시되었는가?
- [ ] **IAM Role (ecsTaskExecutionRole, ecsTaskRole)이 생성되었는가?**
- [ ] **IAM Role에 필수 정책이 연결되었는가?**
- [ ] **Trust Relationship이 올바르게 설정되었는가?**
- [ ] Secrets Manager에 API Key가 저장되었는가?
- [ ] ECS Cluster가 생성되었는가?
- [ ] **CloudWatch Log Group (/ecs/backend, /ecs/frontend)이 생성되었는가?**
- [ ] **Task Definition의 {ACCOUNT_ID}가 실제 계정 ID로 치환되었는가?**
- [ ] Task Definition이 등록되었는가?

### Dual ALB 설정
- [ ] **Backend ALB (backend-alb)가 생성되었는가?**
- [ ] **Frontend ALB (frontend-alb)가 생성되었는가?**
- [ ] **Backend Target Group (backend-tg, Port 8000)이 생성되었는가?**
- [ ] **Frontend Target Group (frontend-tg, Port 80)이 생성되었는가?**
- [ ] **Backend ALB가 backend-tg와 연결되었는가?**
- [ ] **Frontend ALB가 frontend-tg와 연결되었는가?**
- [ ] **Backend ALB 보안 그룹 (Port 80 허용)이 설정되었는가?**
- [ ] **Frontend ALB 보안 그룹 (Port 80 허용)이 설정되었는가?**

### Service 및 프록시 설정
- [ ] **Backend Service가 backend-alb에 연결되어 실행 중인가?**
- [ ] **Frontend Service가 frontend-alb에 연결되어 실행 중인가?**
- [ ] **Frontend nginx.conf가 Backend ALB DNS로 업데이트되었는가?**
- [ ] **Backend CORS 설정에 Frontend ALB DNS가 추가되었는가?**
- [ ] **업데이트된 이미지가 ECR에 푸시되고 Service가 재배포되었는가?**

### 동작 확인
- [ ] **Frontend ALB URL로 접속이 가능한가?**
- [ ] **Backend ALB URL로 직접 API 호출이 가능한가?**
- [ ] **Frontend에서 Backend ALB를 통해 API 호출이 정상 작동하는가?**
- [ ] CloudWatch Logs에서 로그가 확인되는가?
- [ ] 헬스체크가 통과하는가?
- [ ] **각 서비스가 독립적으로 스케일링되는가?**
