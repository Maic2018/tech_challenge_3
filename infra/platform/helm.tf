# ─── Componentes de plataforma via Helm (provider helm) ─────────────────────

# Metrics Server: necessário para o HPA ler CPU dos pods
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = var.metrics_server_chart_version != "" ? var.metrics_server_chart_version : null

  wait    = true
  timeout = 600
}

# Ingress NGINX: cria o Load Balancer de entrada dos microsserviços
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = var.ingress_nginx_chart_version != "" ? var.ingress_nginx_chart_version : null

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  wait    = true
  timeout = 600
}

# ArgoCD: motor de GitOps. UI exposta por Load Balancer (modo insecure/HTTP,
# suficiente para o laboratório). Dex e notifications desativados para economizar pods.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = var.argocd_chart_version != "" ? var.argocd_chart_version : null

  values = [yamlencode({
    configs = {
      params = {
        "server.insecure" = true
      }
      cm = {
        "timeout.reconciliation" = "60s" # verifica o repositório a cada 60s
      }
    }
    server = {
      service = {
        type = "LoadBalancer"
      }
    }
    dex = {
      enabled = false
    }
    notifications = {
      enabled = false
    }
  })]

  wait    = true
  timeout = 900
}
