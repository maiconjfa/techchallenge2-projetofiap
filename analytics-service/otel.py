import os
from opentelemetry import trace, metrics
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.b3 import B3MultiFormat
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
try:
    from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
except Exception:
    BotocoreInstrumentor=None

def init_otel():
    endpoint = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318')
    service = os.getenv('OTEL_SERVICE_NAME', 'analytics-service')
    if ':4317' in endpoint:
        endpoint = endpoint.replace(':4317', ':4318')
    if not endpoint.startswith('http'):
        endpoint = 'http://' + endpoint
    base = endpoint.rstrip('/')
    traces_endpoint = base if base.endswith('/v1/traces') else base + '/v1/traces'
    metrics_endpoint = base.replace('/v1/traces','').rstrip('/') + '/v1/metrics'
    resource = Resource.create({
        'service.name': service,
        'service.namespace': os.getenv('OTEL_SERVICE_NAMESPACE', 'feature-flags'),
        'deployment.environment': os.getenv('OTEL_DEPLOYMENT_ENVIRONMENT', 'demo'),
    })
    tp = TracerProvider(resource=resource)
    tp.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=traces_endpoint)))
    trace.set_tracer_provider(tp)
    reader = PeriodicExportingMetricReader(OTLPMetricExporter(endpoint=metrics_endpoint))
    mp = MeterProvider(resource=resource, metric_readers=[reader])
    metrics.set_meter_provider(mp)
    set_global_textmap(CompositePropagator([TraceContextTextMapPropagator(), B3MultiFormat()]))
    return tp, mp


def instrument_worker():
    try:
        if BotocoreInstrumentor: BotocoreInstrumentor().instrument()
    except Exception: pass
