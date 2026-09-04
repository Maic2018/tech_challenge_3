# VPC, subnets públicas/privadas em 2 AZs, Internet Gateway, NAT Gateway e route tables.

locals {
  azs = ["${var.aws_region}a", "${var.aws_region}b"]

  public_subnets = {
    a = { cidr = cidrsubnet(var.vpc_cidr, 8, 1), az = local.azs[0] }
    b = { cidr = cidrsubnet(var.vpc_cidr, 8, 2), az = local.azs[1] }
  }

  private_subnets = {
    a = { cidr = cidrsubnet(var.vpc_cidr, 8, 3), az = local.azs[0] }
    b = { cidr = cidrsubnet(var.vpc_cidr, 8, 4), az = local.azs[1] }
  }
}

# ─── VPC ─────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ─── SUBNETS PÚBLICAS (Load Balancers, NAT) ──────────────────────────────────
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false # só NAT e Load Balancers ficam aqui; ninguém precisa de IP público automático

  tags = {
    Name                                        = "${var.project_name}-public-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# ─── SUBNETS PRIVADAS (nodes EKS, RDS, Redis) ───────────────────────────────
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name                                        = "${var.project_name}-private-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# ─── INTERNET GATEWAY + ROTA PÚBLICA ────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ─── NAT GATEWAY + ROTA PRIVADA ─────────────────────────────────────────────
# Nodes em subnet privada precisam do NAT para puxar imagens do ECR e falar com
# as APIs da AWS (SQS, DynamoDB) sem ficarem expostos na internet.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id
  tags          = { Name = "${var.project_name}-nat" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
