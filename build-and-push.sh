#!/bin/bash
# build-and-push.sh — FALLBACK LOCAL (sem os gates de DevSecOps).
# O caminho oficial é o pipeline do GitHub Actions (.github/workflows/<serviço>.yml).
# Builda e publica as 5 imagens no ECR com a tag do commit e atualiza gitops/.
# Depois: git add gitops && git commit && git push  (o ArgoCD sincroniza sozinho).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
cd "$REPO_ROOT"
require_cmd aws docker git

ACCOUNT_ID="$(aws_account_id)"
ECR="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TAG="v${APP_VERSION:-1.0.0}-$(git rev-parse --short=7 HEAD)"
log "Registry: $ECR | Tag: $TAG"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR"

for svc in "${SERVICES[@]}"; do
  IMAGE="$ECR/${PROJECT_NAME}/${svc}:${TAG}"
  log "[$svc] build (linux/amd64, mesma plataforma dos nodes EKS)..."
  docker build --platform linux/amd64 -t "$IMAGE" "./$svc"
  log "[$svc] push..."
  docker push "$IMAGE"
  bash scripts/update-image-tag.sh "$svc" "$IMAGE"
done

log "Imagens publicadas com a tag $TAG e manifestos atualizados em gitops/."
log "Agora: git add gitops && git commit -m \"gitops: $TAG\" && git push"
