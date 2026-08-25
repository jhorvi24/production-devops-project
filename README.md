# Production Incident Simulator on AWS

## Objetivo del Proyecto

Simular un entorno de producción real con microservicios en AWS, incluyendo:
- Infraestructura como Código (Terraform)
- Orquestación con Kubernetes (EKS)
- CI/CD con GitOps (ArgoCD)
- Observabilidad completa (Prometheus, Grafana, CloudWatch)
- Escenarios de incidentes inyectables con runbooks de resolución

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                                    │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                        VPC (10.0.0.0/16)                     │    │
│  │                                                               │    │
│  │  ┌──────────────────┐      ┌──────────────────────────┐     │    │
│  │  │  Public Subnets   │      │    Private Subnets        │     │    │
│  │  │                    │      │                            │     │    │
│  │  │  ┌─────────────┐  │      │  ┌────────────────────┐   │     │    │
│  │  │  │     ALB      │  │      │  │    EKS Cluster      │   │     │    │
│  │  │  │  (ingress)   │──│──────│─▶│                      │   │     │    │
│  │  │  └─────────────┘  │      │  │  ┌──────────────┐   │   │     │    │
│  │  │                    │      │  │  │ api-gateway  │   │   │     │    │
│  │  │  ┌─────────────┐  │      │  │  │ order-svc    │   │   │     │    │
│  │  │  │ NAT Gateway  │  │      │  │  │ payment-svc  │   │   │     │    │
│  │  │  └─────────────┘  │      │  │  └──────────────┘   │   │     │    │
│  │  └──────────────────┘      │  └────────────────────┘   │     │    │
│  │                             │                            │     │    │
│  │                             │  ┌────────────────────┐   │     │    │
│  │                             │  │   RDS PostgreSQL    │   │     │    │
│  │                             │  └────────────────────┘   │     │    │
│  │                             │                            │     │    │
│  │                             │  ┌────────────────────┐   │     │    │
│  │                             │  │  ElastiCache Redis  │   │     │    │
│  │                             │  └────────────────────┘   │     │    │
│  │                             └──────────────────────────┘     │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │    ECR    │  │    S3    │  │   SNS    │  │   CloudWatch     │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Decisiones de Arquitectura

### ¿Por qué VPC con subnets públicas y privadas?
- **Seguridad en capas**: Los workloads (EKS, RDS) nunca se exponen directamente a internet.
- **Principio de mínimo privilegio de red**: Solo el ALB y NAT Gateway viven en subnets públicas.
- **En entrevista**: "Implementé una arquitectura de red segura donde el tráfico entrante pasa por un ALB en subnets públicas, mientras que los pods y bases de datos residen en subnets privadas sin acceso directo desde internet."

### ¿Por qué EKS y no ECS?
- **Portabilidad**: Kubernetes es cloud-agnostic, las habilidades se transfieren a GCP/Azure.
- **Ecosistema**: Helm, ArgoCD, Prometheus, Istio — herramientas estándar de la industria.
- **Demanda laboral**: La mayoría de empresas medianas/grandes usan Kubernetes.
- **En entrevista**: "Elegí EKS porque me permite demostrar conocimiento en orquestación de contenedores con el estándar de la industria, y las habilidades son transferibles entre clouds."

### ¿Por qué Terraform y no CloudFormation?
- **Multi-cloud**: Terraform es cloud-agnostic.
- **Estado declarativo**: Plan → Apply workflow con preview de cambios.
- **Comunidad**: Más módulos, más documentación, más ofertas laborales.
- **En entrevista**: "Usé Terraform por su naturaleza multi-cloud y su ecosistema de módulos reutilizables. El workflow de plan/apply me da visibilidad completa de los cambios antes de aplicarlos."

### ¿Por qué GitOps con ArgoCD?
- **Single source of truth**: El estado deseado vive en Git.
- **Auditoría**: Cada cambio es un commit con autor y timestamp.
- **Rollback instantáneo**: git revert = rollback en producción.
- **En entrevista**: "Implementé GitOps con ArgoCD para que el cluster se reconcilie automáticamente con el estado declarado en Git, dando trazabilidad completa y rollbacks en segundos."

## Estructura del Proyecto

