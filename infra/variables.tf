variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto (prefixo de todos os recursos)"
  type        = string
  default     = "togglemaster"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ─── IAM (AWS Academy x conta pessoal) ──────────────────────────────────────
variable "lab_role_name" {
  description = "Nome da role existente usada pelo EKS e pelos nodes (AWS Academy: LabRole). Lida via data source."
  type        = string
  default     = "LabRole"
}

variable "lab_role_arn" {
  description = "Opcional. ARN de uma role própria (conta pessoal). Se vazio, usa a data source da var.lab_role_name."
  type        = string
  default     = ""
}

# ─── EKS ────────────────────────────────────────────────────────────────────
variable "eks_version" {
  description = "Versão do Kubernetes no EKS"
  type        = string
  default     = "1.33"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint público do EKS (0.0.0.0/0 no Academy, pois o IP de saída muda; restrinja ao seu IP quando possível)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Tipos de instância dos nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

# ─── Dados ──────────────────────────────────────────────────────────────────
variable "db_username" {
  description = "Usuário master dos bancos PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Versão major do PostgreSQL (a AWS escolhe a minor mais recente)"
  type        = string
  default     = "15"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "dynamodb_table_name" {
  description = "Nome exato esperado pelo analytics-service"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "create_secrets_manager_secret" {
  description = "Guarda as credenciais do RDS no AWS Secrets Manager (desative se a conta não permitir)"
  type        = bool
  default     = true
}

# ─── Microsserviços ─────────────────────────────────────────────────────────
variable "services" {
  description = "Os 5 microsserviços do ToggleMaster (um repositório ECR para cada)"
  type        = list(string)
  default     = ["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"]
}
