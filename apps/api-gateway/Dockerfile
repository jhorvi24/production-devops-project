# =============================================================================
# DOCKERFILE - Multi-stage build para API Gateway
# =============================================================================
#
# ¿POR QUÉ MULTI-STAGE BUILD?
# - Imagen final más pequeña (solo runtime, sin devDependencies)
# - Superficie de ataque reducida (menos binarios = menos vulnerabilidades)
# - Build más rápido en CI (caché de capas)
#
# ¿POR QUÉ node:20-alpine?
# - Alpine Linux: ~5MB vs ~150MB de Debian
# - Imagen final: ~100MB vs ~500MB
# - Menos vulnerabilidades (menos paquetes instalados)
#
# EN ENTREVISTA: "Uso multi-stage builds para separar las dependencias de
# build de las de runtime. La imagen final usa Alpine Linux para minimizar
# la superficie de ataque y el tamaño. Corro como non-root user (UID 1000)
# para seguir el principio de mínimo privilegio."
# =============================================================================

# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copiar solo package files primero (aprovecha caché de Docker)
COPY package*.json ./

# Instalar todas las dependencias (incluyendo devDependencies para tests)
RUN npm ci --only=production

# Stage 2: Production
FROM node:20-alpine AS production

# Labels (metadata de la imagen)
LABEL maintainer="devops-team"
LABEL description="API Gateway for Production Incident Simulator"
LABEL version="1.0.0"

# Crear usuario non-root
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

WORKDIR /app

# Copiar dependencias desde el builder
COPY --from=builder /app/node_modules ./node_modules

# Copiar código fuente
COPY src/ ./src/
COPY package.json ./

# Directorio temporal (para el readOnlyRootFilesystem de K8s)
RUN mkdir -p /tmp && chown appuser:appgroup /tmp

# Cambiar a usuario non-root
USER appuser

# Exponer puertos
EXPOSE 3000 9090

# Health check integrado en Docker (útil para docker-compose local)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health/live || exit 1

# Comando de inicio
CMD ["node", "src/index.js"]
