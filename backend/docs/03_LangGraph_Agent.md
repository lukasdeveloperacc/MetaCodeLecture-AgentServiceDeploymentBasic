# LangGraph Agent

## Agent란 무엇인가?

Agent는 **목표를 달성하기 위해 스스로 추론하고 행동을 선택하는 AI 시스템**입니다. 단순히 질문에 답변하는 것을 넘어, 도구를 사용하고 복잡한 작업을 수행할 수 있습니다.

### Agent vs 단순 체인

**단순 체인 (Chain)**:
```
사용자 질문 → LLM → 답변
```
- 정해진 순서대로 실행
- 유연성 낮음
- 간단한 작업에 적합

**Agent**:
```
사용자 질문 → Agent가 추론 → 도구 선택 → 실행 → 결과 평가 → 다음 행동 결정 → ...
```
- 동적으로 행동 선택
- 도구 사용 가능
- 복잡한 작업 해결

### Agent의 구성 요소

1. **LLM (Brain)**: 추론과 의사결정
2. **Tools**: 외부 기능 (검색, 계산, API 호출 등)
3. **Memory**: 대화 기록과 상태 저장
4. **Executor**: 행동 실행 및 제어

## LangGraph란?

LangGraph는 **복잡한 Agent 워크플로우를 그래프로 정의하는 프레임워크**입니다.

### 왜 LangGraph인가?

**기존 LangChain Agent의 한계**:
- 선형적인 흐름만 가능
- 복잡한 분기 처리 어려움
- 상태 관리 제한적

**LangGraph의 장점**:
- ✅ 그래프 기반 워크플로우
- ✅ 복잡한 분기와 루프
- ✅ 명시적인 상태 관리
- ✅ 체크포인트와 재실행
- ✅ 사람 개입 가능 (Human-in-the-loop)

## 기본 개념

### 1. 노드 (Node)

그래프의 각 단계를 나타냅니다.

```python
def my_node(state):
    """노드 함수: state를 받아서 업데이트를 반환"""
    print(f"Current state: {state}")
    return {"messages": state["messages"] + ["새 메시지"]}
```

### 2. 엣지 (Edge)

노드 간 연결을 나타냅니다.

**일반 엣지**:
```python
graph.add_edge("node_a", "node_b")  # A → B
```

**조건부 엣지**:
```python
def should_continue(state):
    if state["count"] < 5:
        return "continue"
    else:
        return "end"

graph.add_conditional_edges(
    "node_a",
    should_continue,
    {
        "continue": "node_b",
        "end": END
    }
)
```

### 3. 상태 (State)

그래프 전체에서 공유되는 데이터입니다.

```python
from typing import TypedDict, Annotated, Sequence
from langchain_core.messages import BaseMessage
from langgraph.graph import add_messages

class AgentState(TypedDict):
    messages: Annotated[Sequence[BaseMessage], add_messages]
    current_step: int
    tools_used: list[str]
```

## 간단한 Agent 예제

### 1. 질문 분류 Agent

RAG가 필요한지 판단하는 간단한 Agent:

