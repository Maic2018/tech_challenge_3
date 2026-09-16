#!/bin/bash
# infra/00-check-account.sh — Mostra a identidade AWS atual e salva o Account ID,
# usado para montar o nome do bucket de state do Terraform.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/common.sh"
require_cmd aws

log "Identidade AWS atual:"
aws sts get-caller-identity --output table
ACCOUNT_ID="$(aws_account_id)"

echo "$ACCOUNT_ID" > "$REPO_ROOT/account_id.txt"
log "Account ID $ACCOUNT_ID salvo em account_id.txt (ignorado pelo git)"
log "Bucket de state esperado: $(tfstate_bucket)"
