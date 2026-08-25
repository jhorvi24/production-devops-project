# =============================================================================
# VARIABLES DEL MÓDULO RDS
# =============================================================================

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs de las subnets privadas para el subnet group"
  type        = list(string)
}

variable "instance_class" {
  description = "Clase de instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Almacenamiento en GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Máximo almacenamiento para autoscaling de storage"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "production_sim"
}

variable "engine_version" {
  description = "Versión de PostgreSQL"
  type        = string
  default     = "16.4"
}

variable "multi_az" {
  description = "Habilitar Multi-AZ (alta disponibilidad)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Días de retención de backups automáticos"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Protección contra borrado accidental"
  type        = bool
  default     = false
}

variable "allowed_security_groups" {
  description = "Security Groups permitidos para conectarse a RDS"
  type        = list(string)
  default     = []
}

variable "performance_insights_enabled" {
  description = "Habilitar Performance Insights (diagnóstico de queries lentas)"
  type        = bool
  default     = true
}
