# Após o terraform apply, estes valores são lidos por infra/platform (via
# terraform_remote_state) e pelos scripts. Valores sensíveis só saem com
# `terraform output -raw <nome>`.

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = var.aws_region
}

output "lab_role_arn" {
  value       = local.role_arn
  description = "Role associada ao cluster e aos nodes"
}

# ─── EKS ────────────────────────────────────────────────────────────────────
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_status" {
  value = module.eks.cluster_status
}

output "eks_cluster_version" {
  value = module.eks.cluster_version
}

# ─── Bancos ─────────────────────────────────────────────────────────────────
output "db_username" {
  value = var.db_username
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "db_hosts" {
  value       = module.rds.addresses
  description = "Host (sem porta) de cada RDS, por serviço: auth, flag, targeting"
}

output "db_names" {
  value = local.databases
}

output "db_port" {
  value = module.rds.port
}

output "auth_db_endpoint" {
  value = module.rds.endpoints["auth"]
}

output "flag_db_endpoint" {
  value = module.rds.endpoints["flag"]
}

output "targeting_db_endpoint" {
  value = module.rds.endpoints["targeting"]
}

output "redis_endpoint" {
  value = module.elasticache.endpoint
}

output "redis_port" {
  value = module.elasticache.port
}

output "dynamodb_table" {
  value = module.dynamodb.table_name
}

output "secrets_manager_secret_arn" {
  value = var.create_secrets_manager_secret ? aws_secretsmanager_secret.db[0].arn : null
}

# ─── Mensageria ─────────────────────────────────────────────────────────────
output "sqs_url" {
  value = module.sqs.queue_url
}

output "sqs_arn" {
  value = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  value = module.sqs.dlq_url
}

# ─── ECR ────────────────────────────────────────────────────────────────────
output "ecr_registry" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  description = "Registry usado pelo CI: <registry>/togglemaster/<serviço>:<tag>"
}

output "ecr_urls" {
  value = module.ecr.repository_urls
}
