#!/bin/bash
# Cria (se não existir) o bucket S3 que guarda o terraform.tfstate remoto e o
# deixa versionado, criptografado e sem acesso público. Idempotente.
# É o único passo fora do Terraform: o backend precisa existir antes do 1º init.
# Uso: bash scripts/bootstrap-backend.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd aws

BUCKET="$(tfstate_bucket)"
log "Bucket de state: s3://${BUCKET} (região ${AWS_REGION})"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  log "Bucket já existe."
else
  log "Criando bucket..."
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
fi

log "Versionamento (histórico de cada state)..."
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
log "Criptografia padrão (SSE-S3)..."
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
log "Bloqueio de acesso público..."
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

log "Backend pronto. Próximo passo: bash scripts/tf-init.sh infra"
