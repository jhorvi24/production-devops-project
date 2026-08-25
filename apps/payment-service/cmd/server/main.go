/*
=============================================================================
PAYMENT SERVICE - Procesamiento de pagos (Go)
=============================================================================

ESTE SERVICIO DEMUESTRA:
- Go HTTP server con graceful shutdown
- Métricas Prometheus nativas
- Structured logging con logrus
- Health checks
- Simulación de procesamiento de pagos
- Manejo de errores y timeouts

¿POR QUÉ GORILLA/MUX?
- Router HTTP más popular de Go
- Path parameters, middleware, subrouters
- Estándar de la industria

ESCENARIOS DE INCIDENTES:
- #2: Memory leak simulado (endpoint /debug/leak)
- #8: Credenciales de DB expiradas

EN ENTREVISTA: "El payment-service en Go demuestra un sistema polyglot donde
cada servicio usa la tecnología más apropiada. Go fue elegido por su
rendimiento y la generación de binarios estáticos que producen imágenes
Docker de ~15MB con superficie de ataque mínima."
=============================================================================
*/

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// =============================================================================
// CONFIGURACIÓN
// =============================================================================
var (
	port        = getEnv("PORT", "8080")
	metricsPort = getEnv("METRICS_PORT", "9090")
	environment = getEnv("ENVIRONMENT", "development")
)

// =============================================================================
// MÉTRICAS PROMETHEUS
// =============================================================================
var (
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status_code"},
	)

	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: []float64{0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 5},
		},
		[]string{"method", "endpoint"},
	)

	paymentsProcessed = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "payments_processed_total",
			Help: "Total payments processed",
		},
		[]string{"status", "currency"},
	)

	paymentProcessingTime = prometheus.NewHistogram(
		prometheus.HistogramOpts{
			Name:    "payment_processing_duration_seconds",
			Help:    "Payment processing time",
			Buckets: []float64{0.1, 0.25, 0.5, 1, 2, 5, 10},
		},
	)
)

func init() {
	prometheus.MustRegister(requestsTotal)
	prometheus.MustRegister(requestDuration)
	prometheus.MustRegister(paymentsProcessed)
	prometheus.MustRegister(paymentProcessingTime)
}

// =============================================================================
// MODELOS
// =============================================================================
type PaymentRequest struct {
	OrderID  string  `json:"order_id"`
	Amount   float64 `json:"amount"`
	Currency string  `json:"currency"`
}

type PaymentResponse struct {
	ID        string  `json:"id"`
	OrderID   string  `json:"order_id"`
	Amount    float64 `json:"amount"`
	Currency  string  `json:"currency"`
	Status    string  `json:"status"`
	CreatedAt string  `json:"created_at"`
}

type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
}

// In-memory store
var (
	payments   = make(map[string]PaymentResponse)
	paymentsMu sync.RWMutex
)

// =============================================================================
// HANDLERS
// =============================================================================

func healthLive(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(HealthResponse{
		Status:    "alive",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	})
}

func healthReady(w http.ResponseWriter, r *http.Request) {
	// En producción: verificar DB connection pool
	json.NewEncoder(w).Encode(HealthResponse{
		Status:    "ready",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	})
}

func createPayment(w http.ResponseWriter, r *http.Request) {
	start := time.Now()

	var req PaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error": "invalid request body"}`, http.StatusBadRequest)
		return
	}

	// Simular procesamiento de pago (latencia variable)
	processingTime := time.Duration(100+rand.Intn(400)) * time.Millisecond
	time.Sleep(processingTime)

	// Simular 5% de fallos (realista para payment providers)
	status := "completed"
	if rand.Float32() < 0.05 {
		status = "failed"
	}

	paymentID := fmt.Sprintf("pay-%d", time.Now().UnixNano())
	payment := PaymentResponse{
		ID:        paymentID,
		OrderID:   req.OrderID,
		Amount:    req.Amount,
		Currency:  req.Currency,
		Status:    status,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}

	paymentsMu.Lock()
	payments[paymentID] = payment
	paymentsMu.Unlock()

	// Métricas
	paymentProcessingTime.Observe(time.Since(start).Seconds())
	paymentsProcessed.WithLabelValues(status, req.Currency).Inc()

	if status == "failed" {
		w.WriteHeader(http.StatusUnprocessableEntity)
	} else {
		w.WriteHeader(http.StatusCreated)
	}
	json.NewEncoder(w).Encode(payment)

	log.Printf(`{"level":"info","service":"payment-service","event":"payment_processed","payment_id":"%s","order_id":"%s","status":"%s","duration_ms":%d}`,
		paymentID, req.OrderID, status, time.Since(start).Milliseconds())
}

func getPayment(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	paymentID := vars["id"]

	paymentsMu.RLock()
	payment, exists := payments[paymentID]
	paymentsMu.RUnlock()

	if !exists {
		http.Error(w, `{"error": "payment not found"}`, http.StatusNotFound)
		return
	}

	json.NewEncoder(w).Encode(payment)
}

// Endpoint para simular memory leak (Escenario de incidente #2)
var leakedMemory [][]byte

func debugLeak(w http.ResponseWriter, r *http.Request) {
	// Cada llamada consume ~10MB que nunca se libera
	chunk := make([]byte, 10*1024*1024)
	leakedMemory = append(leakedMemory, chunk)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":     "Leaked 10MB of memory",
		"total_leaked": fmt.Sprintf("%d MB", len(leakedMemory)*10),
	})
}

// =============================================================================
// MIDDLEWARE
// =============================================================================
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		wrapped := &responseWriter{ResponseWriter: w, statusCode: 200}
		next.ServeHTTP(wrapped, r)
		duration := time.Since(start).Seconds()

		requestsTotal.WithLabelValues(
			r.Method,
			r.URL.Path,
			fmt.Sprintf("%d", wrapped.statusCode),
		).Inc()

		requestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func jsonMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		next.ServeHTTP(w, r)
	})
}

// =============================================================================
// MAIN
// =============================================================================
func main() {
	log.Printf(`{"level":"info","service":"payment-service","message":"Starting payment service","port":"%s","environment":"%s"}`, port, environment)

	// Router principal
	r := mux.NewRouter()
	r.Use(jsonMiddleware)
	r.Use(metricsMiddleware)

	// Routes
	r.HandleFunc("/health/live", healthLive).Methods("GET")
	r.HandleFunc("/health/ready", healthReady).Methods("GET")
	r.HandleFunc("/payments", createPayment).Methods("POST")
	r.HandleFunc("/payments/{id}", getPayment).Methods("GET")
	r.HandleFunc("/debug/leak", debugLeak).Methods("POST") // Solo para simulación de incidentes

	// Servidor principal
	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Servidor de métricas (puerto separado)
	metricsSrv := &http.Server{
		Addr:    ":" + metricsPort,
		Handler: promhttp.Handler(),
	}

	// Iniciar servidores
	go func() {
		log.Printf(`{"level":"info","message":"Metrics server on :%s"}`, metricsPort)
		if err := metricsSrv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("Metrics server error: %v", err)
		}
	}()

	go func() {
		log.Printf(`{"level":"info","message":"HTTP server on :%s"}`, port)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit

	log.Println(`{"level":"info","message":"Shutting down gracefully..."}`)
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	srv.Shutdown(ctx)
	metricsSrv.Shutdown(ctx)
	log.Println(`{"level":"info","message":"Server stopped"}`)
}

// =============================================================================
// HELPERS
// =============================================================================
func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
