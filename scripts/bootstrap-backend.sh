#!/bin/bash
# =============================================================================
# BOOTSTRAP - Crea los recursos necesarios para el backend remoto de Terraform
# =============================================================================
#
# ¿POR QUÉ ESTE SCRIPT?
# El backend de Terraform (S3 + DynamoDB) tiene un problema de "huevo y gallina":
# - Terraform necesita el bucket S3 para guardar su estado
# - Pero el bucket aún no existe porque no hemos corrido Terraform
# - Solución: Creamos estos recursos con AWS CLI antes de inicializar Terraform
#
# USO: ./scripts/bootstrap-backend.sh
# =============================================================================

set -euo pipefail

# Configuración
AWS_REGION="us-east-1"
BUCKET_NAME="production-sim-terraform-state"
TABLE_NAME="terraform-state-lock"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "================================================="
echo "  Bootstrap - Terraform Backend"
echo "================================================="
echo "Account ID: ${ACCOUNT_ID}"
echo "Region:     ${AWS_REGION}"
echo "Bucket:     ${BUCKET_NAME}"
echo "Table:      ${TABLE_NAME}"
echo "================================================="

# Crear bucket S3
echo ""
echo "[1/4] Creando bucket S3..."
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
echo "[2/4] Habilitando versionado..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
echo "  ✓ Versionado habilitado"

# Habilitar encriptación por defecto
echo ""
echo "[3/4] Habilitando encriptación..."
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

# Crear tabla DynamoDB para state locking
echo ""
echo "[4/4] Creando tabla DynamoDB para state locking..."
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "  ✓ Tabla ya existe"
else
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"
  echo "  ✓ Tabla creada"
fi

echo ""
echo "================================================="
echo "  ✓ Bootstrap completado exitosamente"
echo "================================================="
echo ""
echo "Próximo paso:"
echo "  cd terraform/environments/dev"
echo "  terraform init"
echo "  terraform plan"
