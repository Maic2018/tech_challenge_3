package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// Evento que será enviado para a fila
type EvaluationEvent struct {
	UserID    string    `json:"user_id"`
	FlagName  string    `json:"flag_name"`
	Result    bool      `json:"result"`
	Timestamp time.Time `json:"timestamp"`
}

// sendEvaluationEvent envia um evento para a fila SQS. O contexto do trace segue
// nos MessageAttributes (traceparent), e o analytics-service continua o mesmo trace
// ao consumir a mensagem: o APM mostra evaluation -> SQS -> analytics.
func (a *App) sendEvaluationEvent(ctx context.Context, userID, flagName string, result bool) {
	// Se a URL da fila não foi configurada, apenas loga localmente e sai.
	if a.SqsClient == nil || a.SqsQueueURL == "" {
		log.Printf("[SQS_DISABLED] Evento: User '%s', Flag '%s', Result '%t'", userID, flagName, result)
		return
	}

	event := EvaluationEvent{
		UserID:    userID,
		FlagName:  flagName,
		Result:    result,
		Timestamp: time.Now().UTC(),
	}

	body, err := json.Marshal(event)
	if err != nil {
		log.Printf("Erro ao serializar evento SQS: %v", err)
		return
	}

	// Span PRODUCER (convenção de mensageria do OpenTelemetry)
	ctx, span := otel.Tracer("evaluation-service").Start(ctx, "evaluation-events publish",
		trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			attribute.String("messaging.system", "aws_sqs"),
			attribute.String("messaging.operation.type", "send"),
			attribute.String("messaging.destination.name", "evaluation-events"),
			attribute.String("togglemaster.flag_name", flagName),
		),
	)
	defer span.End()

	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	attrs := make(map[string]types.MessageAttributeValue, len(carrier))
	for k, v := range carrier {
		attrs[k] = types.MessageAttributeValue{DataType: aws.String("String"), StringValue: aws.String(v)}
	}

	// Envia a mensagem (com timeout para não segurar a goroutine)
	sendCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	_, err = a.SqsClient.SendMessage(sendCtx, &sqs.SendMessageInput{
		MessageBody:       aws.String(string(body)),
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageAttributes: attrs,
	})

	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha ao publicar no SQS")
		log.Printf("trace_id=%s ERRO ao enviar mensagem para SQS: %v", traceID(ctx), err)
	} else {
		log.Printf("Evento de avaliação enviado para SQS (Flag: %s)", flagName)
	}
}
