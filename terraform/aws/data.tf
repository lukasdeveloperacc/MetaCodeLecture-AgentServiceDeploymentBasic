# ==============================================================================
# Data Sources (외부 정보 조회)
# ==============================================================================
#
# Data Source는 이미 존재하는 리소스나 정보를 조회할 때 사용합니다.
#
# 왜 Data Source를 사용하는가?
# - Secret 이름만 알면 ARN을 자동으로 조회
# - 하드코딩 방지 (더 유연하고 재사용 가능한 코드)
# - terraform.tfvars에 긴 ARN 대신 간단한 이름만 입력
#
# Section 3 비교:
# - Section 3: ARN 전체를 복사/붙여넣기 (긴 문자열, 오타 가능성)
# - Terraform: 이름만 입력 → ARN 자동 조회

# ------------------------------------------------------------------------------
# Secrets Manager Secrets (Secret 이름으로 ARN 자동 조회)
# ------------------------------------------------------------------------------

# OpenAI API Key Secret 정보 조회
data "aws_secretsmanager_secret" "openai" {
  name = var.openai_secret_name # 예: "dev/openai-api-key"
}

# Pinecone API Key Secret 정보 조회
data "aws_secretsmanager_secret" "pinecone" {
  name = var.pinecone_secret_name # 예: "dev/pinecone-api-key"
}

# ------------------------------------------------------------------------------
# 사용 예시
# ------------------------------------------------------------------------------
#
# IAM Policy에서:
#   Resource = [
#     data.aws_secretsmanager_secret.openai.arn,
#     data.aws_secretsmanager_secret.pinecone.arn
#   ]
#
# ECS Task Definition에서:
#   secrets = [{
#     name      = "OPENAI_API_KEY"
#     valueFrom = data.aws_secretsmanager_secret.openai.arn
#   }]
