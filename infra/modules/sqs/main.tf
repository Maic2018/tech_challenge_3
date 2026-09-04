# Fila de eventos de avaliação (evaluation-service -> analytics-service) + DLQ.

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-events-dlq"
  message_retention_seconds = 1209600 # 14 dias para investigar mensagens com falha
  tags                      = { Name = "${var.project_name}-events-dlq" }
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.project_name}-events"
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = "${var.project_name}-events" }
}
