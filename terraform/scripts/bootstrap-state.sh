#!/usr/bin/env bash
###############################################################################
# Bootstrap do backend remoto do Terraform.
#
# Cria (uma unica vez) o bucket S3 de estado com:
#   - versionamento habilitado
#   - criptografia SSE-S3
#   - bloqueio total de acesso publico
#
# O lock e feito pelo proprio S3 via 'use_lockfile = true' no backend
# (Terraform >= 1.10) - nao ha necessidade de tabela DynamoDB.
#
# Uso:  AWS_PROFILE=tf ./bootstrap-state.sh
###############################################################################
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
EXPECTED_ACCOUNT="${EXPECTED_ACCOUNT:-248530551510}"

command -v aws >/dev/null || { echo "ERRO: aws cli nao encontrado"; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ "${ACCOUNT_ID}" != "${EXPECTED_ACCOUNT}" ]]; then
  echo "AVISO: conta atual (${ACCOUNT_ID}) difere da esperada (${EXPECTED_ACCOUNT})."
  echo "O nome do bucket usara a conta corrente. Verifique se AWS_PROFILE esta correto."
fi

BUCKET="togglemaster-tfstate-${ACCOUNT_ID}"
echo "==> Backend remoto: s3://${BUCKET}"

echo "==> Garantindo bucket ${BUCKET} em ${AWS_REGION}..."
if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
else
  echo "    bucket ja existe"
fi

echo "==> Bloqueio de acesso publico..."
aws s3api put-public-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Versionamento..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "==> Criptografia padrao (SSE-S3)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo ""
echo "Backend pronto. Atualize terraform/versions.tf se ACCOUNT_ID != ${EXPECTED_ACCOUNT}:"
echo "  bucket = \"${BUCKET}\""
echo ""
echo "Proximos passos:"
echo "  export AWS_PROFILE=tf   # ou o perfil desta conta"
echo "  cd terraform && terraform init && terraform apply"
echo ""
echo "Apos o cluster subir, instale o ArgoCD (camada separada):"
echo "  aws eks update-kubeconfig --name togglemaster-eks --region ${AWS_REGION}"
echo "  cd terraform/argocd-install && terraform init && terraform apply"
