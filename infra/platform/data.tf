data "aws_caller_identity" "current" {}

locals {
  tfstate_bucket = var.tfstate_bucket != "" ? var.tfstate_bucket : "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# Lê os outputs de infra/ direto do state remoto (endpoints, senha do banco, SQS...)
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = local.tfstate_bucket
    key    = "infra/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs
}

data "aws_eks_cluster" "this" {
  name = local.infra.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.infra.eks_cluster_name
}
