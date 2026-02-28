# RAG (Retrieval-Augmented Generation) 기초

## RAG란 무엇인가?

RAG(Retrieval-Augmented Generation)는 **검색 증강 생성**을 의미하며, 대규모 언어 모델(LLM)의 한계를 극복하기 위해 외부 지식을 검색하여 응답 생성에 활용하는 기술입니다.

### 왜 RAG가 필요한가?

1. **지식 업데이트 문제**
   - LLM은 학습 데이터의 시점까지만 지식을 가지고 있음
   - 최신 정보나 실시간 데이터에 대한 응답 불가능
   - RAG를 통해 최신 문서를 검색하여 해결

2. **환각(Hallucination) 문제**
   - LLM은 학습되지 않은 내용에 대해 그럴듯한 거짓 정보를 생성할 수 있음
   - RAG는 실제 문서를 기반으로 답변하여 정확도 향상

3. **도메인 특화 지식**
   - 일반 LLM은 특정 회사나 조직의 내부 지식을 모름
   - RAG를 통해 사내 문서, 매뉴얼 등을 활용 가능

4. **투명성과 검증 가능성**
   - RAG는 응답의 근거가 되는 원본 문서를 제시할 수 있음
   - 사용자가 정보의 출처를 확인하고 신뢰할 수 있음

## RAG 시스템의 구성 요소

### 1. 문서 로더 (Document Loader)

다양한 형식의 문서를 읽어오는 컴포넌트입니다.

**지원 형식**:
- PDF: 논문, 보고서, 계약서
- Markdown: 기술 문서, 위키
- HTML: 웹 페이지, 블로그
- DOCX: 워드 문서
- CSV/Excel: 데이터 시트

**예시 코드**:
```python
from langchain_community.document_loaders import PyPDFLoader, TextLoader

# PDF 로딩
pdf_loader = PyPDFLoader("document.pdf")
pdf_docs = pdf_loader.load()

# 텍스트 파일 로딩
text_loader = TextLoader("document.txt")
text_docs = text_loader.load()
```

### 2. 텍스트 분할기 (Text Splitter)

긴 문서를 작은 청크(chunk)로 나누는 컴포넌트입니다.

**왜 분할이 필요한가?**
- LLM의 컨텍스트 길이 제한 (예: GPT-4는 8K~32K 토큰)
- 검색 정확도 향상 (작은 단위가 더 정확한 매칭)
- 비용 최적화 (필요한 부분만 LLM에 전달)

**분할 전략**:

1. **고정 크기 분할 (Fixed Size)**
   ```python
   from langchain.text_splitter import CharacterTextSplitter

   splitter = CharacterTextSplitter(
       chunk_size=1000,      # 청크 크기
       chunk_overlap=200,    # 중복 크기
       separator="\n\n"      # 구분자
   )
   chunks = splitter.split_documents(docs)
   ```

2. **재귀적 분할 (Recursive)**
   ```python
   from langchain.text_splitter import RecursiveCharacterTextSplitter

   splitter = RecursiveCharacterTextSplitter(
       chunk_size=1000,
       chunk_overlap=200,
       separators=["\n\n", "\n", " ", ""]  # 우선순위
   )
   chunks = splitter.split_documents(docs)
   ```

3. **의미 기반 분할 (Semantic)**
   - 문장이나 단락의 의미를 고려
   - Embedding 유사도 기반 분할

**Best Practices**:
- chunk_size: 500-1500자 권장
- chunk_overlap: chunk_size의 10-20%
- 문서 타입에 따라 적절한 separator 선택

### 3. 임베딩 모델 (Embedding Model)

텍스트를 벡터로 변환하는 모델입니다.

**임베딩이란?**
- 텍스트를 숫자 벡터로 표현 (예: [0.23, -0.45, 0.67, ...])
- 의미적으로 유사한 텍스트는 유사한 벡터를 가짐
- 벡터 간 거리로 유사도 측정 가능

**주요 모델**:

1. **OpenAI Embeddings**
   ```python
   from langchain_openai import OpenAIEmbeddings

   embeddings = OpenAIEmbeddings(
       model="text-embedding-3-small"  # 또는 text-embedding-3-large
   )

   # 단일 텍스트 임베딩
   vector = embeddings.embed_query("안녕하세요")
   print(len(vector))  # 1536 차원
   ```

