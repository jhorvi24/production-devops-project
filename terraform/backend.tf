# =============================================================================
# TERRAFORM BACKEND - Estado Remoto en S3 con Locking Nativo
# =============================================================================
#
# ¿POR QUÉ ESTADO REMOTO?
# En un equipo real, el estado de Terraform NO puede vivir en tu máquina local porque:
# 1. Otros ingenieros necesitan acceder al mismo estado
# 2. Si pierdes tu laptop, pierdes el mapping de recursos
# 3. Necesitas locking para evitar que dos personas apliquen cambios simultáneamente
#
# ¿POR QUÉ S3 CON LOCKING NATIVO?
# - S3: Almacena el archivo .tfstate (versionado, encriptado, durable)
# - S3 native locking (use_lockfile): Usa un archivo .tflock en el mismo bucket
#   como mecanismo de locking, eliminando la necesidad de DynamoDB.
#   Disponible desde Terraform 1.10+.
#
# VENTAJAS vs DynamoDB:
# - Menos infraestructura que mantener (no necesitas tabla DynamoDB)
# - Menor costo (DynamoDB tiene cargos por request)
# - Setup más simple (solo un bucket S3)
# - Mismo nivel de seguridad (conditional writes en S3)
#
# EN ENTREVISTA: "Configuré el backend remoto en S3 con locking nativo usando
# use_lockfile. Esto simplifica la infraestructura eliminando DynamoDB,
# aprovechando los conditional writes de S3 para evitar race conditions.
# El bucket tiene versionado y encriptación KMS habilitados."
# =============================================================================

terraform {
  backend "s3" {
    bucket       = "production-sim-terraform-state"
    key          = "global/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true  # Locking nativo de S3 (Terraform 1.10+)
  }
}

# =============================================================================
# NOTA: El bucket S3 debe crearse ANTES de inicializar este backend.
# Usa el script scripts/bootstrap-backend.sh para crearlo.
# Ya NO se necesita DynamoDB para state locking.
# =============================================================================
