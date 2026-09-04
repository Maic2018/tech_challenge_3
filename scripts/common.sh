#!/bin/bash
# Funções e variáveis compartilhadas pelos scripts do ToggleMaster.
# Uso: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PROJECT_NAME="${PROJECT_NAME:-togglemaster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAMESPACE="${APP_NAMESPACE:-togglemaster}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SERVICES=(auth-service flag-service targeting-service evaluation-service analytics-service)

# Raiz do repositório, independentemente de onde o script foi chamado
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { echo ">>> $*"; }
warn() { echo "!!! $*" >&2; }
die()  { warn "$*"; exit 1; }
step() {
  echo
  echo "================================================================"
  echo " $*"
  echo "================================================================"
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $c"
  done
}

aws_account_id() { aws sts get-caller-identity --query Account --output text; }

# Nome determinístico do bucket de state: <projeto>-tfstate-<account_id>
tfstate_bucket() { echo "${PROJECT_NAME}-tfstate-$(aws_account_id)"; }

# sed -i -E portátil (GNU x BSD/macOS)
sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i -E "$@"; else sed -i '' -E "$@"; fi
}
