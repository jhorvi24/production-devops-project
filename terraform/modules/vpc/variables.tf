# =============================================================================
# VARIABLES DEL MÓDULO VPC
# =============================================================================

variable "project_name" {
  description = "Nombre del proyecto para prefijo de recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block para la VPC (ejemplo: 10.0.0.0/16 = 65,536 IPs)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Lista de AZs donde desplegar subnets"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = <<-EOT
    Si es true, usa un solo NAT Gateway (ahorra ~$64/mes).
    En producción real, deberías usar uno por AZ para HA.
    En dev/staging, uno solo es suficiente.
  EOT
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Habilitar VPC Flow Logs para auditoría de tráfico de red"
  type        = bool
  default     = false
}
