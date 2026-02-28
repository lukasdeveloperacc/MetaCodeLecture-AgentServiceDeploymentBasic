# RAG/Agent Backend - 로컬 실행 가이드

AI 서비스 통합 & 배포 강의를 위한 RAG/Agent 데모 백엔드입니다.

## 📋 주요 기능

- **LLM 직접 호출**: OpenAI API로 일반 질문 응답
- **RAG (Retrieval-Augmented Generation)**: Pinecone 기반 문서 검색 및 답변 생성
- **LangGraph Agent**: 질문 분류 → RAG/LLM 자동 선택
- **Streaming 응답**: Server-Sent Events (SSE) 기반 실시간 스트리밍

## 🛠️ 기술 스택

- **Python 3.11+**
- **FastAPI**: 비동기 웹 프레임워크
- **LangChain / LangGraph**: LLM 체인 및 Agent 구성
- **Pinecone**: 클라우드 Vector Database (Managed Service)
- **OpenAI API**: LLM 및 Embedding

## 📁 프로젝트 구조

```
backend/
├─ app.py                 # FastAPI 메인 애플리케이션
├─ init_pinecone.py       # Pinecone 초기화 스크립트
├─ pyproject.toml         # uv 패키지 관리 설정
├─ .env.example           # 환경변수 템플릿
└─ .env                   # 실제 환경변수 (Git 제외)
```

## 🚀 로컬 실행 방법

### 사전 요구사항

- **Python 3.11 이상** 설치
- **uv** 설치: https://docs.astral.sh/uv/getting-started/installation/
  ```bash
  # macOS/Linux
  curl -LsSf https://astral.sh/uv/install.sh | sh

  # Windows
  powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
  ```
- **OpenAI API Key** 발급: https://platform.openai.com/api-keys
- **Pinecone API Key** 발급: https://app.pinecone.io/ (무료 Starter 플랜 사용 가능)

### 1. 환경변수 설정

```bash
# .env.example을 복사하여 .env 파일 생성
cp .env.example .env

# .env 파일을 열어 OpenAI API Key 입력
# macOS/Linux
nano .env

# Windows
notepad .env
```

**`.env` 파일 내용**:
```bash
# OpenAI API Key (필수!)
OPENAI_API_KEY=sk-proj-your-actual-api-key-here

# Pinecone 설정 (RAG 사용 시 필수)
PINECONE_API_KEY=your-pinecone-api-key-here
PINECONE_INDEX_NAME=ai-service-docs

# LLM 설정
LLM_MODEL=gpt-4o-mini
LLM_TEMPERATURE=0.7
LLM_MAX_TOKENS=1000

# RAG 설정
RAG_TOP_K=3
EMBEDDING_MODEL=text-embedding-3-small

# CORS 설정
CORS_ORIGINS=http://localhost:3000
```

> **참고**: `/ask` 엔드포인트는 Pinecone 없이도 작동합니다. RAG 기능(`/rag`, `/agent`)을 사용하려면 Pinecone 설정이 필요합니다.

### 2. 의존성 설치

```bash
# uv로 가상환경 및 의존성 설치
uv sync
```

### 3. Pinecone 초기화 (RAG 사용 시)

#### 3-1. Pinecone 인덱스 생성

1. **Pinecone 콘솔** 접속: https://app.pinecone.io/
2. **Create Index** 클릭
3. 설정:
   - **Index Name**: `ai-service-docs` (또는 `.env`의 `PINECONE_INDEX_NAME`과 동일하게)
   - **Dimensions**: `1536` (OpenAI text-embedding-3-small 기준)
   - **Metric**: `cosine`
   - **Region**: 가까운 지역 선택 (예: `us-east-1`)
   - **Plan**: Starter (무료)
4. **Create Index** 완료

#### 3-2. 문서 임베딩 업로드 (선택사항)

```bash
# Pinecone에 샘플 문서 임베딩 (docs/ 디렉토리 필요)
uv run python init_pinecone.py
```

**예상 출력**:
```
============================================================
Pinecone 초기화 시작
============================================================
✓ OpenAI API Key: sk-proj***
✓ Pinecone API Key: pcsk***
✓ Pinecone Index: ai-service-docs

Found 5 markdown files in ./docs
✓ Loaded: 01_RAG_기초.md (8234 characters)
✓ Loaded: 02_Vector_Database.md (7512 characters)
...

✓ Split 5 documents into 42 chunks
✓ Successfully uploaded 42 embeddings to Pinecone

============================================================
검증 테스트
============================================================
Test Query: RAG란 무엇인가요?

✓ Retrieved 3 documents from Pinecone
[1] Source: 01_RAG_기초.md
    Content: RAG (Retrieval-Augmented Generation) 기초...

============================================================
Pinecone 초기화 완료!
============================================================
```

> **주의**: `init_pinecone.py` 스크립트가 없는 경우, Pinecone 대시보드에서 직접 문서를 업로드하거나 `/rag`, `/agent` 엔드포인트 없이 `/ask`만 사용할 수 있습니다.

