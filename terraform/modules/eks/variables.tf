# =============================================================================
# VARIABLES DEL MÓDULO EKS
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
  description = "ID de la VPC donde desplegar el cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs de las subnets privadas para los worker nodes"
  type        = list(string)
}

variable "cluster_version" {
  description = "Versión de Kubernetes"
  type        = string
  default     = "1.28"
}

variable "node_instance_types" {
  description = "Tipos de instancia para los worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Número deseado de nodos"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Número mínimo de nodos"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Número máximo de nodos"
  type        = number
  default     = 4
}

variable "node_capacity_type" {
  description = "ON_DEMAND o SPOT"
  type        = string
  default     = "SPOT"
}

variable "node_disk_size" {
  description = "Tamaño del disco de los nodos en GB"
  type        = number
  default     = 50
}

variable "enable_cluster_logging" {
  description = "Habilitar logging del control plane a CloudWatch"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "Tipos de logs del control plane a habilitar"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
