# ==============================================================================
# Saídas do Terraform
# Estes valores serão exibidos após a execução do `terraform apply`.
# ==============================================================================

output "ec2_public_ip" {
  description = "O endereço IP público da instância EC2 de teste."
  value       = aws_instance.test_runner.public_ip
}

output "redis_cluster_endpoint" {
  description = "O endpoint de configuração do cluster ElastiCache Redis."
  value       = aws_elasticache_replication_group.redis_cluster_mode.configuration_endpoint_address
}

output "ssh_command" {
  description = "Comando para conectar à instância EC2 via SSH."
  value       = "ssh -i ~/.ssh/aws_key_pair.pem ec2-user@${aws_instance.test_runner.public_ip}"
}