```
production-devops-projects/
├── terraform/                 # Infraestructura como Código
│   ├── modules/               # Módulos reutilizables
│   │   ├── vpc/               # Red: VPC, subnets, NAT, IGW
│   │   ├── eks/               # Cluster EKS + node groups
│   │   ├── rds/               # Base de datos PostgreSQL
│   │   ├── elasticache/       # Cache Redis
│   │   └── security/          # Security Groups, IAM
│   ├── environments/          # Configuración por ambiente
│   │   ├── dev/
│   │   └── prod/
│   └── backend.tf             # Estado remoto en S3
├── k8s/                       # Manifiestos de Kubernetes
│   ├── base/                  # Recursos base (namespaces, RBAC)
│   ├── apps/                  # Deployments de microservicios
│   ├── monitoring/            # Stack de observabilidad
│   └── argocd/                # Configuración GitOps
├── apps/                      # Código fuente de microservicios
│   ├── api-gateway/           # Punto de entrada (Node.js)
│   ├── order-service/         # Gestión de órdenes (Python)
│   └── payment-service/       # Procesamiento de pagos (Go)
├── ci-cd/                     # Definiciones de pipelines
│   ├── buildspec.yml          # AWS CodeBuild
│   └── pipeline.tf            # CodePipeline en Terraform
├── monitoring/                # Configuración de observabilidad
│   ├── prometheus/            # Scrape configs y rules
│   ├── grafana/               # Dashboards as code
│   └── cloudwatch/            # Alarmas y log groups
├── incidents/                 # Simulación de incidentes
│   ├── scenarios/             # Scripts de inyección de fallos
│   └── runbooks/              # Guías paso a paso de resolución
├── scripts/                   # Utilidades de operación
│   ├── deploy.sh              # Deploy completo
│   ├── teardown.sh            # Destruir infraestructura
│   └── inject-fault.sh        # Inyectar fallos
└── docs/                      # Documentación detallada
    ├── architecture.md        # Decisiones de arquitectura
    ├── incident-response.md   # Proceso de respuesta
    └── interview-prep.md      # Preguntas de entrevista
```

## Escenarios de Incidentes

| # | Escenario | Severidad | Tiempo de Resolución |
|---|-----------|-----------|---------------------|
| 1 | Alta latencia en RDS | SEV-2 | 15-30 min |
| 2 | Memory leak (OOMKilled) | SEV-2 | 10-20 min |
| 3 | Certificado TLS expirado | SEV-1 | 5-10 min |
| 4 | Deployment fallido | SEV-3 | 5-15 min |
| 5 | DDoS simulado | SEV-1 | 10-20 min |
| 6 | Disco lleno en nodos | SEV-2 | 10-15 min |
| 7 | Network policy mal configurada | SEV-2 | 15-30 min |
| 8 | Secrets expirados | SEV-1 | 5-10 min |
| 9 | HPA mal configurado | SEV-3 | 10-20 min |
| 10 | Pérdida de datos (DR) | SEV-1 | 30-60 min |

## Requisitos Previos

- AWS CLI configurado con credenciales
- Terraform >= 1.5
- kubectl
- Docker
- Helm 3
- ArgoCD CLI (opcional)

## Costo Estimado

| Recurso | Tipo | Costo/mes (aprox) |
|---------|------|-------------------|
| EKS Cluster | Control plane | $73 |
| EC2 (2x t3.medium spot) | Worker nodes | $30-40 |
| RDS (db.t3.micro) | PostgreSQL | $15 |
| NAT Gateway | Networking | $32 + data |
| ALB | Load Balancer | $16 + data |
| **Total estimado** | | **~$170-200/mes** |

> **Tip**: Usa los scripts de `teardown.sh` para destruir todo cuando no estés practicando. Puedes reconstruir en ~20 minutos.

## Quick Start

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd production-devops-projects

# 2. Inicializar Terraform
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# 3. Configurar kubectl
aws eks update-kubeconfig --name production-sim-dev --region us-east-1

# 4. Desplegar aplicaciones con ArgoCD
kubectl apply -f k8s/argocd/

# 5. Simular un incidente
./scripts/inject-fault.sh --scenario memory-leak
```
