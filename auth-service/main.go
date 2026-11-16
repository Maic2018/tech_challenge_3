package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/XSAM/otelsql"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/attribute"
)

type App struct {
	DB        *sql.DB
	MasterKey string
	Chaos     *chaosState
}

func main() {
	_ = godotenv.Load()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8001"
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL deve ser definida")
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY deve ser definida")
	}

	shutdownTelemetry, err := setupTelemetry(context.Background(), "auth-service")
	if err != nil {
		log.Fatalf("Não foi possível inicializar o OpenTelemetry: %v", err)
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTelemetry(ctx); err != nil {
			log.Printf("Erro ao encerrar o OpenTelemetry: %v", err)
		}
	}()

	db, err := connectDB(databaseURL)
	if err != nil {
		log.Fatalf("Não foi possível conectar ao banco de dados: %v", err)
	}
	defer db.Close()

	app := &App{
		DB:        db,
		MasterKey: masterKey,
		Chaos:     &chaosState{},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/validate", app.validateKeyHandler)
	mux.Handle("/admin/keys", app.masterKeyAuthMiddleware(http.HandlerFunc(app.createKeyHandler)))
	mux.Handle("/admin/chaos", app.masterKeyAuthMiddleware(http.HandlerFunc(app.chaosHandler)))

	// otelhttp cria o span SERVER de cada requisição (continuando o trace recebido no
	// header traceparent) e as métricas http.server.*. /health fica de fora para não
	// poluir o APM com as probes do kubelet.
	handler := otelhttp.NewHandler(app.chaosMiddleware(mux), "auth-service",
		otelhttp.WithFilter(func(r *http.Request) bool { return r.URL.Path != "/health" }),
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method + " " + r.URL.Path }),
	)

	log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port)
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

func connectDB(databaseURL string) (*sql.DB, error) {
	// otelsql gera um span CLIENT por query (aparece como dependência PostgreSQL no APM)
	db, err := otelsql.Open("pgx", databaseURL,
		otelsql.WithAttributes(attribute.String("db.system.name", "postgresql")),
		otelsql.WithSpanOptions(otelsql.SpanOptions{OmitConnResetSession: true, OmitRows: true}),
	)
	if err != nil {
		return nil, err
	}
	if err = db.Ping(); err != nil {
		return nil, err
	}
	log.Println("Conectado ao PostgreSQL com sucesso!")
	return db, nil
}
