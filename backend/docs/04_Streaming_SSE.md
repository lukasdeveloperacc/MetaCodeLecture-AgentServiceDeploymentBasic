# Streaming과 Server-Sent Events (SSE)

## Streaming이란?

Streaming은 **데이터를 한 번에 전송하지 않고 연속적으로 조금씩 전송하는 방식**입니다. LLM 응답에서는 토큰 단위로 실시간 전송하여 사용자 경험을 개선합니다.

### 일반 응답 vs Streaming

**일반 응답 (Non-Streaming)**:
```
사용자: "Python이란?"
[3초 대기...]
AI: "Python은 고수준 프로그래밍 언어입니다. 1991년 귀도 반 로섬이 개발했으며..."
```

**Streaming 응답**:
```
사용자: "Python이란?"
AI: "Python"
AI: "은 고"
AI: "수준 프"
AI: "로그래밍 언어"
AI: "입니다. 1991"
...
```

### Streaming의 장점

1. **빠른 첫 응답**
   - 전체 생성 완료를 기다리지 않음
   - 첫 토큰이 즉시 표시

2. **향상된 사용자 경험**
   - ChatGPT처럼 타이핑하는 효과
   - 시스템이 작동 중임을 인지
   - 대기 시간 체감 감소

3. **긴 응답 처리**
   - 메모리 효율적
   - 네트워크 부담 분산

4. **조기 중단 가능**
   - 사용자가 원하지 않으면 중단
   - 불필요한 토큰 생성 방지

## Server-Sent Events (SSE)

SSE는 **서버에서 클라이언트로 단방향 실시간 데이터 전송**을 위한 표준입니다.

### SSE vs WebSocket

| 특성 | SSE | WebSocket |
|------|-----|-----------|
| 방향 | 단방향 (서버→클라이언트) | 양방향 |
| 프로토콜 | HTTP | WebSocket (ws://) |
| 재연결 | 자동 | 수동 처리 필요 |
| 구현 | 간단 | 복잡 |
| 사용 사례 | 알림, Streaming | 채팅, 게임 |

**SSE가 적합한 경우**:
- LLM Streaming 응답
- 실시간 알림
- 진행 상황 업데이트
- 로그 스트리밍

**WebSocket이 필요한 경우**:
- 실시간 채팅
- 멀티플레이어 게임
- 협업 도구

### SSE 메시지 형식

```
data: {"type": "token", "content": "안녕"}

data: {"type": "token", "content": "하세요"}

data: {"type": "done"}

```

**규칙**:
- `data:` 접두사
- 빈 줄(`\n\n`)로 메시지 구분
- UTF-8 인코딩

## FastAPI에서 SSE 구현

### 기본 SSE 엔드포인트

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
import asyncio
import json

app = FastAPI()

@app.get("/stream")
async def stream_data():
    async def event_generator():
        for i in range(10):
            # 1초마다 데이터 전송
            await asyncio.sleep(1)

            # SSE 형식으로 전송
            data = json.dumps({"count": i})
            yield f"data: {data}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        }
    )
```

### LLM Streaming 구현

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from langchain_openai import ChatOpenAI
from pydantic import BaseModel
import json
import uuid

app = FastAPI()

class QuestionRequest(BaseModel):
    question: str

@app.post("/ask")
async def ask_llm(request: QuestionRequest):
    """LLM Streaming 응답"""
    trace_id = str(uuid.uuid4())
    llm = ChatOpenAI(model="gpt-4o-mini", streaming=True)

    async def event_generator():
        try:
            token_count = 0

            # LLM Streaming
            async for chunk in llm.astream(request.question):
                if chunk.content:
                    token_count += 1

                    # SSE 형식으로 토큰 전송
                    data = json.dumps({
                        "type": "token",
                        "content": chunk.content,
                        "trace_id": trace_id
                    })
                    yield f"data: {data}\n\n"

            # 완료 이벤트
            yield f"data: {json.dumps({'type': 'done', 'trace_id': trace_id})}\n\n"

        except Exception as e:
            # 에러 이벤트
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # Nginx 버퍼링 방지
            "X-Trace-ID": trace_id
        }
    )
```

### RAG Streaming 구현

```python
from langchain_pinecone import PineconeVectorStore
from langchain_openai import OpenAIEmbeddings

@app.post("/rag")
async def rag_answer(request: QuestionRequest):
    """RAG Streaming 응답"""
    trace_id = str(uuid.uuid4())

    # 벡터 저장소 초기화
    embeddings = OpenAIEmbeddings()
    vectorstore = PineconeVectorStore(
        index_name="my-index",
        embedding=embeddings
    )

    llm = ChatOpenAI(model="gpt-4o-mini", streaming=True)

    async def event_generator():
        try:
            # 1. 관련 문서 검색
            docs = vectorstore.similarity_search(request.question, k=3)

            # 2. 검색된 문서 출처 전송
            sources = [
                {
                    "content": doc.page_content[:200],
                    "metadata": doc.metadata
                }
                for doc in docs
            ]
            yield f"data: {json.dumps({'type': 'sources', 'data': sources})}\n\n"

            # 3. 컨텍스트 구성
            context = "\n\n".join([doc.page_content for doc in docs])

            # 4. RAG 프롬프트
            prompt = f"""다음 문서를 참고하여 질문에 답하세요.

문서:
{context}

질문: {request.question}

답변:"""

            # 5. LLM Streaming
            async for chunk in llm.astream(prompt):
                if chunk.content:
                    data = json.dumps({
                        "type": "token",
                        "content": chunk.content,
                        "trace_id": trace_id
                    })
                    yield f"data: {data}\n\n"

            # 6. 완료 이벤트
            yield f"data: {json.dumps({'type': 'done', 'trace_id': trace_id})}\n\n"

        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            "X-Trace-ID": trace_id
        }
    )
```

