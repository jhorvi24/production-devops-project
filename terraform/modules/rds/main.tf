# =============================================================================
# MÓDULO RDS - Base de datos PostgreSQL
# =============================================================================
#
# ¿POR QUÉ RDS Y NO UNA BD EN EC2 O EN UN POD?
# - Backups automáticos (point-in-time recovery)
# - Parches de seguridad automáticos
# - Multi-AZ failover automático (alta disponibilidad)
# - Read Replicas para escalar lecturas
# - Monitoring integrado (Performance Insights, Enhanced Monitoring)
# - Encriptación at-rest y in-transit
#
# ¿POR QUÉ POSTGRESQL?
# - Open source (sin costos de licencia como Oracle/SQL Server)
# - JSONB para datos semi-estructurados
# - Extensiones (PostGIS, pg_cron, pgvector para AI)
# - Compatible con Aurora PostgreSQL si necesitas escalar
#
# DECISIONES DE SEGURIDAD:
# - Credenciales en Secrets Manager (rotación automática)
# - Security Group restrictivo (solo EKS puede conectarse)
# - Encriptación con KMS
# - Sin acceso público
#
# EN ENTREVISTA: "Usé RDS PostgreSQL con backups automáticos de 7 días,
# encriptación KMS, y acceso restringido solo desde los worker nodes de EKS
# vía Security Groups. Las credenciales se almacenan en Secrets Manager con
# rotación automática, y uso Performance Insights para diagnóstico de queries
# lentas durante incidentes de latencia."
# =============================================================================

# -----------------------------------------------------------------------------
# Subnet Group - Define en qué subnets puede vivir RDS
# Multi-AZ requiere subnets en al menos 2 AZs
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# -----------------------------------------------------------------------------
# Security Group - Controla quién puede conectarse
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  vpc_id      = var.vpc_id
  description = "Security group for RDS PostgreSQL"

  # Solo permite conexiones desde los security groups especificados (EKS nodes)
  dynamic "ingress" {
    for_each = var.allowed_security_groups
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "PostgreSQL from EKS"
    }
  }

  # Sin tráfico saliente específico necesario para RDS
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Credenciales en Secrets Manager
# Genera una contraseña aleatoria y la almacena de forma segura
# -----------------------------------------------------------------------------
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-${var.environment}-db-credentials"
  description             = "RDS PostgreSQL credentials"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name = "${var.project_name}-${var.environment}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
  })
}

# -----------------------------------------------------------------------------
# Parameter Group - Configuración del motor PostgreSQL
# -----------------------------------------------------------------------------
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-pg15"
  family = "postgres15"

  # Logging de queries lentas (útil para troubleshooting)
  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"  # Log queries que tarden más de 1 segundo
    apply_method = "pending-reboot"
  }

  # Estadísticas de queries (parámetro estático - requiere reboot)
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  # Máximo de conexiones (parámetro estático - requiere reboot)
  parameter {
    name         = "max_connections"
    value        = "100"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-pg-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Instancia RDS
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Motor
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = "dbadmin"
  password = random_password.db_password.result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 5432

  # High Availability
  multi_az = var.multi_az

  # Backups
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Monitoring
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn

  # Configuration
  parameter_group_name = aws_db_parameter_group.main.name

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-${var.environment}-final-snapshot" : null
  copy_tags_to_snapshot     = true

  # Actualizaciones menores automáticas
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}

# -----------------------------------------------------------------------------
# Enhanced Monitoring Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms - Alertas proactivas
# -----------------------------------------------------------------------------

# Alarma: CPU alta (posible saturación)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization is above 80% for 15 minutes"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-cpu-alarm"
  }
}

# Alarma: Conexiones altas (posible connection leak)
resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS connections above 80 (max is 100)"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-connections-alarm"
  }
}

# Alarma: Espacio libre bajo
resource "aws_cloudwatch_metric_alarm" "storage_low" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120  # 5 GB en bytes
  alarm_description   = "RDS free storage is below 5GB"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-storage-alarm"
  }
}
