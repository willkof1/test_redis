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

resource "aws_iam_role" "ec2_role" {
  name = "${var.cluster_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_role" {
  name = "${var.cluster_name}-ec2-role"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "test_runner" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  subnet_id                   = var.subnet_ids[0]
  iam_instance_profile        = aws_iam_instance_profile.ec2_role.name
  associate_public_ip_address = true
  # O token é buscado do SSM em runtime — nunca exposto no user_data
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 git screen
    pip3 install "redis[hiredis]"
    aws s3 cp s3://will-artefatos/app.py /home/ec2-user/app.py
    REDIS_ENDPOINT="${aws_elasticache_replication_group.redis_cluster_mode.configuration_endpoint_address}"
    AUTH_TOKEN=$(aws ssm get-parameter \
      --name "/${var.cluster_name}/redis-auth-token" \
      --with-decryption \
      --region "${var.aws_region}" \
      --query Parameter.Value \
      --output text)
    screen -dmS reshard bash -c "python3 -u /home/ec2-user/app.py \
      --redis-endpoint \"$REDIS_ENDPOINT\" \
      --auth-token \"$AUTH_TOKEN\" \
      --action reshard \
      >> /var/log/reshard-test.log 2>&1"
  EOF
  )

  tags = {
    Name = "${var.cluster_name}-test-runner"
  }

  depends_on = [aws_ssm_parameter.redis_auth_token]
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
  num_node_groups            = var.num_shards   # Number of shards
  replicas_per_node_group    = var.num_replicas # Number of read replicas per primary node
  port                       = 6379
  parameter_group_name       = "default.redis7.cluster.on" # Ensure cluster mode parameter group
  snapshot_retention_limit   = 1
  snapshot_window            = "05:00-09:00"
  maintenance_window         = "sun:02:00-sun:04:00"
  apply_immediately          = true
  automatic_failover_enabled = true
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  subnet_group_name          = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids         = [aws_security_group.redis_sg.id]

  tags = {
    Name = var.cluster_name
  }
}

# Armazena o token no SSM
resource "aws_ssm_parameter" "redis_auth_token" {
  name  = "/${var.cluster_name}/redis-auth-token"
  type  = "SecureString"
  value = var.redis_auth_token
}
