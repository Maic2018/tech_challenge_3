variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "role_arn" {
  description = "Role usada pelo control plane e pelos nodes (LabRole no AWS Academy)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "cluster_subnet_ids" {
  description = "Subnets (públicas + privadas) usadas pelo control plane"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets privadas onde os nodes são criados"
  type        = list(string)
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_min_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "ami_type" {
  description = "AMI dos nodes (AL2023 é a única suportada a partir do EKS 1.33)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a falar com o endpoint público da API do EKS. Restrinja ao seu IP quando possível (ex: [\"203.0.113.10/32\"])."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
