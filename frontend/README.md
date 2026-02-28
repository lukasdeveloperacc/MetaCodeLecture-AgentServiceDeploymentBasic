# RAG/Agent Frontend - 로컬 실행 가이드

AI 서비스 통합 & 배포 강의를 위한 RAG/Agent 데모 프론트엔드입니다.

## 📋 주요 기능

- **3가지 인터페이스**: Ask (LLM 직접) / RAG (문서 검색) / Agent (자동 분류)
- **실시간 Streaming**: Server-Sent Events (SSE) 기반 토큰 단위 응답
- **Dark Mode UI**: 현대적이고 깔끔한 디자인
- **반응형 디자인**: 모바일/태블릿/데스크톱 지원

## 🛠️ 기술 스택

- **Vanilla JavaScript**: 프레임워크 없이 순수 JS
- **EventSource API**: SSE 클라이언트
- **CSS3**: 다크 모드, Flexbox, Grid
- **HTML5**: 시맨틱 마크업

## 📁 프로젝트 구조

```
frontend/
├─ index.html         # 메인 UI (3개 탭)
├─ style.css          # 다크 모드 스타일
├─ app.js             # SSE 클라이언트 로직
└─ README.md          # 이 파일
```

## 🚀 로컬 실행 방법

### 사전 요구사항

- **Backend 서버 실행**: `../backend` 디렉토리에서 FastAPI 서버 실행 필요
- **최신 웹 브라우저**: Chrome, Firefox, Safari, Edge (EventSource 지원)

### 방법 1: Python HTTP 서버 (간단)

```bash
# Python 3.x 내장 서버
python3 -m http.server 3000

# 또는 Python 2.x
python -m SimpleHTTPServer 3000
```

**접속**: http://localhost:3000

### 방법 2: Node.js http-server (권장)

```bash
# http-server 설치 (한 번만)
npm install -g http-server

# 서버 실행
http-server -p 3000 -c-1
```

**접속**: http://localhost:3000

### 방법 3: VS Code Live Server

1. VS Code에서 `index.html` 열기
2. 우클릭 → **"Open with Live Server"**
3. 자동으로 브라우저 열림 (기본 포트: 5500)

**주의**: `app.js`의 API_BASE_URL을 확인하세요.

## 🔧 설정

### Backend API URL 변경

`app.js` 파일 상단:

```javascript
// Backend 서버 URL
const API_BASE_URL = 'http://localhost:8000';

// 다른 포트를 사용한다면
// const API_BASE_URL = 'http://localhost:8001';
```

## 📱 사용 방법

### 1. Ask 탭 (LLM 직접 호출)

- OpenAI API를 직접 호출하여 일반 질문 응답
- **예시 질문**:
  - "안녕하세요"
  - "Python의 장점은?"
  - "오늘 날씨 어때?"

### 2. RAG 탭 (문서 검색 기반)

- ChromaDB에서 관련 문서를 검색하여 답변
- **검색된 문서 출처 표시**
- **예시 질문**:
  - "RAG란 무엇인가요?"
  - "Vector Database의 종류는?"
  - "LangGraph Agent는 어떻게 동작하나요?"
  - "SSE와 WebSocket의 차이는?"
  - "환경변수 관리 방법은?"

### 3. Agent 탭 (자동 분류)

- 질문을 분류하여 RAG 또는 Direct LLM 경로로 자동 라우팅
- **분류 결과 표시** (RAG / DIRECT)
- **예시 질문**:
  - "ChromaDB란?" → **RAG** 경로
  - "안녕하세요" → **DIRECT** 경로
  - "Streaming은 왜 필요한가요?" → **RAG** 경로

## 🎨 UI 기능

### 실시간 Streaming
- 답변이 토큰 단위로 실시간 표시
- 타이핑 효과 (ChatGPT 스타일)

### 탭 전환
- 3개 탭 간 부드러운 전환
- 탭 전환 시 이전 응답 유지

### Trace ID
- 각 요청에 고유 ID 부여
- 디버깅 및 로그 추적 용이

### 에러 처리
- 네트워크 에러 시 사용자 친화적 메시지
- 재시도 가능

## 🔧 트러블슈팅

### 1. EventSource와 Backend 통신 방식

**현재 구현 방식**:
- Frontend: `EventSource` API 사용 (GET 방식으로 쿼리 파라미터 전달)
  ```javascript
  const eventSource = new EventSource(`${url}?question=${encodeURIComponent(question)}`);
  ```
- Backend: `POST` 메서드로 JSON Body 수신
  ```python
  @app.post("/ask")
  async def ask_llm(request: QuestionRequest):
  ```

> **참고**: EventSource는 GET만 지원하므로, Backend가 POST를 요구하는 경우 코드 수정이 필요할 수 있습니다. 현재는 쿼리 파라미터 방식으로 작동하도록 구현되어 있습니다.

