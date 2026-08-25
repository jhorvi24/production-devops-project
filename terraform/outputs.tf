# =============================================================================
# OUTPUTS GLOBALES - Información útil después de terraform apply
# =============================================================================

# VPC
output "vpc_id" {
  description = "ID de la VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs de subnets privadas"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs de subnets públicas"
  value       = module.vpc.public_subnet_ids
}

# EKS
output "eks_cluster_name" {
  description = "Nombre del cluster EKS"
  value       = var.create_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint del cluster EKS"
  value       = var.create_eks ? module.eks[0].cluster_endpoint : null
}

output "eks_kubeconfig_command" {
  description = "Comando para configurar kubectl"
  value       = var.create_eks ? "aws eks update-kubeconfig --name ${module.eks[0].cluster_name} --region ${var.aws_region}" : null
}

# RDS
output "rds_endpoint" {
  description = "Endpoint de conexión a RDS"
  value       = var.create_rds ? module.rds[0].endpoint : null
}

output "rds_db_name" {
  description = "Nombre de la base de datos"
  value       = var.create_rds ? module.rds[0].db_name : null
}
