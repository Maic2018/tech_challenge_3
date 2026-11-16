package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/smithy-go/tracing/smithyoteltracing"
	"github.com/joho/godotenv"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
)

// App struct para injeção de dependência
type App struct {
	RedisClient         *redis.Client
	SqsClient           *sqs.Client
	SqsQueueURL         string
	HttpClient          *http.Client
	FlagServiceURL      string
	TargetingServiceURL string
}

func main() {
	_ = godotenv.Load() // Carrega .env para dev local

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}

	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Fatal("REDIS_URL deve ser definida (ex: redis://localhost:6379)")
	}

	flagSvcURL := os.Getenv("FLAG_SERVICE_URL")
	if flagSvcURL == "" {
		log.Fatal("FLAG_SERVICE_URL deve ser definida")
	}

	targetingSvcURL := os.Getenv("TARGETING_SERVICE_URL")
	if targetingSvcURL == "" {
		log.Fatal("TARGETING_SERVICE_URL deve ser definida")
	}

	// SQS é opcional no dev local, mas obrigatório em prod
	sqsQueueURL := os.Getenv("AWS_SQS_URL")
	awsRegion := os.Getenv("AWS_REGION")
	if sqsQueueURL == "" {
		log.Println("Atenção: AWS_SQS_URL não definida. Eventos não serão enviados.")
	}
	if awsRegion == "" && sqsQueueURL != "" {
		log.Fatal("AWS_REGION deve ser definida para usar SQS")
	}

	// --- OpenTelemetry ---
	ctx := context.Background()
	shutdownTelemetry, err := setupTelemetry(ctx, "evaluation-service")
	if err != nil {
		log.Fatalf("Não foi possível inicializar o OpenTelemetry: %v", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTelemetry(shutdownCtx); err != nil {
			log.Printf("Erro ao encerrar o OpenTelemetry: %v", err)
		}
	}()

	// --- Inicializa Clientes ---

	// Cliente Redis (cada comando vira um span CLIENT: cache HIT/MISS visível no trace)
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("Não foi possível parsear a URL do Redis: %v", err)
	}
	rdb := redis.NewClient(opt)
	if err := redisotel.InstrumentTracing(rdb); err != nil {
		log.Fatalf("Não foi possível instrumentar o Redis: %v", err)
	}
	if _, err := rdb.Ping(ctx).Result(); err != nil {
		log.Fatalf("Não foi possível conectar ao Redis: %v", err)
	}
	log.Println("Conectado ao Redis com sucesso!")

	// Cliente SQS (AWS SDK v2). Credenciais vêm da cadeia padrão: no EKS, a role
	// do node via IMDS; no docker-compose, AWS_ACCESS_KEY_ID/AWS_ENDPOINT_URL (LocalStack).
	var sqsClient *sqs.Client
	if sqsQueueURL != "" {
		cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(awsRegion))
		if err != nil {
			log.Fatalf("Não foi possível carregar a configuração AWS: %v", err)
		}
		// Tracing nativo do AWS SDK: span CLIENT para cada chamada (SQS.SendMessage)
		sqsClient = sqs.NewFromConfig(cfg, func(o *sqs.Options) {
			o.TracerProvider = smithyoteltracing.Adapt(otel.GetTracerProvider())
		})
		log.Println("Cliente SQS inicializado com sucesso.")
	}

	// Cliente HTTP (com timeout). O transport do otelhttp cria o span CLIENT e injeta
	// o header traceparent: é isso que liga evaluation -> flag/targeting -> auth no APM.
	httpClient := &http.Client{
		Timeout:   5 * time.Second,
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}

	// Cria a instância da App
	app := &App{
		RedisClient:         rdb,
		SqsClient:           sqsClient,
		SqsQueueURL:         sqsQueueURL,
		HttpClient:          httpClient,
		FlagServiceURL:      flagSvcURL,
		TargetingServiceURL: targetingSvcURL,
	}

	// --- Rotas ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/evaluate", app.evaluationHandler)

	handler := otelhttp.NewHandler(mux, "evaluation-service",
		otelhttp.WithFilter(func(r *http.Request) bool { return r.URL.Path != "/health" }),
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method + " " + r.URL.Path }),
	)

	log.Printf("Serviço de Avaliação (Go) rodando na porta %s", port)
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
