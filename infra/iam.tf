# ─── Role do EKS (cluster + nodes) ──────────────────────────────────────────
# Criada pelo Terraform e usada pelo control plane, pelos nodes e, via IMDS,
# pelos pods que falam com SQS e DynamoDB. Sai junto no terraform destroy.

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
  name               = "${var.project_name}-eks-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.eks.name
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
  name   = "${var.project_name}-app-access"
  role   = aws_iam_role.eks.id
  policy = data.aws_iam_policy_document.app.json
}
