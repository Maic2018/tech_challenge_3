# gitops/monitoring/ — observabilidade e resposta a incidentes (Fase 4)

Tudo aqui é sincronizado pelo ArgoCD. O Terraform (`infra/platform/monitoring.tf`) só
cria o namespace `monitoring`, os Secrets com as credenciais externas e a Application
raiz `togglemaster-monitoring`, que aponta para `apps/` (app-of-apps).

```
gitops/monitoring/
├── apps/                          # 1 Application do ArgoCD por componente
│   ├── kube-prometheus-stack.yaml # chart 92.11.0: Prometheus + Grafana + kube-state-metrics + node-exporter
│   ├── loki.yaml                  # chart 7.3.0: Loki 3.6 (SingleBinary)
│   ├── otel-gateway.yaml          # chart opentelemetry-collector 0.176.1 (Deployment)
│   ├── otel-agent.yaml            # mesmo chart, DaemonSet (logs dos nodes)
│   └── monitoring-config.yaml     # kustomize de manifests/
├── values/                        # values de cada chart (lidos via source $values)
└── manifests/
    ├── grafana-dashboard-togglemaster.yaml  # dashboard customizado (ConfigMap)
    ├── grafana-alerting.yaml                # regras, contact points e políticas (ConfigMap)
    ├── self-healing.yaml                    # ServiceAccount + RBAC + Deployment + Service
    └── self-healing/responder.py            # webhook de self-healing (vira ConfigMap)
```

## Arquitetura do OpenTelemetry

```
 5 microsserviços (SDK OTel)                     otel-agent (DaemonSet, filelog)
  Go: otelhttp, otelsql, redisotel, AWS SDK      lê /var/log/pods de todos os contêineres
  Python: Flask, requests, psycopg2, botocore    + metadados do Kubernetes
        │ OTLP/HTTP :4318 (traces + métricas)          │ OTLP/gRPC :4317 (logs)
        ▼                                              ▼
 ┌──────────────────────────── otel-gateway (Deployment) ────────────────────────────┐
 │ k8sattributes → resource(cluster) → batch                                          │
 │ traces  ──▶ New Relic (OTLP)  e  connector spanmetrics ──▶ métricas RED            │
 │ metrics ──▶ Prometheus (remote write)  /  New Relic (cumulativetodelta)            │
 │ logs    ──▶ Loki (OTLP nativo)  /  New Relic (só namespace togglemaster)            │
 └────────────────────────────────────────────────────────────────────────────────────┘
        │                         │                            │
   Prometheus ◀── scrapes de infra (kubelet/cAdvisor, kube-state-metrics, node-exporter)
        │                         │                            │
        └──────── Grafana (dashboard + alertas) ◀──── Loki ─────┘          New Relic (APM)
```

- **Um único ponto de saída.** Os serviços só conhecem `otel-gateway:4318`. O destino da
  telemetria muda no collector e não no código.
- **Propagação W3C (`traceparent`).** Ela passa pelos saltos HTTP (evaluation → flag/targeting →
  auth) e também pela fila SQS: o `evaluation-service` grava o `traceparent` nos
  MessageAttributes e o `analytics-service` continua o mesmo trace ao consumir a mensagem.
- **Métricas RED por spanmetrics.** Taxa, erros e duração são calculadas dos spans no
  connector `spanmetrics`. A mesma métrica vale para Go e Python
  (`traces_span_metrics_calls_total`, `traces_span_metrics_duration_milliseconds_bucket`)
  e é a base do dashboard e dos alertas.
- **Correlação de logs.** Cada linha de log das aplicações tem `trace_id`. Do log no Loki
  dá para chegar ao trace no New Relic.

## Acesso

```bash
bash scripts/monitoring-info.sh      # URL/senha do Grafana e estado das Applications
```

