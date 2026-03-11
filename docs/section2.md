# Section 2: 멀티 컨테이너 로컬 구성

## 학습 목표
- Backend를 Docker 컨테이너로 패키징
- Frontend를 Nginx 컨테이너로 패키징
- docker-compose로 멀티 컨테이너 통합 관리
- 컨테이너 간 네트워크 통신 설정

## 새로 추가된 파일
```
backend/
  ├── Dockerfile           # Backend 컨테이너 이미지 빌드 파일
  └── .dockerignore        # Docker 빌드 시 제외할 파일

frontend/
  ├── Dockerfile           # Frontend 컨테이너 이미지 빌드 파일
  └── nginx.conf           # Nginx 웹서버 설정

docker-compose.yml         # 멀티 컨테이너 오케스트레이션
```

## Docker 이미지 빌드 및 실행

### 1. 개별 이미지 빌드
```bash
# Backend 이미지 빌드
cd backend
docker build -t backend:v1 .

# Frontend 이미지 빌드
cd frontend
docker build -t frontend:v1 .
```

### 2. 개별 컨테이너 실행
```bash
# Backend 컨테이너 실행
docker run -d \
  --name backend \
  -p 1234:8000 \
  --env-file backend/.env \
  backend:v1

# Frontend 컨테이너 실행
docker run -d \
  --name frontend \
  -p 1235:80 \
  frontend:v1
```

## docker-compose.yml 구조

### 기본 설정
```yaml
services:
  backend:
    platform: linux/amd64  # M1/M2 Mac 호환성
    image: backend:v1
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "1234:8000"  # host:container
    env_file:
      - ./backend/.env
    networks:
      - agent-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  frontend:
    platform: linux/amd64
    image: frontend:v1
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "1235:80"
    depends_on:
      backend:
        condition: service_healthy  # Backend 헬스체크 통과 후 시작
    networks:
      - agent-network

networks:
  agent-network:
    name: agent-network
```

### 주요 설정 설명
- **platform**: M1/M2 Mac에서 AMD64 아키텍처로 빌드
- **healthcheck**: Backend 컨테이너의 상태 확인
- **depends_on**: Frontend는 Backend가 healthy 상태일 때만 시작
- **networks**: 컨테이너 간 통신을 위한 브리지 네트워크

### 개발 환경 볼륨 마운트 (선택사항)
코드 변경 시 자동 반영을 위해 volumes를 활성화할 수 있습니다:
```yaml
# backend 서비스에 추가
volumes:
  - ./backend:/app
```

## Docker Compose로 통합 관리

### 1. 환경변수 설정
```bash
# .env 파일 준비 (backend/.env)
cp backend/.env.dev backend/.env
# API Keys 설정 필수!
```

### 2. 전체 서비스 실행
```bash
# 빌드 + 실행
docker-compose up --build

# 백그라운드 실행
docker-compose up -d

# 로그 확인
docker-compose logs -f

# 특정 서비스 로그만 확인
docker-compose logs -f backend
```

### 3. 서비스 관리
```bash
# 서비스 상태 확인
docker-compose ps

# 서비스 중지
docker-compose stop

# 서비스 재시작
docker-compose restart

# 서비스 중지 및 컨테이너 삭제
docker-compose down

# 볼륨까지 삭제
docker-compose down -v
```

### 4. 개발 환경 핫 리로딩
```bash
# docker-compose.yml의 volumes 설정으로
# 코드 변경 시 자동 반영됨

# Backend 코드 수정 후 자동 재시작 확인
docker-compose logs -f backend
```

## 컨테이너 간 네트워크 통신

### 내부 네트워크
- `agent-network` 브리지 네트워크 생성
- Frontend → Backend 통신: Nginx 리버스 프록시 사용
- 외부 접속:
  - Frontend: http://localhost:1235
  - Backend: http://localhost:1234

### Frontend에서 Backend API 호출
```javascript
// app.js 내부
const API_BASE_URL = '/api';  // Nginx 프록시를 통한 호출

// Nginx가 /api/* 요청을 http://backend:8000/*으로 프록시
// 예: /api/ask → http://backend:8000/ask
```

### Nginx 리버스 프록시 설정
Frontend의 `nginx.conf`에서 `/api` 경로를 Backend로 프록시:
```nginx
location /api/ {
    proxy_pass http://backend:8000/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;

    # SSE(Server-Sent Events) 스트리밍을 위한 설정
    proxy_set_header Connection '';
    proxy_buffering off;
    proxy_cache off;
}
```

## 레이어 캐싱 최적화

### Dockerfile 작성 팁
1. **의존성 먼저 복사**: `COPY pyproject.toml uv.lock` → `RUN uv sync`
2. **코드는 나중에 복사**: `COPY . .`
3. **캐시 재사용**: 의존성이 변경되지 않으면 레이어 재사용

### 빌드 시간 비교
```bash
# 첫 빌드: 2-3분
docker-compose build

# 코드만 수정 후 재빌드: 10-20초 (캐시 활용)
docker-compose build
```

## 완료 체크리스트
- [ ] Backend Dockerfile을 작성했는가?
- [ ] Frontend Dockerfile을 작성했는가?
- [ ] docker-compose.yml을 작성했는가?
- [ ] docker-compose up으로 전체 서비스가 실행되는가?
- [ ] Frontend에서 Backend API 호출이 성공하는가?
- [ ] 컨테이너 로그를 확인할 수 있는가?
- [ ] 코드 수정 시 핫 리로딩이 동작하는가?
- [ ] 헬스체크가 정상 동작하는가?