```python
from langgraph.graph import StateGraph, END
from langchain_openai import ChatOpenAI
from typing import TypedDict

# 1. 상태 정의
class State(TypedDict):
    question: str
    classification: str
    answer: str

# 2. 노드 정의
llm = ChatOpenAI(model="gpt-4o-mini")

def classify_question(state: State) -> State:
    """질문을 RAG/DIRECT로 분류"""
    prompt = f"""다음 질문이 외부 문서 검색이 필요한지 판단하세요.

질문: {state["question"]}

"RAG" 또는 "DIRECT" 중 하나만 답하세요:"""

    result = llm.invoke(prompt)
    classification = result.content.strip()

    return {"classification": classification}

def rag_answer(state: State) -> State:
    """RAG로 답변 생성"""
    # 여기서는 간단히 시뮬레이션
    answer = f"[RAG] {state['question']}에 대한 문서 기반 답변"
    return {"answer": answer}

def direct_answer(state: State) -> State:
    """LLM 직접 답변"""
    result = llm.invoke(state["question"])
    return {"answer": result.content}

# 3. 그래프 구성
workflow = StateGraph(State)

# 노드 추가
workflow.add_node("classify", classify_question)
workflow.add_node("rag", rag_answer)
workflow.add_node("direct", direct_answer)

# 시작점 설정
workflow.set_entry_point("classify")

# 조건부 엣지 (분류 결과에 따라 분기)
def route_question(state: State):
    if state["classification"] == "RAG":
        return "rag"
    else:
        return "direct"

workflow.add_conditional_edges(
    "classify",
    route_question,
    {
        "rag": "rag",
        "direct": "direct"
    }
)

# 종료 엣지
workflow.add_edge("rag", END)
workflow.add_edge("direct", END)

# 4. 컴파일 및 실행
app = workflow.compile()

# 실행
result = app.invoke({
    "question": "RAG란 무엇인가요?",
    "classification": "",
    "answer": ""
})

print(f"분류: {result['classification']}")
print(f"답변: {result['answer']}")
```

### 2. 도구를 사용하는 Agent

```python
from langchain.agents import Tool
from langchain_community.tools import DuckDuckGoSearchRun
from langgraph.prebuilt import create_react_agent

# 1. 도구 정의
search = DuckDuckGoSearchRun()

def calculator(expression: str) -> str:
    """간단한 계산기"""
    try:
        return str(eval(expression))
    except:
        return "계산 오류"

tools = [
    Tool(
        name="Search",
        func=search.run,
        description="웹 검색이 필요할 때 사용. 최신 정보 검색."
    ),
    Tool(
        name="Calculator",
        func=calculator,
        description="수학 계산이 필요할 때 사용. 예: '2 + 2'"
    )
]

# 2. Agent 생성
llm = ChatOpenAI(model="gpt-4o-mini")
agent = create_react_agent(llm, tools)

# 3. 실행
result = agent.invoke({
    "messages": [("user", "2024년 올림픽은 어디서 열렸나요?")]
})

for message in result["messages"]:
    print(f"{message.type}: {message.content}")
```

## 고급 패턴

### 1. ReAct (Reasoning + Acting)

추론과 행동을 반복하는 패턴:

```
Thought: 날씨를 알아야 하니 검색 도구를 사용해야겠다
Action: search("서울 날씨")
Observation: 맑음, 15도
Thought: 이제 답변할 수 있다
Answer: 서울은 현재 맑음, 15도입니다
```

```python
from langgraph.prebuilt import create_react_agent
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)

# ReAct Agent 생성
agent = create_react_agent(llm, tools)

# 실행
result = agent.invoke({
    "messages": [("user", "서울 날씨는?")]
})
```

### 2. Multi-Agent 시스템

여러 Agent가 협업하는 패턴:

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict

class State(TypedDict):
    task: str
    research: str
    draft: str
    final: str

# Agent 1: 리서치 Agent
def research_agent(state: State) -> State:
    # 웹 검색 등으로 정보 수집
    research = f"[리서치] {state['task']}에 대한 정보..."
    return {"research": research}

# Agent 2: 작성 Agent
def writer_agent(state: State) -> State:
    # 리서치 결과로 초안 작성
    draft = f"[초안] {state['research']} 기반 작성..."
    return {"draft": draft}

# Agent 3: 편집 Agent
def editor_agent(state: State) -> State:
    # 초안 검토 및 최종 작성
    final = f"[최종] {state['draft']} 편집 완료"
    return {"final": final}

# 그래프 구성
workflow = StateGraph(State)
workflow.add_node("research", research_agent)
workflow.add_node("write", writer_agent)
workflow.add_node("edit", editor_agent)

