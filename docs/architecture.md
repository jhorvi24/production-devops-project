# Decisiones de Arquitectura (ADRs)

## ADR-001: VPC Multi-AZ con Subnets Públicas/Privadas

**Contexto:** Necesitamos una red que sea segura, altamente disponible, y escalable.

**Decisión:** VPC con 3 AZs, subnets públicas (ALB, NAT) y privadas (EKS, RDS).

**Consecuencias:**
- (+) Alta disponibilidad: Si una AZ falla, 2 siguen operando
- (+) Seguridad: Workloads nunca expuestos directamente a internet
- (+) Compliance: Separación de tráfico público/privado
- (-) Costo: NAT Gateway ($32/mes por AZ en prod)
- (-) Complejidad: Más route tables y security groups que manejar

---

## ADR-002: EKS con Managed Node Groups

**Contexto:** Necesitamos orquestación de contenedores con gestión simplificada de nodos.

**Decisión:** EKS con Managed Node Groups (no self-managed, no Fargate).

**Alternativas descartadas:**
- Self-managed: Más control pero más operational burden
- Fargate: Serverless pero más caro y sin daemonsets
- ECS: Más simple pero no es el estándar de la industria

**Consecuencias:**
- (+) AMIs parchadas automáticamente por AWS
- (+) Rolling updates de nodos sin downtime
- (+) Integración nativa con ASG
- (-) Menos control sobre la AMI que self-managed
- (-) Costo de control plane ($73/mes)

---

## ADR-003: GitOps con ArgoCD

**Contexto:** Necesitamos un mecanismo de deployment que sea auditable, reversible, y seguro.

**Decisión:** GitOps con ArgoCD (pull-based deployment).

**Alternativas descartadas:**
- kubectl apply desde CI (push-based): CI necesita credenciales del cluster
- Helm install desde CI: Misma limitación + no detecta drift
- FluxCD: Viable pero ArgoCD tiene mejor UI y adopción

**Consecuencias:**
- (+) Git como única fuente de verdad (auditoría completa)
- (+) Rollback = git revert (segundos)
- (+) Drift detection y self-healing
- (+) CI no necesita acceso al cluster
- (-) Curva de aprendizaje inicial
- (-) Un componente más que mantener en el cluster

---

## ADR-004: Observabilidad Dual (Prometheus + CloudWatch)

**Contexto:** Necesitamos métricas tanto de infraestructura AWS como de aplicación.

**Decisión:** Prometheus para métricas custom de app + CloudWatch para métricas de infra AWS.

**Justificación:**
- CloudWatch es nativo y captura RDS, ALB, nodos sin configuración extra
- Prometheus permite métricas custom por endpoint con labels flexibles
- Grafana unifica ambas fuentes en un solo dashboard

---

## ADR-005: Microservicios Polyglot

**Contexto:** Demostrar competencia en múltiples tecnologías y el patrón de microservicios.

**Decisión:** Node.js (API Gateway), Python (Order Service), Go (Payment Service).

**Justificación:**
- Node.js: Ideal para I/O bound (proxy de requests)
- Python: Productividad alta para lógica de negocio
- Go: Rendimiento para servicios críticos + imagen Docker mínima
- Demuestra que un sistema real puede ser polyglot

---

## ADR-006: Seguridad en Capas (Defense in Depth)

**Capas implementadas:**

| Capa | Implementación |
|------|---------------|
| Red | VPC private subnets, Security Groups, Network Policies |
| Identidad | IAM, IRSA, RBAC |
| Datos | KMS encryption, Secrets Manager, TLS in-transit |
| Aplicación | Rate limiting, input validation, security headers |
| Container | Non-root, read-only filesystem, no privilege escalation |
| Supply chain | Trivy image scanning, ECR scan-on-push |
| Auditoría | CloudTrail, VPC Flow Logs, EKS control plane logs |
