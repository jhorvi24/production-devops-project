#!/bin/bash
# =============================================================================
# INJECT-FAULT.SH - Inyector de escenarios de incidentes
# =============================================================================
#
# Este script permite simular diferentes tipos de incidentes para practicar
# la respuesta y resolución.
#
# USO:
#   ./scripts/inject-fault.sh --scenario <nombre>
#   ./scripts/inject-fault.sh --list
#   ./scripts/inject-fault.sh --cleanup <nombre>
#
# EJEMPLOS:
#   ./scripts/inject-fault.sh --scenario memory-leak
#   ./scripts/inject-fault.sh --scenario network-policy
#   ./scripts/inject-fault.sh --scenario db-latency
#   ./scripts/inject-fault.sh --scenario deployment-failed
#   ./scripts/inject-fault.sh --cleanup memory-leak
#
# EN ENTREVISTA: "Creé un framework de chaos engineering donde puedo inyectar
# fallas controladas para practicar incident response. Cada escenario tiene
# un runbook asociado con el paso a paso de resolución."
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

NAMESPACE="applications"

# =====================================================================
# FUNCIONES AUXILIARES
# =====================================================================
show_header() {
  echo -e "${PURPLE}"
  echo "========================================================="
  echo "  🔥 Incident Simulator - Fault Injection"
  echo "========================================================="
  echo -e "${NC}"
}

show_scenarios() {
  echo ""
  echo "Escenarios disponibles:"
  echo ""
  echo -e "  ${YELLOW}memory-leak${NC}       - Memory leak → OOMKilled → CrashLoopBackOff"
  echo -e "  ${YELLOW}network-policy${NC}    - Bloqueo de tráfico entre servicios"
  echo -e "  ${YELLOW}db-latency${NC}        - Saturación del connection pool de DB"
  echo -e "  ${YELLOW}deployment-failed${NC} - Deploy con imagen incorrecta"
  echo ""
  echo "Uso:"
  echo "  $0 --scenario <nombre>    Inyectar falla"
  echo "  $0 --cleanup <nombre>     Limpiar falla"
  echo "  $0 --list                 Listar escenarios"
  echo ""
}

countdown() {
  local seconds=$1
  echo -e "${YELLOW}  Inyectando falla en ${seconds} segundos... (Ctrl+C para cancelar)${NC}"
  for i in $(seq $seconds -1 1); do
    echo -ne "  ${i}...\r"
    sleep 1
  done
  echo ""
}

# =====================================================================
# ESCENARIO: Memory Leak
# =====================================================================
inject_memory_leak() {
  echo -e "${RED}[INJECT] Escenario: Memory Leak (OOMKilled)${NC}"
  echo ""
  echo "  Servicio afectado: payment-service"
  echo "  Severidad esperada: SEV-2"
  echo "  Tiempo de resolución: 10-20 min"
  echo ""
  echo "  SÍNTOMAS que verás:"
  echo "  - Pod en CrashLoopBackOff"
  echo "  - Alerta PodMemoryHigh"
  echo "  - Payment failures incrementando"
  echo ""
  echo -e "  RUNBOOK: ${BLUE}incidents/runbooks/memory-leak.md${NC}"
  echo ""

  countdown 5

  echo -e "${RED}  Inyectando memory leak...${NC}"
  for i in $(seq 1 30); do
    kubectl exec -n ${NAMESPACE} deploy/api-gateway -- \
      curl -s -X POST http://payment-service:8080/debug/leak > /dev/null 2>&1 || true
    echo -ne "  Leaked: $((i * 10)) MB\r"
    sleep 2
  done

  echo ""
  echo -e "${RED}  ✓ Memory leak inyectado (300MB). El pod debería ser OOMKilled pronto.${NC}"
  echo ""
  echo -e "${YELLOW}  AHORA: Abre el runbook y resuelve el incidente.${NC}"
  echo -e "${YELLOW}  Monitorear: kubectl get pods -n ${NAMESPACE} -l app=payment-service -w${NC}"
}

cleanup_memory_leak() {
  echo -e "${GREEN}[CLEANUP] Limpiando memory leak...${NC}"
  kubectl rollout restart deployment/payment-service -n ${NAMESPACE}
  kubectl rollout status deployment/payment-service -n ${NAMESPACE} --timeout=120s
  echo -e "${GREEN}  ✓ payment-service reiniciado y healthy${NC}"
}

# =====================================================================
# ESCENARIO: Network Policy
# =====================================================================
inject_network_policy() {
  echo -e "${RED}[INJECT] Escenario: Network Policy Misconfigured${NC}"
  echo ""
  echo "  Servicio afectado: order-service → payment-service"
  echo "  Severidad esperada: SEV-2"
  echo "  Tiempo de resolución: 15-30 min"
  echo ""
  echo "  SÍNTOMAS que verás:"
  echo "  - Payment timeouts en order-service"
  echo "  - payment-service SIGUE healthy (readiness OK)"
  echo "  - Pero order-service NO PUEDE alcanzarlo"
  echo ""
  echo -e "  RUNBOOK: ${BLUE}incidents/runbooks/network-policy-misconfigured.md${NC}"
  echo ""

  countdown 5

  echo -e "${RED}  Aplicando NetworkPolicy restrictiva...${NC}"
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-order-to-payment
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: order-service
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
EOF

  echo -e "${RED}  ✓ NetworkPolicy aplicada. order-service ya no puede hablar con payment-service.${NC}"
  echo ""
  echo -e "${YELLOW}  AHORA: Intenta crear una orden y observa el timeout.${NC}"
  echo -e "${YELLOW}  Test: kubectl exec -n ${NAMESPACE} deploy/order-service -- wget --timeout=5 -qO- http://payment-service:8080/health/live${NC}"
}

