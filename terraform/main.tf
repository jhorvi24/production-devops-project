# =============================================================================
# MAIN - Orquestación de módulos
# =============================================================================
#
# ¿POR QUÉ MÓDULOS?
# Los módulos en Terraform son como funciones en programación:
# - Encapsulan complejidad (100 líneas → 1 llamada)
# - Son reutilizables (mismo módulo para dev y prod)
# - Son testeables de forma aislada
# - Facilitan la colaboración (cada equipo mantiene sus módulos)
#
# ORDEN DE DEPENDENCIAS:
# VPC → EKS → RDS (cada uno necesita outputs del anterior)
# Terraform resuelve esto automáticamente por las referencias.
#
# EN ENTREVISTA: "Organicé la infraestructura en módulos reutilizables que
# encapsulan la lógica de cada servicio. Esto permite que el mismo código
# sirva para dev y prod con diferentes parámetros, y facilita que equipos
# distintos mantengan cada módulo independientemente."
# =============================================================================

# -----------------------------------------------------------------------------
# Módulo VPC - Red base
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  single_nat_gateway = var.environment == "prod" ? false : true
  enable_flow_logs   = var.environment == "prod" ? true : false
}

# -----------------------------------------------------------------------------
# Módulo EKS - Cluster de Kubernetes
# -----------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"
  count  = var.create_eks ? 1 : 0

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  cluster_version     = var.eks_cluster_version
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_capacity_type  = var.eks_node_capacity_type
}

# -----------------------------------------------------------------------------
# Módulo RDS - Base de datos PostgreSQL
# -----------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"
  count  = var.create_rds ? 1 : 0

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  instance_class     = var.rds_instance_class
  allocated_storage  = var.rds_allocated_storage
  db_name            = var.rds_db_name

  # Solo permite conexiones desde los Security Groups de EKS
  allowed_security_groups = var.create_eks ? [module.eks[0].node_security_group_id] : []
}
