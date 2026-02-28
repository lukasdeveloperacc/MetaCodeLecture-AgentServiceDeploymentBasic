"""
RAG/Agent Demo Service - FastAPI Backend
AI 서비스 통합 & 배포 강의용 데모 애플리케이션
"""

import os
import json
import uuid
import logging
from typing import AsyncGenerator
from dotenv import load_dotenv

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_pinecone import PineconeVectorStore

# 환경변수 로드
load_dotenv()


# Custom Formatter: trace_id가 없으면 기본값 제공
class TraceIdFormatter(logging.Formatter):
    """trace_id가 없는 로그 레코드에 기본값을 제공"""
    def format(self, record):
        if not hasattr(record, 'trace_id'):
            record.trace_id = 'N/A'
        return super().format(record)


# 로깅 설정 (JSON 포맷)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Console handler with custom formatter
handler = logging.StreamHandler()
handler.setFormatter(TraceIdFormatter(
    '{"time": "%(asctime)s", "level": "%(levelname)s", "trace_id": "%(trace_id)s", "message": "%(message)s"}'
))
logger.addHandler(handler)

# Root logger에도 동일 formatter 적용 (httpx 등 외부 라이브러리용)
logging.root.setLevel(logging.INFO)
logging.root.addHandler(handler)

# FastAPI 앱 생성
app = FastAPI(
    title="RAG/Agent Demo Service",
    description="AI 서비스 통합 & 배포 강의용 데모",
    version="1.0.0"
)

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:5500",  # Live Server
        "http://localhost:5500"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 전역 변수
vectorstore = None
llm = None


# API 키 마스킹 함수
def mask_api_key(key: str) -> str:
    """API 키를 마스킹하여 로그에 안전하게 출력"""
    if not key:
        return "None"
    return f"{key[:7]}***"


# Pinecone 초기화
def init_pinecone():
    """Pinecone VectorStore 초기화 (클라우드 매니지드)"""
    global vectorstore

    try:
        index_name = os.getenv("PINECONE_INDEX_NAME", "ai-service-docs")

        # Embeddings 모델 초기화
        embeddings = OpenAIEmbeddings(
            model=os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
        )

        # VectorStore 초기화 (Pinecone)
        vectorstore = PineconeVectorStore(
            index_name=index_name,
            embedding=embeddings
        )

        logger.info(f"Pinecone initialized: {index_name}", extra={"trace_id": "init"})
        return True

    except Exception as e:
        logger.error(f"Pinecone initialization failed: {e}", extra={"trace_id": "init"})
        return False


# LLM 초기화
def init_llm():
    """OpenAI LLM 초기화"""
    global llm

    try:
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY not found in environment")

        llm = ChatOpenAI(
            model=os.getenv("LLM_MODEL", "gpt-4o-mini"),
            temperature=float(os.getenv("LLM_TEMPERATURE", "0.7")),
            max_tokens=int(os.getenv("LLM_MAX_TOKENS", "1000")),
            streaming=True
        )

        logger.info(
            f"LLM initialized: {os.getenv('LLM_MODEL', 'gpt-4o-mini')}, API Key: {mask_api_key(api_key)}",
            extra={"trace_id": "init"}
        )
        return True

    except Exception as e:
        logger.error(f"LLM initialization failed: {e}", extra={"trace_id": "init"})
        return False


@app.on_event("startup")
async def startup_event():
    """애플리케이션 시작 시 초기화"""
    logger.info("Application starting...", extra={"trace_id": "startup"})

    # LLM 초기화
    if not init_llm():
        logger.error("Failed to initialize LLM - check OPENAI_API_KEY", extra={"trace_id": "startup"})

    # Pinecone 초기화 (선택적 - 없어도 /ask 엔드포인트는 동작)
    if not init_pinecone():
        logger.warning("Pinecone not available - RAG endpoints will fail", extra={"trace_id": "startup"})

    logger.info("Application started successfully", extra={"trace_id": "startup"})


