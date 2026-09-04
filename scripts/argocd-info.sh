#!/bin/bash
# Mostra URL, usuário e senha inicial do ArgoCD e o estado das Applications.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd kubectl
URL="$(kubectl -n "$ARGOCD_NAMESPACE" get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
PASS="$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
echo
echo ">>> ArgoCD:   http://${URL:-<load balancer ainda pendente>}"
echo ">>> Usuário:  admin"
echo ">>> Senha:    ${PASS:-<secret ainda não criado>}"
echo
kubectl -n "$ARGOCD_NAMESPACE" get applications.argoproj.io 2>/dev/null || true
