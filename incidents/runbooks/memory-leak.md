# Runbook: Memory Leak (OOMKilled) - SEV-2

## Resumen

Un pod está consumiendo memoria de forma continua hasta exceder su limit, causando OOMKilled y CrashLoopBackOff.

## Indicadores de Alerta

| Alerta | Condición |
|--------|-----------|
| PodMemoryHigh | container_memory > 90% del limit por 5 min |
| PodCrashLooping | Pod reiniciando frecuentemente |
| PaymentFailureRateHigh | > 10% de pagos fallan |

## Impacto

- **Usuarios**: Pagos fallando intermitentemente
- **Severidad**: SEV-2 (servicio degradado, no completamente caído)
- **Blast radius**: Solo payment-service (order-service fallback a status "payment_timeout")

## Paso a Paso de Resolución

### Paso 1: Confirmar el problema (2 min)

```bash
# Ver estado de los pods
kubectl get pods -n applications -l app=payment-service

# Buscar OOMKilled en events
kubectl describe pod -n applications -l app=payment-service | grep -A5 "Last State"

# Ver consumo actual de recursos
kubectl top pods -n applications -l app=payment-service
```

**¿Qué buscar?**
- `OOMKilled` en el campo "Last State"
- `CrashLoopBackOff` en STATUS
- Memory usage cercana al limit (256Mi para payment-service)

### Paso 2: Mitigación inmediata (5 min)

```bash
# Opción A: Restart del deployment (limpia la memoria leaked)
kubectl rollout restart deployment/payment-service -n applications

# Opción B: Si el restart no ayuda (leak es muy rápido),
# aumentar temporalmente el memory limit
kubectl patch deployment payment-service -n applications -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "payment-service",
          "resources": {
            "limits": {
              "memory": "512Mi"
            }
          }
        }]
      }
    }
  }
}'
```

### Paso 3: Diagnóstico de root cause (10-15 min)

```bash
# Ver logs antes del OOMKill
kubectl logs -n applications deploy/payment-service --previous

# Verificar métricas de memoria (qué está creciendo)
# En Grafana: query container_memory_usage_bytes{pod=~"payment.*"}

# Para Go: pprof heap profile
kubectl port-forward deploy/payment-service -n applications 6060:6060
# Luego: go tool pprof http://localhost:6060/debug/pprof/heap

# Buscar el endpoint que causa el leak
kubectl logs -n applications -l app=payment-service | grep "debug/leak"
```

### Paso 4: Fix permanente

```bash
# En este caso: deshabilitar o proteger el endpoint de debug
# 1. Remover /debug/leak en producción
# 2. O protegerlo con auth

# Deploy del fix vía GitOps:
git commit -m "fix: remove debug leak endpoint in production"
git push origin main
# ArgoCD sincronizará automáticamente
```

### Paso 5: Verificación (5 min)

```bash
# Confirmar que el pod está Running estable
kubectl get pods -n applications -l app=payment-service -w

# Verificar que la memoria es estable (no crece linealmente)
kubectl top pods -n applications -l app=payment-service
# Esperar 2-3 minutos y verificar que no crece

# Verificar que los pagos funcionan
kubectl exec -n applications deploy/api-gateway -- \
  curl -s -X POST http://payment-service:8080/payments \
  -H "Content-Type: application/json" \
  -d '{"order_id":"test","amount":10.00,"currency":"USD"}'
```

## Prevención

- [ ] Configurar alerts de memory trending (crecimiento lineal = leak)
- [ ] Code review para endpoints de debug en producción
- [ ] Memory profiling en CI pipeline
- [ ] Resource limits siempre configurados
- [ ] PDB para mantener al menos 1 replica durante restarts

## Comunicación

- **Escalar a**: Team lead si no se resuelve en 20 min
- **Notificar**: Canal #incidents en Slack
- **Status page**: Actualizar si pagos están fallando > 5 min

## EN ENTREVISTA

> "Cuando detecto un OOMKilled, primero hago rollout restart para mitigar
> inmediatamente. Luego investigo con logs --previous y métricas de memoria
> en Grafana. Para Go, uso pprof para obtener heap profiles. El fix se
> despliega vía GitOps y verifico que la memoria se estabiliza."
