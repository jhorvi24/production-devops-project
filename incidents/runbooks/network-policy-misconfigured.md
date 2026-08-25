# Runbook: Network Policy Mal Configurada - SEV-2

## Resumen

Una NetworkPolicy está bloqueando tráfico legítimo entre microservicios, causando timeouts de comunicación.

## Indicadores de Alerta

| Alerta | Condición |
|--------|-----------|
| PaymentFailureRateHigh | > 10% pagos fallando |
| HighErrorRate | > 5% error rate en order-service |

## Lo engañoso de este incidente

- El payment-service está **HEALTHY** (readiness probe pasa)
- Pero order-service **NO PUEDE** comunicarse con él
- No hay errors en payment-service logs (nunca recibe el request)
- El error está en la CAPA DE RED, no en la aplicación

## Paso a Paso de Resolución

### Paso 1: Confirmar conectividad (3 min)

```bash
# Test de conectividad desde order-service a payment-service
kubectl exec -n applications deploy/order-service -- \
  wget --timeout=5 -qO- http://payment-service:8080/health/live

# Si timeout → problema de red confirmado

# Verificar que payment-service está Running
kubectl get pods -n applications -l app=payment-service

# Verificar que el Service existe y tiene endpoints
kubectl get endpoints payment-service -n applications
```

### Paso 2: Inspeccionar NetworkPolicies (5 min)

```bash
# Listar TODAS las NetworkPolicies del namespace
kubectl get networkpolicies -n applications

# Ver detalles de cada una (buscar la conflictiva)
kubectl describe networkpolicies -n applications

# CLAVE: Si hay una policy "deny-all" + policies específicas,
# buscar cuál falta o cuál está bloqueando
kubectl get networkpolicy -n applications -o yaml > /tmp/all-policies.yaml
```

**¿Qué buscar?**
- ¿Hay una policy deny-all que bloquea todo?
- ¿Las policies de egress del order-service incluyen el puerto 8080?
- ¿Las policies de ingress del payment-service aceptan traffic del order-service?
- ¿Los labels matchean correctamente?

### Paso 3: Identificar la policy conflictiva (5 min)

```bash
# Comparar con las políticas originales en Git
git diff HEAD k8s/base/network-policies.yaml

# Buscar policies que no pertenecen
kubectl get networkpolicies -n applications -o name | sort

# Las esperadas son:
# - deny-all
# - allow-ingress-to-api-gateway
# - allow-api-gateway-egress
# - allow-order-service
# - allow-payment-service
# - allow-monitoring-scrape
#
# ¿Hay alguna extra? ¿Falta alguna?
```

### Paso 4: Fix (2 min)

```bash
# Opción A: Eliminar la policy conflictiva
kubectl delete networkpolicy block-order-to-payment -n applications

# Opción B: Re-aplicar las policies correctas desde Git
kubectl apply -f k8s/base/network-policies.yaml

# Opción C: En emergencia, eliminar deny-all temporalmente
# (SOLO como último recurso, abre todo el tráfico)
kubectl delete networkpolicy deny-all -n applications
```

### Paso 5: Verificar (3 min)

```bash
# Test de conectividad
kubectl exec -n applications deploy/order-service -- \
  wget --timeout=5 -qO- http://payment-service:8080/health/live

# Test funcional (crear una orden que requiere pago)
kubectl exec -n applications deploy/api-gateway -- \
  curl -s -X POST http://order-service:8000/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"test","items":[{"id":"1"}],"total_amount":10.00}'

# Monitorear que el error rate baje
# Grafana → Services Overview → Error Rate
```

## Debugging avanzado con tcpdump

```bash
# Si el test de conectividad es ambiguo, capturar paquetes:
kubectl debug -it deploy/order-service -n applications --image=nicolaka/netshoot -- \
  tcpdump -i any host payment-service -c 20
```

## Prevención

- [ ] Validar NetworkPolicies en CI antes de aplicar
- [ ] Test de conectividad automatizado post-deploy
- [ ] Labels y selectors estandarizados y documentados
- [ ] ArgoCD selfHeal para revertir cambios manuales

## EN ENTREVISTA

> "Para troubleshootear Network Policies, primero confirmo el problema con
> un test de conectividad directo desde el pod afectado usando exec. Luego
> listo todas las policies del namespace y busco conflictos entre deny-all
> y las políticas de allow. El error más común es un label mismatch o un
> puerto incorrecto en la regla de egress."
