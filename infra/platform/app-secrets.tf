# ─── Namespace + Secrets da aplicação ───────────────────────────────────────
# Os valores vêm do state remoto da infra (RDS, Redis, SQS) e de geradores
# aleatórios. Nenhuma credencial passa por arquivo de texto ou pelo repositório
# GitOps: os manifestos só referenciam os Secrets pelo nome.

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/part-of" = var.project_name
    }
  }
}

# MASTER_KEY do auth-service (protege POST /admin/keys)
resource "random_password" "master_key" {
  length  = 32
  special = false
}

# Chave de API interna usada pelo evaluation-service para falar com flag/targeting.
# Mesmo formato gerado pelo auth-service (tm_key_ + 32 bytes em hex). O hash é
# inserido no banco pelo run-migrations.sh.
resource "random_id" "service_api_key" {
  byte_length = 32
}

locals {
  db_urls = {
    for key, host in local.infra.db_hosts :
    key => "postgres://${local.infra.db_username}:${local.infra.db_password}@${host}:${local.infra.db_port}/${local.infra.db_names[key]}?sslmode=require"
  }
  redis_url       = "redis://${local.infra.redis_endpoint}:${local.infra.redis_port}"
  service_api_key = "tm_key_${random_id.service_api_key.hex}"
}

resource "kubernetes_secret_v1" "auth" {
  metadata {
    name      = "auth-service-secret"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    DATABASE_URL = local.db_urls["auth"]
    MASTER_KEY   = random_password.master_key.result
  }
}

resource "kubernetes_secret_v1" "flag" {
  metadata {
    name      = "flag-service-secret"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    DATABASE_URL = local.db_urls["flag"]
  }
}

resource "kubernetes_secret_v1" "targeting" {
  metadata {
    name      = "targeting-service-secret"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    DATABASE_URL = local.db_urls["targeting"]
  }
}

resource "kubernetes_secret_v1" "evaluation" {
  metadata {
    name      = "evaluation-service-secret"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    REDIS_URL       = local.redis_url
    AWS_SQS_URL     = local.infra.sqs_url
    SERVICE_API_KEY = local.service_api_key
  }
}

resource "kubernetes_secret_v1" "analytics" {
  metadata {
    name      = "analytics-service-secret"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    AWS_SQS_URL = local.infra.sqs_url
  }
}
