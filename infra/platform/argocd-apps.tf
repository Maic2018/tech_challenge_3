# ─── Registro das aplicações no ArgoCD ──────────────────────────────────────
# Um ApplicationSet gera uma Application por pasta em gitops/apps/* (os 5
# microsserviços) e uma Application separada cuida de gitops/platform
# (ConfigMap e Ingress). Sync automático com prune + selfHeal: o que está no git
# é o que roda no cluster.

# Credencial do repositório (apenas se for privado)
resource "kubernetes_secret_v1" "gitops_repo" {
  count = var.gitops_repo_token != "" ? 1 : 0

  metadata {
    name      = "${var.project_name}-gitops-repo"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = var.gitops_repo_username
    password = var.gitops_repo_token
  }

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "services_applicationset" {
  yaml_body = templatefile("${path.module}/argocd/applicationset-services.yaml", {
    repo_url  = var.gitops_repo_url
    revision  = var.gitops_revision
    namespace = var.app_namespace
  })

  depends_on = [
    helm_release.argocd,
    helm_release.ingress_nginx,
    helm_release.metrics_server,
    kubernetes_secret_v1.auth,
    kubernetes_secret_v1.flag,
    kubernetes_secret_v1.targeting,
    kubernetes_secret_v1.evaluation,
    kubernetes_secret_v1.analytics,
    kubernetes_secret_v1.gitops_repo,
  ]
}

resource "kubectl_manifest" "platform_application" {
  yaml_body = templatefile("${path.module}/argocd/application-platform.yaml", {
    repo_url  = var.gitops_repo_url
    revision  = var.gitops_revision
    namespace = var.app_namespace
  })

  depends_on = [
    helm_release.argocd,
    helm_release.ingress_nginx,
    kubernetes_secret_v1.gitops_repo,
  ]
}
