#!/bin/bash
# terraform init apontando para o backend S3 do account atual.
# Uso: bash scripts/tf-init.sh [infra|platform]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd aws terraform

TARGET="${1:-infra}"
case "$TARGET" in
  infra)    DIR="$REPO_ROOT/infra" ;;
  platform) DIR="$REPO_ROOT/infra/platform" ;;
  *) die "Uso: bash scripts/tf-init.sh [infra|platform]" ;;
esac

BUCKET="$(tfstate_bucket)"
log "terraform init em $DIR (bucket: $BUCKET)"
terraform -chdir="$DIR" init -input=false -reconfigure -backend-config="bucket=${BUCKET}"
