# analytics-service with OTel
import os
import sys
import threading
import json
import uuid
import time
import logging
from urllib.parse import urlparse

import boto3
from botocore.exceptions import NoCredentialsError, ClientError
from flask import Flask, jsonify
from dotenv import load_dotenv

from otel import init_otel, instrument_worker
from opentelemetry import trace, propagate
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

tp, mp = init_otel()
instrument_worker()
tracer = trace.get_tracer('analytics-service')

AWS_REGION = os.getenv('AWS_REGION')
SQS_QUEUE_URL = os.getenv('AWS_SQS_URL')
DYNAMODB_TABLE_NAME = os.getenv('AWS_DYNAMODB_TABLE')
AWS_ENDPOINT = os.getenv('AWS_ENDPOINT_URL')

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical('Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.')
    sys.exit(1)

if not AWS_ENDPOINT:
    parsed = urlparse(SQS_QUEUE_URL)
    if parsed.port:
        AWS_ENDPOINT = f'{parsed.scheme}://{parsed.hostname}:{parsed.port}'
    else:
        AWS_ENDPOINT = None

try:
    session = boto3.Session(region_name=AWS_REGION)
    sqs_client = session.client('sqs', endpoint_url=AWS_ENDPOINT)
    dynamodb_client = session.client('dynamodb', endpoint_url=AWS_ENDPOINT)
    log.info(f'Clientes Boto3 inicializados na região {AWS_REGION} (endpoint: {AWS_ENDPOINT})')
except Exception as e:
    log.critical(f'Erro ao inicializar o Boto3: {e}')
    sys.exit(1)

def process_message(message):
    try:
        attrs = message.get('MessageAttributes', {})
        ctx = None
        if attrs:
            carrier = {}
            if 'traceparent' in attrs:
                carrier['traceparent'] = attrs['traceparent']['StringValue']
            if 'tracestate' in attrs:
                carrier['tracestate'] = attrs['tracestate']['StringValue']
            if carrier:
                ctx = TraceContextTextMapPropagator().extract(carrier=carrier)
        with tracer.start_as_current_span('sqs.consume.evaluation_event', context=ctx):
            log.info(f"Processando mensagem ID: {message['MessageId']}")
            body = json.loads(message['Body'])
            event_id = str(uuid.uuid4())
            item = {
                'event_id': {'S': event_id},
                'user_id': {'S': body['user_id']},
                'flag_name': {'S': body['flag_name']},
                'result': {'BOOL': body['result']},
                'timestamp': {'S': body['timestamp']}
            }
            dynamodb_client.put_item(TableName=DYNAMODB_TABLE_NAME, Item=item)
            log.info(f"Evento {event_id} (Flag: {body['flag_name']}) salvo no DynamoDB.")
            sqs_client.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=message['ReceiptHandle'])
    except Exception as e:
        log.error(f'Erro ao processar mensagem: {e}')

def sqs_worker_loop():
    log.info('Iniciando o worker SQS...')
    while True:
        try:
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,
                MessageAttributeNames=['All']
            )
            messages = response.get('Messages', [])
            if not messages:
                continue
            for message in messages:
                process_message(message)
        except Exception as e:
            log.error(f'Erro no loop SQS: {e}')
            time.sleep(10)

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

def start_worker():
    worker_thread = threading.Thread(target=sqs_worker_loop, daemon=True)
    worker_thread.start()

start_worker()

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8005))
    app.run(host='0.0.0.0', port=port, debug=False)
