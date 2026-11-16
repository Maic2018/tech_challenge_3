data "kubernetes_service_v1" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

data "kubernetes_service_v1" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}

data "kubernetes_secret_v1" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_url" {
  value       = "http://${try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname, "pendente")}"
  description = "UI do ArgoCD (usuário admin)"
}

output "argocd_admin_password" {
  value     = try(data.kubernetes_secret_v1.argocd_initial_admin.data["password"], "")
  sensitive = true
}

output "app_url" {
  value       = "http://${try(data.kubernetes_service_v1.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname, "pendente")}"
  description = "Load Balancer do Ingress NGINX (rotas /auth, /flags, /targeting, /evaluate, /analytics)"
}

output "app_namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "master_key" {
  value     = random_password.master_key.result
  sensitive = true
}

output "service_api_key" {
  value     = local.service_api_key
  sensitive = true
}

# ─── Fase 4 ─────────────────────────────────────────────────────────────────
output "grafana_url" {
  value       = "http://${try(data.kubernetes_service_v1.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname, "pendente")}/grafana/"
  description = "Grafana (usuário admin) publicado no Load Balancer do Ingress NGINX"
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}

output "observability_integrations" {
  value = {
    new_relic = nonsensitive(var.new_relic_license_key != "") ? "configurado (${var.new_relic_otlp_endpoint})" : "NÃO configurado"
    pagerduty = nonsensitive(var.pagerduty_integration_key != "") ? "configurado" : "NÃO configurado"
    discord   = nonsensitive(var.discord_webhook_url != "") ? "configurado" : "NÃO configurado"
  }
  description = "Quais integrações externas receberam credencial"
}
