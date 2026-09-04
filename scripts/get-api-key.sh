#!/bin/bash
# Lê a chave de API interna (gerada pelo Terraform e registrada pelo
# run-migrations.sh) e salva em api_key.txt (ignorado pelo git) para os testes.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd kubectl
KEY="$(kubectl -n "$APP_NAMESPACE" get secret evaluation-service-secret -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)"
[ -n "$KEY" ] || die "SERVICE_API_KEY não encontrada. A plataforma foi aplicada (infra/platform)?"
printf '%s\n' "$KEY" > "$REPO_ROOT/api_key.txt"
log "Chave salva em api_key.txt"
echo "$KEY"
