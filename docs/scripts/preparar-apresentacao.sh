#!/usr/bin/env bash
###############################################################################
# FASE 0 - deixa TUDO pronto para a apresentacao (idempotente e filmavel).
#
# Uso:
#   AWS_PROFILE=tf bash docs/scripts/preparar-apresentacao.sh            # executa, pausa por fase
#   AWS_PROFILE=tf bash docs/scripts/preparar-apresentacao.sh --dry-run  # so imprime os comandos
#   bash docs/scripts/preparar-apresentacao.sh --no-smoke               # pula o smoke test final
#
# Conta/Alvo: 248530551510 / us-east-1 / cluster togglemaster-eks
###############################################################################
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRY=0
SMOKE=1
[ "${1:-}" = "--dry-run" ] && DRY=1
[ "${1:-}" = "--no-smoke" ] && SMOKE=0
[ "${2:-}" = "--no-smoke" ] && SMOKE=0

EXPECTED_ACCOUNT="${EXPECTED_ACCOUNT:-248530551510}"
AWS_REGION="${AWS_REGION:-us-east-1}"
REPO="maiconjfa/techchallenge2-projetofiap"
PUSH_URL="git@github.com:${REPO}.git"
ACTIONS_URL="https://github.com/${REPO}/actions"
CLUSTER="togglemaster-eks"
TFAVS="$ROOT/terraform/terraform.tfvars"

say()  { echo; echo "#############################################################"; echo "# $*"; echo "#############################################################"; }
warn() { echo "!! $*"; }
die()  { echo "ERRO: $*" >&2; exit 1; }
pause() { if [ "$DRY" -eq 0 ]; then read -r -p ">>> Enter para continuar (ou Ctrl-C para pausar)... " _ || exit 1; fi; }

# hrun "descricao" cmd...
hrun() {
  local desc="$1"; shift
  echo; echo "### ${desc}"
  if [ "$DRY" -eq 0 ]; then "$@"; else printf '    %s\n' "$*"; fi
  pause
}

for t in aws terraform kubectl git jq base64 docker; do
  command -v "$t" >/dev/null || die "'$t' nao instalado"
done
HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1

say "FASE 0 - ToggleMaster"
echo "terraform : $(terraform version | awk '/^Terraform/{print $2}')"
echo "profile   : ${AWS_PROFILE:-<padrao da CLI>}"
echo "conta     : (esperada ${EXPECTED_ACCOUNT})"
pause

###############################################################################
say "1/9 - Valida credencial AWS"
###############################################################################
if [ "$DRY" -eq 0 ]; then
  ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
  echo "conta autenticada: ${ACCOUNT}"
  [ "$ACCOUNT" = "$EXPECTED_ACCOUNT" ] || warn "conta difere da esperada - confira AWS_PROFILE"
else
  echo "    aws sts get-caller-identity --query Account --output text"
fi
pause

###############################################################################
say "2/9 - terraform.tfvars"
###############################################################################
if [ -f "$TFAVS" ]; then
  echo "ja existe: $TFAVS (nao sobrescrevo)"
else
  hrun "Cria terraform.tfvars a partir do exemplo" cp "$ROOT/terraform/terraform.tfvars.example" "$TFAVS"
fi
echo "--- conteudo ---"
[ "$DRY" -eq 0 ] && sed 's/^/    /' "$TFAVS" || true
pause

###############################################################################
say "3/9 - Backend remoto S3 (state NUNCA local)"
###############################################################################
hrun "bootstrap-state.sh (bucket + versionamento + SSE-S3 + bloqueio publico)" \
  "$ROOT/terraform/scripts/bootstrap-state.sh"
pause

###############################################################################
say "4/9 - Provisiona a infraestrutura (VPC, EKS, RDSx3, Redis, DynamoDB, SQS, ECRx5, OIDC)"
###############################################################################
hrun "terraform init" terraform -chdir="$ROOT/terraform" init
hrun "terraform plan (gera plan.out para filmar a lista de ~20 recursos)" \
  terraform -chdir="$ROOT/terraform" plan -out="$ROOT/terraform/plan.out"
hrun "terraform apply plan.out" terraform -chdir="$ROOT/terraform" apply "$ROOT/terraform/plan.out"

