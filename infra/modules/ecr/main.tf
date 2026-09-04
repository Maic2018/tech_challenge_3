# Um repositório ECR por microsserviço. O CI publica imagens com a tag do commit
# (ex: v1.0.0-a1b2c3d) e o ECR faz um scan adicional no push.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true # laboratório: permite destroy com imagens dentro

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = each.key }
}

# Mantém só as últimas imagens para não acumular custo de armazenamento.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter apenas as ultimas ${var.keep_last_images} imagens"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_images
      }
      action = { type = "expire" }
    }]
  })
}
