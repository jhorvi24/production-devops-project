# =============================================================================
# OUTPUTS DEL MÓDULO VPC
# =============================================================================
# Los outputs permiten que otros módulos (EKS, RDS) referencien estos recursos.
# Es el mecanismo de comunicación entre módulos en Terraform.
# =============================================================================

output "vpc_id" {
  description = "ID de la VPC creada"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block de la VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas (para ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (para EKS, RDS)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDRs de las subnets públicas"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDRs de las subnets privadas"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ips" {
  description = "IPs elásticas de los NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "ID del Internet Gateway"
  value       = aws_internet_gateway.main.id
}