2. **HuggingFace Embeddings**
   ```python
   from langchain_huggingface import HuggingFaceEmbeddings

   embeddings = HuggingFaceEmbeddings(
       model_name="sentence-transformers/all-MiniLM-L6-v2"
   )
   ```

**모델 선택 기준**:
- 정확도: text-embedding-3-large > text-embedding-3-small
- 속도: text-embedding-3-small이 더 빠름
- 비용: small 모델이 저렴
- 언어: 다국어 지원 여부 확인

### 4. 벡터 데이터베이스 (Vector Database)

임베딩 벡터를 저장하고 검색하는 데이터베이스입니다.

**주요 제품**:
- **Pinecone**: 클라우드 매니지드, 확장성 우수
- **Chroma**: 오픈소스, 로컬 개발 적합
- **Weaviate**: 오픈소스, GraphQL 지원
- **Qdrant**: 오픈소스, Rust 기반 고성능
- **Milvus**: 대규모 운영 환경

**Pinecone 예시**:
```python
from langchain_pinecone import PineconeVectorStore
from langchain_openai import OpenAIEmbeddings

embeddings = OpenAIEmbeddings()

# 벡터 저장소 초기화
vectorstore = PineconeVectorStore(
    index_name="my-index",
    embedding=embeddings
)

# 문서 추가
vectorstore.add_documents(chunks)

# 유사도 검색
results = vectorstore.similarity_search(
    query="RAG란 무엇인가?",
    k=3  # 상위 3개 결과
)
```

### 5. 검색기 (Retriever)

벡터 데이터베이스에서 관련 문서를 검색하는 컴포넌트입니다.

**검색 방법**:

1. **유사도 검색 (Similarity Search)**
   ```python
   retriever = vectorstore.as_retriever(
       search_type="similarity",
       search_kwargs={"k": 5}
   )
   ```

2. **MMR (Maximum Marginal Relevance)**
   - 관련성과 다양성을 모두 고려
   ```python
   retriever = vectorstore.as_retriever(
       search_type="mmr",
       search_kwargs={
           "k": 5,
           "fetch_k": 20,
           "lambda_mult": 0.5
       }
   )
   ```

3. **유사도 점수 임계값**
   ```python
   retriever = vectorstore.as_retriever(
       search_type="similarity_score_threshold",
       search_kwargs={
           "score_threshold": 0.8,
           "k": 5
       }
   )
   ```

### 6. LLM (Large Language Model)

검색된 문서를 기반으로 최종 답변을 생성하는 모델입니다.

**주요 모델**:
- GPT-4, GPT-4o, GPT-4o-mini (OpenAI)
- Claude 3 (Anthropic)
- Gemini Pro (Google)

**예시**:
```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="gpt-4o-mini",
    temperature=0.7,
    max_tokens=1000
)
```

### 7. 프롬프트 템플릿 (Prompt Template)

검색된 문서와 질문을 LLM에 전달하기 위한 형식입니다.

```python
from langchain.prompts import PromptTemplate

template = """다음 문서를 참고하여 질문에 답하세요.

문서:
{context}

질문: {question}

답변:"""

prompt = PromptTemplate(
    template=template,
    input_variables=["context", "question"]
)
```

## RAG 파이프라인 전체 흐름

### 1. 인덱싱 단계 (Offline)

```
문서 수집 → 로딩 → 분할 → 임베딩 → 벡터 DB 저장
```

```python
# 1. 문서 로딩
from langchain_community.document_loaders import TextLoader
loader = TextLoader("data.txt")
docs = loader.load()

# 2. 분할
from langchain.text_splitter import RecursiveCharacterTextSplitter
splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
chunks = splitter.split_documents(docs)

# 3. 임베딩 & 저장
from langchain_openai import OpenAIEmbeddings
from langchain_pinecone import PineconeVectorStore

embeddings = OpenAIEmbeddings()
vectorstore = PineconeVectorStore.from_documents(
    documents=chunks,
    embedding=embeddings,
    index_name="my-index"
)
```

### 2. 검색 단계 (Online)

```
사용자 질문 → 임베딩 → 벡터 검색 → 관련 문서 반환
```

