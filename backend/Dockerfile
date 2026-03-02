# Base Image
FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Working Directory
WORKDIR /app

# 의존성 파일 복사
COPY pyproject.toml uv.lock ./

# uv 설치 // .venv/
RUN pip install uv && uv sync

# 나머지 소스코드 복사
# <local path> <container path>
COPY . . 

# 포트 노출
EXPOSE 8000

# 컨테니어 시작 시 실행할 명령어
CMD ["uv", "run", "uvicorn", "app:app", "--host", "0.0.0.0", "--reload", "--port", "8000"]