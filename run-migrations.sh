#!/bin/bash
# run-migrations.sh — Cria as tabelas nos 3 bancos RDS e registra a chave de API
# interna do evaluation-service. Roda como um Job dentro do cluster (os bancos
# estão em subnets privadas) e lê as credenciais direto dos Secrets criados pelo
# Terraform: nenhuma senha passa por arquivo ou pela linha de comando.
# Uso: bash run-migrations.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
require_cmd kubectl
cd "$REPO_ROOT"
NS="$APP_NAMESPACE"

for f in auth-service/db/init.sql flag-service/db/init.sql targeting-service/db/init.sql; do
  [ -f "$f" ] || die "Arquivo não encontrado: $f (rode da raiz do projeto)"
done

log "Publicando os SQLs em um ConfigMap..."
kubectl -n "$NS" create configmap migration-sqls \
  --from-file=init-auth.sql=auth-service/db/init.sql \
  --from-file=init-flag.sql=flag-service/db/init.sql \
  --from-file=init-targeting.sql=targeting-service/db/init.sql \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" delete job db-migrations --ignore-not-found >/dev/null
log "Criando Job db-migrations..."
kubectl -n "$NS" apply -f - <<'__K8S__'
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrations
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 900
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:16-alpine
          env:
            - name: AUTH_DATABASE_URL
              valueFrom: { secretKeyRef: { name: auth-service-secret, key: DATABASE_URL } }
            - name: FLAG_DATABASE_URL
              valueFrom: { secretKeyRef: { name: flag-service-secret, key: DATABASE_URL } }
            - name: TARGETING_DATABASE_URL
              valueFrom: { secretKeyRef: { name: targeting-service-secret, key: DATABASE_URL } }
            - name: SERVICE_API_KEY
              valueFrom: { secretKeyRef: { name: evaluation-service-secret, key: SERVICE_API_KEY } }
          command: ["/bin/sh", "-ec"]
          args:
            - |
              echo "=== auth_db ===";      psql "$AUTH_DATABASE_URL"      -v ON_ERROR_STOP=1 -f /sqls/init-auth.sql
              echo "=== flag_db ===";      psql "$FLAG_DATABASE_URL"      -v ON_ERROR_STOP=1 -f /sqls/init-flag.sql
              echo "=== targeting_db ==="; psql "$TARGETING_DATABASE_URL" -v ON_ERROR_STOP=1 -f /sqls/init-targeting.sql
              echo "=== chave interna do evaluation-service (hash SHA-256) ==="
              HASH=$(printf '%s' "$SERVICE_API_KEY" | sha256sum | awk '{print $1}')
              psql "$AUTH_DATABASE_URL" -v ON_ERROR_STOP=1 \
                -c "INSERT INTO api_keys (name, key_hash) VALUES ('evaluation-service', '$HASH') ON CONFLICT (key_hash) DO NOTHING;"
              echo "=== Migrations concluídas ==="
          volumeMounts:
            - { name: sqls, mountPath: /sqls }
      volumes:
        - name: sqls
          configMap: { name: migration-sqls }
__K8S__

log "Aguardando o Job terminar (até 5 min)..."
if kubectl -n "$NS" wait --for=condition=complete job/db-migrations --timeout=300s; then
  kubectl -n "$NS" logs job/db-migrations
  log "Migrations concluídas."
else
  warn "Job não concluiu. Logs:"
  kubectl -n "$NS" logs job/db-migrations --all-containers 2>/dev/null || true
  kubectl -n "$NS" describe job db-migrations | tail -20 || true
  exit 1
fi
