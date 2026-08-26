# =============================================================================
# DOCKERFILE - Payment Service (Go)
# =============================================================================
# ¿POR QUÉ GO PARA ESTE SERVICIO?
# - Binario estático (no necesita runtime → imagen mínima ~15MB con scratch)
# - Excelente rendimiento para servicios críticos (pagos)
# - Concurrencia nativa con goroutines
# - Demuestra un stack polyglot: Node.js + Python + Go
#
# EN ENTREVISTA: "Elegí Go para el payment-service porque es un servicio
# crítico donde el rendimiento importa. Go produce binarios estáticos que
# corren en una imagen 'scratch' de ~15MB sin dependencias externas,
# minimizando la superficie de ataque para un componente financiero."
# =============================================================================

# Stage 1: Build
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copiar go.mod y go.sum primero (cache de dependencias)
COPY go.mod ./
RUN go mod download

# Copiar código fuente
COPY . .
RUN go mod tidy

# Build estático
RUN CGO_ENABLED=0 GOOS=linux go build -o /payment-service ./cmd/server

# Stage 2: Production (imagen minimal)
FROM scratch

LABEL maintainer="devops-team"
LABEL description="Payment Service for Production Incident Simulator"

# Copiar certificados CA (necesarios para HTTPS a payment providers)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copiar binario
COPY --from=builder /payment-service /payment-service

# El usuario está hardcoded en el binario (securityContext de K8s lo enforce)
EXPOSE 8080 9090

ENTRYPOINT ["/payment-service"]