@app.get("/health")
async def health_check():
    """헬스체크 엔드포인트"""
    return {"status": "healthy"}


@app.get("/ready")
async def readiness_check():
    """Readiness 체크 엔드포인트"""
    checks = {
        "llm": llm is not None,
        "vectorstore": vectorstore is not None
    }

    status = "ready" if all(checks.values()) else "not_ready"

    return {
        "status": status,
        "checks": checks
    }


@app.get("/ask")
async def ask_llm(question: str):
    """
    LLM API 직접 호출 (Streaming)
    - OpenAI API를 직접 호출하여 답변 생성
    - Server-Sent Events (SSE)로 실시간 스트리밍
    """
    trace_id = str(uuid.uuid4())

    if not question or not question.strip():
        raise HTTPException(status_code=400, detail="Question is required")

    logger.info(
        f"[/ask] Question: {question[:50]}...",
        extra={"trace_id": trace_id}
    )

    if not llm:
        raise HTTPException(status_code=503, detail="LLM not initialized")

    async def event_generator() -> AsyncGenerator[str, None]:
        """SSE 이벤트 생성기"""
        try:
            token_count = 0

            # LLM Streaming
            async for chunk in llm.astream(question):
                if chunk.content:
                    token_count += 1

                    # SSE 형식으로 전송
                    data = json.dumps({
                        "type": "token",
                        "content": chunk.content,
                        "trace_id": trace_id
                    })
                    yield f"data: {data}\n\n"

            # 완료 이벤트
            logger.info(
                f"[/ask] Completed: {token_count} tokens",
                extra={"trace_id": trace_id}
            )

            yield f"data: {json.dumps({'type': 'done', 'trace_id': trace_id})}\n\n"

        except Exception as e:
            logger.error(
                f"[/ask] Error: {e}",
                extra={"trace_id": trace_id}
            )

            # 에러 이벤트
            yield f"data: {json.dumps({'type': 'error', 'message': str(e), 'trace_id': trace_id})}\n\n"

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


@app.get("/rag")
async def rag_answer(question: str):
    """
    RAG 기반 질문 응답 (Streaming)
    - Pinecone에서 관련 문서 검색
    - 검색 결과를 컨텍스트로 LLM 답변 생성
    - 근거 문서 출처 포함
    """
    trace_id = str(uuid.uuid4())

    if not question or not question.strip():
        raise HTTPException(status_code=400, detail="Question is required")

    logger.info(
        f"[/rag] Question: {question[:50]}...",
        extra={"trace_id": trace_id}
    )

    if not vectorstore:
        raise HTTPException(status_code=503, detail="Pinecone not initialized")

    if not llm:
        raise HTTPException(status_code=503, detail="LLM not initialized")

    async def event_generator() -> AsyncGenerator[str, None]:
        """SSE 이벤트 생성기"""
        try:
            # Pinecone에서 관련 문서 검색
            top_k = int(os.getenv("RAG_TOP_K", "3"))
            docs = vectorstore.similarity_search(question, k=top_k)

            # 검색된 문서 출처 전송
            sources = [{"content": doc.page_content[:200], "metadata": doc.metadata} for doc in docs]
            yield f"data: {json.dumps({'type': 'sources', 'data': sources, 'trace_id': trace_id})}\n\n"

            # 컨텍스트 구성
            context = "\n\n".join([doc.page_content for doc in docs])

            # RAG 프롬프트
            prompt = f"""다음 문서를 참고하여 질문에 답하세요.

문서:
{context}

질문: {question}

답변:"""

            # LLM Streaming
            token_count = 0
            async for chunk in llm.astream(prompt):
                if chunk.content:
                    token_count += 1

                    data = json.dumps({
                        "type": "token",
                        "content": chunk.content,
                        "trace_id": trace_id
                    })
                    yield f"data: {data}\n\n"

            # 완료 이벤트
            logger.info(
                f"[/rag] Completed: {token_count} tokens, {len(docs)} docs retrieved",
                extra={"trace_id": trace_id}
            )

            yield f"data: {json.dumps({'type': 'done', 'trace_id': trace_id})}\n\n"

        except Exception as e:
            logger.error(
                f"[/rag] Error: {e}",
                extra={"trace_id": trace_id}
            )

            yield f"data: {json.dumps({'type': 'error', 'message': str(e), 'trace_id': trace_id})}\n\n"

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


