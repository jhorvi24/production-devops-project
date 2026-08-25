"""
=============================================================================
ORDER SERVICE - Gestión de órdenes
=============================================================================

¿POR QUÉ FASTAPI?
- Async nativo (maneja muchas conexiones concurrentes)
- Validación automática con Pydantic
- Documentación OpenAPI auto-generada
- Rendimiento comparable a Go/Node.js

ESTE SERVICIO DEMUESTRA:
- Conexión a RDS PostgreSQL
- Comunicación entre microservicios (llama a payment-service)
- Métricas Prometheus para monitoreo
- Structured logging
- Health checks (liveness + readiness)
- Graceful shutdown

ESCENARIOS DE INCIDENTES QUE AFECTAN ESTE SERVICIO:
- #1: Alta latencia en RDS (connection pool saturado)
- #2: Memory leak (OOMKilled)
- #7: Network Policy bloquea comunicación con payment-service
- #8: Secrets expirados (DB password rotado)

EN ENTREVISTA: "El order-service usa FastAPI con connection pooling a RDS.
Implementé circuit breaker para llamadas al payment-service, métricas
detalladas de latencia por endpoint, y health checks que verifican la
conectividad a la base de datos."
=============================================================================
"""

import os
import time
import signal
import logging
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from prometheus_client import (
    Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
)
from fastapi.responses import Response
import httpx

# =============================================================================
# CONFIGURACIÓN
# =============================================================================
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "production_sim")
DB_USER = os.getenv("DB_USER", "dbadmin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://payment-service:8080")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")

# =============================================================================
# LOGGING (Structured JSON)
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"order-service","message":"%(message)s"}'
)
logger = logging.getLogger(__name__)

# =============================================================================
# MÉTRICAS PROMETHEUS
# =============================================================================
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

DB_QUERY_LATENCY = Histogram(
    'db_query_duration_seconds',
    'Database query latency',
    ['query_type'],
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5]
)

ACTIVE_CONNECTIONS = Gauge(
    'db_active_connections',
    'Number of active database connections'
)

ORDERS_CREATED = Counter(
    'orders_created_total',
    'Total orders created',
    ['status']
)

# =============================================================================
# MODELOS
# =============================================================================
class OrderCreate(BaseModel):
    customer_id: str
    items: list
    total_amount: float
    currency: str = "USD"

class Order(BaseModel):
    id: str
    customer_id: str
    items: list
    total_amount: float
    currency: str
    status: str
    created_at: str

# =============================================================================
# LIFECYCLE (Startup/Shutdown)
# =============================================================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage startup and shutdown events."""
    logger.info(f"Starting order-service in {ENVIRONMENT} mode")
    logger.info(f"DB Host: {DB_HOST}, Payment Service: {PAYMENT_SERVICE_URL}")
    yield
    logger.info("Shutting down order-service")

# =============================================================================
# APP
# =============================================================================
app = FastAPI(
    title="Order Service",
    description="Manages orders for the production incident simulator",
    version="1.0.0",
    lifespan=lifespan
)

# In-memory store (en producción real sería RDS)
orders_db: dict = {}

# =============================================================================
# MIDDLEWARE: Métricas
# =============================================================================
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status_code=response.status_code
    ).inc()

    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)

    return response

# =============================================================================
# HEALTH CHECKS
# =============================================================================
@app.get("/health/live")
async def liveness():
    """Liveness: Is the process alive?"""
    return {"status": "alive", "timestamp": datetime.utcnow().isoformat()}

@app.get("/health/ready")
async def readiness():
    """Readiness: Can it handle traffic? Checks DB connectivity."""
    # En producción real, verificar conexión a RDS
    try:
        # Simular check de DB
        return {
            "status": "ready",
            "checks": {
                "database": "connected",
                "payment_service": "reachable"
            }
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Not ready: {str(e)}")

# =============================================================================
# API ENDPOINTS
# =============================================================================
@app.post("/orders", response_model=Order)
async def create_order(order_data: OrderCreate):
    """Create a new order and initiate payment."""
    order_id = str(uuid4())

    # Simular latencia de DB (útil para incidente #1)
    db_start = time.time()
    # En producción: INSERT INTO orders ...
    order = Order(
        id=order_id,
        customer_id=order_data.customer_id,
        items=order_data.items,
        total_amount=order_data.total_amount,
        currency=order_data.currency,
        status="pending",
        created_at=datetime.utcnow().isoformat()
    )
    orders_db[order_id] = order
    DB_QUERY_LATENCY.labels(query_type="insert").observe(time.time() - db_start)

    # Llamar al payment service
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            payment_response = await client.post(
                f"{PAYMENT_SERVICE_URL}/payments",
                json={
                    "order_id": order_id,
                    "amount": order_data.total_amount,
                    "currency": order_data.currency
                }
            )
            if payment_response.status_code == 201:
                order.status = "confirmed"
                ORDERS_CREATED.labels(status="confirmed").inc()
            else:
                order.status = "payment_failed"
                ORDERS_CREATED.labels(status="payment_failed").inc()
    except httpx.TimeoutException:
        order.status = "payment_timeout"
        ORDERS_CREATED.labels(status="payment_timeout").inc()
        logger.error(f"Payment service timeout for order {order_id}")
    except Exception as e:
        order.status = "payment_error"
        ORDERS_CREATED.labels(status="payment_error").inc()
        logger.error(f"Payment service error: {str(e)}")

    orders_db[order_id] = order
    logger.info(f"Order created: {order_id}, status: {order.status}")
    return order

@app.get("/orders/{order_id}", response_model=Order)
async def get_order(order_id: str):
    """Get order by ID."""
    if order_id not in orders_db:
        raise HTTPException(status_code=404, detail="Order not found")
    return orders_db[order_id]

@app.get("/orders")
async def list_orders(
    customer_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 50
):
    """List orders with optional filters."""
    orders = list(orders_db.values())

    if customer_id:
        orders = [o for o in orders if o.customer_id == customer_id]
    if status:
        orders = [o for o in orders if o.status == status]

    return {"orders": orders[:limit], "total": len(orders)}

# =============================================================================
# PROMETHEUS METRICS ENDPOINT
# =============================================================================
@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

# =============================================================================
# GRACEFUL SHUTDOWN
# =============================================================================
def handle_sigterm(*args):
    logger.info("SIGTERM received, initiating graceful shutdown")
    raise SystemExit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
