# ==============================================================================
# Network Resources: Security Groups, ALB, Target Groups
# ==============================================================================
#
# 🎯 왜 필요한가?
# Section 3에서는 AWS Console에서 클릭으로 ALB, Security Groups를 만들었습니다.
# Terraform으로 관리하면:
# - 네트워크 구성을 코드로 명확히 문서화
# - 보안 규칙 변경 시 Git으로 변경 이력 추적
# - 여러 환경(dev/staging/prod)에 동일한 구성 재현 가능
#
# Section 3 비교:
# - Section 3: AWS Console > EC2 > Security Groups > Create (10단계 클릭)
# - Terraform: resource "aws_security_group" { ... } (10줄 코드)

# ==============================================================================
# Security Groups
# ==============================================================================

# ------------------------------------------------------------------------------
# Frontend ALB Security Group
# ------------------------------------------------------------------------------
# 인터넷에서 Frontend ALB로의 HTTP/HTTPS 트래픽 허용

resource "aws_security_group" "frontend_alb" {
  name        = "frontend-alb-sg-${var.environment}"
  description = "Security group for Frontend ALB - Allow HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  # Inbound: 인터넷에서 HTTP 80 포트 허용
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 모든 IP 허용
  }

  # Inbound: 인터넷에서 HTTPS 443 포트 허용 (선택사항)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: 모든 아웃바운드 트래픽 허용
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-alb-sg-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Backend ALB Security Group
# ------------------------------------------------------------------------------
# 인터넷에서 Backend ALB로의 HTTP/HTTPS 트래픽 허용

resource "aws_security_group" "backend_alb" {
  name        = "backend-alb-sg-${var.environment}"
  description = "Security group for Backend ALB - Allow HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  # Inbound: 인터넷에서 HTTP 80 포트 허용
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound: 인터넷에서 HTTPS 443 포트 허용 (선택사항)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: 모든 아웃바운드 트래픽 허용
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-alb-sg-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Backend Security Group
# ------------------------------------------------------------------------------
# Backend ALB에서 Backend 컨테이너(8000 포트)로의 트래픽만 허용

resource "aws_security_group" "backend" {
  name        = "backend-sg-${var.environment}"
  description = "Security group for backend ECS tasks - Allow traffic from Backend ALB only"
  vpc_id      = var.vpc_id

  # Inbound: Backend ALB Security Group에서만 8000 포트 허용
  ingress {
    description     = "Backend port from Backend ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_alb.id] # Backend ALB SG만 허용
  }

  # Outbound: 모든 아웃바운드 트래픽 허용 (외부 API 호출 등)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Frontend Security Group
# ------------------------------------------------------------------------------
# Frontend ALB에서 Frontend 컨테이너(80 포트)로의 트래픽만 허용

resource "aws_security_group" "frontend" {
  name        = "frontend-sg-${var.environment}"
  description = "Security group for frontend ECS tasks - Allow traffic from Frontend ALB only"
  vpc_id      = var.vpc_id

  # Inbound: Frontend ALB Security Group에서만 80 포트 허용
  ingress {
    description     = "Frontend port from Frontend ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_alb.id] # Frontend ALB SG만 허용
  }

  # Outbound: 모든 아웃바운드 트래픽 허용
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-sg-${var.environment}"
  }
}

# ==============================================================================
# Application Load Balancers (ALB)
# ==============================================================================
#
# Section 3에서 배운 Dual ALB 아키텍처를 구현합니다.
# - Frontend ALB: Frontend 서비스 전용
# - Backend ALB: Backend 서비스 전용
#
# 장점:
# - 독립적인 서비스 관리
# - 명확한 서비스 분리
# - 보안 그룹 세밀 제어
# - 장애 격리

# ------------------------------------------------------------------------------
# Frontend ALB
# ------------------------------------------------------------------------------

resource "aws_lb" "frontend" {
  name               = "frontend-alb-${var.environment}"
  internal           = false # 인터넷 연결 (internet-facing)
  load_balancer_type = "application"
  security_groups    = [aws_security_group.frontend_alb.id]
  subnets            = var.public_subnet_ids # 최소 2개 AZ

  enable_deletion_protection = false # 삭제 보호 비활성화 (학습용)

  tags = {
    Name = "frontend-alb-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Backend ALB
# ------------------------------------------------------------------------------

resource "aws_lb" "backend" {
  name               = "backend-alb-${var.environment}"
  internal           = false # 인터넷 연결 (internet-facing)
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_alb.id]
  subnets            = var.public_subnet_ids # 최소 2개 AZ

  enable_deletion_protection = false # 삭제 보호 비활성화 (학습용)

  tags = {
    Name = "backend-alb-${var.environment}"
  }
}

# ==============================================================================
# Target Groups
# ==============================================================================
#
# Target Group은 ALB가 트래픽을 전달할 대상(ECS Task)을 그룹화합니다.

# ------------------------------------------------------------------------------
# Backend Target Group
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "backend" {
  name        = "backend-tg-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate는 IP 타입 사용

  # Health Check 설정
  health_check {
    enabled             = true
    healthy_threshold   = 2         # 2번 성공 시 정상
    unhealthy_threshold = 3         # 3번 실패 시 비정상
    timeout             = 5         # 5초 타임아웃
    interval            = 30        # 30초마다 체크
    path                = "/health" # Backend의 /health 엔드포인트
    matcher             = "200"     # HTTP 200 응답 기대
  }

  # Deregistration Delay: Task 종료 시 연결 드레인 시간
  deregistration_delay = 30

  tags = {
    Name = "backend-tg-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# Frontend Target Group
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/" # Frontend의 루트 경로
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "frontend-tg-${var.environment}"
  }
}

# ==============================================================================
# ALB Listeners
# ==============================================================================
#
# Dual ALB 아키텍처에서는 각 ALB마다 Listener가 있습니다.
# - Frontend Listener: Frontend ALB → Frontend Target Group
# - Backend Listener: Backend ALB → Backend Target Group
#
# 경로 기반 라우팅이 필요 없어 Listener Rule이 없습니다.

# ------------------------------------------------------------------------------
# Frontend ALB HTTP Listener (Port 80)
# ------------------------------------------------------------------------------

resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = "80"
  protocol          = "HTTP"

  # 모든 요청을 Frontend Target Group으로 전달
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ------------------------------------------------------------------------------
# Backend ALB HTTP Listener (Port 80)
# ------------------------------------------------------------------------------

resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = "80"
  protocol          = "HTTP"

  # 모든 요청을 Backend Target Group으로 전달
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# HTTPS Listener 추가 (선택사항, SSL 인증서 필요)
# resource "aws_lb_listener" "frontend_https" {
#   load_balancer_arn = aws_lb.frontend.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = "arn:aws:acm:region:account-id:certificate/certificate-id"
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.frontend.arn
#   }
# }
#
# resource "aws_lb_listener" "backend_https" {
#   load_balancer_arn = aws_lb.backend.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = "arn:aws:acm:region:account-id:certificate/certificate-id"
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.backend.arn
#   }
# }
