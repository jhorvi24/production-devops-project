#!/bin/bash
# =============================================================================
# TEARDOWN.SH - Destruir toda la infraestructura (ahorrar dinero)
# =============================================================================
#
# IMPORTANTE: Este script destruye TODOS los recursos de AWS.
# Úsalo cuando termines de practicar para no incurrir en gastos.
#
# USO:
#   ./scripts/teardown.sh [dev|prod]
#
# COSTO DE NO EJECUTAR ESTO: ~$6-7/día
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENVIRONMENT="${1:-dev}"
CLUSTER_NAME="production-sim-${ENVIRONMENT}"
AWS_REGION="us-east-1"

echo -e "${RED}"
echo "========================================================="
echo "  ⚠️  TEARDOWN - Destruyendo infraestructura"
echo "========================================================="
echo -e "  Environment: ${YELLOW}${ENVIRONMENT}${RED}"
echo "========================================================="
echo -e "${NC}"
echo ""

# Confirmación
read -p "¿Estás seguro de que quieres destruir ${ENVIRONMENT}? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
  echo "Cancelado."
  exit 0
fi

# =====================================================================
# PASO 1: Eliminar aplicaciones de ArgoCD
# =====================================================================
echo ""
echo -e "${YELLOW}[1/4] Eliminando aplicaciones de ArgoCD...${NC}"
kubectl delete -f k8s/argocd/applications/ --ignore-not-found 2>/dev/null || true
kubectl delete -f k8s/argocd/project.yaml --ignore-not-found 2>/dev/null || true

# Esperar a que ArgoCD limpie los recursos
echo "  → Esperando limpieza (30s)..."
sleep 30

# =====================================================================
# PASO 2: Eliminar recursos de Kubernetes
# =====================================================================
echo ""
echo -e "${YELLOW}[2/4] Eliminando recursos de Kubernetes...${NC}"
kubectl delete -f k8s/base/ --ignore-not-found 2>/dev/null || true
kubectl delete namespace applications monitoring ingress --ignore-not-found 2>/dev/null || true

# Eliminar ALB (creado por ingress controller)
echo "  → Esperando eliminación de Load Balancers (60s)..."
sleep 60

# =====================================================================
# PASO 3: Terraform destroy
# =====================================================================
echo ""
echo -e "${YELLOW}[3/4] Destruyendo infraestructura con Terraform...${NC}"
cd terraform/environments/${ENVIRONMENT}

terraform init -input=false
terraform destroy -auto-approve

cd ../../..
echo -e "${GREEN}  ✓ Infraestructura destruida${NC}"

# =====================================================================
# PASO 4: Limpiar kubeconfig
# =====================================================================
echo ""
echo -e "${YELLOW}[4/4] Limpiando kubeconfig...${NC}"
kubectl config delete-cluster "arn:aws:eks:${AWS_REGION}:*:cluster/${CLUSTER_NAME}" 2>/dev/null || true
kubectl config delete-context "arn:aws:eks:${AWS_REGION}:*:cluster/${CLUSTER_NAME}" 2>/dev/null || true
echo -e "${GREEN}  ✓ kubeconfig limpiado${NC}"

# =====================================================================
# RESUMEN
# =====================================================================
echo ""
echo -e "${GREEN}"
echo "========================================================="
echo "  ✓ TEARDOWN COMPLETADO"
echo "========================================================="
echo ""
echo "  Todos los recursos de ${ENVIRONMENT} han sido eliminados."
echo ""
echo "  NOTA: El backend de Terraform (S3) NO se"
echo "  eliminó. Si quieres eliminarlo también, ejecuta:"
echo "    aws s3 rb s3://production-sim-terraform-state --force"
echo ""
echo "  Para redesplegar:"
echo "    ./scripts/deploy.sh ${ENVIRONMENT}"
echo "========================================================="
echo -e "${NC}"
