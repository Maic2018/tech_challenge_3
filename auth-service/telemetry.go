package main

import (
	"context"
	"errors"
	"log"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

// setupTelemetry inicializa o SDK do OpenTelemetry (traces + métricas via OTLP/HTTP).
// O destino vem das variáveis padrão OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME e
// OTEL_RESOURCE_ATTRIBUTES; no cluster elas apontam para o OTel Collector gateway.
// Sem OTEL_EXPORTER_OTLP_ENDPOINT (dev local, testes) a telemetria fica desligada e
// a instrumentação vira no-op.
func setupTelemetry(ctx context.Context, serviceName string) (func(context.Context) error, error) {
	// Propagação W3C (traceparent) entre os microsserviços
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		log.Println("OTEL_EXPORTER_OTLP_ENDPOINT não definida: telemetria desligada.")
		return func(context.Context) error { return nil }, nil
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(attribute.String("service.name", serviceName)),
		resource.WithFromEnv(), // OTEL_SERVICE_NAME / OTEL_RESOURCE_ATTRIBUTES têm precedência
		resource.WithTelemetrySDK(),
		resource.WithProcessRuntimeName(),
		resource.WithProcessRuntimeVersion(),
	)
	if err != nil {
		return nil, err
	}

	traceExporter, err := otlptracehttp.New(ctx)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	metricExporter, err := otlpmetrichttp.New(ctx)
	if err != nil {
		return nil, err
	}
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter, sdkmetric.WithInterval(15*time.Second))),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	log.Printf("OpenTelemetry ativo: exportando para %s", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))
	return func(ctx context.Context) error {
		return errors.Join(tp.Shutdown(ctx), mp.Shutdown(ctx))
	}, nil
}

// traceID devolve o trace id da requisição para correlacionar logs (Loki) e traces (APM)
func traceID(ctx context.Context) string {
	sc := trace.SpanContextFromContext(ctx)
	if !sc.HasTraceID() {
		return "-"
	}
	return sc.TraceID().String()
}
