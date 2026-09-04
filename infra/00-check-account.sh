#!/bin/bash
# infra/00-check-account.sh — Mostra a identidade AWS atual e confere se a LabRole
# existe. Não edita mais o terraform.tfvars: a LabRole é lida pelo Terraform via
# data source (aws_iam_role), então nada muda entre sessões do Academy.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/common.sh"
require_cmd aws

log "Identidade AWS atual:"
aws sts get-caller-identity --output table
ACCOUNT_ID="$(aws_account_id)"

ROLE_NAME="${LAB_ROLE_NAME:-LabRole}"
if ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text 2>/dev/null)"; then
  log "$ROLE_NAME encontrada: $ARN (usada pelo EKS e pelos nodes via data source)"
else
  warn "$ROLE_NAME não encontrada. Em conta pessoal, defina lab_role_arn em infra/terraform.tfvars."
fi

echo "$ACCOUNT_ID" > "$REPO_ROOT/account_id.txt"
log "Account ID $ACCOUNT_ID salvo em account_id.txt (ignorado pelo git)"
log "Bucket de state esperado: $(tfstate_bucket)"
