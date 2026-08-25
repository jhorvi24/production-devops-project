# Runbook: Deployment Fallido - SEV-3

## Resumen

Un deployment nuevo causa CrashLoopBackOff o errores 500. Se necesita rollback a la versión anterior estable.

## Indicadores de Alerta

| Alerta | Condición |
|--------|-----------|
| PodCrashLooping | Pods reiniciando frecuentemente |
| HighErrorRate | > 5% error rate tras deploy |
| ArgoCD Degraded | Application status = Degraded |

## Impacto

- **Usuarios**: Errors intermitentes (si hay réplicas old que siguen vivas)
- **Severidad**: SEV-3 (si rolling update no completó, old pods siguen sirviendo)
- **Duración típica**: 5-15 min hasta rollback

## Paso a Paso de Resolución

### Paso 1: Confirmar deployment fallido (1 min)

```bash
# Ver estado del deployment
kubectl rollout status deployment/api-gateway -n applications

# Ver pods (old vs new)
kubectl get pods -n applications -l app=api-gateway -o wide

# Ver eventos recientes
kubectl get events -n applications --sort-by=.lastTimestamp | tail -20

# Ver en ArgoCD
argocd app get api-gateway
```

### Paso 2: Determinar la causa (3 min)

```bash
# Logs del pod que está fallando
kubectl logs -n applications -l app=api-gateway --container=api-gateway --tail=50

# Si está en CrashLoopBackOff, ver logs del intento anterior
kubectl logs -n applications -l app=api-gateway --previous --tail=50

# Comparar imagen actual vs anterior
kubectl get deployment api-gateway -n applications -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Causas comunes:**
- Imagen no existe en ECR (typo en tag)
- Variable de entorno faltante
- Crash en el startup (bug en el código)
- Configmap/Secret no existe
- Puerto incorrecto (probe falla)

### Paso 3: Rollback (2 min)

```bash
# Opción A: Rollback con kubectl (inmediato)
kubectl rollout undo deployment/api-gateway -n applications

# Opción B: Rollback con ArgoCD (GitOps way - preferido)
# Revertir el commit que actualizó la imagen
git revert HEAD
git push origin main
# ArgoCD sincroniza automáticamente

# Opción C: Ver historial y rollback a versión específica
kubectl rollout history deployment/api-gateway -n applications
kubectl rollout undo deployment/api-gateway -n applications --to-revision=3
```

### Paso 4: Verificar rollback (2 min)

```bash
# Confirmar que los pods viejos están Running
kubectl get pods -n applications -l app=api-gateway

# Confirmar que el rollout completó
kubectl rollout status deployment/api-gateway -n applications

# Test funcional rápido
kubectl exec -n applications deploy/api-gateway -- \
  curl -s http://localhost:3000/health/ready

# Verificar en ArgoCD
argocd app get api-gateway | grep -i "health\|status"
```

### Paso 5: Postmortem del deployment fallido

```bash
# Crear un branch con el fix
git checkout -b fix/deployment-issue
# ... fix the issue ...
git push origin fix/deployment-issue
# PR → Code Review → Merge → Deploy automático (esta vez exitoso)
```

## Prevención

- [ ] Canary deployments (deploy al 10% de pods primero)
- [ ] Automated rollback en ArgoCD si probes fallan
- [ ] Smoke tests post-deployment en CI
- [ ] maxUnavailable: 0 (nunca menos pods que los deseados)
- [ ] Readiness gates con timeout

## EN ENTREVISTA

> "Cuando un deployment falla, primero verifico los logs del pod nuevo con
> --previous flag para ver por qué crasheó. Para mitigar, hago rollback con
> kubectl rollout undo (inmediato) o git revert (GitOps). Luego investigo
> la causa root - que típicamente es un secret faltante, imagen incorrecta,
> o bug introducido en el código. El fix va por PR para evitar repetir."