cleanup_network_policy() {
  echo -e "${GREEN}[CLEANUP] Eliminando NetworkPolicy conflictiva...${NC}"
  kubectl delete networkpolicy block-order-to-payment -n ${NAMESPACE} --ignore-not-found
  echo -e "${GREEN}  ✓ Tráfico restaurado entre order-service y payment-service${NC}"
}

# =====================================================================
# ESCENARIO: DB Latency
# =====================================================================
inject_db_latency() {
  echo -e "${RED}[INJECT] Escenario: High Database Latency${NC}"
  echo ""
  echo "  Servicio afectado: order-service"
  echo "  Severidad esperada: SEV-2"
  echo "  Tiempo de resolución: 15-30 min"
  echo ""
  echo "  SÍNTOMAS que verás:"
  echo "  - Latencia alta en order-service"
  echo "  - CloudWatch alarm: RDS connections high"
  echo "  - Timeouts en cascada"
  echo ""
  echo -e "  RUNBOOK: ${BLUE}incidents/runbooks/high-db-latency.md${NC}"
  echo ""

  countdown 5

  echo -e "${RED}  Generando carga en la base de datos...${NC}"
  echo -e "${YELLOW}  NOTA: Esto requiere acceso al endpoint de RDS.${NC}"
  echo -e "${YELLOW}  Si estás en local, simula con load testing al order-service:${NC}"
  echo ""
  echo "  # Instalar hey (HTTP load generator)"
  echo "  # go install github.com/rakyll/hey@latest"
  echo ""
  echo "  # Generar 200 requests concurrentes al order-service"
  echo "  kubectl port-forward svc/api-gateway -n ${NAMESPACE} 3000:3000 &"
  echo "  hey -n 1000 -c 200 -m POST \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"customer_id\":\"stress\",\"items\":[{\"id\":\"1\"}],\"total_amount\":10}' \\"
  echo "    http://localhost:3000/api/orders"
  echo ""
  echo -e "${RED}  ✓ Instrucciones mostradas. Ejecuta el load test manualmente.${NC}"
}

cleanup_db_latency() {
  echo -e "${GREEN}[CLEANUP] Limpiando DB latency...${NC}"
  kubectl rollout restart deployment/order-service -n ${NAMESPACE}
  echo -e "${GREEN}  ✓ order-service reiniciado (conexiones liberadas)${NC}"
}

# =====================================================================
# ESCENARIO: Deployment Failed
# =====================================================================
inject_deployment_failed() {
  echo -e "${RED}[INJECT] Escenario: Failed Deployment${NC}"
  echo ""
  echo "  Servicio afectado: api-gateway"
  echo "  Severidad esperada: SEV-3"
  echo "  Tiempo de resolución: 5-15 min"
  echo ""
  echo "  SÍNTOMAS que verás:"
  echo "  - Pods nuevos en CrashLoopBackOff"
  echo "  - Pods viejos siguen sirviendo (por maxUnavailable: 0)"
  echo "  - ArgoCD muestra status: Degraded"
  echo ""
  echo -e "  RUNBOOK: ${BLUE}incidents/runbooks/deployment-failed.md${NC}"
  echo ""

  countdown 5

  echo -e "${RED}  Desplegando imagen incorrecta...${NC}"
  kubectl set image deployment/api-gateway \
    api-gateway=busybox:latest \
    -n ${NAMESPACE}

  echo -e "${RED}  ✓ Imagen incorrecta desplegada. Los pods nuevos van a crashear.${NC}"
  echo ""
  echo -e "${YELLOW}  AHORA: Observa los pods y haz rollback.${NC}"
  echo -e "${YELLOW}  Monitor: kubectl get pods -n ${NAMESPACE} -l app=api-gateway -w${NC}"
}

cleanup_deployment_failed() {
  echo -e "${GREEN}[CLEANUP] Haciendo rollback del deployment...${NC}"
  kubectl rollout undo deployment/api-gateway -n ${NAMESPACE}
  kubectl rollout status deployment/api-gateway -n ${NAMESPACE} --timeout=120s
  echo -e "${GREEN}  ✓ api-gateway restaurado a versión anterior${NC}"
}

# =====================================================================
# MAIN
# =====================================================================
show_header

case "${1:-}" in
  --list)
    show_scenarios
    ;;
  --scenario)
    case "${2:-}" in
      memory-leak)       inject_memory_leak ;;
      network-policy)    inject_network_policy ;;
      db-latency)        inject_db_latency ;;
      deployment-failed) inject_deployment_failed ;;
      *)
        echo -e "${RED}Error: Escenario desconocido '${2:-}'${NC}"
        show_scenarios
        exit 1
        ;;
    esac
    ;;
  --cleanup)
    case "${2:-}" in
      memory-leak)       cleanup_memory_leak ;;
      network-policy)    cleanup_network_policy ;;
      db-latency)        cleanup_db_latency ;;
      deployment-failed) cleanup_deployment_failed ;;
      *)
        echo -e "${RED}Error: Escenario desconocido '${2:-}'${NC}"
        exit 1
        ;;
    esac
    ;;
  *)
    show_scenarios
    ;;
esac
