# ─────────────────────────────────────────────────────────────────────────────
# ToggleMaster – Infraestrutura AWS (Tech Challenge Fase 3)
# Root module: apenas orquestra os módulos em ./modules. "Se não está no código,
# não existe": nenhum recurso é criado pelo console.
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend remoto (requisito da Fase 3): o tfstate NUNCA fica local.
  # O bucket é versionado e criptografado; o lock usa use_lockfile (Terraform >= 1.10),
  # sem precisar de tabela DynamoDB para lock.
  # O nome do bucket depende do Account ID (que muda no AWS Academy), por isso é
  # informado no init:
  #   terraform init -backend-config="bucket=togglemaster-tfstate-<ACCOUNT_ID>"
  # (scripts/tf-init.sh infra faz isso automaticamente)
  backend "s3" {
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Phase     = "3"
    }
  }
}

data "aws_caller_identity" "current" {}

# ─── LabRole (AWS Academy) ───────────────────────────────────────────────────
# O Academy não permite criar Roles/Policies de IAM. A LabRole existente é
# importada via data source (Opção A do enunciado) e associada ao cluster e aos
# node groups. Em conta pessoal (Opção B), informe var.lab_role_arn.
data "aws_iam_role" "lab" {
  count = var.lab_role_arn == "" ? 1 : 0
  name  = var.lab_role_name
}

locals {
  cluster_name = "${var.project_name}-cluster"
  role_arn     = var.lab_role_arn != "" ? var.lab_role_arn : data.aws_iam_role.lab[0].arn

  # Um banco PostgreSQL isolado por serviço que precisa de dados relacionais
  databases = {
    auth      = "auth_db"
    flag      = "flag_db"
    targeting = "targeting_db"
  }
}

# ─── 1. Networking ──────────────────────────────────────────────────────────
module "network" {
  source = "./modules/network"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
  cluster_name = local.cluster_name
}

# ─── 2. Cluster EKS + Node Group (LabRole) ──────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  cluster_name        = local.cluster_name
  cluster_version     = var.eks_version
  role_arn            = local.role_arn
  vpc_id              = module.network.vpc_id
  cluster_subnet_ids  = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  node_subnet_ids     = module.network.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
  public_access_cidrs = var.eks_public_access_cidrs
}

# ─── 3. Bancos de dados ─────────────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  project_name               = var.project_name
  databases                  = local.databases
  vpc_id                     = module.network.vpc_id
  vpc_cidr                   = module.network.vpc_cidr
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = module.eks.node_security_group_ids
  username                   = var.db_username
  password                   = random_password.db.result
  instance_class             = var.db_instance_class
  engine_version             = var.db_engine_version
}

module "elasticache" {
  source = "./modules/elasticache"

  project_name               = var.project_name
  vpc_id                     = module.network.vpc_id
  vpc_cidr                   = module.network.vpc_cidr
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = module.eks.node_security_group_ids
  node_type                  = var.redis_node_type
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = var.dynamodb_table_name
}

# ─── 4. Mensageria ──────────────────────────────────────────────────────────
module "sqs" {
  source = "./modules/sqs"

  project_name = var.project_name
}

# ─── 5. Repositórios de imagens ─────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  services     = var.services
}
