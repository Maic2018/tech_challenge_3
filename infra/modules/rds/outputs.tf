output "endpoints" {
  description = "host:porta de cada instância, por chave"
  value       = { for k, db in aws_db_instance.this : k => db.endpoint }
}

output "addresses" {
  description = "host (sem porta) de cada instância, por chave"
  value       = { for k, db in aws_db_instance.this : k => db.address }
}

output "port" {
  value = var.port
}

output "security_group_id" {
  value = aws_security_group.this.id
}
