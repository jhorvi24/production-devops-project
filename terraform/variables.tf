# =============================================================================
# VARIABLES GLOBALES - Parámetros configurables del proyecto
# =============================================================================
#
# ¿POR QUÉ VARIABLES?
# - Reutilización: El mismo código para dev y prod, solo cambian valores
# - Seguridad: Los valores sensibles no se hardcodean en el código
# - Flexibilidad: Puedes cambiar configuración sin modificar lógica
#
# CONVENCIÓN DE NOMBRES:
# - Prefijo por dominio: vpc_, eks_, rds_
# - Nombres descriptivos en snake_case
# - Siempre incluir description y type
# - Valores por defecto solo cuando tiene sentido (no para prod)
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "Región de AWS donde se despliega la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de despliegue (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El ambiente debe ser: dev, staging, o prod."
  }
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en recursos"
  type        = string
  default     = "production-sim"
}

# -----------------------------------------------------------------------------
# Feature Flags
# -----------------------------------------------------------------------------
variable "create_eks" {
  description = "Si se debe crear el cluster EKS (útil para desarrollo incremental)"
  type        = bool
  default     = true
}

variable "create_rds" {
  description = "Si se debe crear la instancia RDS"
  type        = bool
  default     = true
}

variable "create_elasticache" {
  description = "Si se debe crear el cluster de ElastiCache"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Lista de Availability Zones a usar"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------
variable "eks_cluster_version" {
  description = "Versión de Kubernetes para el cluster EKS"
  type        = string
  default     = "1.28"
}

variable "eks_node_instance_types" {
  description = "Tipos de instancia para los nodos worker de EKS"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "Número deseado de nodos worker"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Número mínimo de nodos worker"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Número máximo de nodos worker"
  type        = number
  default     = 4
}

variable "eks_node_capacity_type" {
  description = "Tipo de capacidad: ON_DEMAND o SPOT"
  type        = string
  default     = "SPOT"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_node_capacity_type)
    error_message = "Debe ser ON_DEMAND o SPOT."
  }
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------
variable "rds_instance_class" {
  description = "Clase de instancia para RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Almacenamiento asignado en GB"
  type        = number
  default     = 20
}

variable "rds_db_name" {
  description = "Nombre de la base de datos inicial"
  type        = string
  default     = "production_sim"
}

# -----------------------------------------------------------------------------
# Tags adicionales
# -----------------------------------------------------------------------------
variable "additional_tags" {
  description = "Tags adicionales para aplicar a todos los recursos"
  type        = map(string)
  default     = {}
}
