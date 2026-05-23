# ==============================================================================
# 1. NETWORK CORE (VPC & SUBNETS)
# ==============================================================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = { Name = "devops-assignment-vpc" }
}

# Private Subnet (for EC2 instances, not directly accessible from the internet)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr_private
  availability_zone = "ap-south-1a"

  tags = { Name = "private-subnet" }
}

# Public Subnet (for ALB and NAT Gateway, accessible from the internet)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_public_A
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true  

  tags = { Name = "public-subnet-a" }
}

# Public Subnet B (Added to satisfy AWS ALB multi-AZ requirement)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_public_B
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true  

  tags = { Name = "public-subnet-b" }
}

# ==============================================================================
# 2. EDGE GATEWAYS & ROUTING
# ==============================================================================

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "main-igw" }
}

# EIP for NAT gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = { Name = "main-nat-gateway" }
}

# Route Table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Route Table Association for public subnet a
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
# Route Table Association for public subnet b
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Route Table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

# Route Table Association for private subnet 
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ==============================================================================
# 3. SECURITY GROUPS (FIREWALLS)
# ==============================================================================

## SG Load Balancer, allows public HTTP traffic in from the internet
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow public HTTP traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Shared Worker Security Group for internal communication
resource "aws_security_group" "workers" {
  name        = "workers-sg"
  description = "Allow traffic between ALB and workers, and worker-to-worker"
  vpc_id      = aws_vpc.main.id

  # 1. Allow the Application Load Balancer to hit Port 3000 on the Caller Worker
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # 2. Allow workers to talk to each other freely on ALL ports internally
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # 3. Allow workers to talk out to the internet (to run npm install / pip install)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==============================================================================
# 4. LOAD BALANCER (ALB)
# ==============================================================================

# Application Load Balancer
resource "aws_lb" "external" {
  name               = "external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

# LB target group for caller worker
resource "aws_lb_target_group" "caller" {
  name     = "caller-target-group"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health" 
    protocol            = "HTTP"
    matcher             = "200" 
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener to forward HTTP traffic from ALB to our caller worker target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.caller.arn
  }
}

# ==============================================================================
# 5. COMPUTE (EC2 INSTANCES) & USER DATA INJECTION
# ==============================================================================

# Prerequisite for EC2 Instances 
data "aws_ami" "ubuntu" {
  most_recent = true

  # Filter down to the official Ubuntu base server image
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  # This is the exact AWS Account ID owned by Canonical (the creators of Ubuntu)
  # This prevents malicious third-parties from spoofing an image
  owners = ["099720109477"] 
}

# EC2 Instance for inference worker
resource "aws_instance" "inference_worker" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.workers.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name

  depends_on = [
  aws_nat_gateway.nat,
  aws_route_table_association.private,
]

  user_data = templatefile("${path.module}/../scripts/deploy-inference.sh", {})

  tags = { Name = "inference-worker" }
}

# EC2 Instance for caller worker
resource "aws_instance" "caller_worker" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.workers.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name

  depends_on = [
  aws_nat_gateway.nat,
  aws_route_table_association.private,
]

  user_data = replace(
    templatefile("${path.module}/../scripts/deploy-caller.sh", {}),
    "PYTHON_PRIVATE_IP_PLACEHOLDER",
    aws_instance.inference_worker.private_ip
  )

  tags = { Name = "caller-worker" }
}

# LB target group attachment for caller
resource "aws_lb_target_group_attachment" "caller" {
  target_group_arn = aws_lb_target_group.caller.arn
  target_id        = aws_instance.caller_worker.id
  port             = 3000
}

# IAM role allowing EC2 to talk to SSM
resource "aws_iam_role" "ec2_ssm" {
  name = "ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ==============================================================================
# 6. OUTPUTS
# ==============================================================================

output "alb_dns_name" {
  description = "The public URL to hit the JSON HTTP API endpoint via curl"
  value       = aws_lb.external.dns_name
}
