# =============================================================================
# AMBIENTE DEV - Configuración de desarrollo
# =============================================================================
#
# ¿POR QUÉ AMBIENTES SEPARADOS?
# En un proyecto real NUNCA se usa el mismo Terraform workspace para dev y prod.
# Cada ambiente tiene:
# - Su propio state file (aislamiento de errores)
# - Su propio backend key (S3 path separado)
# - Sus propios valores (menos recursos = menor costo)
#
# PATRÓN: Cada ambiente es un directorio que referencia los módulos raíz.
# Esto da máxima flexibilidad:
# - Dev puede tener features experimentales que prod no
# - Puedes destruir dev sin afectar prod
# - Cada ambiente evoluciona a su propio ritmo
#
# EN ENTREVISTA: "Implementé ambientes aislados con state files independientes
# en S3. Cada ambiente tiene su propio backend key, lo que garantiza que un
# error en dev jamás corrompa el estado de producción. Los valores se parametrizan
# con tfvars para que el mismo código produzca infraestructura ajustada al
# propósito de cada ambiente."
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "production-sim-terraform-state"
    key            = "environments/dev/terraform.tfstate"
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
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}

# Referenciar los módulos desde el directorio raíz
module "infrastructure" {
  source = "../../"

  # Variables del ambiente
  environment         = "dev"
  aws_region          = var.aws_region
  project_name        = "production-sim"
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # EKS - Configuración económica para dev
  create_eks              = true
  eks_cluster_version     = "1.28"
  eks_node_instance_types = ["t3.medium"]
  eks_node_desired_size   = 2
  eks_node_min_size       = 1
  eks_node_max_size       = 3
  eks_node_capacity_type  = "SPOT"  # 60-90% ahorro

  # RDS - Mínimo para dev
  create_rds          = true
  rds_instance_class  = "db.t3.micro"
  rds_allocated_storage = 20
  rds_db_name         = "production_sim"

  # ElastiCache - Deshabilitado en dev para ahorrar
  create_elasticache = false
}

# Variables locales del ambiente
variable "aws_region" {
  default = "us-east-1"
}

# Outputs útiles
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
