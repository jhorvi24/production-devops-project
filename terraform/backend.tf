# =============================================================================
# TERRAFORM BACKEND - Estado Remoto en S3
# =============================================================================
#
# ¿POR QUÉ ESTADO REMOTO?
# En un equipo real, el estado de Terraform NO puede vivir en tu máquina local porque:
# 1. Otros ingenieros necesitan acceder al mismo estado
# 2. Si pierdes tu laptop, pierdes el mapping de recursos
# 3. Necesitas locking para evitar que dos personas apliquen cambios simultáneamente
#
# ¿POR QUÉ S3 + DYNAMODB?
# - S3: Almacena el archivo .tfstate (versionado, encriptado, durable)
# - DynamoDB: Proporciona locking distribuido (evita race conditions)
#
# EN ENTREVISTA: "Configuré el backend remoto en S3 con DynamoDB para state locking,
# garantizando que múltiples ingenieros puedan trabajar en la misma infraestructura
# sin conflictos, con encriptación at-rest y versionado para auditoría."
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "production-sim-terraform-state"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true

    # Tags no se soportan en el bloque backend, pero el bucket debe tenerlos
  }
}

# =============================================================================
# NOTA: El bucket S3 y la tabla DynamoDB deben crearse ANTES de inicializar
# este backend. Usa el script scripts/bootstrap-backend.sh para crearlos.
# =============================================================================
