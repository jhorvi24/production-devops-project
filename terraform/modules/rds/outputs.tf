# =============================================================================
# OUTPUTS DEL MÓDULO RDS
# =============================================================================

output "endpoint" {
  description = "Endpoint de conexión (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "Hostname de la instancia RDS"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "Puerto de la base de datos"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Nombre de la base de datos"
  value       = aws_db_instance.main.db_name
}

output "secret_arn" {
  description = "ARN del secreto en Secrets Manager con las credenciales"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "security_group_id" {
  description = "ID del Security Group de RDS"
  value       = aws_security_group.rds.id
}

output "instance_id" {
  description = "ID de la instancia RDS"
  value       = aws_db_instance.main.id
}