## 프론트엔드에서 SSE 수신

### EventSource API (GET 요청)

```javascript
const API_BASE_URL = 'http://localhost:8000';

// EventSource 생성 (GET만 지원)
const eventSource = new EventSource(
    `${API_BASE_URL}/ask?question=${encodeURIComponent('Python이란?')}`
);

let fullResponse = '';

// 메시지 수신
eventSource.onmessage = (event) => {
    const data = JSON.parse(event.data);

    switch (data.type) {
        case 'token':
            // 토큰 추가
            fullResponse += data.content;
            document.getElementById('response').textContent = fullResponse;
            break;

        case 'done':
            // 완료
            console.log('Streaming 완료:', data.trace_id);
            eventSource.close();
            break;

        case 'error':
            // 에러
            console.error('에러:', data.message);
            eventSource.close();
            break;
    }
};

// 에러 처리
eventSource.onerror = (error) => {
    console.error('SSE 연결 오류:', error);

    if (eventSource.readyState === EventSource.CLOSED) {
        console.log('연결 종료됨');
    }
};

// 연결 종료
// eventSource.close();
```

### Fetch API (POST 요청)

EventSource는 GET만 지원하므로, POST가 필요하면 Fetch 사용:

```javascript
async function streamWithFetch(question) {
    const response = await fetch('http://localhost:8000/ask', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ question })
    });

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
        const { done, value } = await reader.read();

        if (done) {
            console.log('Streaming 완료');
            break;
        }

        // 청크 디코딩
        buffer += decoder.decode(value, { stream: true });

        // SSE 메시지 파싱
        const lines = buffer.split('\n');

        for (let i = 0; i < lines.length - 1; i++) {
            const line = lines[i].trim();

            if (line.startsWith('data: ')) {
                const data = JSON.parse(line.slice(6));

                if (data.type === 'token') {
                    document.getElementById('response').textContent += data.content;
                }
            }
        }

        // 마지막 불완전한 라인 유지
        buffer = lines[lines.length - 1];
    }
}

// 사용
streamWithFetch('Python이란?');
```

### React에서 SSE 사용

```javascript
import { useState, useEffect } from 'react';

function ChatComponent() {
    const [response, setResponse] = useState('');
    const [isStreaming, setIsStreaming] = useState(false);

    const askQuestion = (question) => {
        setResponse('');
        setIsStreaming(true);

        const eventSource = new EventSource(
            `http://localhost:8000/ask?question=${encodeURIComponent(question)}`
        );

        eventSource.onmessage = (event) => {
            const data = JSON.parse(event.data);

            if (data.type === 'token') {
                setResponse(prev => prev + data.content);
            } else if (data.type === 'done') {
                setIsStreaming(false);
                eventSource.close();
            }
        };

        eventSource.onerror = () => {
            setIsStreaming(false);
            eventSource.close();
        };
    };

    return (
        <div>
            <button onClick={() => askQuestion('Python이란?')}>
                질문하기
            </button>
            <div>
                {response}
                {isStreaming && <span className="cursor">|</span>}
            </div>
        </div>
    );
}
```

## CORS 설정

프론트엔드와 백엔드가 다른 도메인일 때:

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # 프론트엔드 도메인
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## 에러 처리

### 백엔드 에러 처리

```python
@app.post("/ask")
async def ask_llm(request: QuestionRequest):
    async def event_generator():
        try:
            # 검증
            if not request.question.strip():
                yield f"data: {json.dumps({'type': 'error', 'message': '질문을 입력하세요'})}\n\n"
                return

            # LLM Streaming
            async for chunk in llm.astream(request.question):
                yield f"data: {json.dumps({'type': 'token', 'content': chunk.content})}\n\n"

        except openai.RateLimitError:
            yield f"data: {json.dumps({'type': 'error', 'message': 'API 호출 한도 초과'})}\n\n"

        except openai.APIError as e:
            yield f"data: {json.dumps({'type': 'error', 'message': f'OpenAI API 에러: {str(e)}'})}\n\n"

        except Exception as e:
            # 예상치 못한 에러
            logger.error(f"Unexpected error: {e}")
            yield f"data: {json.dumps({'type': 'error', 'message': '서버 오류가 발생했습니다'})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
