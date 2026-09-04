variable "project_name" {
  type = string
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
  type    = list(string)
  default = []
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "parameter_group_name" {
  type    = string
  default = "default.redis7"
}

variable "port" {
  type    = number
  default = 6379
}
