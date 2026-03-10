#!/bin/bash

# ECS Task Execution Trust Policy
cat > aws/iam/ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# ECS Task Trust Policy
cat > aws/iam/ecs-task-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Role 생성
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://aws/iam/ecs-task-execution-trust-policy.json \
  --description "ECS Task Execution Role" \
  --region ap-northeast-2

# 기본 권한 연결 (ECR, CloudWatch Logs 접근)
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Secrets Manager 접근 권한 추가
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Role 생성
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file:///tmp/ecs-task-trust-policy.json \
  --description "ECS Task Role for application AWS API access" \
  --region ap-northeast-2

# CloudWatch Logs 접근 권한
aws iam attach-role-policy \
  --role-name ecsTaskRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# 생성된 Role 확인
aws iam get-role --role-name ecsTaskExecutionRole
aws iam get-role --role-name ecsTaskRole

# 연결된 정책 확인
aws iam list-attached-role-policies --role-name ecsTaskExecutionRole
aws iam list-attached-role-policies --role-name ecsTaskRole

# Backend Log Group 생성
aws logs create-log-group \
  --log-group-name /ecs/backend \
  --region ap-northeast-2

# Frontend Log Group 생성
aws logs create-log-group \
  --log-group-name /ecs/frontend \
  --region ap-northeast-2

# Log Group 확인
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/backend \
  --region ap-northeast-2

# Backend 로그 7일 보관
aws logs put-retention-policy \
  --log-group-name /ecs/backend \
  --retention-in-days 7 \
  --region ap-northeast-2

# Frontend 로그 7일 보관
aws logs put-retention-policy \
  --log-group-name /ecs/frontend \
  --retention-in-days 7 \
  --region ap-northeast-2

# Task Definition 파일 수정 ({ACCOUNT_ID} 교체)
sed -i "s/{ACCOUNT_ID}/$(aws sts get-caller-identity --query Account --output text)/g" aws/ecs/task_definition/task-definition-backend.json

# Task Definition 등록
aws ecs register-task-definition \
  --cli-input-json file://aws/ecs/task_definition/task-definition-backend.json

aws ecs register-task-definition \
  --cli-input-json file://aws/ecs/task_definition/task-definition-frontend.json

# ECS Service 강제 재배포
aws ecs update-service \
  --cluster agent-cluster-dev \
  --service frontend-service \
  --force-new-deployment \
  --region ap-northeast-2

aws ecs update-service \
  --cluster agent-cluster-dev \
  --service backend-service \
  --force-new-deployment \
  --region ap-northeast-2

# CloudWatch Logs로 이동
aws logs tail /ecs/backend --follow

# CPU 사용률 80% 초과 시 알람
aws cloudwatch put-metric-alarm \
  --alarm-name backend-high-cpu \
  --alarm-description "Backend CPU > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold

# ALB DNS 확인
aws elbv2 describe-load-balancers \
  --names agent-service-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ap-northeast-2