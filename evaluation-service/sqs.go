package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

type Event struct {
	UserID    string `json:"user_id"`
	FlagName  string `json:"flag_name"`
	Result    bool   `json:"result"`
	Timestamp string `json:"timestamp"`
}

func (a *App) sendEvaluationEvent(parentCtx context.Context, userID, flagName string, result bool) {
	if a.SqsSvc == nil || a.SqsQueueURL == "" {
		return
	}

	msgCtx := otel.GetTextMapPropagator().Extract(parentCtx, propagation.HeaderCarrier{})
	tracer := otel.Tracer("evaluation-service")
	_, span := tracer.Start(msgCtx, "sqs.send.evaluation_event")
	defer span.End()

	body, err := json.Marshal(Event{
		UserID:    userID,
		FlagName:  flagName,
		Result:    result,
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
	})
	if err != nil {
		log.Printf("Erro ao serializar evento SQS: %v", err)
		return
	}

	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(msgCtx, carrier)

	attrs := map[string]*sqs.MessageAttributeValue{
		"traceparent": {DataType: aws.String("String"), StringValue: aws.String(carrier["traceparent"])},
	}
	if ts, ok := carrier["tracestate"]; ok && ts != "" {
		attrs["tracestate"] = &sqs.MessageAttributeValue{DataType: aws.String("String"), StringValue: aws.String(ts)}
	}

	_, err = a.SqsSvc.SendMessage(&sqs.SendMessageInput{
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageBody:       aws.String(string(body)),
		MessageAttributes: attrs,
	})
	if err != nil {
		log.Printf("Erro ao enviar mensagem SQS: %v", err)
	}
}
