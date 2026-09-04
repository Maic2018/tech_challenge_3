#!/bin/bash
# Dispara o pipeline dos 5 microsserviços (workflow_dispatch) e espera terminar.
# Ao final, cada pipeline publicou a imagem no ECR e commitou a nova tag em
# gitops/apps/<serviço>/deployment.yaml — o ArgoCD faz o resto.
# Uso: bash scripts/trigger-ci.sh [branch]   (padrão: main)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd gh git
cd "$REPO_ROOT"
gh auth status >/dev/null 2>&1 || die "Faça login no GitHub primeiro: gh auth login"

REF="${1:-main}"
log "Disparando os workflows na branch $REF"
for svc in "${SERVICES[@]}"; do
  gh workflow run "${svc}.yml" --ref "$REF" && echo "    ${svc}.yml disparado"
done

log "Aguardando o GitHub registrar as execuções..."
sleep 15

STATUS=0
for svc in "${SERVICES[@]}"; do
  RUN_ID="$(gh run list --workflow "${svc}.yml" --branch "$REF" --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId')"
  if [ -z "$RUN_ID" ]; then warn "Execução de $svc não encontrada"; STATUS=1; continue; fi
  log "$svc -> run $RUN_ID"
  if ! gh run watch "$RUN_ID" --exit-status; then
    warn "Pipeline de $svc FALHOU. Detalhes: gh run view $RUN_ID --log-failed"
    STATUS=1
  fi
done

[ "$STATUS" -eq 0 ] || die "Um ou mais pipelines falharam."
log "Todos os pipelines passaram. Tags atualizadas em gitops/apps/*/deployment.yaml ($REF)."
