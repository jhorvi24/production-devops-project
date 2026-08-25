# =============================================================================
# AMBIENTE PROD - Configuración de producción
# =============================================================================
#
# DIFERENCIAS CLAVE CON DEV:
# - On-Demand instances (no Spot) → Sin interrupciones
# - Multi-AZ para RDS → Failover automático
# - 3 NAT Gateways (uno por AZ) → Sin single point of failure
# - Deletion protection habilitada → Previene borrados accidentales
# - Flow Logs habilitados → Auditoría de tráfico
# - Más nodos, más storage → Capacidad para carga real
#
# EN ENTREVISTA: "La diferencia entre dev y prod no es solo escala, sino
# resiliencia. Producción tiene Multi-AZ para RDS con failover automático,
# NAT Gateways redundantes por AZ, instancias On-Demand para estabilidad,
# deletion protection para evitar errores humanos, y VPC Flow Logs para
# auditoría de seguridad."
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "production-sim-terraform-state"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "production-incident-simulator"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}

module "infrastructure" {
  source = "../../"

  # Variables del ambiente
  environment         = "prod"
  aws_region          = var.aws_region
  project_name        = "production-sim"
  vpc_cidr            = "10.1.0.0/16"  # CIDR diferente a dev (por si haces VPC peering)
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # EKS - Configuración robusta para producción
  create_eks              = true
  eks_cluster_version     = "1.28"
  eks_node_instance_types = ["t3.large"]      # Más capacidad
  eks_node_desired_size   = 3                  # Más nodos
  eks_node_min_size       = 2                  # Nunca menos de 2
  eks_node_max_size       = 6                  # Puede escalar más
  eks_node_capacity_type  = "ON_DEMAND"        # Sin interrupciones

  # RDS - Configuración robusta
  create_rds            = true
  rds_instance_class    = "db.t3.medium"       # Más CPU y RAM
  rds_allocated_storage = 50                    # Más storage
  rds_db_name           = "production_sim"

  # ElastiCache - Habilitado en prod para caché
  create_elasticache = true
}

variable "aws_region" {
  default = "us-east-1"
}

output "vpc_id" {
  value = module.infrastructure.vpc_id
}

output "eks_cluster_name" {
  value = module.infrastructure.eks_cluster_name
}

output "eks_kubeconfig_command" {
  value = module.infrastructure.eks_kubeconfig_command
}

output "rds_endpoint" {
  value     = module.infrastructure.rds_endpoint
  sensitive = true
}
