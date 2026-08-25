/**
 * Structured Logging con Winston
 *
 * ¿POR QUÉ STRUCTURED LOGGING?
 * - JSON logs se pueden parsear automáticamente en CloudWatch/ELK
 * - Puedes filtrar por campos (level, service, requestId)
 * - Correlación de logs entre servicios con request IDs
 *
 * EN ENTREVISTA: "Implementé structured logging en JSON para que CloudWatch
 * Insights pueda hacer queries sobre campos específicos. Esto permite
 * buscar todos los logs de un request ID durante un incidente y reconstruir
 * el flujo completo del request entre microservicios."
 */

const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: {
    service: 'api-gateway',
    environment: process.env.NODE_ENV || 'development'
  },
  transports: [
    new winston.transports.Console()
  ]
});

module.exports = logger;