### 2. CORS 에러
```
Access to EventSource at 'http://localhost:8000/ask' from origin 'http://localhost:3000' has been blocked by CORS policy
```

**해결**:
- Backend `.env` 파일에서 CORS 설정 확인
  ```bash
  CORS_ORIGINS=http://localhost:3000
  ```
- Frontend를 다른 포트로 실행 중이라면 해당 포트 추가

### 3. Backend 연결 실패
```
EventSource's response has a MIME type ("application/json") that is not "text/event-stream"
```

**해결**:
- Backend 서버가 실행 중인지 확인
  ```bash
  curl http://localhost:8000/health
  ```
- Backend가 `text/event-stream` MIME 타입으로 응답하는지 확인
- `app.js`의 `API_BASE_URL` 확인

### 4. Streaming이 작동하지 않음

**해결**:
- 브라우저 개발자 도구 (F12) → Console 확인
- EventSource 연결 상태 확인
  ```javascript
  eventSource.readyState
  // 0: CONNECTING, 1: OPEN, 2: CLOSED
  ```
- Network 탭에서 SSE 연결 상태 및 응답 형식 확인
- Backend 로그에서 에러 메시지 확인

### 5. 빈 응답
```
응답:
(아무것도 표시 안 됨)
```

**해결**:
- Backend에서 Pinecone 초기화 확인 (RAG/Agent 탭의 경우)
  ```bash
  cd ../backend
  # Pinecone 인덱스가 생성되어 있는지 확인
  ```
- Backend 로그 확인
- `/ask` 엔드포인트 테스트 (Pinecone 없이 작동)
  ```bash
  curl -X POST "http://localhost:8000/ask" \
    -H "Content-Type: application/json" \
    -d '{"question": "안녕하세요"}'
  ```

## 📚 다음 단계

1. **Backend 수정**: API 엔드포인트 추가
2. **Docker 학습**: Frontend를 Nginx 컨테이너로 배포
3. **AWS/GCP 배포**: 정적 파일 호스팅 (S3, Cloud Storage)

## 💡 학습 포인트

### EventSource (SSE) 사용법

#### 1. GET 방식 (현재 구현)
```javascript
// 쿼리 파라미터로 데이터 전달 (EventSource는 GET만 지원)
const eventSource = new EventSource('http://localhost:8000/ask?question=' + encodeURIComponent('안녕'));

eventSource.onmessage = (event) => {
    const data = JSON.parse(event.data);

    // 이벤트 타입별 처리
    switch (data.type) {
        case 'token':
            console.log('Token:', data.content);
            break;
        case 'done':
            console.log('완료');
            eventSource.close();
            break;
        case 'error':
            console.error('에러:', data.message);
            eventSource.close();
            break;
    }
};

eventSource.onerror = (error) => {
    console.error('SSE Error:', error);

    if (eventSource.readyState === EventSource.CLOSED) {
        console.log('연결 종료됨');
    }
};

// 연결 종료
eventSource.close();
```

#### 2. POST + ReadableStream 방식 (대안)
```javascript
// POST 요청으로 SSE 수신 (EventSource 대신 Fetch 사용)
const response = await fetch('http://localhost:8000/ask', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ question: '안녕' })
});

const reader = response.body.getReader();
const decoder = new TextDecoder();

while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value);

    // SSE 형식 파싱: "data: {...}\n\n"
    const lines = chunk.split('\n');
    for (const line of lines) {
        if (line.startsWith('data: ')) {
            const data = JSON.parse(line.slice(6));
            console.log(data);
        }
    }
}
```

### SSE 이벤트 형식
```
data: {"type": "token", "content": "안녕", "trace_id": "abc123"}

data: {"type": "done", "trace_id": "abc123"}

```

> **참고**: SSE는 각 메시지가 `data: ` 접두사로 시작하고 빈 줄(`\n\n`)로 구분됩니다.

## ⚠️ 주의사항

- **Backend 서버를 먼저 실행**해야 합니다 (`../backend` 디렉토리)
- **CORS 설정**이 올바른지 확인하세요 (Backend `.env` 파일)
- **EventSource는 GET만 지원**합니다
  - 쿼리 파라미터로 데이터 전달 (URL 길이 제한 주의)
  - POST가 필요한 경우 Fetch API + ReadableStream 사용
- **브라우저 호환성**: 최신 브라우저 사용 (EventSource 지원 확인)

## 📖 참고 자료

- MDN EventSource: https://developer.mozilla.org/en-US/docs/Web/API/EventSource
- Server-Sent Events: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events
- Fetch API: https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API

## 📄 라이센스

MIT License - 교육 목적으로 자유롭게 사용 가능합니다.
