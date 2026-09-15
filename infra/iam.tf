# ─── Role própria (conta pessoal, Opção B) ──────────────────────────────────
# No AWS Academy a LabRole já existe e é lida via data source (main.tf). Numa
# conta pessoal ela não existe: com create_iam_role = true o Terraform cria uma
# role equivalente, usada pelo cluster, pelos nodes e, via IMDS, pelos pods que
# falam com SQS e DynamoDB. Sai junto no terraform destroy.

data "aws_iam_policy_document" "eks_assume" {
  count = var.create_iam_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks" {
  count = var.create_iam_role ? 1 : 0

  name               = "${var.project_name}-eks-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume[0].json
}

resource "aws_iam_role_policy_attachment" "eks" {
  for_each = var.create_iam_role ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])

  role       = aws_iam_role.eks[0].name
  policy_arn = each.value
}

# Acesso da aplicação: evaluation publica na fila, analytics consome e grava no DynamoDB
data "aws_iam_policy_document" "app" {
  count = var.create_iam_role ? 1 : 0

  statement {
    actions = [
      "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
      "sqs:GetQueueAttributes", "sqs:GetQueueUrl",
    ]
    resources = ["arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-*"]
  }

  statement {
    actions = [
      "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan",
      "dynamodb:DescribeTable", "dynamodb:CreateTable",
    ]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"]
  }
}

resource "aws_iam_role_policy" "app" {
  count = var.create_iam_role ? 1 : 0

  name   = "${var.project_name}-app-access"
  role   = aws_iam_role.eks[0].id
  policy = data.aws_iam_policy_document.app[0].json
}
