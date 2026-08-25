# Proceso de Respuesta a Incidentes

## Severidades

| Nivel | Criterio | Tiempo de Respuesta | Ejemplo |
|-------|----------|---------------------|---------|
| SEV-1 | Servicio completamente caído | < 5 min | TLS expirado, secrets inválidos |
| SEV-2 | Servicio degradado | < 15 min | Memory leak, DB latency alta |
| SEV-3 | Impacto menor | < 1 hora | Deployment fallido (old pods sirven) |

## Flujo de Respuesta

```
ALERTA DISPARA
     │
     ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  1. DETECT  │────▶│  2. TRIAGE   │────▶│  3. MITIGATE│
│  (Automático)│     │  (Severidad) │     │  (Inmediato)│
└─────────────┘     └──────────────┘     └─────────────┘
                                                │
     ┌──────────────────────────────────────────┘
     │
     ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ 4. ROOT     │────▶│  5. FIX      │────▶│ 6. POSTMORT │
│    CAUSE    │     │  (Permanente)│     │ (Documentar)│
└─────────────┘     └──────────────┘     └─────────────┘
```

## 1. DETECT (Automático)

Las alertas de Prometheus/CloudWatch detectan violaciones de SLOs:
- Error rate > 5% → Alerta crítica
- P99 latency > 500ms → Alerta warning
- Pod CrashLooping → Alerta crítica

## 2. TRIAGE (2 minutos)

Preguntas clave:
- ¿Qué servicio está afectado? (Grafana dashboard)
- ¿Desde cuándo? (timeline de métricas)
- ¿Hubo un deploy reciente? (ArgoCD history)
- ¿Cuántos usuarios impactados? (traffic metrics)

## 3. MITIGATE (5-15 minutos)

Acciones comunes de mitigación inmediata:
- **Rollback**: `kubectl rollout undo deployment/X`
- **Scale up**: `kubectl scale deployment/X --replicas=5`
- **Restart**: `kubectl rollout restart deployment/X`
- **Revert config**: `git revert && git push` (ArgoCD aplica)
- **Bypass**: Redirect traffic away from unhealthy service

## 4. ROOT CAUSE (Variable)

Herramientas de investigación:
```bash
# Logs recientes
kubectl logs -n applications -l app=X --tail=100

# Eventos del cluster
kubectl get events -n applications --sort-by=.lastTimestamp

# Métricas de recursos
kubectl top pods -n applications

# Network connectivity
kubectl exec deploy/X -- wget --timeout=5 -qO- http://service:port/health

# CloudWatch para infra AWS
aws cloudwatch get-metric-statistics --namespace AWS/RDS ...
```

## 5. FIX (Permanente)

El fix permanente va por el flujo normal:
1. Branch → Fix → PR → Review → Merge
2. CI pipeline: test → build → push
3. ArgoCD sincroniza automáticamente
4. Verificar en production que el fix funciona

## 6. POSTMORTEM

Template de postmortem:
- **Impacto**: Duración, usuarios afectados, revenue impactado
- **Timeline**: Minuto a minuto de lo que pasó
- **Root cause**: Causa raíz real (no síntomas)
- **Resolución**: Qué se hizo para resolver
- **Prevention items**: ¿Cómo evitamos que pase de nuevo?
- **Learnings**: ¿Qué aprendimos? (blameless)

## Escenarios Practicables

Usa el script de inyección de fallas para practicar:

```bash
# Ver escenarios disponibles
./scripts/inject-fault.sh --list

# Inyectar una falla
./scripts/inject-fault.sh --scenario memory-leak

# Resolver usando el runbook correspondiente
# Ver: incidents/runbooks/memory-leak.md

# Limpiar cuando termines
./scripts/inject-fault.sh --cleanup memory-leak
```

## Comunicación Durante Incidentes

1. **Notificar** al canal de incidentes (Slack #incidents)
2. **Status page**: Actualizar cada 15 minutos si impacta usuarios
3. **Escalar** si no resuelves en el tiempo esperado para la severidad
4. **Postmortem** dentro de 48 horas del incidente
