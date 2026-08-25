# =============================================================================
# PROVIDERS - Configuración de proveedores de Terraform
# =============================================================================
#
# ¿QUÉ ES UN PROVIDER?
# Un provider es el plugin que Terraform usa para comunicarse con una API.
# AWS provider traduce tus recursos HCL a llamadas a la API de AWS.
#
# ¿POR QUÉ FIJAR VERSIONES?
# - Reproducibilidad: El mismo código produce el mismo resultado siempre
# - Estabilidad: Evitas que un upgrade rompa tu infraestructura
# - Seguridad: Controlas cuándo adoptas nuevas versiones (después de probar)
#
# EN ENTREVISTA: "Fijo versiones de providers y de Terraform para garantizar
# builds reproducibles. Actualizo versiones de forma controlada después de
# validar en el ambiente de desarrollo."
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Provider principal de AWS
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "production-incident-simulator"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}

# Provider de Kubernetes - se configura después de crear EKS
provider "kubernetes" {
  host                   = try(module.eks[0].cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks[0].cluster_ca_certificate), "")
  token                  = try(data.aws_eks_cluster_auth.cluster[0].token, "")
}

# Provider de Helm - para instalar charts en EKS
provider "helm" {
  kubernetes {
    host                   = try(module.eks[0].cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks[0].cluster_ca_certificate), "")
    token                  = try(data.aws_eks_cluster_auth.cluster[0].token, "")
  }
}

# Data source para autenticación con EKS
data "aws_eks_cluster_auth" "cluster" {
  count = var.create_eks ? 1 : 0
  name  = module.eks[0].cluster_name
}
