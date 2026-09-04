variable "project_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS (usado nas tags de descoberta de subnets)"
  type        = string
}
