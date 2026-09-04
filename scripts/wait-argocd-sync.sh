#!/bin/bash
# Aguarda as Applications do ArgoCD (5 microsserviços + platform) ficarem
# Synced/Healthy. Uso: bash scripts/wait-argocd-sync.sh [timeout_segundos]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd kubectl
TIMEOUT="${1:-900}"; EXPECTED="${EXPECTED_APPS:-6}"; ELAPSED=0
while :; do
  LIST="$(kubectl -n "$ARGOCD_NAMESPACE" get applications.argoproj.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.status.sync.status}{"/"}{.status.health.status}{"\n"}{end}' 2>/dev/null || true)"
  TOTAL="$(printf '%s\n' "$LIST" | grep -c '=' || true)"
  OK="$(printf '%s\n' "$LIST" | grep -c '=Synced/Healthy' || true)"
  echo ">>> [$ELAPSED s] Applications Synced/Healthy: $OK/$TOTAL (esperado $EXPECTED)"
  if [ "$TOTAL" -ge "$EXPECTED" ] && [ "$OK" -eq "$TOTAL" ]; then
    printf '%s\n' "$LIST"; log "ArgoCD sincronizou todas as aplicações."; exit 0
  fi
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    printf '%s\n' "$LIST"; die "Timeout aguardando o ArgoCD. Veja: kubectl -n $ARGOCD_NAMESPACE get applications"
  fi
  sleep 15; ELAPSED=$((ELAPSED + 15))
done
