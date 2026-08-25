# =============================================================================
# DOCKERFILE - Order Service (Python/FastAPI)
# =============================================================================
# ¿POR QUÉ PYTHON PARA ESTE SERVICIO?
# - Demuestra que un sistema de microservicios puede ser polyglot
# - FastAPI es uno de los frameworks más rápidos de Python
# - En un equipo real, cada equipo elige su stack
# =============================================================================

# Stage 1: Build
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Production
FROM python:3.11-slim AS production

LABEL maintainer="devops-team"
LABEL description="Order Service for Production Incident Simulator"

# Crear usuario non-root
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup -s /bin/sh appuser

WORKDIR /app

# Copiar dependencias instaladas
COPY --from=builder /root/.local /home/appuser/.local
ENV PATH=/home/appuser/.local/bin:$PATH

# Copiar código
COPY app/ ./app/

RUN mkdir -p /tmp && chown appuser:appgroup /tmp

USER appuser

EXPOSE 8000 9090

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/live')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
