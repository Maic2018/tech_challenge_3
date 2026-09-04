variable "project_name" {
  type = string
}

variable "message_retention_seconds" {
  type    = number
  default = 86400 # 1 dia
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}
