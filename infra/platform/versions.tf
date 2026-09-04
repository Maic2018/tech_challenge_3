# ─────────────────────────────────────────────────────────────────────────────
# ToggleMaster – Plataforma no cluster (Fase 3)
# Segundo root module, aplicado DEPOIS de infra/: instala ArgoCD, ingress-nginx e
# metrics-server via Helm, cria o namespace e os Secrets da aplicação a partir dos
# outputs do Terraform (nada de credencial em arquivo de texto) e registra as
# Applications do ArgoCD que apontam para a pasta gitops/ deste repositório.
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Mesmo bucket do state da infra, chave diferente.
  #   terraform init -backend-config="bucket=togglemaster-tfstate-<ACCOUNT_ID>"
  # (scripts/tf-init.sh platform)
  backend "s3" {
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
