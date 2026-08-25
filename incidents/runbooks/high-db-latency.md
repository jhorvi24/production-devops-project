# Runbook: Alta Latencia en Base de Datos - SEV-2

## Resumen

El pool de conexiones a PostgreSQL está saturado, causando que los requests encolen y experimenten timeouts.

## Indicadores de Alerta

| Alerta | Condición |
|--------|-----------|
| DatabaseLatencyHigh | p99 DB query > 1s por 3 min |
| HighLatency | p99 HTTP request > 500ms por 5 min |
| RDS Connections High | > 80 conexiones activas (CW Alarm) |
| RDS CPU High | > 80% CPU por 15 min (CW Alarm) |

## Impacto

- **Usuarios**: Ordenes lentas, timeouts al crear pedidos
- **Severidad**: SEV-2
- **Servicios afectados**: order-service, payment-service (ambos usan RDS)

## Paso a Paso de Resolución

### Paso 1: Confirmar el problema (2 min)

```bash
# Ver métricas de RDS en CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=production-sim-dev-postgres \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum

# Ver CPU de RDS
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=production-sim-dev-postgres \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average

# Ver logs de la app para timeouts
kubectl logs -n applications -l app=order-service --tail=50 | grep -i "timeout\|slow\|error"
```

### Paso 2: Identificar root cause (5 min)

```bash
# Opción A: Performance Insights en la consola AWS
# RDS → Performance Insights → "Top SQL" muestra las queries lentas

# Opción B: Queries lentas desde psql
kubectl run psql-debug --rm -it --image=postgres:15 -n applications -- \
  psql -h $DB_HOST -U dbadmin -d production_sim -c "
    SELECT pid, now() - query_start AS duration, query, state
    FROM pg_stat_activity
    WHERE state = 'active'
    ORDER BY duration DESC
    LIMIT 10;
  "

# Opción C: Ver waiting locks (posible deadlock)
kubectl run psql-debug --rm -it --image=postgres:15 -n applications -- \
  psql -h $DB_HOST -U dbadmin -d production_sim -c "
    SELECT blocked_locks.pid AS blocked_pid,
           blocked_activity.usename AS blocked_user,
           blocking_locks.pid AS blocking_pid,
           blocking_activity.usename AS blocking_user,
           blocked_activity.query AS blocked_statement
    FROM pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
    JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
    WHERE NOT blocked_locks.granted AND blocking_locks.granted;
  "
```

### Paso 3: Mitigación (5-10 min)

```bash
# Si hay queries lentas corriendo: Terminarlas
kubectl run psql-debug --rm -it --image=postgres:15 -n applications -- \
  psql -h $DB_HOST -U dbadmin -d production_sim -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE duration > interval '30 seconds'
    AND state = 'active'
    AND query NOT LIKE '%pg_stat%';
  "

# Si el connection pool está saturado: Restart pods (libera conexiones)
kubectl rollout restart deployment/order-service -n applications

# Si es por falta de índice: Crear índice (si es urgente)
kubectl run psql-debug --rm -it --image=postgres:15 -n applications -- \
  psql -h $DB_HOST -U dbadmin -d production_sim -c "
    CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
  "
```

### Paso 4: Escalamiento si no mejora

```bash
# Opción A: Scale up RDS (toma ~5 min)
aws rds modify-db-instance \
  --db-instance-identifier production-sim-dev-postgres \
  --db-instance-class db.t3.medium \
  --apply-immediately

# Opción B: Aumentar max_connections (requiere reboot del parameter group)
# Opción C: Agregar read replica para distribuir queries de lectura
```

### Paso 5: Verificación (5 min)

```bash
# Confirmar que las conexiones bajan
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=production-sim-dev-postgres \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum

# Confirmar que la latencia baja
kubectl exec -n applications deploy/api-gateway -- \
  curl -s -w "\nTime: %{time_total}s\n" http://order-service:8000/health/ready
```

## Prevención

- [ ] Connection pooling con PgBouncer
- [ ] Query timeouts configurados (statement_timeout = 30s)
- [ ] Slow query logging habilitado (log_min_duration_statement = 1000)
- [ ] Performance Insights siempre activo
- [ ] Alertas proactivas en trending de conexiones

## EN ENTREVISTA

> "Ante alta latencia en la DB, primero verifico en Performance Insights
> qué queries están causando el problema. Si son queries lentas sin índice,
> creo el índice concurrently. Si es saturación de conexiones, reinicio los
> pods para liberar el pool y evalúo si necesito PgBouncer o scale up de la
> instancia RDS."
