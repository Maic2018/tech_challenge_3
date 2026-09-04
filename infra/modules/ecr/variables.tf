variable "project_name" {
  type = string
}

variable "services" {
  type = list(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE permite re-executar o pipeline do mesmo commit; IMMUTABLE é mais rígido"
  type        = string
  default     = "MUTABLE"
}

variable "keep_last_images" {
  type    = number
  default = 10
}
