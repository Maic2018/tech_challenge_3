# ─── Fase 4: observabilidade (namespace, Secrets e registro no ArgoCD) ──────
# A stack em si (kube-prometheus-stack, Loki, OTel Collector, dashboard, alertas e
# self-healing) é GitOps: Applications do ArgoCD em gitops/monitoring/apps. O Terraform
# só cria o que não pode ir para o git — as credenciais — e registra a Application raiz.

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/part-of" = var.project_name
    }
  }
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

# Token compartilhado entre o webhook do Grafana e o serviço de self-healing
resource "random_password" "self_healing_token" {
  length  = 40
  special = false
}

locals {
  # Sem credencial informada, o valor vira um marcador: o Grafana sobe normalmente
  # (contact point com campo vazio invalida o provisionamento) e só o envio falha.
  pagerduty_integration_key = var.pagerduty_integration_key != "" ? var.pagerduty_integration_key : "nao-configurado"
  discord_webhook_url       = var.discord_webhook_url != "" ? var.discord_webhook_url : "https://discord.com/api/webhooks/nao-configurado"
  new_relic_license_key     = var.new_relic_license_key != "" ? var.new_relic_license_key : "nao-configurado"

  ingress_hostname = try(data.kubernetes_service_v1.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname, "")
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# Variáveis de ambiente do Grafana, interpoladas nos contact points provisionados
# (gitops/monitoring/manifests/grafana-alerting.yaml)
resource "kubernetes_secret_v1" "grafana_alerting" {
  metadata {
    name      = "grafana-alerting"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = merge(
    {
      PAGERDUTY_INTEGRATION_KEY = local.pagerduty_integration_key
      DISCORD_WEBHOOK_URL       = local.discord_webhook_url
      SELF_HEALING_TOKEN        = random_password.self_healing_token.result
    },
    # Links das notificações (PagerDuty/Discord) apontando para o Grafana publicado no LB
    local.ingress_hostname != "" ? { GF_SERVER_ROOT_URL = "http://${local.ingress_hostname}/grafana/" } : {},
  )
}

resource "kubernetes_secret_v1" "otel_newrelic" {
  metadata {
    name      = "otel-newrelic"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    NEW_RELIC_LICENSE_KEY   = local.new_relic_license_key
    NEW_RELIC_OTLP_ENDPOINT = var.new_relic_otlp_endpoint
  }
}

resource "kubernetes_secret_v1" "self_healing" {
  metadata {
    name      = "self-healing"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    WEBHOOK_TOKEN       = random_password.self_healing_token.result
    DISCORD_WEBHOOK_URL = local.discord_webhook_url
  }
}

# Application raiz (app-of-apps) que sincroniza gitops/monitoring/apps/*
resource "kubectl_manifest" "monitoring_application" {
  yaml_body = templatefile("${path.module}/argocd/application-monitoring.yaml", {
    repo_url = var.gitops_repo_url
    revision = var.gitops_revision
  })

  depends_on = [
    helm_release.argocd,
    helm_release.ingress_nginx,
    kubernetes_secret_v1.grafana_admin,
    kubernetes_secret_v1.grafana_alerting,
    kubernetes_secret_v1.otel_newrelic,
    kubernetes_secret_v1.self_healing,
    kubernetes_secret_v1.gitops_repo,
  ]
}
