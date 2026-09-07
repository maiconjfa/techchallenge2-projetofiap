#!/usr/bin/env bash
###############################################################################
# Gera o Secret Kubernetes (gitops/base/secrets.yaml) a partir dos outputs do
# Terraform. O arquivo gerado NAO deve ser versionado com valores reais
# (gitops/base/secrets.yaml esta no .gitignore).
#
# Uso:  AWS_PROFILE=tf ./generate-k8s-secrets.sh
#       MASTER_KEY=... SERVICE_API_KEY=... ./generate-k8s-secrets.sh  (override)
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/.."
OUT_FILE="${TF_DIR}/../gitops/base/secrets.yaml"

command -v terraform >/dev/null || { echo "ERRO: terraform nao encontrado"; exit 1; }
command -v base64 >/dev/null || { echo "ERRO: base64 nao encontrado"; exit 1; }
command -v jq >/dev/null || { echo "ERRO: jq nao encontrado"; exit 1; }

echo "==> Lendo outputs do Terraform..."
TFOUT="$(terraform -chdir="${TF_DIR}" output -json)"

jq_get() { echo "${TFOUT}" | jq -r ".$1.value"; }

DB_USER="$(jq_get rds_username)"
REDIS_URL="$(jq_get redis_url)"
SQS_URL="$(jq_get sqs_queue_url)"

AUTH_HOST="$(echo "${TFOUT}" | jq -r '.rds_endpoints.value.auth_db')"
FLAG_HOST="$(echo "${TFOUT}" | jq -r '.rds_endpoints.value.flag_db')"
TARGETING_HOST="$(echo "${TFOUT}" | jq -r '.rds_endpoints.value.targeting_db')"

AUTH_PASS="$(echo "${TFOUT}" | jq -r '.rds_passwords.value."auth_db"')"
FLAG_PASS="$(echo "${TFOUT}" | jq -r '.rds_passwords.value."flag_db"')"
TARGETING_PASS="$(echo "${TFOUT}" | jq -r '.rds_passwords.value."targeting_db"')"

MASTER_KEY="${MASTER_KEY:-admin-segredo-123}"
SERVICE_API_KEY="${SERVICE_API_KEY:-tm_key_dev}"

b64() { printf '%s' "$1" | base64 -w0; }

cat > "${OUT_FILE}" <<EOF
# GERADO AUTOMATICAMENTE por terraform/scripts/generate-k8s-secrets.sh
# NAO commite valores reais deste arquivo.
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: feature-flags
type: Opaque
data:
  DATABASE_URL_AUTH: "$(b64 "postgresql://${DB_USER}:${AUTH_PASS}@${AUTH_HOST}:5432/auth_db")"
  DATABASE_URL_FLAG: "$(b64 "postgresql://${DB_USER}:${FLAG_PASS}@${FLAG_HOST}:5432/flag_db")"
  DATABASE_URL_TARGETING: "$(b64 "postgresql://${DB_USER}:${TARGETING_PASS}@${TARGETING_HOST}:5432/targeting_db")"
  REDIS_URL: "$(b64 "${REDIS_URL}")"
  AWS_SQS_URL: "$(b64 "${SQS_URL}")"
  MASTER_KEY: "$(b64 "${MASTER_KEY}")"
  SERVICE_API_KEY: "$(b64 "${SERVICE_API_KEY}")"
EOF

chmod 600 "${OUT_FILE}"

echo "==> Secret gerado em ${OUT_FILE}"
echo ""
echo "Proximos passos:"
echo "  kubectl apply -k gitops/base"
echo ""
echo "LEMBRETE: apos o primeiro deploy, crie a API key de servico no auth-service"
echo "(POST /keys) e reinicie evaluation/flag services se SERVICE_API_KEY mudar."
