# =============================================================================
# CLOUDWATCH ALARMS - Monitoreo nativo de AWS
# =============================================================================
#
# ¿POR QUÉ CLOUDWATCH ADEMÁS DE PROMETHEUS?
# - Prometheus: Métricas de aplicación (custom) y Kubernetes
# - CloudWatch: Métricas de infraestructura AWS (RDS, ALB, EKS, NAT)
#
# Ambos se complementan:
# - Prometheus → "Mi app tiene latencia alta"
# - CloudWatch → "Porque RDS tiene CPU al 95%"
#
# ESTRUCTURA DE ALERTAS:
# Alarm → SNS Topic → Lambda/Email/PagerDuty
#
# EN ENTREVISTA: "Usé CloudWatch para métricas de infraestructura AWS
# (RDS, ALB, nodos) y Prometheus para métricas custom de aplicación.
# CloudWatch Alarms notifica vía SNS a un canal de Slack y PagerDuty
# para respuesta de incidentes."
# =============================================================================

# SNS Topic para notificaciones de alarmas
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =============================================================================
# ALB Alarms
# =============================================================================

# ALB - 5xx errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "ALB is returning more than 50 5xx errors in 5 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# ALB - Response time
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "p99"
  threshold           = 1
  alarm_description   = "ALB p99 response time > 1 second for 15 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# =============================================================================
# EKS Node Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EKS node CPU > 80% for 15 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "node_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-node-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "EKS node memory > 85% for 15 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-${var.environment}"
  }
}

# =============================================================================
# Variables
# =============================================================================
variable "project_name" {
  type    = string
  default = "production-sim"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "alert_email" {
  description = "Email for alarm notifications"
  type        = string
  default     = "devops@example.com"
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB"
  type        = string
  default     = ""
}
