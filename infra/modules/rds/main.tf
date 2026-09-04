# N instâncias RDS PostgreSQL (uma por serviço), em subnets privadas.

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.project_name}-db-subnet-group" }
}

# Regras como recursos separados (aws_vpc_security_group_*_rule): assim o RDS
# depende só do SG (criado na hora) e é provisionado em paralelo com o EKS,
# mesmo que a regra referencie o SG do cluster, conhecido só depois do apply.
resource "aws_security_group" "this" {
  name        = "${var.project_name}-rds-sg"
  description = "PostgreSQL acessivel apenas de dentro da VPC (nodes EKS)"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project_name}-rds-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "Nodes EKS"
}

resource "aws_vpc_security_group_ingress_rule" "from_vpc" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "Recursos internos da VPC (ex: job de migracao)"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier        = "${var.project_name}-${each.key}-db"
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name  = each.value
  username = var.username
  password = var.password
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  publicly_accessible = false
  skip_final_snapshot = true # ambiente de laboratório: permite destroy sem snapshot
  apply_immediately   = true

  tags = { Name = "${var.project_name}-${each.key}-db" }
}