### 4. FastAPI 서버 실행

```bash
# 개발 서버 실행 (자동 리로드)
uv run uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

**예상 출력**:
```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     Started reloader process [12345] using WatchFiles
INFO:     Started server process [12346]
INFO:     Waiting for application startup.
{"time": "2024-02-16 10:00:00", "level": "INFO", "trace_id": "startup", "message": "Application starting..."}
{"time": "2024-02-16 10:00:00", "level": "INFO", "trace_id": "init", "message": "LLM initialized: gpt-4o-mini, API Key: sk-proj***"}
{"time": "2024-02-16 10:00:00", "level": "INFO", "trace_id": "init", "message": "Pinecone initialized: ai-service-docs"}
{"time": "2024-02-16 10:00:01", "level": "INFO", "trace_id": "startup", "message": "Application started successfully"}
INFO:     Application startup complete.
```

> **참고**: Pinecone 설정이 없어도 서버는 시작되며, `/ask` 엔드포인트는 정상 작동합니다.

### 5. 접속 및 테스트

- **API Docs (Swagger UI)**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health
- **Readiness Check**: http://localhost:8000/ready

## 📡 API 엔드포인트

### 1. `/ask` - LLM 직접 호출 (Streaming)
```bash
curl -X POST "http://localhost:8000/ask" \
  -H "Content-Type: application/json" \
  -d '{"question": "Python의 장점은 무엇인가요?"}'
```

### 2. `/rag` - RAG 기반 답변 (Streaming)
```bash
curl -X POST "http://localhost:8000/rag" \
  -H "Content-Type: application/json" \
  -d '{"question": "RAG란 무엇인가요?"}'
```

### 3. `/agent` - Agent 자동 분류 (Streaming)
```bash
curl -X POST "http://localhost:8000/agent" \
  -H "Content-Type: application/json" \
  -d '{"question": "Vector Database의 장점은?"}'
```

## 🧪 테스트 질문 예시

### Ask 탭 (LLM 직접 호출)
- "안녕하세요"
- "Python에서 리스트와 튜플의 차이는?"
- "오늘 날씨 어때?"

### RAG 탭 (문서 검색 기반)
- "RAG란 무엇인가요?"
- "Vector Database의 종류는?"
- "LangGraph Agent는 어떻게 동작하나요?"
- "SSE와 WebSocket의 차이는?"
- "환경변수 관리 방법은?"

### Agent 탭 (자동 분류)
- "ChromaDB란?" → RAG 경로
- "안녕하세요" → Direct LLM 경로
- "Streaming은 왜 필요한가요?" → RAG 경로

## 🔧 트러블슈팅

### 1. `uv` 명령어를 찾을 수 없음
```bash
# uv 설치 확인
uv --version

# 설치되지 않았다면
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # 또는 ~/.zshrc
```

### 2. OpenAI API Key 에러
```
✗ Error: OPENAI_API_KEY not found in environment
```

**해결**:
- `.env` 파일에 올바른 API Key 입력 확인
- API Key가 `sk-proj-` 또는 `sk-`로 시작하는지 확인

### 3. Pinecone 연결 실패
```
✗ Error: Pinecone initialization failed
```

**해결**:
- `.env` 파일에 `PINECONE_API_KEY` 확인
- Pinecone 대시보드에서 인덱스 생성 확인
- 인덱스 이름이 `.env`의 `PINECONE_INDEX_NAME`과 일치하는지 확인
- 무료 플랜은 1개 인덱스만 생성 가능 (기존 인덱스 삭제 후 재생성)

### 4. Embedding 차원 불일치
```
✗ Error: Dimension mismatch
```

**해결**:
- Pinecone 인덱스 차원: `1536` (text-embedding-3-small)
- 다른 모델 사용 시:
  - `text-embedding-3-large`: 3072
  - `text-embedding-ada-002`: 1536

### 5. 포트 8000이 이미 사용 중
```bash
# 다른 포트로 실행
uv run uvicorn app:app --reload --port 8001
```

## 📚 다음 단계

1. **Frontend 연동**: `../frontend` 디렉토리에서 프론트엔드 실행
2. **Docker 학습**: Docker 컨테이너화 실습
3. **AWS/GCP 배포**: 클라우드 배포 실습

## ⚠️ 주의사항

- `.env` 파일은 절대 Git에 커밋하지 마세요!
- API Key는 타인과 공유하지 마세요
- Pinecone 무료 플랜은 1개 인덱스만 생성 가능합니다
- `/ask` 엔드포인트는 Pinecone 없이도 작동합니다 (LLM 직접 호출)

## 📖 참고 자료

- FastAPI 문서: https://fastapi.tiangolo.com/
- LangChain 문서: https://python.langchain.com/
- Pinecone 문서: https://docs.pinecone.io/
- uv 문서: https://docs.astral.sh/uv/

## 📄 라이센스

MIT License - 교육 목적으로 자유롭게 사용 가능합니다.
