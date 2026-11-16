#!/bin/bash
# chaos-demo.sh — "Prova Real" da Fase 4: injeta falha no auth-service e gera tráfego
# até o alerta disparar (Grafana -> PagerDuty + Discord + webhook) e o self-healing
# reiniciar o deployment. O restart limpa a falha (ela vive só na memória do pod).
#
# Uso: bash scripts/chaos-demo.sh [error_rate] [duração_máxima_s]
#   error_rate: % das chamadas a /validate que devolvem HTTP 500 (padrão 50)
#   duração:    tempo máximo gerando tráfego (padrão 480 s)
# Em outros terminais, durante o vídeo:
#   kubectl -n togglemaster get pods -l app=auth-service -w
#   kubectl -n monitoring logs deploy/self-healing -f
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"
require_cmd kubectl curl

RATE="${1:-50}"
DURATION="${2:-480}"
HOST="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
[ -n "$HOST" ] || die "Load Balancer do ingress-nginx não encontrado."
LB="http://$HOST"
MASTER_KEY="$(kubectl -n "$APP_NAMESPACE" get secret auth-service-secret -o jsonpath='{.data.MASTER_KEY}' | base64 -d)"
[ -f api_key.txt ] || bash scripts/get-api-key.sh >/dev/null
API_KEY="$(cat api_key.txt)"

pods_auth() {
  kubectl -n "$APP_NAMESPACE" get pods -l app=auth-service -o jsonpath='{.items[*].metadata.name}'
}

POD_INICIAL="$(pods_auth)"
HEALED=0
# Se o self-healing não agir (ex.: alerta sem credenciais), desliga a falha na saída
cleanup() {
  if [ "$HEALED" -eq 0 ]; then
    warn "Self-healing não detectado: desligando a falha manualmente."
    curl -s -X POST "$LB/auth/admin/chaos" -H "Authorization: Bearer $MASTER_KEY" \
      -H 'Content-Type: application/json' -d '{"error_rate": 0}' || true
    echo
  fi
}
trap cleanup EXIT

step "1. Injetando falha: ${RATE}% das chamadas a /validate do auth-service devolvem HTTP 500"
log "Pod atual do auth-service: $POD_INICIAL"
curl -fsS -X POST "$LB/auth/admin/chaos" -H "Authorization: Bearer $MASTER_KEY" \
  -H 'Content-Type: application/json' -d "{\"error_rate\": $RATE}"
echo

step "2. Gerando tráfego (até ${DURATION}s ou até o self-healing agir)"
log "Esperado: alerta Firing no Grafana em ~1-2 min -> incidente no PagerDuty + mensagem no"
log "Discord -> webhook do self-healing -> kubectl rollout restart deployment/auth-service"
START=$SECONDS
LAST=0
OK=0
ERR=0
while [ $((SECONDS - START)) -lt "$DURATION" ]; do
  for _ in 1 2 3 4 5; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$LB/auth/validate" \
      -H "Authorization: Bearer $API_KEY" || true)"
    case "$CODE" in
      2*) OK=$((OK + 1)) ;;
      *) ERR=$((ERR + 1)) ;;
    esac
  done
  # Avaliações completas: geram traces distribuídos (evaluation -> flag/targeting -> auth -> SQS)
  curl -s -o /dev/null --max-time 5 "$LB/evaluate/evaluate?flag_name=nova_ui&user_id=user_$RANDOM" \
    -H "Authorization: Bearer $API_KEY" || true

  if [ $((SECONDS - LAST)) -ge 10 ]; then
    LAST=$SECONDS
    PODS="$(pods_auth)"
    log "[$((SECONDS - START))s] respostas 2xx=$OK  erros=$ERR  pods=$PODS"
    case " $PODS " in
      *" $POD_INICIAL "*) ;;
      *)
        HEALED=1
        step "3. Self-healing executado: o pod $POD_INICIAL foi substituído por $PODS"
        break
        ;;
    esac
  fi
done

step "4. Estado depois do restart"
log "Falha injetada no pod novo (esperado error_rate 0):"
curl -s "$LB/auth/admin/chaos" -H "Authorization: Bearer $MASTER_KEY" || true
echo
for _ in 1 2 3 4 5; do
  curl -s -o /dev/null -w '   /validate -> HTTP %{http_code}\n' --max-time 5 "$LB/auth/validate" \
    -H "Authorization: Bearer $API_KEY" || true
done
kubectl -n "$APP_NAMESPACE" get pods -l app=auth-service
echo
log "Execução do self-healing (evidência para o relatório):"
kubectl -n monitoring logs deploy/self-healing --tail=20 || true
log "O alerta volta a Normal em ~1-2 min e o Grafana manda o 'resolved' para PagerDuty/Discord."
