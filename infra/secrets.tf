# ─── Credenciais: nunca em texto plano no repositório ───────────────────────
# A senha dos bancos é gerada aqui (random_password) e guardada no state remoto
# (S3 criptografado) e no AWS Secrets Manager. Os Secrets do Kubernetes são
# criados pelo Terraform em infra/platform a partir destes valores.

resource "random_password" "db" {
  length  = 24
  special = false # evita caracteres que exigem URL-encoding na DATABASE_URL
}

resource "aws_secretsmanager_secret" "db" {
  count = var.create_secrets_manager_secret ? 1 : 0

  name                    = "${var.project_name}/rds"
  description             = "Credenciais dos bancos PostgreSQL do ToggleMaster (gerenciado pelo Terraform)"
  recovery_window_in_days = 0 # permite destroy/apply repetidos no Academy sem conflito de nome
}

resource "aws_secretsmanager_secret_version" "db" {
  count = var.create_secrets_manager_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.db[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    port     = module.rds.port
    hosts    = module.rds.addresses
    dbnames  = local.databases
  })
}
