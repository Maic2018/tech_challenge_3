variable "project_name" {
  type = string
}

variable "databases" {
  description = "Mapa <chave do serviço> => <nome do banco>. Ex: { auth = \"auth_db\" }"
  type        = map(string)
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security Groups autorizados a conectar na porta do PostgreSQL"
  type        = list(string)
  default     = []
}

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "15"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "port" {
  type    = number
  default = 5432
}
