# Cluster EKS + Managed Node Group usando uma role existente (LabRole no Academy).

# ─── SECURITY GROUP ADICIONAL DOS NODES ─────────────────────────────────────
resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security Group adicional dos nodes EKS (referenciado por RDS e Redis)"
  vpc_id      = var.vpc_id

  ingress {
    description = "Trafego entre os proprios nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Saida liberada (ECR, APIs AWS via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-eks-nodes-sg" }
}

# ─── LAUNCH TEMPLATE ────────────────────────────────────────────────────────
# Corrige permanentemente o IMDS hop limit: sem hop_limit=2 os pods não alcançam
# as credenciais da LabRole via metadata da instância e as chamadas ao SQS/DynamoDB
# falham com "NoCredentialProviders".
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.project_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-node" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── CLUSTER ────────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [aws_security_group.nodes.id]
  }

  tags = { Name = var.cluster_name }
}

# ─── NODE GROUP ─────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = var.role_arn
  subnet_ids      = var.node_subnet_ids
  ami_type        = var.ami_type
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  tags = { Name = "${var.project_name}-nodes" }

  depends_on = [aws_eks_cluster.this]
}
