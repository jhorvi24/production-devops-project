#!/bin/bash
# =============================================================================
# BOOTSTRAP - Crea el bucket S3 para el backend remoto de Terraform
# =============================================================================
#
# ¿POR QUÉ ESTE SCRIPT?
# El backend de Terraform (S3) tiene un problema de "huevo y gallina":
# - Terraform necesita el bucket S3 para guardar su estado
# - Pero el bucket aún no existe porque no hemos corrido Terraform
# - Solución: Creamos el bucket con AWS CLI antes de inicializar Terraform
#
# NOTA: Desde Terraform 1.10+, S3 soporta locking nativo con use_lockfile.
# Ya NO se necesita DynamoDB para state locking.
#
# USO: ./scripts/bootstrap-backend.sh
# =============================================================================

set -euo pipefail

# Configuración
AWS_REGION="us-east-1"
BUCKET_NAME="production-sim-terraform-state"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "================================================="
echo "  Bootstrap - Terraform Backend (S3)"
echo "================================================="
echo "Account ID: ${ACCOUNT_ID}"
echo "Region:     ${AWS_REGION}"
echo "Bucket:     ${BUCKET_NAME}"
echo "Locking:    S3 native (use_lockfile)"
echo "================================================="

# Crear bucket S3
echo ""
echo "[1/3] Creando bucket S3..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "  ✓ Bucket ya existe"
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}"
  echo "  ✓ Bucket creado"
fi

# Habilitar versionado (para poder recuperar estados anteriores)
echo ""
echo "[2/3] Habilitando versionado..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
echo "  ✓ Versionado habilitado"

# Habilitar encriptación por defecto
echo ""
echo "[3/3] Habilitando encriptación..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
      },
      "BucketKeyEnabled": true
    }]
  }'
echo "  ✓ Encriptación KMS habilitada"

echo ""
echo "================================================="
echo "  ✓ Bootstrap completado exitosamente"
echo "================================================="
echo ""
echo "Próximo paso:"
echo "  cd terraform/environments/dev"
echo "  terraform init"
echo "  terraform plan"
echo ""
echo "NOTA: El locking se maneja nativamente por S3"
echo "(use_lockfile = true en backend.tf). No se necesita DynamoDB."
