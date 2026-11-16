# ─── Role do EKS (cluster + nodes) ──────────────────────────────────────────
# Usada pelo control plane, pelos nodes e, via IMDS, pelos pods que falam com SQS e
# DynamoDB. Dois modos:
#   - conta própria (padrão): o Terraform cria a role e as policies abaixo;
#   - AWS Academy: existing_role_name = "LabRole". O Learner Lab não permite criar
#     roles nem anexar policies, então a LabRole (que já tem EKS/EC2/ECR/SQS/DynamoDB)
#     é apenas lida e nenhum recurso de IAM é criado.

locals {
  create_role  = var.existing_role_name == ""
  eks_role_arn = local.create_role ? aws_iam_role.eks[0].arn : data.aws_iam_role.existing[0].arn
}

data "aws_iam_role" "existing" {
  count = local.create_role ? 0 : 1
  name  = var.existing_role_name
}

data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks" {
  count              = local.create_role ? 1 : 0
  name               = "${var.project_name}-eks-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks" {
  for_each = local.create_role ? toset([
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
  count  = local.create_role ? 1 : 0
  name   = "${var.project_name}-app-access"
  role   = aws_iam_role.eks[0].id
  policy = data.aws_iam_policy_document.app.json
}
