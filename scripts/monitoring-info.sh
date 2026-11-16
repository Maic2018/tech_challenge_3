#!/bin/bash
# Mostra URL e credenciais do Grafana e o estado da stack de observabilidade (Fase 4).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd kubectl
HOST="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
PASS="$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)"
echo
echo ">>> Grafana:      http://${HOST:-<load balancer pendente>}/grafana/"
echo ">>> Usuário:      admin"
echo ">>> Senha:        ${PASS:-<secret grafana-admin ainda não criado>}"
echo ">>> Dashboard:    http://${HOST:-<lb>}/grafana/d/togglemaster-overview"
echo ">>> Alertas:      http://${HOST:-<lb>}/grafana/alerting/list"
echo ">>> Prometheus:   kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090"
echo ">>> Self-healing: kubectl -n monitoring logs deploy/self-healing -f"
echo
kubectl -n "$ARGOCD_NAMESPACE" get applications.argoproj.io -l app.kubernetes.io/part-of=togglemaster-monitoring 2>/dev/null || true
echo
kubectl -n monitoring get pods 2>/dev/null || true
