import redis.cluster
import time
import os
import sys

# =================================================================================
# Aplicação para testar a resiliência de uma conexão a um cluster Redis
# durante operações de adição e remoção de shards (resharding).
#
# Como funciona:
# - A biblioteca `redis-py` com suporte a cluster é inteligente.
# - Quando você envia um comando, ela pode receber um erro de redirecionamento
#   "MOVED" ou "ASK" do Redis se o slot da chave migrou para outro nó.
# - O cliente automaticamente lida com isso, atualiza seu mapa interno de slots
#   e reenvia o comando para o nó correto.
# - O objetivo deste teste é ver essa resiliência em ação.
# =================================================================================

def run_reshard_test():
    """
    Executa um loop infinito de escrita e leitura no cluster Redis,
    reportando sucessos e falhas.
    """
    try:
        # Pega o endpoint do cluster de uma variável de ambiente.
        # É uma boa prática não colocar credenciais ou endpoints no código.
        redis_host = os.environ.get("REDIS_CLUSTER_ENDPOINT")
        if not redis_host:
            print("Erro: A variável de ambiente REDIS_CLUSTER_ENDPOINT não foi definida.")
            print("Execute: export REDIS_CLUSTER_ENDPOINT='seu-endpoint-aqui'")
            sys.exit(1)

        print(f"Iniciando teste de resiliência contra o cluster: {redis_host}")

        # Conecta-se ao cluster.
        # `decode_responses=True` para que as respostas venham como strings.
        # `skip_full_coverage_check=True` é recomendado para clusters gerenciados como o ElastiCache.
        rc = redis.cluster.RedisCluster(
            host=redis_host,
            port=6379,
            decode_responses=True,
            skip_full_coverage_check=True,
            ssl=True # ElastiCache geralmente tem encryption-in-transit habilitado
        )

        # Verifica a conexão inicial
        rc.ping()
        print("Conexão com o cluster Redis estabelecida com sucesso!")

    except Exception as e:
        print(f"Falha fatal ao conectar ao cluster Redis: {e}")
        sys.exit(1)

    counter = 0
    while True:
        try:
            counter += 1
            key = f"reshard-test-key-{counter}"
            value = f"value-{int(time.time())}"

            # 1. Escreve no cluster
            rc.set(key, value, ex=60) # `ex=60` define um TTL de 60s para a chave não ficar para sempre

            # 2. Lê do cluster
            retrieved_value = rc.get(key)

            # 3. Valida
            if retrieved_value == value:
                print(f"SUCESSO [Iteração {counter}]: Chave '{key}' escrita e lida corretamente.")
            else:
                print(f"FALHA DE DADOS [Iteração {counter}]: Chave '{key}'. Esperado: '{value}', Recebido: '{retrieved_value}'")

        except redis.exceptions.RedisClusterException as e:
            # Captura exceções específicas do cluster que podem ocorrer durante o resharding
            print(f"AVISO - Exceção de Cluster [Iteração {counter}]: {e}. O cliente deve se recuperar.")
        except redis.exceptions.ConnectionError as e:
            print(f"AVISO - Erro de Conexão [Iteração {counter}]: {e}. Tentando reconectar...")
        except redis.exceptions.TimeoutError as e:
            print(f"AVISO - Timeout [Iteração {counter}]: {e}. O cluster pode estar ocupado.")
        except Exception as e:
            # Captura qualquer outra exceção
            print(f"ERRO INESPERADO [Iteração {counter}]: {e}")

        # Pausa para não sobrecarregar o terminal e o cluster
        time.sleep(0.5)


if __name__ == "__main__":
    run_reshard_test()