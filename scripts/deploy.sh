#!/bin/bash
# =============================================================================
# DEPLOY.SH - Despliegue completo de la infraestructura
# =============================================================================
#
# Este script ejecuta el despliegue completo del proyecto:
# 1. Bootstrap del backend (S3 + DynamoDB)
# 2. Terraform init + plan + apply
# 3. Configurar kubectl
# 4. Instalar ArgoCD
# 5. Aplicar manifests base
# 6. Desplegar aplicaciones vía GitOps
#
# USO:
#   ./scripts/deploy.sh [dev|prod]
#
# TIEMPO ESTIMADO: ~20 minutos para un deploy completo
# =============================================================================

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
ENVIRONMENT="${1:-dev}"
AWS_REGION="us-east-1"
PROJECT_NAME="production-sim"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

echo -e "${BLUE}"
echo "========================================================="
echo "  Production Incident Simulator - Deploy"
echo "========================================================="
echo -e "  Environment: ${YELLOW}${ENVIRONMENT}${BLUE}"
echo -e "  Region:      ${YELLOW}${AWS_REGION}${BLUE}"
echo -e "  Cluster:     ${YELLOW}${CLUSTER_NAME}${BLUE}"
echo "========================================================="
echo -e "${NC}"

# Verificar prerequisitos
echo -e "${BLUE}[0/6] Verificando prerequisitos...${NC}"
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Error: AWS CLI no instalado${NC}"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Error: Terraform no instalado${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl no instalado${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: Helm no instalado${NC}"; exit 1; }

# Verificar credenciales AWS
aws sts get-caller-identity >/dev/null 2>&1 || { echo -e "${RED}Error: AWS credentials no configuradas${NC}"; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}  ✓ AWS Account: ${ACCOUNT_ID}${NC}"
echo -e "${GREEN}  ✓ Todos los prerequisitos OK${NC}"

# =====================================================================
# PASO 1: Bootstrap backend
# =====================================================================
echo ""
echo -e "${BLUE}[1/6] Bootstrapping Terraform backend...${NC}"
bash scripts/bootstrap-backend.sh
echo -e "${GREEN}  ✓ Backend listo${NC}"

# =====================================================================
# PASO 2: Terraform
# =====================================================================
echo ""
echo -e "${BLUE}[2/6] Desplegando infraestructura con Terraform...${NC}"
cd terraform/environments/${ENVIRONMENT}

echo "  → terraform init..."
terraform init -input=false

echo "  → terraform plan..."
terraform plan -out=tfplan -input=false

echo "  → terraform apply..."
terraform apply -input=false tfplan

# Obtener outputs
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
cd ../../..

echo -e "${GREEN}  ✓ Infraestructura desplegada${NC}"

# =====================================================================
# PASO 3: Configurar kubectl
# =====================================================================
echo ""
echo -e "${BLUE}[3/6] Configurando kubectl...${NC}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
echo -e "${GREEN}  ✓ kubectl configurado${NC}"

# Verificar conexión al cluster
kubectl cluster-info || { echo -e "${RED}Error: No se puede conectar al cluster${NC}"; exit 1; }

# =====================================================================
# PASO 4: Aplicar manifests base
# =====================================================================
echo ""
echo -e "${BLUE}[4/6] Aplicando manifests base (namespaces, RBAC, policies)...${NC}"
kubectl apply -f k8s/base/namespaces.yaml
kubectl apply -f k8s/base/rbac.yaml
kubectl apply -f k8s/base/network-policies.yaml
kubectl apply -f k8s/base/limit-ranges.yaml
kubectl apply -f k8s/base/resource-quotas.yaml
echo -e "${GREEN}  ✓ Manifests base aplicados${NC}"

# =====================================================================
# PASO 5: Instalar ArgoCD
# =====================================================================
echo ""
echo -e "${BLUE}[5/6] Instalando ArgoCD...${NC}"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar a que ArgoCD esté listo
echo "  → Esperando a que ArgoCD esté ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Obtener password inicial
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}  ✓ ArgoCD instalado${NC}"
echo -e "${YELLOW}  → ArgoCD Admin Password: ${ARGOCD_PASSWORD}${NC}"
echo -e "${YELLOW}  → Acceso UI: kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"

# =====================================================================
# PASO 6: Desplegar aplicaciones vía ArgoCD
# =====================================================================
echo ""
echo -e "${BLUE}[6/6] Desplegando aplicaciones con ArgoCD (App of Apps)...${NC}"
kubectl apply -f k8s/argocd/project.yaml
kubectl apply -f k8s/argocd/applications/app-of-apps.yaml

echo -e "${GREEN}  ✓ App of Apps desplegada. ArgoCD sincronizará automáticamente.${NC}"

# =====================================================================
# RESUMEN
# =====================================================================
echo ""
echo -e "${GREEN}"
echo "========================================================="
echo "  ✓ DEPLOY COMPLETADO EXITOSAMENTE"
echo "========================================================="
echo ""
echo "  Cluster:    ${CLUSTER_NAME}"
echo "  Region:     ${AWS_REGION}"
echo "  Account:    ${ACCOUNT_ID}"
echo ""
echo "  Próximos pasos:"
echo "  1. Acceder a ArgoCD UI:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "     https://localhost:8080 (admin / ${ARGOCD_PASSWORD})"
echo ""
echo "  2. Verificar pods:"
echo "     kubectl get pods -A"
echo ""
echo "  3. Simular un incidente:"
echo "     ./scripts/inject-fault.sh --scenario memory-leak"
echo ""
echo "  4. Destruir todo cuando termines:"
echo "     ./scripts/teardown.sh ${ENVIRONMENT}"
echo "========================================================="
echo -e "${NC}"
