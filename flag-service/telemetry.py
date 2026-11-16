"""Instrumentação OpenTelemetry dos serviços Python do ToggleMaster.

Traces e métricas saem por OTLP/HTTP para o OTel Collector gateway, configurado pelas
variáveis padrão do OpenTelemetry (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME,
OTEL_RESOURCE_ATTRIBUTES). Sem OTEL_EXPORTER_OTLP_ENDPOINT (dev local, CI) nada é
ativado e o serviço funciona como antes.

É chamado no import do app.py, ou seja, dentro de cada worker do gunicorn (que roda
sem --preload): cada processo cria o próprio exportador, sem problemas de fork.
"""
import logging
import os

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# trace_id em toda linha de log: do log no Loki se chega ao trace no APM (e vice-versa)
LOG_FORMAT = (
    "%(asctime)s %(levelname)s [%(name)s] "
    "[trace_id=%(otelTraceID)s span_id=%(otelSpanID)s] %(message)s"
)


def setup_telemetry(service_name):
    """Configura os providers de traces/métricas e a correlação de logs.

    Deve rodar antes do logging.basicConfig do app. Retorna True se a telemetria foi ativada.
    """
    if not os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return False

    resource = Resource.create({"service.name": os.getenv("OTEL_SERVICE_NAME", service_name)})

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)

    reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=15000)
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

    LoggingInstrumentor().instrument(set_logging_format=True, logging_format=LOG_FORMAT, log_level=logging.INFO)
    return True
