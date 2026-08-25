# Guía de Preparación para Entrevistas - Cloud Engineer / DevOps

## Cómo usar este documento

Este documento compila las respuestas a preguntas comunes de entrevista para posiciones de Cloud Engineer y DevOps. Cada respuesta está vinculada a componentes reales de este proyecto que puedes mostrar como evidencia.

---

## 1. Infraestructura como Código (Terraform)

### "¿Cómo gestionas la infraestructura?"

> "Uso Terraform con módulos reutilizables para VPC, EKS y RDS. Cada ambiente (dev/prod) tiene su propio state file en S3 con DynamoDB locking para evitar conflictos. Los módulos encapsulan la lógica de cada servicio y los ambientes solo difieren en los valores de las variables, no en el código."

**Mostrar:** `terraform/modules/`, `terraform/environments/`

### "¿Cómo manejas el estado de Terraform en equipo?"

> "Backend remoto en S3 con versionado y encriptación KMS. DynamoDB proporciona state locking distribuido para que dos ingenieros no apliquen cambios simultáneamente. Cada ambiente tiene su propio key en S3 para aislamiento total."

**Mostrar:** `terraform/backend.tf`, `scripts/bootstrap-backend.sh`

### "¿Cuál es la diferencia entre tu ambiente dev y prod?"

| Aspecto | Dev | Prod |
|---------|-----|------|
| Instancias EKS | t3.medium SPOT | t3.large ON_DEMAND |
| NAT Gateways | 1 (ahorro) | 3 (uno por AZ, HA) |
| RDS Multi-AZ | No | Sí |
| VPC Flow Logs | No | Sí |
| Deletion Protection | No | Sí |

**Mostrar:** `terraform/environments/dev/main.tf` vs `terraform/environments/prod/main.tf`

---

## 2. Kubernetes / EKS

### "¿Cómo diseñas un cluster de Kubernetes para producción?"

> "Cluster EKS con Managed Node Groups en subnets privadas. Uso IRSA para permisos IAM granulares por pod (principio de mínimo privilegio). Habilito todos los logs del control plane para troubleshooting. Para HA, distribuyo nodos en 3 AZs con pod anti-affinity para que las réplicas no estén en el mismo nodo."

**Mostrar:** `terraform/modules/eks/`, `k8s/apps/api-gateway/deployment.yaml`

### "¿Cómo aseguras un cluster de Kubernetes?"

> "Múltiples capas: Network Policies con estrategia deny-all (microsegmentación), RBAC con roles específicos por función (developer solo lee, CI/CD solo despliega), SecurityContext non-root con filesystem read-only, Resource Quotas por namespace, y IRSA para que cada pod solo tenga los permisos IAM que necesita."

**Mostrar:** `k8s/base/network-policies.yaml`, `k8s/base/rbac.yaml`

### "¿Cómo manejas el escalamiento?"

> "HPA (Horizontal Pod Autoscaler) basado en CPU y memoria con behavior rules para evitar flapping. El scale-up es agresivo (15s estabilización) para responder rápido a picos. El scale-down es conservador (5 minutos) para evitar oscilaciones. También tengo Cluster Autoscaler para agregar nodos cuando no hay capacidad."

**Mostrar:** `k8s/apps/api-gateway/hpa.yaml`

### "¿Qué es un PDB y por qué lo usas?"

> "Un Pod Disruption Budget garantiza un mínimo de pods disponibles durante disrupciones voluntarias como upgrades de nodos o scaling. Sin PDB, Kubernetes podría terminar todos los pods de un servicio durante mantenimiento. Mi PDB dice 'siempre al menos 1 pod disponible', así que el drain de nodos espera a que los pods se reagenden antes de continuar."

**Mostrar:** `k8s/apps/api-gateway/pdb.yaml`

---

## 3. CI/CD y GitOps

### "Explica tu pipeline de CI/CD"

