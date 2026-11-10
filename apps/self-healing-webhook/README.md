# Self-Healing Webhook

Webhook receiver (Flask + gunicorn) that triggers `kubectl rollout restart` for deployments in `feature-flags` namespace when Alertmanager fires.

Endpoints:
- GET /healthz -> health check
- POST /webhook -> processes Alertmanager payload; restarts matching service deployments (auth-service, analytics-service, evaluation-service, flag-service, targeting-service)

RBAC: ServiceAccount in self-healing namespace with Role (get/list/patch/update deployments) in feature-flags.
