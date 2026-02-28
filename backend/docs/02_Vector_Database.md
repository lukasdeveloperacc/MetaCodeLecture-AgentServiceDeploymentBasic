# Vector Database (벡터 데이터베이스)

## Vector Database란?

Vector Database는 **고차원 벡터를 효율적으로 저장하고 검색하는 데이터베이스**입니다. 일반 데이터베이스가 숫자, 문자열, 날짜 등을 저장한다면, Vector Database는 임베딩 벡터를 저장하고 유사도 검색을 수행합니다.

### 왜 필요한가?

1. **의미 기반 검색**
   - 키워드 매칭이 아닌 의미적 유사성 검색
   - "강아지"와 "개"를 동일한 의미로 인식

2. **대규모 벡터 처리**
   - 수백만~수십억 개의 벡터를 빠르게 검색
   - 일반 데이터베이스로는 불가능한 성능

3. **AI 애플리케이션 필수**
   - RAG, 추천 시스템, 이미지 검색 등
   - 임베딩 기반 모든 작업에 필요

## 벡터와 임베딩

### 임베딩이란?

임베딩(Embedding)은 **텍스트, 이미지, 오디오 등을 숫자 벡터로 변환**한 것입니다.

**예시**:
```python
text = "안녕하세요"
embedding = [0.23, -0.45, 0.67, 0.12, -0.89, ...]  # 1536차원
```

### 벡터의 특성

1. **고차원**
   - 일반적으로 384~3072차원
   - OpenAI text-embedding-3-small: 1536차원
   - OpenAI text-embedding-3-large: 3072차원

2. **의미적 유사성**
   - 유사한 의미의 텍스트는 유사한 벡터
   - 벡터 간 거리로 유사도 측정

**예시**:
```
"강아지" → [0.2, 0.5, 0.1, ...]
"개"     → [0.3, 0.6, 0.2, ...]  # 가까움
"자동차" → [0.8, -0.3, 0.9, ...] # 멀음
```

### 유사도 측정 방법

#### 1. Cosine Similarity (코사인 유사도)

가장 많이 사용되는 방법입니다.

```python
import numpy as np

def cosine_similarity(vec1, vec2):
    dot_product = np.dot(vec1, vec2)
    norm1 = np.linalg.norm(vec1)
    norm2 = np.linalg.norm(vec2)
    return dot_product / (norm1 * norm2)

# 값 범위: -1 ~ 1
# 1: 완전히 같음
# 0: 관련 없음
# -1: 완전히 반대
```

**특징**:
- 벡터의 방향만 고려 (크기 무시)
- 정규화된 벡터에 적합
- 대부분의 텍스트 임베딩에서 사용

#### 2. Euclidean Distance (유클리드 거리)

```python
def euclidean_distance(vec1, vec2):
    return np.linalg.norm(vec1 - vec2)

# 값 범위: 0 ~ 무한대
# 0: 완전히 같음
# 클수록: 더 다름
```

**특징**:
- 실제 거리 측정
- 이미지 임베딩에서 많이 사용

#### 3. Dot Product (내적)

```python
def dot_product(vec1, vec2):
    return np.dot(vec1, vec2)
```

**특징**:
- 가장 빠름
- 정규화된 벡터에서는 cosine과 동일

## 주요 Vector Database

### 1. Pinecone

**특징**:
- ✅ 완전 관리형 클라우드 서비스
- ✅ 설치/운영 불필요
- ✅ 자동 확장
- ✅ 빠른 성능
- ❌ 비용 (무료 플랜 제한적)