say "-> Nesta cena, filmamos o plan (verde, saldo de recursos) e o apply concluindo. Apos o apply:"
echo "    AWS Console > VPC togglemaster-vpc / EKS togglemaster-eks / RDS x3 / ElastiCache /"
echo "    DynamoDB ToggleMasterAnalytics / SQS / ECR x5 / IAM role togglemaster-github-ci-role"
pause

###############################################################################
say "5/9 - Kubeconfig do EKS"
###############################################################################
hrun "aws eks update-kubeconfig" aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"
pause

###############################################################################
say "6/9 - ArgoCD (2a camada de terraform, estado proprio)"
###############################################################################
hrun "argocd-install: terraform init" terraform -chdir="$ROOT/terraform/argocd-install" init
hrun "argocd-install: terraform apply" terraform -chdir="$ROOT/terraform/argocd-install" apply -auto-approve
pause

###############################################################################
say "7/9 - Secrets dos 5 servicos no cluster (feature-flags)"
###############################################################################
hrun "generate-k8s-secrets.sh (le outputs do terraform e gera gitops/base/secrets.yaml)" \
  "$ROOT/terraform/scripts/generate-k8s-secrets.sh"
hrun "kubectl apply -k gitops/base" kubectl apply -k "$ROOT/gitops/base"
pause

###############################################################################
say "8/9 - Secret AWS_ROLE_ARN no GitHub (destrava jobs docker-build-scan-push e update-gitops)"
###############################################################################
ROLLBACK_ROLE_FILE="$ROOT/terraform/.aws_role_arn.txt"
if [ "$HAVE_GH" -eq 1 ]; then
  hrun "gh secret set AWS_ROLE_ARN" bash -c \
    "terraform -chdir='$ROOT/terraform' output -raw github_ci_role_arn | gh secret set AWS_ROLE_ARN --repo '$REPO'"
else
  hrun "Salva AWS_ROLE_ARN em arquivo (crie a secret manualmente na UI do GitHub)" bash -c \
    "terraform -chdir='$ROOT/terraform' output -raw github_ci_role_arn > '$ROLLBACK_ROLE_FILE'"
  echo "ARN salvo em: $ROLLBACK_ROLE_FILE"
  echo "Crie manualmente: GitHub > Settings > Secrets and variables > Actions > New secret"
  echo "  Name = AWS_ROLE_ARN | Value = conteudo do arquivo acima"
fi
pause

###############################################################################
say "9/9 - Ativa as 5 Applications do ArgoCD (GitOps)"
###############################################################################
hrun "kubectl apply -f gitops/argocd/applications/" kubectl apply -f "$ROOT/gitops/argocd/applications/"
pause

###############################################################################
if [ "$SMOKE" -eq 1 ]; then
say "Smoke test - dispara a pipeline completa (5 jobs) em todos os servicos"
  hrun "commit --allow-empty + push na main (dispara 5 workflows; aguarde verde antes de gravar)" bash -c \
    "git -C '$ROOT' commit --allow-empty -m 'ci: smoke test' && git -C '$ROOT' push '$PUSH_URL' main:main"
  echo "Acompanhe: $ACTIONS_URL"
fi
pause

say "CHECKLIST - so considere pronto quando TODOS os itens responderem SIM"
cat <<EOF
  [ ] GitHub Actions: 5 pipelines (auth, flag, targeting, evaluation, analytics) verdes
      inclusive os jobs docker-build-scan-push e update-gitops
  [ ] ECR: 5 repositorios com imagem <v1.0.0-sha7> e :latest
  [ ] gitops/apps/*/kustomization.yaml receberam commit do bot (bump newTag)
  [ ] ArgoCD: 5 Applications Synchronized + Healthy  (kubectl -n argocd get applications)
  [ ] Pods em feature-flags: kubectl get pods -n feature-flags   (5 Running)
  [ ] Acesso UI ArgoCD:  kubectl -n argocd get svc  -> port-forward 8080:443
EOF
echo
echo "Depois disso, siga o roteiro em docs/apresentacao-video.md"
echo "e use os scripts provocar-{sca,sast,lint}.sh para as cenas de falha."
[ "$DRY" -eq 1 ] && echo "(dry-run finalizado - nenhum comando foi executado)"