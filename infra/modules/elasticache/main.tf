# Cluster ElastiCache Redis (cache do hot path do evaluation-service).

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.project_name}-redis-sg"
  description = "Redis acessivel apenas de dentro da VPC (nodes EKS)"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project_name}-redis-sg" }
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
  description       = "Recursos internos da VPC"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = var.parameter_group_name
  port                 = var.port

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  tags = { Name = "${var.project_name}-redis" }
}
