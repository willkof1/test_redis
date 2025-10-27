# ==============================================================================
# Configuração Principal do Terraform
# Define os recursos da AWS: Security Groups, EC2 e ElastiCache Redis
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Pega seu IP público para a regra de SSH ---
data "http" "my_ip" {
  url = "http://checkip.amazonaws.com"
}

# --- 1. Security Groups ---

# Security Group para a instância EC2
resource "aws_security_group" "ec2_sg" {
  name        = "${var.cluster_name}-ec2-sg"
  description = "Permite SSH"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  # Permite toda a saída
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-ec2-sg"
  }
}

# Security Group para o cluster ElastiCache Redis
resource "aws_security_group" "redis_sg" {
  name        = "${var.cluster_name}-redis-sg"
  description = "Permite acesso ao Redis a partir da EC2"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tags = {
    Name = "${var.cluster_name}-redis-sg"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "template_file" "user_data" {
  template = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 git
    pip3 install "redis[hiredis]"
    aws s3 cp s3://will-artefatos/app.py /home/ec2-user/app.py
    export REDIS_CLUSTER_ENDPOINT=${aws_elasticache_replication_group.redis_cluster_mode.configuration_endpoint_address}
    export REDIS_AUTH_TOKEN=${var.redis_auth_token}
    python3 /home/ec2-user/app.py --redis-endpoint $REDIS_CLUSTER_ENDPOINT --auth-token $REDIS_AUTH_TOKEN --action reshard
    EOF
}

resource "aws_instance" "test_runner" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  subnet_id                   = var.subnet_ids[0]
  user_data                   = data.template_file.user_data.rendered
  iam_instance_profile        = "ec2_s3_profile" # ou o nome do instance profile associado à role s3-role
  associate_public_ip_address = true


  tags = {
    Name = "${var.cluster_name}-test-runner"
  }
}

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "${var.cluster_name}-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_replication_group" "redis_cluster_mode" {
  replication_group_id       = var.cluster_name
  description                = "My Redis Cluster Mode Enabled ElastiCache"
  engine                     = "redis"
  engine_version             = "7.0" # Specify your desired Redis version
  node_type                  = var.redis_node_type
  num_node_groups            = 1 # Number of shards
  replicas_per_node_group    = 2 # Number of read replicas per primary node
  port                       = 6379
  parameter_group_name       = "default.redis7.cluster.on" # Ensure cluster mode parameter group
  snapshot_retention_limit   = 7
  snapshot_window            = "05:00-09:00"
  automatic_failover_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  subnet_group_name          = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids         = [aws_security_group.redis_sg.id]

  tags = {
    Name = var.cluster_name
  }
}
