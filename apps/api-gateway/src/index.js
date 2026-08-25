/**
 * =============================================================================
 * API GATEWAY - Punto de entrada de la aplicación
 * =============================================================================
 *
 * ¿POR QUÉ UN API GATEWAY?
 * - Punto único de entrada (single entry point)
 * - Rutea requests a los microservicios internos
 * - Cross-cutting concerns: auth, rate limiting, logging, métricas
 * - Los clientes no necesitan conocer la ubicación de cada servicio
 *
 * ¿POR QUÉ NODE.JS PARA EL GATEWAY?
 * - Excelente para I/O bound (proxying requests)
 * - Event loop no-bloqueante maneja muchas conexiones concurrentes
 * - Bajo overhead de memoria por request
 * - Arranque rápido (importante para scaling)
 *
 * EN ENTREVISTA: "El API Gateway actúa como punto de entrada único,
 * agregando rate limiting, métricas Prometheus, structured logging, y
 * health checks. Los microservicios internos solo se comunican entre sí
 * sin exposición directa a internet."
 * =============================================================================
 */

const express = require('express');
const axios = require('axios');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const { register, collectDefaultMetrics, Counter, Histogram } = require('prom-client');
const logger = require('./logger');

const app = express();
const PORT = process.env.PORT || 3000;

// URLs de los servicios internos (resolución DNS de Kubernetes)
const ORDER_SERVICE_URL = process.env.ORDER_SERVICE_URL || 'http://order-service:8000';
const PAYMENT_SERVICE_URL = process.env.PAYMENT_SERVICE_URL || 'http://payment-service:8080';

// =============================================================================
// MÉTRICAS PROMETHEUS
// =============================================================================
// Estas métricas son clave para observabilidad y para detectar incidentes.
collectDefaultMetrics({ prefix: 'api_gateway_' });

const httpRequestsTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
});

const upstreamRequestDuration = new Histogram({
  name: 'upstream_request_duration_seconds',
  help: 'Duration of upstream service requests',
  labelNames: ['service', 'method', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
});

// =============================================================================
// MIDDLEWARE
// =============================================================================
app.use(helmet());                    // Security headers
app.use(cors());                      // CORS para desarrollo
app.use(express.json());              // Parse JSON bodies
app.use(morgan('combined', {          // Access logs
  stream: { write: (msg) => logger.info(msg.trim()) }
}));

// Rate Limiting - Protección contra DDoS (Escenario de Incidente #5)
const limiter = rateLimit({
  windowMs: 60 * 1000,    // 1 minuto
  max: 100,                // Máximo 100 requests por IP por minuto
  message: { error: 'Too many requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});
app.use('/api/', limiter);

// Middleware de métricas (mide cada request)
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    httpRequestsTotal.inc({
      method: req.method,
      route: route,
      status_code: res.statusCode
    });
    httpRequestDuration.observe(
      { method: req.method, route: route, status_code: res.statusCode },
      duration
    );
  });
  next();
});

// =============================================================================
// HEALTH CHECKS
// =============================================================================
// Estos endpoints son usados por Kubernetes probes (liveness/readiness)

// Liveness: ¿El proceso está vivo?
app.get('/health/live', (req, res) => {
  res.status(200).json({ status: 'alive', timestamp: new Date().toISOString() });
});

// Readiness: ¿Puede recibir tráfico? (verifica dependencias)
app.get('/health/ready', async (req, res) => {
  try {
    // Verificar que los servicios downstream están disponibles
    const checks = await Promise.allSettled([
      axios.get(`${ORDER_SERVICE_URL}/health/live`, { timeout: 2000 }),
      axios.get(`${PAYMENT_SERVICE_URL}/health/live`, { timeout: 2000 })
    ]);

    const allHealthy = checks.every(c => c.status === 'fulfilled');

    if (allHealthy) {
      res.status(200).json({
        status: 'ready',
        services: {
          orderService: 'healthy',
          paymentService: 'healthy'
        }
      });
    } else {
      // Degraded but still serving (partial availability)
      res.status(200).json({
        status: 'degraded',
        services: {
          orderService: checks[0].status === 'fulfilled' ? 'healthy' : 'unhealthy',
          paymentService: checks[1].status === 'fulfilled' ? 'healthy' : 'unhealthy'
        }
      });
    }
  } catch (error) {
    res.status(503).json({ status: 'unhealthy', error: error.message });
  }
});

// =============================================================================
// API ROUTES
// =============================================================================

// Proxy a Order Service
app.all('/api/orders*', async (req, res) => {
  const start = Date.now();
  try {
    const response = await axios({
      method: req.method,
      url: `${ORDER_SERVICE_URL}${req.path.replace('/api', '')}`,
      data: req.body,
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': req.headers['x-request-id'] || generateRequestId()
      },
      timeout: 5000
    });

    upstreamRequestDuration.observe(
      { service: 'order-service', method: req.method, status_code: response.status },
      (Date.now() - start) / 1000
    );

    res.status(response.status).json(response.data);
  } catch (error) {
    const status = error.response?.status || 503;
    upstreamRequestDuration.observe(
      { service: 'order-service', method: req.method, status_code: status },
      (Date.now() - start) / 1000
    );
    logger.error('Order service error', { error: error.message, path: req.path });
    res.status(status).json({
      error: 'Order service unavailable',
      message: error.message
    });
  }
});

// Proxy a Payment Service
app.all('/api/payments*', async (req, res) => {
  const start = Date.now();
  try {
    const response = await axios({
      method: req.method,
      url: `${PAYMENT_SERVICE_URL}${req.path.replace('/api', '')}`,
      data: req.body,
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': req.headers['x-request-id'] || generateRequestId()
      },
      timeout: 5000
    });

    upstreamRequestDuration.observe(
      { service: 'payment-service', method: req.method, status_code: response.status },
      (Date.now() - start) / 1000
    );

    res.status(response.status).json(response.data);
  } catch (error) {
    const status = error.response?.status || 503;
    upstreamRequestDuration.observe(
      { service: 'payment-service', method: req.method, status_code: status },
      (Date.now() - start) / 1000
    );
    logger.error('Payment service error', { error: error.message, path: req.path });
    res.status(status).json({
      error: 'Payment service unavailable',
      message: error.message
    });
  }
});

// Endpoint de info
app.get('/api/info', (req, res) => {
  res.json({
    service: 'api-gateway',
    version: process.env.npm_package_version || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    uptime: process.uptime()
  });
});

// =============================================================================
// MÉTRICAS PROMETHEUS ENDPOINT
// =============================================================================
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// =============================================================================
// ERROR HANDLING
// =============================================================================
app.use((err, req, res, next) => {
  logger.error('Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// =============================================================================
// START SERVER
// =============================================================================
const server = app.listen(PORT, () => {
  logger.info(`API Gateway running on port ${PORT}`, {
    environment: process.env.NODE_ENV,
    orderServiceUrl: ORDER_SERVICE_URL,
    paymentServiceUrl: PAYMENT_SERVICE_URL
  });
});

// Graceful shutdown (para preStop hook de Kubernetes)
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, starting graceful shutdown');
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
  // Force close after 25 seconds (terminationGracePeriod is 30s)
  setTimeout(() => process.exit(1), 25000);
});

// Helper
function generateRequestId() {
  return `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

module.exports = app;
