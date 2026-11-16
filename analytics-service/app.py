import os
import sys
import threading
import json
import uuid
import time
import logging
import boto3
from botocore.exceptions import NoCredentialsError, ClientError
from flask import Flask, jsonify
from dotenv import load_dotenv
from opentelemetry import propagate, trace
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
from opentelemetry.trace import SpanKind, Status, StatusCode

from telemetry import setup_telemetry

load_dotenv()

# OpenTelemetry antes do logging (o formato de log passa a incluir trace_id/span_id)
TELEMETRY_ENABLED = setup_telemetry("analytics-service")
if TELEMETRY_ENABLED:
    # Span CLIENT para cada chamada à AWS (SQS.ReceiveMessage, DynamoDB.PutItem...)
    BotocoreInstrumentor().instrument()

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)
tracer = trace.get_tracer("analytics-service")

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("AWS_SQS_URL")
DYNAMODB_TABLE_NAME = os.getenv("AWS_DYNAMODB_TABLE")
AWS_ENDPOINT_URL = os.getenv("AWS_ENDPOINT_URL")
DYNAMODB_ENDPOINT_URL = os.getenv("DYNAMODB_ENDPOINT_URL", AWS_ENDPOINT_URL)

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical("Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.")
    sys.exit(1)

try:
    # endpoint_url aponta para LocalStack quando definido, ou AWS real quando None
    sqs_client = boto3.client(
        "sqs",
        region_name=AWS_REGION,
        endpoint_url=AWS_ENDPOINT_URL,
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY")
    )
    dynamodb_client = boto3.client(
        "dynamodb",
        region_name=AWS_REGION,
        endpoint_url=DYNAMODB_ENDPOINT_URL,
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY")
    )
    log.info(f"Clientes Boto3 inicializados na região {AWS_REGION}")
    log.info(f"SQS endpoint: {AWS_ENDPOINT_URL}")
    log.info(f"DynamoDB endpoint: {DYNAMODB_ENDPOINT_URL}")
except NoCredentialsError:
    log.critical("Credenciais da AWS não encontradas.")
    sys.exit(1)
except Exception as e:
    log.critical(f"Erro ao inicializar o Boto3: {e}")
    sys.exit(1)


def ensure_dynamodb_table():
    """Cria a tabela no DynamoDB local se não existir"""
    try:
        dynamodb_client.create_table(
            TableName=DYNAMODB_TABLE_NAME,
            KeySchema=[{'AttributeName': 'event_id', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'event_id', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST'
        )
        log.info(f"Tabela {DYNAMODB_TABLE_NAME} criada no DynamoDB.")
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            log.info(f"Tabela {DYNAMODB_TABLE_NAME} já existe.")
        else:
            log.error(f"Erro ao criar tabela DynamoDB: {e}")


def trace_context(message):
    """Extrai o traceparent que o evaluation-service colocou nos MessageAttributes."""
    carrier = {
        key: attr["StringValue"]
        for key, attr in message.get("MessageAttributes", {}).items()
        if "StringValue" in attr
    }
    return propagate.extract(carrier)


def process_message(message):
    # Span CONSUMER filho do span PRODUCER do evaluation-service: o trace distribuído
    # atravessa a fila e o APM liga evaluation-service -> analytics-service.
    with tracer.start_as_current_span(
        "evaluation-events process",
        context=trace_context(message),
        kind=SpanKind.CONSUMER,
        attributes={
            "messaging.system": "aws_sqs",
            "messaging.operation.type": "process",
            "messaging.destination.name": "evaluation-events",
            "messaging.message.id": message['MessageId'],
        },
    ):
        _process_message(message)


def mark_span_error(error):
    """Marca o span atual como erro (o trace fica vermelho no APM)."""
    span = trace.get_current_span()
    span.record_exception(error)
    span.set_status(Status(StatusCode.ERROR, str(error)))


def _process_message(message):
    try:
        log.info(f"Processando mensagem ID: {message['MessageId']}")
        body = json.loads(message['Body'])

        event_id = str(uuid.uuid4())

        item = {
            'event_id': {'S': event_id},
            'user_id': {'S': str(body.get('user_id', 'unknown'))},
            'flag_name': {'S': str(body.get('flag_name', 'unknown'))},
            'result': {'BOOL': bool(body.get('result', False))},
            'timestamp': {'S': str(body.get('timestamp', ''))}
        }

        dynamodb_client.put_item(TableName=DYNAMODB_TABLE_NAME, Item=item)
        log.info(f"Evento {event_id} salvo no DynamoDB.")

        sqs_client.delete_message(
            QueueUrl=SQS_QUEUE_URL,
            ReceiptHandle=message['ReceiptHandle']
        )

    except json.JSONDecodeError as e:
        mark_span_error(e)
        log.error(f"Erro ao decodificar JSON da mensagem: {message['MessageId']}")
    except ClientError as e:
        mark_span_error(e)
        log.error(f"Erro do Boto3 ao processar {message['MessageId']}: {e}")
    except Exception as e:
        mark_span_error(e)
        log.error(f"Erro inesperado ao processar {message['MessageId']}: {e}")


def sqs_worker_loop():
    log.info("Iniciando o worker SQS...")
    # Aguarda um pouco para garantir que o LocalStack está pronto
    time.sleep(5)
    ensure_dynamodb_table()

    while True:
        try:
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,
                MessageAttributeNames=['All'],  # traz o traceparent junto com a mensagem
            )

            messages = response.get('Messages', [])
            if not messages:
                continue

            log.info(f"Recebidas {len(messages)} mensagens.")
            for message in messages:
                process_message(message)

        except ClientError as e:
            log.error(f"Erro do Boto3 no loop SQS: {e}")
            time.sleep(10)
        except Exception as e:
            log.error(f"Erro inesperado no loop SQS: {e}")
            time.sleep(10)


app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok"})


def start_worker():
    worker_thread = threading.Thread(target=sqs_worker_loop, daemon=True)
    worker_thread.start()


start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8005))
    app.run(host=os.getenv('HOST', '127.0.0.1'), port=port, debug=False)
