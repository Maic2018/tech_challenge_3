#!/bin/bash
# update-api-key.sh — Cria uma chave de API adicional (para testes/clientes) via
# POST /auth/admin/keys, usando a MASTER_KEY gerada pelo Terraform (lida do Secret
# do cluster, nunca hardcoded). A chave interna do evaluation-service já é
# registrada pelo run-migrations.sh; este script é opcional.
# Uso: bash update-api-key.sh <URL_DO_LOAD_BALANCER> [nome-da-chave]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
require_cmd kubectl curl

LB="${1:?Uso: bash update-api-key.sh <URL_DO_LOAD_BALANCER> [nome-da-chave]}"
NAME="${2:-tech-challenge-key}"

MASTER_KEY="$(kubectl -n "$APP_NAMESPACE" get secret auth-service-secret -o jsonpath='{.data.MASTER_KEY}' | base64 -d)"
[ -n "$MASTER_KEY" ] || die "MASTER_KEY não encontrada no Secret auth-service-secret"

log "Criando chave '$NAME' via $LB/auth/admin/keys"
RESPONSE="$(curl -s --request POST --url "$LB/auth/admin/keys" \
  --header "Authorization: Bearer $MASTER_KEY" \
  --header 'Content-Type: application/json' \
  --data "{\"name\": \"$NAME\"}")"

API_KEY="$(echo "$RESPONSE" | grep -o '"key":"[^"]*' | cut -d'"' -f4 || true)"
[ -n "$API_KEY" ] || die "Não foi possível criar a chave. Resposta: $RESPONSE"

printf '%s\n' "$API_KEY" > "$REPO_ROOT/api_key.txt"
log "Chave criada e salva em api_key.txt (ignorado pelo git):"
echo "$API_KEY"
