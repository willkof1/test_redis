# Test Redis - Infraestrutura e Teste de Resiliência

Este projeto contém a infraestrutura como código (IaC) para criar um cluster Redis na AWS e uma aplicação Python para testar sua resiliência durante operações de resharding.

## Ferramentaas

- AWS
- Terraform
- Python
- Github Copilot

## AWS

## Terraform - Infraestrutura

### Recursos Provisionados

- **ElastiCache Redis Cluster**
  - Modo cluster habilitado
  - Redis 7.0
  - 1 shard com 2 réplicas
  - Criptografia em trânsito habilitada
  - Autenticação via token
  - Backup automático configurado

- **EC2 Instance**
  - Amazon Linux 2
  - Python 3 instalado
  - Scripts de teste automaticamente deployados
  - IP público para acesso SSH

- **Security Groups**
  - EC2: Permite SSH do seu IP
  - Redis: Permite acesso apenas da EC2

### Variáveis Principais

- `aws_region`: Região AWS (default: us-east-1)
- `cluster_name`: Nome base para recursos (default: cluster-reshard-test)
- `instance_type`: Tipo da EC2 (default: t2.micro)
- `redis_node_type`: Tipo do nó Redis (default: cache.t3.small)
- `redis_auth_token`: Token de autenticação do Redis (sensível)
- `vpc_id`: ID da VPC
- `subnet_ids`: Lista de Subnets
- `key_pair_name`: Nome do Key Pair para SSH

## App Python - Teste de Resiliência

### Funcionalidade

O script `app.py` testa continuamente a resiliência do cluster Redis durante operações de resharding:

1. Conecta ao cluster usando redis-py com suporte a cluster
2. Executa um loop infinito de operações:
   - Escrita de chaves
   - Leitura de chaves
   - Validação dos dados
   - Relatório de sucesso/falha

### Características

- Reconexão automática em caso de falhas
- Suporte a SSL/TLS
- Tratamento de erros MOVED/ASK do Redis
- Logging detalhado de operações
- TTL nas chaves para limpeza automática

### Execução

O script é automaticamente iniciado na EC2 via user-data com as variáveis de ambiente:
- `REDIS_CLUSTER_ENDPOINT`
- `REDIS_AUTH_TOKEN`

### Monitoramento

A aplicação registra:
- Sucessos de operações
- Falhas de conexão
- Erros de cluster
- Timeouts
- Exceções inesperadas