**사용법**:
```python
from pinecone import Pinecone
from langchain_pinecone import PineconeVectorStore
from langchain_openai import OpenAIEmbeddings

# 초기화
pc = Pinecone(api_key="your-api-key")

# 인덱스 생성 (콘솔에서 생성 권장)
# pc.create_index(
#     name="my-index",
#     dimension=1536,
#     metric="cosine"
# )

# LangChain과 연동
embeddings = OpenAIEmbeddings()
vectorstore = PineconeVectorStore(
    index_name="my-index",
    embedding=embeddings
)

# 문서 추가
vectorstore.add_texts(
    texts=["안녕하세요", "반갑습니다"],
    metadatas=[{"source": "greeting1"}, {"source": "greeting2"}]
)

# 검색
results = vectorstore.similarity_search("안녕", k=3)
```

**요금**:
- Starter (무료): 1개 인덱스, 100K 벡터
- Standard: $70/월 (1M 벡터)

**장점**:
- 운영 부담 없음
- 글로벌 분산 가능
- 높은 안정성

**단점**:
- 비용
- 벤더 종속성

### 2. Chroma

**특징**:
- ✅ 오픈소스
- ✅ 로컬 개발 최적
- ✅ 간단한 사용법
- ✅ 무료
- ❌ 대규모 운영 어려움

**사용법**:
```python
from langchain_chroma import Chroma
from langchain_openai import OpenAIEmbeddings

embeddings = OpenAIEmbeddings()

# 로컬 저장소 초기화
vectorstore = Chroma(
    collection_name="my_collection",
    embedding_function=embeddings,
    persist_directory="./chroma_db"  # 로컬 저장
)

# 문서 추가
vectorstore.add_texts(["안녕하세요", "반갑습니다"])

# 검색
results = vectorstore.similarity_search("안녕", k=3)

# 명시적 저장 (자동으로도 됨)
vectorstore.persist()
```

**장점**:
- 설치 간단
- 개발 환경에 최적
- 무료

**단점**:
- 대규모 확장 어려움
- 분산 환경 부적합

### 3. Weaviate

**특징**:
- ✅ 오픈소스
- ✅ GraphQL 지원
- ✅ 하이브리드 검색 (키워드 + 벡터)
- ✅ 클라우드/온프레미스 모두 지원

**사용법**:
```python
from langchain_weaviate import WeaviateVectorStore
import weaviate

# 클라이언트 초기화
client = weaviate.Client(
    url="http://localhost:8080"  # 또는 클라우드 URL
)

vectorstore = WeaviateVectorStore(
    client=client,
    index_name="MyIndex",
    text_key="text",
    embedding=embeddings
)
```

**장점**:
- 유연한 스키마
- GraphQL 쿼리
- 하이브리드 검색

**단점**:
- 설정 복잡
- 학습 곡선

### 4. Qdrant

**특징**:
- ✅ Rust 기반 고성능
- ✅ 오픈소스
- ✅ 필터링 강력
- ✅ 클라우드/로컬 모두 지원

**사용법**:
```python
from langchain_qdrant import QdrantVectorStore
from qdrant_client import QdrantClient

client = QdrantClient(url="http://localhost:6333")

vectorstore = QdrantVectorStore(
    client=client,
    collection_name="my_collection",
    embedding=embeddings
)
```

**장점**:
- 빠른 성능
- 강력한 필터링
- 로컬 개발 지원

### 5. Milvus

**특징**:
- ✅ 대규모 운영 환경 최적
- ✅ 오픈소스
- ✅ 높은 확장성
- ❌ 설정 복잡

**사용법**:
```python
from langchain_milvus import Milvus

vectorstore = Milvus(
    embedding_function=embeddings,
    connection_args={"host": "localhost", "port": "19530"},
    collection_name="my_collection"
)
```

**장점**:
- 엔터프라이즈급 성능
- 수십억 벡터 지원
- 활발한 커뮤니티

**단점**:
- 운영 복잡도
- 리소스 요구사항 높음

## Vector Database 선택 가이드

### 프로젝트 단계별 추천

| 단계 | 추천 | 이유 |
|------|------|------|
| 프로토타입 | Chroma | 빠른 시작, 로컬 개발 |
| MVP | Pinecone | 관리 부담 없음 |
| 중소 규모 | Qdrant | 성능과 비용 균형 |
| 대규모 | Milvus | 확장성, 커스터마이징 |