workflow.set_entry_point("research")
workflow.add_edge("research", "write")
workflow.add_edge("write", "edit")
workflow.add_edge("edit", END)

app = workflow.compile()
```

### 3. Human-in-the-Loop

사람이 개입하여 Agent를 제어:

```python
from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.graph import StateGraph, END

# 체크포인트 설정 (상태 저장)
memory = SqliteSaver.from_conn_string(":memory:")

workflow = StateGraph(State)
# ... 노드 추가 ...

# 컴파일 시 체크포인터 설정
app = workflow.compile(checkpointer=memory)

# 실행 (중간에 멈출 수 있음)
config = {"configurable": {"thread_id": "1"}}

# 첫 단계 실행
result = app.invoke({"question": "..."}, config)

# 사용자가 결과 확인 후 계속 진행 여부 결정
user_approval = input("계속 진행? (y/n): ")

if user_approval == "y":
    # 이어서 실행
    result = app.invoke(None, config)
```

### 4. 루프와 재시도

실패 시 재시도하는 패턴:

```python
class State(TypedDict):
    question: str
    answer: str
    retry_count: int

def answer_question(state: State) -> State:
    try:
        # 답변 생성 시도
        answer = llm.invoke(state["question"]).content
        return {"answer": answer}
    except Exception as e:
        return {"retry_count": state["retry_count"] + 1}

def should_retry(state: State):
    if state["retry_count"] < 3 and not state.get("answer"):
        return "retry"
    elif state.get("answer"):
        return "success"
    else:
        return "failed"

workflow = StateGraph(State)
workflow.add_node("answer", answer_question)
workflow.set_entry_point("answer")

workflow.add_conditional_edges(
    "answer",
    should_retry,
    {
        "retry": "answer",  # 다시 시도
        "success": END,
        "failed": END
    }
)
```

## 실전 예제: RAG Agent

질문을 분석하고 필요시 RAG를 사용하는 완전한 Agent:

```python
from langgraph.graph import StateGraph, END
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_pinecone import PineconeVectorStore
from typing import TypedDict, Sequence
from langchain_core.messages import BaseMessage, HumanMessage, AIMessage

# 1. 상태 정의
class AgentState(TypedDict):
    messages: Sequence[BaseMessage]
    classification: str
    retrieved_docs: list

# 2. LLM 및 벡터 저장소 초기화
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
embeddings = OpenAIEmbeddings()
vectorstore = PineconeVectorStore(
    index_name="my-index",
    embedding=embeddings
)

# 3. 노드 함수들
def classify_node(state: AgentState):
    """질문 분류"""
    last_message = state["messages"][-1]

    prompt = f"""다음 질문이 외부 문서 검색이 필요한지 판단하세요.

- 기술 문서, 특정 지식이 필요 → "RAG"
- 일반 상식, 간단한 질문 → "DIRECT"

질문: {last_message.content}

"RAG" 또는 "DIRECT" 중 하나만:"""

    result = llm.invoke(prompt)
    classification = result.content.strip()

    return {"classification": classification}

def retrieve_node(state: AgentState):
    """문서 검색"""
    last_message = state["messages"][-1]

    # Pinecone에서 관련 문서 검색
    docs = vectorstore.similarity_search(
        last_message.content,
        k=3
    )

    return {"retrieved_docs": docs}

def generate_node(state: AgentState):
    """답변 생성"""
    last_message = state["messages"][-1]

    if state["classification"] == "RAG":
        # RAG 모드: 검색된 문서 활용
        context = "\n\n".join([doc.page_content for doc in state["retrieved_docs"]])

        prompt = f"""다음 문서를 참고하여 질문에 답하세요.

문서:
{context}

질문: {last_message.content}

답변:"""
    else:
        # Direct 모드: 일반 답변
        prompt = last_message.content

    result = llm.invoke(prompt)

    return {
        "messages": [AIMessage(content=result.content)]
    }

# 4. 그래프 구성
workflow = StateGraph(AgentState)

