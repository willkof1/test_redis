import redis.cluster
import time
import sys
import argparse

# =================================================================================
# Aplicação para testar a resiliência de uma conexão a um cluster Redis
# durante operações de adição e remoção de shards (resharding).
#
# Como funciona:
# - A biblioteca `redis-py` com suporte a cluster lida automaticamente com
#   erros de redirecionamento "MOVED" e "ASK" durante o resharding.
# - O cliente atualiza seu mapa interno de slots e reenvia o comando ao nó correto.
# - O objetivo deste teste é observar essa resiliência em ação.
# =================================================================================

def parse_args():
    parser = argparse.ArgumentParser(description="Teste de resiliência do cluster Redis durante resharding.")
    parser.add_argument("--redis-endpoint", required=True, help="Endpoint de configuração do cluster Redis")
    parser.add_argument("--auth-token",     required=True, help="Token de autenticação do Redis")
    parser.add_argument("--action",         default="reshard", help="Ação a executar (padrão: reshard)")
    return parser.parse_args()


def connect(redis_host: str, auth_token: str) -> redis.cluster.RedisCluster:
    """Cria e valida a conexão com o cluster Redis."""
    rc = redis.cluster.RedisCluster(
        host=redis_host,
        port=6379,
        password=auth_token,
        decode_responses=True,
        skip_full_coverage_check=True,  # recomendado para clusters gerenciados (ElastiCache)
        ssl=True,
    )
    rc.ping()
    return rc


def run_reshard_test(redis_host: str, auth_token: str) -> None:
    """
    Executa um loop de escrita e leitura no cluster Redis,
    reportando sucessos e falhas. Encerra graciosamente com Ctrl+C.
    """
    try:
        print(f"Conectando ao cluster: {redis_host}")
        rc = connect(redis_host, auth_token)
        print("Conexão estabelecida com sucesso.")
    except Exception as e:
        print(f"Falha fatal ao conectar ao cluster Redis: {e}")
        sys.exit(1)

    stats = {"success": 0, "data_mismatch": 0, "cluster_error": 0, "connection_error": 0, "timeout": 0, "unexpected": 0}
    counter = 0

    try:
        while True:
            counter += 1
            key   = f"reshard-test-key-{counter}"
            value = f"value-{int(time.time())}"

            try:
                rc.set(key, value, ex=60)  # TTL de 60s para não acumular chaves
                retrieved = rc.get(key)

                if retrieved == value:
                    stats["success"] += 1
                    print(f"SUCESSO      [{counter:>6}]: '{key}' ok")
                else:
                    stats["data_mismatch"] += 1
                    print(f"DADO ERRADO  [{counter:>6}]: esperado='{value}' recebido='{retrieved}'")

            except redis.exceptions.RedisClusterException as e:
                stats["cluster_error"] += 1
                print(f"CLUSTER ERR  [{counter:>6}]: {e}")
            except redis.exceptions.ConnectionError as e:
                stats["connection_error"] += 1
                print(f"CONN ERR     [{counter:>6}]: {e}")
            except redis.exceptions.TimeoutError as e:
                stats["timeout"] += 1
                print(f"TIMEOUT      [{counter:>6}]: {e}")
            except Exception as e:
                stats["unexpected"] += 1
                print(f"INESPERADO   [{counter:>6}]: {e}")

            time.sleep(0.5)

    except KeyboardInterrupt:
        pass

    # Resumo final
    total  = counter
    errors = total - stats["success"]
    print("\n" + "=" * 50)
    print(f"Teste encerrado após {total} iterações.")
    print(f"  Sucessos:          {stats['success']}")
    print(f"  Dados incorretos:  {stats['data_mismatch']}")
    print(f"  Erros de cluster:  {stats['cluster_error']}")
    print(f"  Erros de conexão:  {stats['connection_error']}")
    print(f"  Timeouts:          {stats['timeout']}")
    print(f"  Inesperados:       {stats['unexpected']}")
    print(f"  Taxa de sucesso:   {stats['success'] / total * 100:.1f}%" if total else "  Nenhuma iteração concluída.")
    print("=" * 50)


if __name__ == "__main__":
    args = parse_args()
    run_reshard_test(args.redis_endpoint, args.auth_token)
