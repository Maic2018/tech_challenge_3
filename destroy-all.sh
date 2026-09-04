#!/bin/bash
# destroy-all.sh — Remove tudo na ordem certa:
#   1) plataforma (o Helm remove ArgoCD/ingress e, com eles, os Load Balancers)
#   2) infraestrutura (EKS, RDS, Redis, VPC...)
#   3) opcional: bucket do state (--delete-state-bucket)
# Uso: bash destroy-all.sh [--delete-state-bucket]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
cd "$REPO_ROOT"
require_cmd aws terraform

DELETE_BUCKET=0
[ "${1:-}" = "--delete-state-bucket" ] && DELETE_BUCKET=1
BUCKET="$(tfstate_bucket)"

step "PASSO 1/4 — Plataforma (ArgoCD, Ingress NGINX, Metrics Server, Secrets)"
if aws s3api head-object --bucket "$BUCKET" --key platform/terraform.tfstate >/dev/null 2>&1; then
  bash scripts/tf-init.sh platform
  if terraform -chdir=infra/platform destroy -input=false -auto-approve; then
    log "Aguardando 60s para a AWS liberar Load Balancers e ENIs..."
    sleep 60
  else
    warn "Destroy da plataforma falhou (cluster já removido?). Seguindo: os recursos morrem com o cluster."
  fi
else
  log "Sem state da plataforma. Pulando."
fi

step "PASSO 2/4 — Load Balancers ainda ativos (informativo)"
aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancers[*].[LoadBalancerName,DNSName]' --output table 2>/dev/null || true
aws elb describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output table 2>/dev/null || true

step "PASSO 3/4 — Infraestrutura (terraform destroy)"
bash scripts/tf-init.sh infra
terraform -chdir=infra destroy -input=false -auto-approve
# O state da plataforma fica órfão (tudo que ele descrevia morreu com o cluster)
aws s3 rm "s3://${BUCKET}/platform/terraform.tfstate" >/dev/null 2>&1 || true

step "PASSO 4/4 — Limpeza local"
rm -f account_id.txt api_key.txt infra/tfplan
if [ "$DELETE_BUCKET" -eq 1 ]; then
  log "Removendo todas as versões dos objetos e o bucket $BUCKET..."
  TMP="$(mktemp)"
  for kind in Versions DeleteMarkers; do
    while :; do
      aws s3api list-object-versions --bucket "$BUCKET" --max-keys 500 --output json \
        --query "{Objects: ${kind}[].{Key:Key,VersionId:VersionId}, Quiet: \`true\`}" > "$TMP"
      grep -q '"Key"' "$TMP" || break
      aws s3api delete-objects --bucket "$BUCKET" --delete "file://$TMP" >/dev/null
    done
  done
  rm -f "$TMP"
  aws s3api delete-bucket --bucket "$BUCKET"
  log "Bucket removido."
else
  log "Bucket de state mantido ($BUCKET). Use --delete-state-bucket para removê-lo."
fi
log "Destroy completo. Para recriar: bash run-all.sh"