### 요구사항별 선택

**간단한 RAG 시스템**:
- Chroma (로컬)
- Pinecone (클라우드)

**하이브리드 검색 필요**:
- Weaviate
- Qdrant

**대규모 (수백만 벡터)**:
- Pinecone
- Milvus

**온프레미스 필수**:
- Qdrant
- Milvus
- Weaviate

**비용 최소화**:
- Chroma
- Qdrant (셀프 호스팅)

## 성능 최적화

### 1. 인덱스 타입 선택

**HNSW (Hierarchical Navigable Small World)**:
- 가장 많이 사용
- 빠른 검색 속도
- 메모리 사용량 높음

```python
# Pinecone에서 HNSW 사용 (기본값)
pc.create_index(
    name="my-index",
    dimension=1536,
    metric="cosine",
    spec=ServerlessSpec(cloud="aws", region="us-east-1")
)
```

**IVF (Inverted File Index)**:
- 메모리 효율적
- 대규모 데이터셋
- 검색 속도 약간 느림

### 2. 벡터 양자화 (Quantization)

벡터 크기를 줄여 메모리와 속도 개선:

```python
# Product Quantization
# 1536차원 → 384차원 (4배 압축)
# 정확도 약간 감소, 속도 향상
```

### 3. 배치 삽입

```python
# 나쁜 예: 하나씩 삽입
for text in texts:
    vectorstore.add_texts([text])

# 좋은 예: 배치 삽입
vectorstore.add_texts(texts, batch_size=100)
```

### 4. 메타데이터 필터링

불필요한 벡터 검색 방지:

```python
# 날짜, 카테고리 등으로 사전 필터링
results = vectorstore.similarity_search(
    query="AI",
    k=5,
    filter={
        "category": "technology",
        "date": {"$gte": "2024-01-01"}
    }
)
```

## 실전 예제: RAG 시스템 구축

### 1. Pinecone 기반 RAG

```python
import os
from pinecone import Pinecone
from langchain_pinecone import PineconeVectorStore
from langchain_openai import OpenAIEmbeddings, ChatOpenAI
from langchain.chains import RetrievalQA
from langchain_community.document_loaders import TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter

# 1. 환경 설정
os.environ["PINECONE_API_KEY"] = "your-api-key"
os.environ["OPENAI_API_KEY"] = "your-api-key"

# 2. 문서 로딩 및 분할
loader = TextLoader("data.txt")
docs = loader.load()

splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,
    chunk_overlap=200
)
chunks = splitter.split_documents(docs)

# 3. 임베딩 및 벡터 저장
embeddings = OpenAIEmbeddings(model="text-embedding-3-small")

vectorstore = PineconeVectorStore.from_documents(
    documents=chunks,
    embedding=embeddings,
    index_name="my-rag-index"
)

# 4. RAG 체인 구성
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)

qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    chain_type="stuff",
    retriever=vectorstore.as_retriever(
        search_type="similarity",
        search_kwargs={"k": 3}
    ),
    return_source_documents=True
)

# 5. 질의응답
result = qa_chain.invoke({"query": "Vector Database란?"})
print(result["result"])
print("\n출처:")
for doc in result["source_documents"]:
    print(f"- {doc.metadata.get('source', 'Unknown')}")
```

### 2. Chroma 기반 로컬 RAG

```python
from langchain_chroma import Chroma
from langchain_openai import OpenAIEmbeddings, ChatOpenAI
from langchain.chains import RetrievalQA

# 임베딩
embeddings = OpenAIEmbeddings()

# Chroma 초기화 (로컬 저장)
vectorstore = Chroma(
    collection_name="my_docs",
    embedding_function=embeddings,
    persist_directory="./chroma_data"
)

# 문서 추가
texts = [
    "Vector Database는 임베딩 벡터를 저장합니다.",
    "Pinecone은 클라우드 벡터 데이터베이스입니다.",
    "Chroma는 로컬 개발에 적합합니다."
]
vectorstore.add_texts(texts)

# RAG 구성
llm = ChatOpenAI(model="gpt-4o-mini")
qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    retriever=vectorstore.as_retriever(search_kwargs={"k": 2})
)

# 질의
answer = qa_chain.invoke({"query": "Pinecone이란?"})
print(answer["result"])
```

