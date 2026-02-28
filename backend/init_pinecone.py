"""
Pinecone 초기화 스크립트
AI 서비스 기술 문서를 Pinecone에 임베딩하여 저장
"""

import os
import glob
from dotenv import load_dotenv

from langchain_openai import OpenAIEmbeddings
from langchain_pinecone import PineconeVectorStore
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.documents import Document
from pinecone import Pinecone, ServerlessSpec

# 환경변수 로드
load_dotenv()


def load_documents_from_markdown(docs_dir: str = "./docs") -> list[Document]:
    """
    Markdown 문서 로드

    Args:
        docs_dir: 문서 디렉토리 경로

    Returns:
        Document 객체 리스트
    """
    documents = []

    # docs 디렉토리의 모든 .md 파일 읽기
    md_files = glob.glob(os.path.join(docs_dir, "*.md"))

    print(f"Found {len(md_files)} markdown files in {docs_dir}")

    for file_path in md_files:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()

            # 파일명에서 메타데이터 추출
            filename = os.path.basename(file_path)

            doc = Document(
                page_content=content,
                metadata={
                    "source": filename,
                    "file_path": file_path
                }
            )

            documents.append(doc)
            print(f"✓ Loaded: {filename} ({len(content)} characters)")

        except Exception as e:
            print(f"✗ Failed to load {file_path}: {e}")

    return documents


def split_documents(documents: list[Document], chunk_size: int = 1000, chunk_overlap: int = 200) -> list[Document]:
    """
    문서를 청크로 분할

    Args:
        documents: 원본 문서 리스트
        chunk_size: 청크 크기 (토큰 단위)
        chunk_overlap: 청크 간 겹치는 크기

    Returns:
        분할된 Document 리스트
    """
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len,
        separators=["\n\n", "\n", " ", ""]
    )

    splits = text_splitter.split_documents(documents)

    print(f"\n✓ Split {len(documents)} documents into {len(splits)} chunks")

    return splits


def init_pinecone():
    """Pinecone에 문서 임베딩 및 저장 (클라우드 매니지드)"""

    print("=" * 60)
    print("Pinecone 초기화 시작 (클라우드 매니지드)")
    print("=" * 60)

    # 1. API 키 확인
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        print("✗ Error: OPENAI_API_KEY not found in environment")
        print("  Please create .env file with OPENAI_API_KEY")
        return False

    print(f"✓ OpenAI API Key: {api_key[:7]}***")

    pinecone_api_key = os.getenv("PINECONE_API_KEY")
    if not pinecone_api_key:
        print("✗ Error: PINECONE_API_KEY not found in environment")
        print("  Please create .env file with PINECONE_API_KEY")
        return False

    print(f"✓ Pinecone API Key: {pinecone_api_key[:7]}***")

    index_name = os.getenv("PINECONE_INDEX_NAME", "ai-service-docs")
    print(f"✓ Pinecone Index Name: {index_name}")

    # 2. Pinecone 인덱스 확인 및 생성
    pc = Pinecone(api_key=pinecone_api_key)

    existing_indexes = [idx.name for idx in pc.list_indexes()]
    if index_name not in existing_indexes:
        print(f"\n✓ Creating Pinecone index '{index_name}'...")
        pc.create_index(
            name=index_name,
            dimension=1536,
            metric="cosine",
            spec=ServerlessSpec(cloud="aws", region="us-east-1")
        )
        print(f"✓ Index '{index_name}' created successfully")
    else:
        print(f"\n✓ Index '{index_name}' already exists")

    # 3. 문서 로드
    documents = load_documents_from_markdown("./docs")

    if not documents:
        print("✗ No documents found in ./docs directory")
        return False

    # 4. 문서 분할
    chunks = split_documents(documents)

    # 5. Embeddings 모델 초기화
    print("\n✓ Initializing OpenAI Embeddings...")
    embeddings = OpenAIEmbeddings(
        model=os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
    )

    # 6. Pinecone에 저장
    print(f"\n✓ Storing documents in Pinecone index '{index_name}'...")

    try:
        vectorstore = PineconeVectorStore.from_documents(
            documents=chunks,
            embedding=embeddings,
            index_name=index_name
        )

        print(f"✓ Successfully stored {len(chunks)} chunks in Pinecone")

    except Exception as e:
        print(f"✗ Failed to create vectorstore: {e}")
        return False

    # 7. 검증 테스트
    print("\n" + "=" * 60)
    print("검증 테스트")
    print("=" * 60)

    test_query = "RAG란 무엇인가요?"
    print(f"\nTest Query: {test_query}")

    results = vectorstore.similarity_search(test_query, k=2)

    print(f"\n✓ Retrieved {len(results)} documents:")
    for i, doc in enumerate(results, 1):
        print(f"\n[{i}] Source: {doc.metadata.get('source', 'Unknown')}")
        print(f"    Content: {doc.page_content[:150]}...")

    print("\n" + "=" * 60)
    print("Pinecone 초기화 완료!")
    print("=" * 60)

    return True


if __name__ == "__main__":
    success = init_pinecone()

    if success:
        print("\n✓ Pinecone is ready for RAG queries")
    else:
        print("\n✗ Pinecone initialization failed")
        exit(1)