| Ferramenta | Onde |
|---|---|
| Grafana | `http://<LB do ingress>/grafana/`, usuário `admin` e senha no Secret `grafana-admin` |
| Dashboard | Grafana → pasta **ToggleMaster** → *ToggleMaster — Saúde do Ecossistema* |
| Logs (Loki) | painel de logs do dashboard, ou Explore → Loki → `{k8s_namespace_name="togglemaster"}` |
| Prometheus | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090` |
| APM | New Relic → APM & Services → *Distributed tracing* e *Service map* |
| Self-healing | `kubectl -n monitoring logs deploy/self-healing -f` |

## Alertas (Grafana unified alerting, provisionados como código)

| Regra | Condição | Severidade | Destino |
|---|---|---|---|
| auth-service - erros HTTP 5xx acima de 5% | 5xx/total > 5% por 1 min | critical | PagerDuty + Discord + **self-healing** |
| Microsserviço com erros HTTP 5xx acima de 5% | demais serviços, por 2 min | warning | Discord |
| evaluation-service - latência p95 acima de 500 ms | por 5 min | warning | Discord |
| HPA no número máximo de réplicas | por 5 min | warning | Discord |
| Contêiner reiniciando repetidamente | > 3 restarts em 15 min | warning | Discord |

Para evitar *alert fatigue*, só o alerta que tem ação automática e impacto direto
(todas as chamadas autenticadas passam pelo auth-service) abre incidente e acorda alguém.
Os outros alertas viram mensagem no canal. As notificações são agrupadas por
alerta e serviço, e o intervalo de repetição é de 30 min no crítico e 4 h nos avisos.

## Runbook: auth-service 5xx

**Automático.** O Grafana chama o webhook do `self-healing`. O serviço confere o token e
o label `remediation=rollout-restart`, e então executa o equivalente a
`kubectl rollout restart deployment/auth-service -n togglemaster`. Em seguida acompanha o
rollout até os pods novos ficarem prontos e avisa no Discord. Há um cooldown de 5 min por
deployment e uma allowlist dos 5 serviços. Os alertas `DatasourceError` são ignorados.

**Se o alerta continuar Firing depois do restart:**

1. Veja os logs com erro no dashboard, filtrando por `auth-service`, ou rode
   `kubectl -n togglemaster logs deploy/auth-service`.
2. Abra um trace com erro no New Relic e confira se a falha está na query ao PostgreSQL
   (span `db`) ou no próprio handler.
3. Banco indisponível: confira o RDS `togglemaster-auth` no console da AWS. Um restart
   não resolve esse caso.
4. Release com defeito: faça `git revert` do commit de GitOps da imagem. O ArgoCD volta a
   versão anterior.

**Simulação (prova real do vídeo):** `bash scripts/chaos-demo.sh 50`. O script liga a
injeção de falhas do auth-service (`POST /admin/chaos`, protegido pela MASTER_KEY), que
devolve 500 em 50% das chamadas a `/validate`, e gera tráfego. A falha vive só na memória
do pod, então o restart feito pelo self-healing resolve o problema.

## Justificativa técnica

**OpenTelemetry com gateway e agent.**

- O SDK do OpenTelemetry nos 5 serviços deixa o código livre de fornecedor. Trocar o
  New Relic por outro APM é uma mudança só no exporter do collector.
- O gateway centraliza o roteamento, o enriquecimento com metadados do Kubernetes e a
  geração das métricas RED.
- O agent em DaemonSet cobre o requisito "todos os logs dos contêineres do cluster" sem
  alterar as aplicações: os serviços continuam logando em stdout.

**New Relic em vez de Datadog.**

- Recebe OTLP nativamente (`otlp.nr-data.net`), sem agente proprietário no cluster. O
  Datadog exigiria o Datadog Agent ou um exporter específico.
- O plano gratuito é permanente (100 GB/mês de ingestão, 1 usuário completo), sem prazo
  de trial.
- Monta o *Service map* e o *Distributed tracing* direto dos spans OTel, sem
  configuração extra.

**PagerDuty em vez de OpsGenie.**

- A Atlassian encerrou a venda do OpsGenie e anunciou o fim do produto, que migrou para
  o Jira Service Management.
- O PagerDuty tem plano gratuito para até 5 usuários.
- A integração com o Grafana é nativa (Events API v2): o incidente abre ao disparar e
  fecha sozinho quando o alerta resolve.

## Credenciais externas

Ficam fora do git. Passe-as como variáveis de ambiente antes do `run-all.sh` ou do apply
de `infra/platform`:

```bash
export NEW_RELIC_LICENSE_KEY=...          # New Relic → API Keys → INGEST - LICENSE
export PAGERDUTY_INTEGRATION_KEY=...      # PagerDuty → Service → Integrations → Events API v2
export DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...   # Canal → Integrações → Webhooks
# conta New Relic na UE: export NEW_RELIC_OTLP_ENDPOINT=https://otlp.eu01.nr-data.net
bash scripts/tf-init.sh platform && TF_VAR_new_relic_license_key="$NEW_RELIC_LICENSE_KEY" \
  TF_VAR_pagerduty_integration_key="$PAGERDUTY_INTEGRATION_KEY" \
  TF_VAR_discord_webhook_url="$DISCORD_WEBHOOK_URL" terraform -chdir=infra/platform apply
```

Sem uma das chaves, a stack sobe normalmente e só o envio para aquele destino falha. O
Terraform grava um valor marcador no lugar da chave.

- Depois de alterar a chave do New Relic, reinicie o gateway:
  `kubectl -n monitoring rollout restart deploy/otel-gateway`.
- Depois de alterar a chave do PagerDuty ou a URL do Discord, reinicie o Grafana e o
  self-healing:
  `kubectl -n monitoring rollout restart deploy/kube-prometheus-stack-grafana deploy/self-healing`.
