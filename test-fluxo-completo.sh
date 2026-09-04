#!/bin/bash
# test-fluxo-completo.sh — Testa o fluxo inteiro via Load Balancer: health checks,
# cria flag, cria regra de targeting, avalia e confere o envio ao SQS.
# A chave de API vem do Secret do cluster (scripts/get-api-key.sh).
# Uso: bash test-fluxo-completo.sh <URL_DO_LOAD_BALANCER>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
cd "$REPO_ROOT"
require_cmd curl kubectl

LB="${1:?Uso: bash test-fluxo-completo.sh <URL_DO_LOAD_BALANCER>}"
[ -f api_key.txt ] || bash scripts/get-api-key.sh >/dev/null
API_KEY="$(cat api_key.txt)"

log "1. Health checks"
for svc in auth flags targeting evaluate analytics; do
  printf '   %-10s ' "$svc"; curl -s --max-time 10 "$LB/$svc/health" || echo "FALHOU"; echo
done

log "2. Criando flag 'nova_ui'"
curl -s --request POST --url "$LB/flags/flags" \
  --header "Authorization: Bearer $API_KEY" --header 'Content-Type: application/json' \
  --data '{"name": "nova_ui", "description": "Testa nova interface", "is_enabled": true}'; echo

log "3. Criando regra de targeting (50%)"
curl -s --request POST --url "$LB/targeting/rules" \
  --header "Authorization: Bearer $API_KEY" --header 'Content-Type: application/json' \
  --data '{"flag_name": "nova_ui", "is_enabled": true, "rules": {"type": "PERCENTAGE", "value": 50}}'; echo

log "4. Avaliando a flag"
curl -s --request GET --url "$LB/evaluate/evaluate?flag_name=nova_ui&user_id=user_42&country=BR" \
  --header "Authorization: Bearer $API_KEY"; echo

log "5. Log do evaluation-service (envio ao SQS)"
sleep 2
kubectl -n "$APP_NAMESPACE" logs deployment/evaluation-service --tail=5 || true

echo
log "Se o passo 4 retornou JSON sem erro, o fluxo está OK."
log "Teste de carga (HPA): bash tools/hey-wrapper.sh -z 3m -c 150 -H \"Authorization: Bearer \$(cat api_key.txt)\" \"$LB/evaluate/evaluate?flag_name=nova_ui&user_id=user_42&country=BR\""
