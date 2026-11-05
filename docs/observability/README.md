# Observabilidade - ToggleMaster (Fase 4)

## Arquitetura

Apps (OTel SDK) -> OTLP gRPC :4317 -> OTel Collector (observability) -> Prometheus/Loki/Datadog.

## Fluxo

AuthServiceHigh5xxRate -> Alertmanager -> PagerDuty + Teams + Self-Healing webhook -> rollout restart.

## Justificativas

Datadog vs New Relic: Datadog (APM) com Distributed Tracing + Service Map, ingestão OTLP via exporter, forte correlação Traces/Metrics/Logs.
PagerDuty vs OpsGenie: PagerDuty (Events API v2) + Alertmanager p/ gestão de incidentes/on-call.
