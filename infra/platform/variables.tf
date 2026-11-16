variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "togglemaster"
}

variable "tfstate_bucket" {
  description = "Bucket do state da infra. Vazio = <project_name>-tfstate-<account_id>"
  type        = string
  default     = ""
}

variable "app_namespace" {
  description = "Namespace onde o ArgoCD implanta os 5 microsserviços"
  type        = string
  default     = "togglemaster"
}

# ─── GitOps ─────────────────────────────────────────────────────────────────
variable "gitops_repo_url" {
  description = "Repositório que o ArgoCD monitora (pasta gitops/ deste monorepo)"
  type        = string
  default     = "https://github.com/Maic2018/tech_challenge_3.git"
}

variable "gitops_revision" {
  description = "Branch/tag acompanhada pelo ArgoCD"
  type        = string
  default     = "main"
}

variable "gitops_repo_username" {
  description = "Usuário para repositório privado (qualquer valor com token do GitHub)"
  type        = string
  default     = "git"
}

variable "gitops_repo_token" {
  description = "Token de leitura do repositório (só necessário se o repositório for privado)"
  type        = string
  default     = ""
  sensitive   = true
}

# ─── Versões dos charts (vazio = última versão publicada) ───────────────────
variable "argocd_chart_version" {
  type    = string
  default = ""
}

variable "ingress_nginx_chart_version" {
  type    = string
  default = ""
}

variable "metrics_server_chart_version" {
  type    = string
  default = ""
}

# ─── Fase 4: observabilidade (credenciais; nunca em arquivo versionado) ─────
# Passe por variável de ambiente: TF_VAR_new_relic_license_key=... (o run-all.sh faz isso
# a partir de NEW_RELIC_LICENSE_KEY, PAGERDUTY_INTEGRATION_KEY e DISCORD_WEBHOOK_URL).
variable "new_relic_license_key" {
  description = "Ingest License Key do New Relic (APM). Vazio = exportação para o New Relic desativada na prática"
  type        = string
  default     = ""
  sensitive   = true
}

variable "new_relic_otlp_endpoint" {
  description = "Endpoint OTLP do New Relic (US: https://otlp.nr-data.net | EU: https://otlp.eu01.nr-data.net)"
  type        = string
  default     = "https://otlp.nr-data.net"
}

variable "pagerduty_integration_key" {
  description = "Integration Key (Events API v2) do serviço no PagerDuty"
  type        = string
  default     = ""
  sensitive   = true
}

variable "discord_webhook_url" {
  description = "Webhook do canal do Discord que recebe as notificações (ChatOps)"
  type        = string
  default     = ""
  sensitive   = true
}
