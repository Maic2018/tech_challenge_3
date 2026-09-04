variable "table_name" {
  type = string
}

variable "hash_key" {
  description = "Chave primária usada pelo analytics-service"
  type        = string
  default     = "event_id"
}
