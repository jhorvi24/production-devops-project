# =============================================================================
# OUTPUTS DEL MÓDULO EKS
# =============================================================================

output "cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint del API server de Kubernetes"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Certificado CA del cluster (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group del cluster (control plane)"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group de los worker nodes"
  value       = aws_security_group.node.id
}

output "cluster_oidc_issuer_url" {
  description = "URL del OIDC issuer (para IRSA)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN del OIDC provider (para IRSA)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_role_arn" {
  description = "ARN del IAM role de los worker nodes"
  value       = aws_iam_role.node.arn
}