> "El pipeline tiene 4 fases: Source (detecta cambios en Git), Build (tests + Docker build + push a ECR), Security (scan de vulnerabilidades con Trivy), y Deploy (actualiza manifests en Git → ArgoCD sincroniza). El deploy nunca toca el cluster directamente - sigue el patrón GitOps donde Git es la única fuente de verdad."

**Mostrar:** `ci-cd/buildspec.yml`, `ci-cd/github-actions.yml`

### "¿Por qué GitOps y no kubectl apply desde CI?"

> "Tres razones: 1) Seguridad - el pipeline no necesita credenciales del cluster. 2) Auditoría - cada cambio es un commit con autor y timestamp. 3) Rollback instantáneo - git revert = rollback en producción en segundos. Además, ArgoCD detecta drift (si alguien modifica el cluster manualmente, lo revierte)."

**Mostrar:** `k8s/argocd/applications/`

### "¿Cómo haces rollback?"

> "Para aplicaciones: `kubectl rollout undo` para inmediato, o `git revert` para GitOps. Para infraestructura: Terraform tiene el state anterior en S3 versionado. En ambos casos el rollback es cuestión de segundos/minutos, no de reconstruir todo."

---

## 4. Observabilidad

### "¿Cómo monitoreas tus servicios?"

> "Tres pilares: Métricas (Prometheus + CloudWatch), Logs (structured JSON → CloudWatch Insights), y Traces (X-Ray). Uso los 4 golden signals de SRE: latencia, tráfico, errores, y saturación. Cada servicio expone métricas Prometheus en /metrics que se scrapean automáticamente vía annotations."

**Mostrar:** `monitoring/`, `k8s/monitoring/`

### "¿Cómo defines tus alertas?"

> "Alerto sobre SÍNTOMAS que afectan al usuario, no sobre causas. 'Error rate > 5%' es actionable. 'CPU alta' por sí sola no lo es (puede ser normal bajo carga). Cada alerta tiene: severidad, equipo responsable, y link a un runbook con el paso a paso de resolución."

**Mostrar:** `k8s/monitoring/alerting-rules.yaml`

### "¿Qué SLOs tienes definidos?"

> "Disponibilidad 99.9% (43 min downtime/mes máximo), P99 latencia < 500ms, y error rate < 1%. Los SLOs están codificados como alerting rules en Prometheus. Si el error budget se consume, paramos features y priorizamos fiabilidad."

---

## 5. Respuesta a Incidentes

### "Cuéntame sobre un incidente que hayas manejado"

> "Simulé un escenario donde una Network Policy mal configurada bloqueaba la comunicación entre servicios. Los síntomas eran: payment timeouts, pero payment-service reportaba healthy. Lo engañoso es que el problema estaba en la capa de red, no en la aplicación. Diagnostiqué con exec + wget entre pods, identifiqué la policy conflictiva con kubectl describe, y la eliminé. Resolución: 15 minutos."

**Mostrar:** `incidents/runbooks/network-policy-misconfigured.md`

### "¿Cómo es tu proceso de incident response?"

> "1. DETECT: Alertas basadas en SLOs disparan. 2. TRIAGE: Determinar severidad y servicios afectados. 3. MITIGATE: Acción inmediata para restaurar servicio (rollback, restart, scale). 4. ROOT CAUSE: Investigar con logs, métricas, y traces. 5. FIX: Deploy permanente del fix. 6. POSTMORTEM: Documentar, identificar prevention items."

### "¿Qué herramientas usas para troubleshooting?"

| Capa | Herramienta | Uso |
|------|-------------|-----|
| Infra AWS | CloudWatch Alarms | RDS, ALB, nodos |
| Cluster | kubectl + events | Estado de pods/nodos |
| Aplicación | Prometheus + Grafana | Métricas custom |
| Logs | CloudWatch Insights | Queries sobre logs JSON |
| Red | NetworkPolicy + tcpdump | Conectividad entre pods |
| DB | Performance Insights | Queries lentas |

