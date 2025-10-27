variable "aws_region" {
  description = "A região da AWS onde os recursos serão criados."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome base para todos os recursos criados (cluster, SGs, etc.)."
  type        = string
  default     = "cluster-reshard-test"
}

variable "instance_type" {
  description = "Tipo da instância EC2 que executará o script de teste."
  type        = string
  default     = "t2.micro"
}

variable "redis_node_type" {
  description = "Tipo de nó para o cluster ElastiCache Redis."
  type        = string
  default     = "cache.t3.small"
}

variable "redis_auth_token" {
  description = "Authentication token for Redis"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "O ID da sua VPC existente."
  type        = string
}

variable "subnet_ids" {
  description = "Uma lista de IDs de subnet existentes onde o cluster ElastiCache será criado."
  type        = list(string)
}

variable "key_pair_name" {
  description = "Nome do seu Key Pair da EC2 para acesso SSH. DEVE existir na região."
  type        = string
}
