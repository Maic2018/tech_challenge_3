output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_status" {
  value = aws_eks_cluster.this.status
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "node_security_group_ids" {
  description = "SG adicional dos nodes + SG do cluster (o que a AWS anexa às ENIs dos nodes)"
  value = [
    aws_security_group.nodes.id,
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
  ]
}

output "node_group_name" {
  value = aws_eks_node_group.this.node_group_name
}