## 하이브리드 검색

키워드 검색과 벡터 검색을 결합하여 정확도 향상:

```python
from langchain.retrievers import EnsembleRetriever
from langchain_community.retrievers import BM25Retriever

# BM25 키워드 검색
bm25_retriever = BM25Retriever.from_documents(chunks)
bm25_retriever.k = 3

# 벡터 검색
vector_retriever = vectorstore.as_retriever(search_kwargs={"k": 3})

# 하이브리드 검색 (가중치 조정)
ensemble_retriever = EnsembleRetriever(
    retrievers=[bm25_retriever, vector_retriever],
    weights=[0.3, 0.7]  # 벡터 검색에 더 높은 가중치
)

# 사용
results = ensemble_retriever.get_relevant_documents("검색 쿼리")
```

## 모니터링과 디버깅

### 1. 검색 품질 측정

```python
# 검색 결과와 점수 확인
results_with_scores = vectorstore.similarity_search_with_score(
    query="Vector Database",
    k=5
)

for doc, score in results_with_scores:
    print(f"Score: {score:.4f}")
    print(f"Content: {doc.page_content[:100]}...")
    print("---")
```

### 2. 벡터 시각화

```python
import numpy as np
from sklearn.decomposition import PCA
import matplotlib.pyplot as plt

# 벡터 추출
vectors = [embeddings.embed_query(text) for text in texts]

# 차원 축소 (1536 → 2차원)
pca = PCA(n_components=2)
vectors_2d = pca.fit_transform(vectors)

# 시각화
plt.figure(figsize=(10, 8))
plt.scatter(vectors_2d[:, 0], vectors_2d[:, 1])
for i, text in enumerate(texts):
    plt.annotate(text[:20], (vectors_2d[i, 0], vectors_2d[i, 1]))
plt.title("Vector Visualization (PCA)")
plt.show()
```

## Best Practices

1. **적절한 청크 크기**
   - 500-1500자 권장
   - 문서 타입에 따라 조정

2. **메타데이터 활용**
   - 출처, 날짜, 카테고리 저장
   - 필터링으로 검색 정확도 향상

3. **배치 처리**
   - 대량 문서는 배치로 처리
   - 네트워크 오버헤드 감소

4. **재랭킹**
   - 검색 결과를 LLM으로 재평가
   - 최종 정확도 향상

5. **정기 업데이트**
   - 오래된 문서 삭제
   - 새 문서 추가
   - 인덱스 최적화

## 비용 최적화

### Pinecone 비용 절감

1. **인덱스 통합**
   - 여러 작은 인덱스 대신 하나의 큰 인덱스 + 메타데이터 필터링

2. **벡터 차원 축소**
   - text-embedding-3-large (3072) → text-embedding-3-small (1536)
   - 비용 절반, 정확도 약간 감소

3. **불필요한 벡터 삭제**
   - 주기적으로 사용하지 않는 문서 삭제

### 오픈소스 DB 비용

1. **클라우드 비용**
   - 작은 인스턴스로 시작 (t3.small)
   - 필요시 수직/수평 확장

2. **스토리지 최적화**
   - 압축 활성화
   - 불필요한 메타데이터 제거

## 다음 단계

Vector Database를 마스터했다면:

1. **LangGraph Agent**: 복잡한 워크플로우 구성
2. **평가 메트릭**: 검색 품질 측정 (Recall, Precision, MRR)
3. **프로덕션 배포**: 모니터링, 로깅, 에러 처리
4. **고급 기법**: Reranking, Query Expansion, Hypothetical Document Embeddings