---

## 6. Arquitectura y Diseño

### "¿Por qué microservicios y no monolito?"

> "Para este proyecto de simulación, microservicios me permite demostrar: comunicación inter-servicio, fallas parciales (un servicio caído no tumba todo), escalamiento independiente, y deployments independientes. En la vida real, empezaría monolito y extraería servicios solo cuando el equipo o la carga lo justifique."

### "¿Por qué EKS y no ECS?"

> "Kubernetes es el estándar de la industria para orquestación. Las habilidades son transferibles entre clouds (GKE, AKS). El ecosistema (Helm, ArgoCD, Prometheus, Istio) es incomparable. Y la demanda laboral es significativamente mayor para Kubernetes."

### "¿Cómo gestionas secrets?"

> "AWS Secrets Manager para credenciales de DB con rotación automática. En Kubernetes, uso External Secrets Operator que sincroniza desde Secrets Manager a K8s Secrets. IRSA para que cada pod solo pueda leer los secrets que le corresponden. Nunca hardcodeo credenciales en código o manifests."

**Mostrar:** `terraform/modules/rds/main.tf` (sección de Secrets Manager)

---

## 7. Preguntas Situacionales

### "Un servicio está lento. ¿Cómo lo diagnosticas?"

> "1. Grafana: ¿Cuál servicio tiene latencia alta? (golden signals dashboard). 2. ¿Es la app o la DB? (db_query_duration_seconds). 3. Si es la DB: Performance Insights → Top SQL. 4. Si es la app: resource usage (CPU/memory). 5. Si son recursos: ¿HPA escaló? ¿Cluster Autoscaler agregó nodos? 6. Si es red: Network Policy o DNS."

### "¿Cómo reduces costos en AWS?"

> "1. Spot instances para dev/staging (60-90% ahorro). 2. Teardown de ambientes no-prod fuera de horario. 3. RDS db.t3.micro para dev (vs db.t3.medium en prod). 4. Un solo NAT Gateway en dev (vs uno por AZ en prod). 5. ECR lifecycle policies (mantener solo 10 imágenes). 6. S3 lifecycle rules para logs viejos."

### "Tu cluster se queda sin nodos. ¿Qué haces?"

> "Primero verifico si hay pods Pending con kubectl get pods. Luego kubectl describe pod para ver el evento de scheduling (Insufficient cpu/memory). Verifico el Cluster Autoscaler logs. Si no está escalando: revisar maxSize del node group, IAM permissions del autoscaler, y tags de los subnets. Como mitigación inmediata: scale manual del ASG."

---

## 8. Tecnologías para mencionar en tu CV

| Categoría | Tecnologías |
|-----------|-------------|
| Cloud | AWS (EKS, RDS, VPC, IAM, CloudWatch, ECR, ALB, S3) |
| IaC | Terraform, CloudFormation |
| Containers | Docker, Kubernetes, Helm |
| CI/CD | GitHub Actions, AWS CodePipeline, CodeBuild, ArgoCD |
| Monitoring | Prometheus, Grafana, CloudWatch, X-Ray |
| Languages | Python, Go, Node.js, Bash, HCL |
| Security | Network Policies, RBAC, IRSA, Secrets Manager, Trivy |
| Metodologías | GitOps, SRE, Incident Response, Chaos Engineering |

---

## Tips Finales para la Entrevista

1. **Siempre explica el POR QUÉ**, no solo el qué
2. **Usa números**: "60-90% de ahorro", "99.9% disponibilidad", "43 min/mes downtime"
3. **Menciona trade-offs**: "Elegí X sobre Y porque..."
4. **Habla de seguridad proactivamente** (incluso si no preguntan)
5. **Demuestra experiencia con incidentes** (los runbooks son tu evidencia)
6. **Muestra el repositorio** como portfolio (link en LinkedIn/CV)
