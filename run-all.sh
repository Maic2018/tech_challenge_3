#!/bin/bash
# run-all.sh — Sobe o ambiente completo do zero (Fase 3):
#   backend S3 -> infra (Terraform) -> imagens via pipeline GitHub Actions ->
#   plataforma (ArgoCD, Ingress, Metrics Server, Secrets via Terraform) ->
#   migrations -> ArgoCD sincroniza os 5 microsserviços -> teste do fluxo.
# Nada é aplicado com kubectl apply a partir desta máquina: o deploy é GitOps.
#
# Uso: bash run-all.sh
# Variáveis opcionais: AUTO_APPROVE=1 (não pede confirmação do plan)
#                      SKIP_CI=1 (não dispara o pipeline; imagens já existem no ECR)
#                      CI_REF=main (branch cujos workflows serão disparados)
#                      GITOPS_REPO_TOKEN=... (repositório privado: token de leitura p/ ArgoCD)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
cd "$REPO_ROOT"
require_cmd aws terraform kubectl curl

step "PASSO 1/8 — Identidade AWS e LabRole"
bash infra/00-check-account.sh

step "PASSO 2/8 — Backend remoto do Terraform (bucket S3 versionado + lock)"
bash scripts/bootstrap-backend.sh

step "PASSO 3/8 — Infraestrutura: VPC, EKS, RDS x3, Redis, DynamoDB, SQS, ECR"
bash scripts/tf-init.sh infra
terraform -chdir=infra plan -input=false -out=tfplan
if [ "${AUTO_APPROVE:-0}" != "1" ]; then
  read -r -p ">>> Confira o plan acima. ENTER para aplicar (Ctrl+C cancela)..."
fi
log "Aplicando (~20 min: RDS e EKS são lentos). Não interrompa."
terraform -chdir=infra apply -input=false tfplan
rm -f infra/tfplan

step "PASSO 4/8 — kubectl apontando para o cluster"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$(terraform -chdir=infra output -raw eks_cluster_name)"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes

step "PASSO 5/8 — Imagens: pipeline de CI/DevSecOps publica no ECR e atualiza o GitOps"
if [ "${SKIP_CI:-0}" = "1" ]; then
  warn "SKIP_CI=1: pulando o pipeline. As imagens precisam existir no ECR deste account."
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  bash scripts/set-github-secrets.sh
  bash scripts/trigger-ci.sh "${CI_REF:-main}"
else
  warn "GitHub CLI (gh) não autenticado. Opções:"
  warn "  a) gh auth login && bash scripts/set-github-secrets.sh && bash scripts/trigger-ci.sh"
  warn "  b) fallback local sem DevSecOps: bash build-and-push.sh (depois commit + push de gitops/)"
  read -r -p ">>> ENTER quando as imagens estiverem no ECR e a tag no gitops/ (Ctrl+C cancela)..."
fi

step "PASSO 6/8 — Plataforma: ArgoCD, Ingress NGINX, Metrics Server e Secrets (Terraform)"
export TF_VAR_gitops_repo_token="${GITOPS_REPO_TOKEN:-}"
bash scripts/tf-init.sh platform
terraform -chdir=infra/platform apply -input=false -auto-approve

step "PASSO 7/8 — Migrations SQL + registro da chave interna do evaluation-service"
bash run-migrations.sh

step "PASSO 8/8 — ArgoCD sincronizando os 5 microsserviços + teste do fluxo"
bash scripts/wait-argocd-sync.sh
APP_URL="$(terraform -chdir=infra/platform output -raw app_url)"
bash scripts/get-api-key.sh >/dev/null
bash test-fluxo-completo.sh "$APP_URL"

echo
log "AMBIENTE COMPLETO."
log "Aplicação: $APP_URL"
bash scripts/argocd-info.sh