```python
# 질문 임베딩 & 검색
results = vectorstore.similarity_search(
    query="RAG의 장점은?",
    k=3
)
```

### 3. 생성 단계 (Online)

```
질문 + 검색된 문서 → 프롬프트 구성 → LLM 호출 → 답변 생성
```

```python
from langchain_openai import ChatOpenAI
from langchain.chains import RetrievalQA

llm = ChatOpenAI(model="gpt-4o-mini")

qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    chain_type="stuff",
    retriever=vectorstore.as_retriever(search_kwargs={"k": 3})
)

answer = qa_chain.invoke({"query": "RAG의 장점은?"})
print(answer["result"])
```

## RAG의 장점

1. **정확한 정보 제공**
   - 실제 문서 기반 답변으로 환각 감소
   - 근거 있는 정보 제공

2. **최신 정보 활용**
   - LLM 재학습 없이 최신 문서 추가 가능
   - 실시간 정보 업데이트

3. **도메인 특화**
   - 기업 내부 문서, 매뉴얼 활용
   - 전문 분야 지식 제공

4. **비용 효율성**
   - LLM 재학습 불필요
   - 필요한 정보만 컨텍스트로 전달

5. **투명성**
   - 답변의 출처 제공
   - 사용자가 정보 검증 가능

## RAG의 한계와 도전 과제

1. **검색 품질 의존성**
   - 관련 문서를 찾지 못하면 정확한 답변 불가
   - 임베딩 모델의 성능이 중요

2. **청크 크기 최적화**
   - 너무 작으면 맥락 손실
   - 너무 크면 노이즈 증가

3. **비용**
   - 임베딩 생성 비용
   - 벡터 DB 운영 비용
   - LLM 호출 비용

4. **지연 시간**
   - 검색 + 생성 과정으로 응답 시간 증가
   - 최적화 필요

## RAG 활용 사례

1. **고객 지원 챗봇**
   - FAQ, 매뉴얼 기반 자동 응답
   - 제품 문서 검색

2. **기술 문서 Q&A**
   - 개발자 문서 검색
   - API 레퍼런스 질의응답

3. **법률/의료 상담**
   - 판례, 의학 논문 기반 답변
   - 전문 지식 제공

4. **연구 보조**
   - 논문 요약 및 분석
   - 관련 연구 검색

5. **사내 지식 관리**
   - 사내 위키, 문서 검색
   - 온보딩 자동화

## 실전 팁

### 1. 청크 크기 실험

```python
# 다양한 크기 테스트
for chunk_size in [500, 1000, 1500, 2000]:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=int(chunk_size * 0.1)
    )
    # 검색 품질 평가
```

### 2. 하이브리드 검색

```python
# 키워드 검색 + 벡터 검색 결합
from langchain.retrievers import EnsembleRetriever
from langchain_community.retrievers import BM25Retriever

# BM25 키워드 검색
bm25_retriever = BM25Retriever.from_documents(chunks)

# 벡터 검색
vector_retriever = vectorstore.as_retriever()

# 결합
ensemble_retriever = EnsembleRetriever(
    retrievers=[bm25_retriever, vector_retriever],
    weights=[0.5, 0.5]
)
```

### 3. 재랭킹 (Reranking)

```python
from langchain.retrievers import ContextualCompressionRetriever
from langchain.retrievers.document_compressors import LLMChainExtractor

# LLM으로 관련성 재평가
compressor = LLMChainExtractor.from_llm(llm)
compression_retriever = ContextualCompressionRetriever(
    base_compressor=compressor,
    base_retriever=vector_retriever
)
```

### 4. 메타데이터 필터링

```python
# 날짜, 카테고리 등으로 필터링
results = vectorstore.similarity_search(
    query="RAG",
    k=5,
    filter={"category": "AI", "date": {"$gte": "2024-01-01"}}
)
```

## 다음 단계

RAG 시스템을 구축했다면, 다음 주제를 학습하세요:

1. **Vector Database 심화**: Pinecone, Chroma 등 벡터 DB 운영
2. **LangGraph Agent**: RAG + Agent 결합
3. **평가 지표**: RAG 성능 측정 및 개선
4. **프로덕션 배포**: 확장성, 모니터링, 비용 최적화
