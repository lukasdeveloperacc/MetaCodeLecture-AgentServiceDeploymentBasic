# Section 0: Backend + Frontend 로컬 실행

## 학습 목표
- Python/uv 환경 설정
- FastAPI 서버 실행 및 Swagger UI 확인
- Frontend 연동 및 통합 테스트
- Pinecone 초기화 및 Vector DB 연동
- 3가지 탭 테스트: Ask / RAG / Agent

## 포함된 코드
```
backend/
  ├── app.py                 # FastAPI 메인 애플리케이션
  ├── init_pinecone.py       # Pinecone Vector DB 초기화
  ├── pyproject.toml         # Python 의존성 관리
  └── docs/                  # 이론 문서들

frontend/
  ├── index.html             # 메인 HTML
  ├── app.js                 # JavaScript 로직
  └── style.css              # 스타일링
```

## 실행 방법

### 1. Backend 실행
```bash
cd backend
uv sync
uv run uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

### 2. Frontend 실행
```bash
cd frontend
# Live Server 또는 Python HTTP Server 사용
uv run python -m http.server 3000
```

### 3. 브라우저 접속
- Frontend: http://localhost:3000
- Backend API Docs: http://localhost:8000/docs

## 완료 체크리스트
- [ ] Backend가 정상적으로 실행되는가?
- [ ] Swagger UI에서 API 테스트가 가능한가?
- [ ] Frontend가 Backend와 통신하는가?
- [ ] Ask 탭에서 LLM 응답을 받을 수 있는가?
- [ ] RAG 탭에서 Vector DB 검색이 동작하는가?
- [ ] Agent 탭에서 다단계 추론이 동작하는가?
