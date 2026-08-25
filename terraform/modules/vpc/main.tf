# =============================================================================
# MÓDULO VPC - Red base de la infraestructura
# =============================================================================
#
# ARQUITECTURA DE RED:
# Este módulo crea una VPC con topología multi-AZ (Alta Disponibilidad):
#
#   Internet
#      │
#   ┌──▼──┐
#   │ IGW │  (Internet Gateway - permite tráfico hacia/desde internet)
#   └──┬──┘
#      │
#   ┌──▼────────────────────────────────────────┐
#   │           Public Subnets (3 AZs)           │
#   │  - ALB (Application Load Balancer)         │
#   │  - NAT Gateways                            │
#   │  - Bastion hosts (si se necesitan)         │
#   └──┬────────────────────────────────────────┘
#      │ (NAT Gateway - tráfico saliente)
#   ┌──▼────────────────────────────────────────┐
#   │          Private Subnets (3 AZs)           │
#   │  - EKS Worker Nodes                        │
#   │  - RDS                                     │
#   │  - ElastiCache                             │
#   └───────────────────────────────────────────┘
#
# ¿POR QUÉ 3 AZs?
# - Alta Disponibilidad: Si una AZ falla, las otras 2 siguen funcionando
# - EKS requiere mínimo 2 AZs, pero 3 es el estándar de producción
# - RDS Multi-AZ necesita al menos 2 subnets en diferentes AZs
#
# ¿POR QUÉ NAT GATEWAY?
# Los pods en subnets privadas necesitan acceso a internet para:
# - Pull de imágenes Docker desde ECR/DockerHub
# - Llamadas a APIs externas
# - Actualizaciones de paquetes
# Pero NO deben ser accesibles desde internet directamente.
#
# EN ENTREVISTA: "Diseñé la VPC con 3 AZs para alta disponibilidad, separando
# el tráfico público del privado. Los workloads en subnets privadas acceden a
# internet vía NAT Gateway, pero no son alcanzables desde fuera. Esto cumple
# con el principio de defensa en profundidad."
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Principal
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # Necesario para EKS
  enable_dns_support   = true  # Necesario para resolución DNS interna

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
    # Tags requeridos por EKS para auto-discovery
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway - Puerta de entrada/salida a internet
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# -----------------------------------------------------------------------------
# Subnets Públicas - Una por AZ
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true  # Instancias aquí obtienen IP pública

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
    # Tag requerido por EKS para saber dónde crear ALB
    "kubernetes.io/role/elb"                                        = "1"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# Subnets Privadas - Una por AZ
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${var.availability_zones[count.index]}"
    # Tag requerido por EKS para saber dónde crear internal ALB
    "kubernetes.io/role/internal-elb"                               = "1"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# Elastic IPs para NAT Gateways
# Una por AZ para alta disponibilidad (en prod)
# En dev, solo una para ahorrar costos
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT Gateways - Permiten tráfico saliente desde subnets privadas
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route Tables - Tablas de enrutamiento
# -----------------------------------------------------------------------------

# Route table para subnets públicas (comparten una sola)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

# Route tables para subnets privadas (una por AZ para redundancia)
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index}"
  }
}

# Asociaciones de route tables
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs - Registro de tráfico de red (para troubleshooting)
# -----------------------------------------------------------------------------
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/flow-logs/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-logs"
  }
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.project_name}-${var.environment}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "flow-log-policy"
  role  = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}
