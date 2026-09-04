# Tabela de eventos de analytics (consumida pelo analytics-service).
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST" # paga só pelo que usa
  hash_key     = var.hash_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  tags = { Name = var.table_name }
}
