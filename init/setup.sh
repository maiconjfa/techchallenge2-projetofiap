#!/bin/bash
set -e

echo "=== Inicializando recursos do LocalStack ==="

# Cria a fila SQS
echo "Criando fila SQS: evaluation-events..."
awslocal sqs create-queue --queue-name evaluation-events

# Cria a tabela DynamoDB
echo "Criando tabela DynamoDB: evaluation_events..."
awslocal dynamodb create-table \
    --table-name evaluation_events \
    --key-schema AttributeName=event_id,KeyType=HASH \
    --attribute-definitions AttributeName=event_id,AttributeType=S \
    --billing-mode PAY_PER_REQUEST

echo "=== Inicialização concluída com sucesso ==="
