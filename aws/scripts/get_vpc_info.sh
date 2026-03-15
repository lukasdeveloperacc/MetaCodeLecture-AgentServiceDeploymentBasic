#!/bin/bash

# AWS VPC 정보 자동 확인 스크립트
# Section 5 Terraform 실습을 위한 VPC/Subnet 정보 수집

set -e

echo "🔍 AWS 기본 VPC 정보를 확인합니다..."
echo ""

# AWS CLI 설치 확인
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI가 설치되어 있지 않습니다."
    echo "설치: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# AWS 자격증명 확인
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS 자격증명이 설정되어 있지 않습니다."
    echo "실행: aws configure"
    exit 1
fi

# 리전 확인
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    REGION="ap-northeast-2"
    echo "⚠️  리전이 설정되지 않아 기본값(ap-northeast-2)을 사용합니다."
fi

echo "📍 리전: $REGION"
echo ""

# 1. 기본 VPC ID 확인
echo "1️⃣  기본 VPC 확인 중..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --region $REGION 2>/dev/null)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "❌ 기본 VPC를 찾을 수 없습니다."
    echo "AWS Console에서 VPC를 생성하거나, 다른 VPC를 사용하세요."
    exit 1
fi

echo "✅ VPC ID: $VPC_ID"
echo ""

# 2. Public Subnets 확인 (최소 2개 필요)
echo "2️⃣  Public Subnet 확인 중 (ALB는 최소 2개 AZ 필요)..."
SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
    --output text \
    --region $REGION)

if [ -z "$SUBNETS" ]; then
    echo "⚠️  Public Subnet이 없습니다. 기본 VPC의 모든 Subnet을 표시합니다."
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
        --output text \
        --region $REGION)
fi

echo "$SUBNETS" | awk '{printf "  - %s (%s, %s)\n", $1, $2, $3}'
echo ""

# Subnet ID 배열 생성
SUBNET_IDS=($(echo "$SUBNETS" | awk '{print $1}'))
SUBNET_COUNT=${#SUBNET_IDS[@]}

if [ $SUBNET_COUNT -lt 2 ]; then
    echo "❌ ALB는 최소 2개의 서로 다른 AZ에 있는 Subnet이 필요합니다."
    echo "현재 Subnet 수: $SUBNET_COUNT"
    exit 1
fi

echo "✅ Subnet 수: $SUBNET_COUNT (충분함)"
echo ""

# 3. terraform.tfvars 생성
echo "3️⃣  terraform.tfvars 파일 생성 중..."

# terraform/aws 디렉토리 생성
TERRAFORM_DIR="$(cd "$(dirname "$0")/../.." && pwd)/terraform/aws"
mkdir -p "$TERRAFORM_DIR"

# terraform.tfvars 파일 생성
TFVARS_FILE="$TERRAFORM_DIR/terraform.tfvars"

cat > "$TFVARS_FILE" << EOF
# AWS 리전
aws_region = "$REGION"

# 프로젝트 정보
project_name = "agent-service"
environment  = "tf"  # 리소스 이름: backend-tf, frontend-tf, agent-cluster-tf

# VPC 정보 (기본 VPC 사용)
vpc_id = "$VPC_ID"

# Public Subnet IDs (최소 2개의 AZ)
public_subnet_ids = ["${SUBNET_IDS[0]}", "${SUBNET_IDS[1]}"]

# Secrets Manager 시크릿 이름 (Section 3에서 생성한 것)
# Terraform이 자동으로 ARN을 조회하므로 이름만 확인하면 됩니다
openai_secret_name   = "dev/openai-api-key"
pinecone_secret_name = "dev/pinecone-api-key"

# Task 설정 (필요 시 수정)
backend_cpu    = "512"   # 0.5 vCPU
backend_memory = "1024"  # 1 GB

frontend_cpu    = "256"  # 0.25 vCPU
frontend_memory = "512"  # 512 MB

# Service 설정
backend_desired_count  = 2
frontend_desired_count = 2
EOF

echo "✅ 생성 완료: $TFVARS_FILE"
echo ""

# 4. Secret 이름 확인 방법 안내
echo "4️⃣  다음 단계:"
echo ""
echo "  1. (선택) Secrets Manager에서 Secret 이름 확인:"
echo "     aws secretsmanager list-secrets --region $REGION --query 'SecretList[*].Name' --output table"
echo ""
echo "  2. terraform.tfvars 파일 확인:"
echo "     vi $TFVARS_FILE"
echo ""
echo "  3. Secret 이름이 Section 3와 다르다면 수정 (기본값: dev/openai-api-key, dev/pinecone-api-key)"
echo ""
echo "  4. Terraform 실행:"
echo "     cd $TERRAFORM_DIR"
echo "     terraform init"
echo "     terraform plan"
echo "     terraform apply"
echo ""

echo "✅ 모든 VPC 정보 확인 완료!"