```

### 프론트엔드 에러 처리

```javascript
eventSource.onerror = (error) => {
    console.error('SSE Error:', error);

    // 연결 상태 확인
    switch (eventSource.readyState) {
        case EventSource.CONNECTING:
            console.log('재연결 중...');
            break;

        case EventSource.OPEN:
            console.log('연결 정상');
            break;

        case EventSource.CLOSED:
            console.log('연결 종료됨');
            // UI 업데이트
            setIsStreaming(false);
            break;
    }
};
```

## 재연결 처리

SSE는 자동 재연결을 지원하지만, 커스터마이징 가능:

```javascript
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 3;

function createEventSource(url) {
    const eventSource = new EventSource(url);

    eventSource.onerror = () => {
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts++;
            console.log(`재연결 시도 ${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS}`);

            // 3초 후 재연결
            setTimeout(() => {
                eventSource.close();
                createEventSource(url);
            }, 3000);
        } else {
            console.error('최대 재연결 횟수 초과');
            eventSource.close();
        }
    };

    eventSource.onopen = () => {
        reconnectAttempts = 0;  // 성공 시 리셋
        console.log('연결 성공');
    };

    return eventSource;
}
```

## 성능 최적화

### 1. 버퍼 크기 조정

```python
async def event_generator():
    buffer = []
    buffer_size = 5  # 5개 토큰씩 묶어서 전송

    async for chunk in llm.astream(prompt):
        if chunk.content:
            buffer.append(chunk.content)

            if len(buffer) >= buffer_size:
                # 버퍼가 차면 전송
                content = ''.join(buffer)
                yield f"data: {json.dumps({'type': 'token', 'content': content})}\n\n"
                buffer = []

    # 남은 토큰 전송
    if buffer:
        content = ''.join(buffer)
        yield f"data: {json.dumps({'type': 'token', 'content': content})}\n\n"
```

### 2. 압축

```python
from fastapi.responses import StreamingResponse
import gzip

@app.post("/ask")
async def ask_llm(request: QuestionRequest):
    async def event_generator():
        # ... streaming logic ...
        pass

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Content-Encoding": "gzip",  # 압축 사용
        }
    )
```

### 3. 연결 풀링

```python
from langchain_openai import ChatOpenAI

# 싱글톤 패턴으로 LLM 인스턴스 재사용
llm_instance = None

def get_llm():
    global llm_instance
    if llm_instance is None:
        llm_instance = ChatOpenAI(model="gpt-4o-mini", streaming=True)
    return llm_instance

@app.post("/ask")
async def ask_llm(request: QuestionRequest):
    llm = get_llm()  # 재사용
    # ...
```

## 로깅과 모니터링

### 구조화된 로깅

```python
import logging
import json

# JSON 로그 포맷
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "trace_id": "%(trace_id)s", "message": "%(message)s"}'
)

logger = logging.getLogger(__name__)

@app.post("/ask")
async def ask_llm(request: QuestionRequest):
    trace_id = str(uuid.uuid4())

    async def event_generator():
        token_count = 0
        start_time = time.time()

        logger.info(
            f"Streaming started: {request.question[:50]}...",
            extra={"trace_id": trace_id}
        )

        async for chunk in llm.astream(request.question):
            token_count += 1
            yield f"data: {json.dumps({'type': 'token', 'content': chunk.content})}\n\n"

        duration = time.time() - start_time

        logger.info(
            f"Streaming completed: {token_count} tokens in {duration:.2f}s",
            extra={"trace_id": trace_id}
        )

    return StreamingResponse(...)
```

## Best Practices

1. **타임아웃 설정**
   ```python
   import asyncio

   async def event_generator():
       try:
           async with asyncio.timeout(30):  # 30초 타임아웃
               async for chunk in llm.astream(prompt):
                   yield ...
       except asyncio.TimeoutError:
           yield f"data: {json.dumps({'type': 'error', 'message': 'Timeout'})}\n\n"
   ```

2. **Heartbeat**
   ```python
   async def event_generator():
       last_sent = time.time()

       async for chunk in llm.astream(prompt):
           yield ...
           last_sent = time.time()

       # 30초마다 keep-alive 전송
       if time.time() - last_sent > 30:
           yield ": keep-alive\n\n"
   ```

3. **Graceful Shutdown**
   ```python
   from contextlib import asynccontextmanager

   @asynccontextmanager
   async def lifespan(app: FastAPI):
       # Startup
       yield
       # Shutdown
       # 진행 중인 스트리밍 정리
   ```

4. **메모리 관리**
   - 큰 응답은 청크로 분할
   - 버퍼 크기 제한
   - 타임아웃 설정

## 다음 단계

SSE Streaming을 마스터했다면:

1. **Agent Streaming**: LangGraph Agent의 진행 상황 스트리밍
2. **실시간 협업**: WebSocket으로 확장
3. **모니터링**: 메트릭 수집 및 대시보드
4. **프로덕션 최적화**: CDN, 로드 밸런싱, 캐싱