@app.get("/agent")
async def agent_answer(question: str):
    """
    LangGraph Agent 실행 (Streaming)
    - Step 1: 질문 분류 (RAG 필요 vs LLM 직접 답변)
    - Step 2: 분류 결과에 따라 RAG 또는 Direct LLM 실행

    Note: 실제 LangGraph 구현은 agent.py에서 import 예정
    현재는 간단한 분류 로직으로 구현
    """
    trace_id = str(uuid.uuid4())

    if not question or not question.strip():
        raise HTTPException(status_code=400, detail="Question is required")

    logger.info(
        f"[/agent] Question: {question[:50]}...",
        extra={"trace_id": trace_id}
    )

    if not llm:
        raise HTTPException(status_code=503, detail="LLM not initialized")

    async def event_generator() -> AsyncGenerator[str, None]:
        """SSE 이벤트 생성기"""
        try:
            # Step 1: 질문 분류
            classify_prompt = f"""다음 질문이 외부 문서 검색이 필요한지 판단하세요.

- 기술 문서, 내부 자료, 특정 도메인 지식이 필요한 질문 → "RAG"
- 일반 상식, 간단한 질문 → "DIRECT"

질문: {question}

"RAG" 또는 "DIRECT" 중 하나만 답하세요 (다른 설명 없이):"""

            # 분류 실행
            classification_result = await llm.ainvoke(classify_prompt)
            classification = classification_result.content.strip().upper()

            # RAG/DIRECT 외 다른 답변이 오면 기본값 처리
            if classification not in ["RAG", "DIRECT"]:
                classification = "DIRECT"

            # 분류 결과 전송
            yield f"data: {json.dumps({'type': 'classification', 'result': classification, 'trace_id': trace_id})}\n\n"

            logger.info(
                f"[/agent] Classification: {classification}",
                extra={"trace_id": trace_id}
            )

            # Step 2: 분류에 따라 실행
            if classification == "RAG" and vectorstore:
                # RAG 경로
                top_k = int(os.getenv("RAG_TOP_K", "3"))
                docs = vectorstore.similarity_search(question, k=top_k)

                sources = [{"content": doc.page_content[:200], "metadata": doc.metadata} for doc in docs]
                yield f"data: {json.dumps({'type': 'sources', 'data': sources, 'trace_id': trace_id})}\n\n"

                context = "\n\n".join([doc.page_content for doc in docs])
                prompt = f"""다음 문서를 참고하여 질문에 답하세요.

문서:
{context}

질문: {question}

답변:"""
            else:
                # Direct LLM 경로
                prompt = question

            # LLM Streaming
            token_count = 0
            async for chunk in llm.astream(prompt):
                if chunk.content:
                    token_count += 1

                    data = json.dumps({
                        "type": "token",
                        "content": chunk.content,
                        "trace_id": trace_id
                    })
                    yield f"data: {data}\n\n"

            # 완료 이벤트
            logger.info(
                f"[/agent] Completed: {classification} path, {token_count} tokens",
                extra={"trace_id": trace_id}
            )

            yield f"data: {json.dumps({'type': 'done', 'trace_id': trace_id})}\n\n"

        except Exception as e:
            logger.error(
                f"[/agent] Error: {e}",
                extra={"trace_id": trace_id}
            )

            yield f"data: {json.dumps({'type': 'error', 'message': str(e), 'trace_id': trace_id})}\n\n"

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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