# 노드 추가
workflow.add_node("classify", classify_node)
workflow.add_node("retrieve", retrieve_node)
workflow.add_node("generate", generate_node)

# 시작점
workflow.set_entry_point("classify")

# 분류 후 조건부 분기
def route_after_classify(state: AgentState):
    if state["classification"] == "RAG":
        return "retrieve"
    else:
        return "generate"

workflow.add_conditional_edges(
    "classify",
    route_after_classify,
    {
        "retrieve": "retrieve",
        "generate": "generate"
    }
)

# RAG 경로
workflow.add_edge("retrieve", "generate")

# 종료
workflow.add_edge("generate", END)

# 5. 컴파일
app = workflow.compile()

# 6. 실행
def ask_agent(question: str):
    result = app.invoke({
        "messages": [HumanMessage(content=question)],
        "classification": "",
        "retrieved_docs": []
    })

    return result["messages"][-1].content

# 테스트
print(ask_agent("RAG란 무엇인가요?"))  # RAG 경로
print(ask_agent("안녕하세요"))  # Direct 경로
```

## 스트리밍 Agent

실시간으로 Agent의 진행 상황을 보여주는 방법:

```python
async def run_agent_streaming(question: str):
    async for event in app.astream_events(
        {"messages": [HumanMessage(content=question)]},
        version="v1"
    ):
        kind = event["event"]

        if kind == "on_chat_model_stream":
            # LLM 토큰 스트리밍
            content = event["data"]["chunk"].content
            if content:
                print(content, end="", flush=True)

        elif kind == "on_tool_start":
            # 도구 사용 시작
            print(f"\n[도구 사용] {event['name']}")

        elif kind == "on_tool_end":
            # 도구 사용 완료
            print(f"[완료] {event['data'].get('output')}")

# FastAPI에서 SSE로 스트리밍
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

app_fastapi = FastAPI()

@app_fastapi.post("/agent")
async def agent_endpoint(question: str):
    async def event_generator():
        async for event in app.astream_events(...):
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream"
    )
```

## Agent 평가

Agent의 성능을 측정하는 방법:

```python
# 테스트 케이스
test_cases = [
    {
        "question": "RAG란?",
        "expected_classification": "RAG",
        "expected_keywords": ["검색", "증강", "생성"]
    },
    {
        "question": "안녕",
        "expected_classification": "DIRECT",
        "expected_keywords": ["안녕"]
    }
]

# 평가
for case in test_cases:
    result = app.invoke({
        "messages": [HumanMessage(content=case["question"])],
        "classification": "",
        "retrieved_docs": []
    })

    # 분류 정확도
    correct_classification = result["classification"] == case["expected_classification"]

    # 키워드 포함 여부
    answer = result["messages"][-1].content
    keywords_found = all(kw in answer for kw in case["expected_keywords"])

    print(f"질문: {case['question']}")
    print(f"분류 정확: {correct_classification}")
    print(f"키워드 포함: {keywords_found}")
    print("---")
```

## Best Practices

1. **명확한 상태 정의**
   - TypedDict로 타입 안전성 확보
   - 필요한 필드만 포함

2. **작은 노드로 분리**
   - 각 노드는 하나의 책임만
   - 재사용 가능하게 설계

3. **에러 처리**
   - try-except로 안전하게 처리
   - 실패 시 재시도 로직

4. **로깅**
   - 각 단계마다 로그 남기기
   - 디버깅 용이

5. **체크포인트 활용**
   - 긴 작업은 체크포인트 저장
   - 재실행 가능하게 설계

## 다음 단계

LangGraph Agent를 마스터했다면:

1. **복잡한 워크플로우**: 멀티 Agent, 계층적 Agent
2. **도구 개발**: 커스텀 도구 작성 및 통합
3. **평가 시스템**: Agent 성능 측정 및 개선
4. **프로덕션 배포**: 스케일링, 모니터링, 비용 최적화
