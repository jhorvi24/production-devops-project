# =============================================================================
# MÓDULO EKS - Cluster de Kubernetes en AWS
# =============================================================================
#
# COMPONENTES DE EKS:
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │                     EKS Cluster                              │
#   │                                                              │
#   │  ┌───────────────────────────────────────────────────────┐  │
#   │  │         Control Plane (Managed by AWS)                 │  │
#   │  │  - API Server                                          │  │
#   │  │  - etcd (almacena estado del cluster)                  │  │
#   │  │  - Controller Manager                                  │  │
#   │  │  - Scheduler                                           │  │
#   │  └───────────────────────────────────────────────────────┘  │
#   │                          │                                   │
#   │  ┌───────────────────────▼───────────────────────────────┐  │
#   │  │         Data Plane (Worker Nodes)                      │  │
#   │  │                                                        │  │
#   │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
#   │  │  │  Node 1   │  │  Node 2   │  │  Node 3   │           │  │
#   │  │  │ (t3.med)  │  │ (t3.med)  │  │ (t3.med)  │           │  │
#   │  │  │           │  │           │  │           │           │  │
#   │  │  │ [pod][pod]│  │ [pod][pod]│  │ [pod][pod]│           │  │
#   │  │  └──────────┘  └──────────┘  └──────────┘           │  │
#   │  └────────────────────────────────────────────────────────┘  │
#   └─────────────────────────────────────────────────────────────┘
#
# ¿POR QUÉ MANAGED NODE GROUPS?
# - AWS se encarga de las AMIs, parches de seguridad y actualizaciones
# - Integración nativa con Auto Scaling Groups
# - Drain automático de nodos durante updates (sin downtime)
# Alternativas: Self-managed nodes (más control), Fargate (serverless)
#
# ¿POR QUÉ SPOT INSTANCES EN DEV?
# - 60-90% más baratas que On-Demand
# - Para dev/staging el riesgo de interrupción es aceptable
# - En producción real: mezcla de On-Demand (base) + Spot (burst)
#
# ¿POR QUÉ HABILITAR TODOS LOS LOGS DEL CONTROL PLANE?
# - api: Cada request al API server (quién hizo qué)
# - audit: Registro detallado de acciones (compliance)
# - authenticator: Intentos de autenticación (seguridad)
# - controllerManager: Estado de controllers (troubleshooting)
# - scheduler: Decisiones de scheduling (por qué un pod está pending)
#
# EN ENTREVISTA: "Configuré EKS con Managed Node Groups usando instancias Spot
# para desarrollo (ahorro 60-90%) y On-Demand para producción. Habilité todos
# los logs del control plane para tener visibilidad completa durante incidentes,
# y configuré IRSA (IAM Roles for Service Accounts) para seguir el principio
# de mínimo privilegio por pod."
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role para el Cluster (Control Plane)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-role"
  }
}

# Políticas necesarias para el cluster
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# -----------------------------------------------------------------------------
# Security Group del Cluster
# -----------------------------------------------------------------------------
resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-${var.environment}-eks-cluster-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS cluster control plane"

  # Permite todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true  # En prod real: false + VPN/bastion
  }

  # Logging del control plane
  dynamic "enabled_cluster_log_types" {
    for_each = var.enable_cluster_logging ? [1] : []
    content {
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]
}

# Habilitar logging (forma correcta)
resource "aws_cloudwatch_log_group" "eks" {
  count             = var.enable_cluster_logging ? 1 : 0
  name              = "/aws/eks/${var.project_name}-${var.environment}/cluster"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-logs"
  }
}

# -----------------------------------------------------------------------------
# IAM Role para Worker Nodes
# -----------------------------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-role"
  }
}

# Políticas necesarias para los worker nodes
resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# Para CloudWatch Container Insights
resource "aws_iam_role_policy_attachment" "node_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.node.name
}

# -----------------------------------------------------------------------------
# Managed Node Group
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1  # Actualiza de a un nodo a la vez (rolling update)
  }

  labels = {
    Environment = var.environment
    NodeGroup   = "main"
  }

  tags = {
    Name                                                           = "${var.project_name}-${var.environment}-worker"
    "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                           = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# -----------------------------------------------------------------------------
# OIDC Provider - Para IRSA (IAM Roles for Service Accounts)
# -----------------------------------------------------------------------------
# IRSA permite asignar permisos IAM a pods individuales en lugar de al nodo completo.
# Esto sigue el principio de mínimo privilegio.

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-oidc"
  }
}

# -----------------------------------------------------------------------------
# Security Group para los Nodes
# -----------------------------------------------------------------------------
resource "aws_security_group" "node" {
  name_prefix = "${var.project_name}-${var.environment}-eks-node-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS worker nodes"

  # Comunicación entre nodes
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Comunicación desde el control plane
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  # Tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                                           = "${var.project_name}-${var.environment}-eks-node-sg"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "owned"
  }

  lifecycle {
    create_before_destroy = true
  }
}
