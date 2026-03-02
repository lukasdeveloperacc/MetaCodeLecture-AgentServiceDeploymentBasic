# Section 1: Docker & 환경변수 기초

## 학습 목표
- Docker 기초 개념 이해 (컨테이너 vs VM, 이미지 vs 컨테이너)
- Docker 필수 명령어 실습
- 환경별 설정 분리 전략 (dev/stage/prod)
- API Key 및 민감 정보 보안 관리

## 새로 추가된 파일
```
backend/
  ├── .env.dev       # 개발 환경 설정
  ├── .env.stage     # 스테이징 환경 설정
  └── .env.prod      # 프로덕션 환경 설정 (템플릿)
```

## Docker 기본 명령어 실습

### 1. 이미지 관리
```bash
# 공식 이미지 pull
docker pull python:3.11-slim

# 로컬 이미지 목록 확인
docker images

# 이미지 삭제
docker rmi python:3.11-slim
```

### 2. 컨테이너 실행
```bash
# 컨테이너 실행 (인터랙티브)
docker run -it python:3.11-slim bash

# 컨테이너 백그라운드 실행
docker run -d --name my-python python:3.11-slim sleep 3600

# 실행 중인 컨테이너 확인
docker ps

# 모든 컨테이너 확인 (중지된 것 포함)
docker ps -a
```

### 3. 컨테이너 관리
```bash
# 컨테이너 로그 확인
docker logs my-python

# 실행 중인 컨테이너 접속
docker exec -it my-python bash

# 컨테이너 중지
docker stop my-python

# 컨테이너 삭제
docker rm my-python
```

## 환경변수 관리 전략

### 환경별 .env 파일 사용
```bash
# 개발 환경
cp backend/.env.dev backend/.env
uvicorn app:app --reload

# 스테이징 환경
cp backend/.env.stage backend/.env
uvicorn app:app

# 프로덕션 (클라우드에서 환경변수로 주입)
# AWS Secrets Manager, GCP Secret Manager 사용
```

### 환경변수 우선순위
1. 시스템 환경변수
2. .env 파일
3. 코드 내 기본값

### API Key 보안 체크리스트
- [ ] `.gitignore`에 `.env` 파일 추가
- [ ] `.env.example` 파일로 템플릿 제공
- [ ] 프로덕션에서는 Secrets Manager 사용
- [ ] 코드에 하드코딩 금지
- [ ] 로그에 민감 정보 출력 금지

## 완료 체크리스트
- [ ] Docker 기본 명령어를 실습했는가?
- [ ] 환경별 .env 파일을 작성했는가?
- [ ] 개발/스테이징/프로덕션 환경 차이를 이해했는가?
- [ ] API Key를 안전하게 관리하는 방법을 알고 있는가?
- [ ] .gitignore에 민감 정보 파일이 추가되어 있는가?
