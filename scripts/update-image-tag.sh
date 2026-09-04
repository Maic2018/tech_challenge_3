#!/bin/bash
# Atualiza a linha "image:" do Deployment de um microsserviço no repositório GitOps
# (gitops/apps/<serviço>/deployment.yaml). Usado pelo pipeline de CI (job 5) e
# pelo fallback local build-and-push.sh.
# Uso: bash scripts/update-image-tag.sh <serviço> <registry>/togglemaster/<serviço>:<tag>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SERVICE="${1:?Uso: update-image-tag.sh <serviço> <imagem:tag>}"
IMAGE="${2:?Uso: update-image-tag.sh <serviço> <imagem:tag>}"
FILE="$REPO_ROOT/gitops/apps/$SERVICE/deployment.yaml"

[ -f "$FILE" ] || die "Manifesto não encontrado: $FILE"
case "$IMAGE" in
  */"$SERVICE":*) ;;
  *) die "A imagem deve ser do serviço $SERVICE (.../$SERVICE:<tag>): $IMAGE" ;;
esac
grep -qE "^[[:space:]]*image:[[:space:]]*[^[:space:]]*/${SERVICE}:[^[:space:]]+" "$FILE" \
  || die "Linha 'image:' do $SERVICE não encontrada em $FILE"

sed_inplace "s#^([[:space:]]*image:[[:space:]]*)[^[:space:]]*/${SERVICE}:[^[:space:]]+#\1${IMAGE}#" "$FILE"
log "$FILE"
grep -nE "^[[:space:]]*image:" "$FILE"
