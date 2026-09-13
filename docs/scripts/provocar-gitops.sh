#!/usr/bin/env bash
###############################################################################
# GATILHO VERDE de CD/GitOps - dispara o CI dos 5 microsservicos de uma vez.
#
# Adiciona UMA linha de comentario benigna no arquivo de entrada de CADA um dos
# 5 servicos (main.go / app.py). O comentario passa em todos os gates (build,
# golangci-lint/flake8+pylint, gosec/bandit, Trivy) - os 5 runs ficam VERDEs, os
# jobs update-gitops bumpam as 5 tags no repositorio GitOps, e o ArgoCD detecta
# e sincroniza as 5 Applications automaticamente.
#
# NUNCA introduz variavel/comentario que quebre lint. Use com o guia
# docs/gitops-argocd-demo.md. Depois rode reverter-gitops.sh.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_main_clean
require_no_open_demo

GO_FILES=("auth-service/main.go" "evaluation-service/main.go")
PY_FILES=("analytics-service/app.py" "flag-service/app.py" "targeting-service/app.py")
GO_COMMENT='// demo(gitops): mudanca benigna - dispara CI/CD dos 5 servicos.'
PY_COMMENT='# demo(gitops): mudanca benigna - dispara CI/CD dos 5 servicos.'

add_comment() {
  local file="$1" comment="$2"
  [ -f "$file" ] || die "arquivo nao encontrado: $file"
  grep -q 'demo(gitops)' "$file" && die "marcador 'demo(gitops)' ja existe em $file; reveja o arquivo"
  sed -i "1i ${comment}" "$file"
  grep -q 'demo(gitops)' "$file" || die "insercao nao aplicada em $file; aborte e reveja o arquivo"
  echo "    ok: $file"
}

echo "==> Aplicando mudanca benigna (linha de comentario) nos 5 servicos..."
for f in "${GO_FILES[@]}"; do add_comment "$f" "$GO_COMMENT"; done
for f in "${PY_FILES[@]}"; do add_comment "$f" "$PY_COMMENT"; done

git add "${GO_FILES[@]}" "${PY_FILES[@]}"
git diff --cached --quiet && die "nenhuma mudanca (:,- nada para commitar"

git commit -m "demo(gitops): mudanca benigna nos 5 microsservicos (dispara CI/CD de todos) - demonstracao"
remote_push

echo
echo "==> Push enviado. Os 5 pipelines rodam em paralelo (runs VERDES) e cada job"
echo "    'Update GitOps - nova tag (<servico>)' comita o bump da tag no GitOps."
show_run "$(git rev-parse HEAD)"

echo
echo "==> Proximo passo (guia docs/gitops-argocd-demo.md):"
echo "    Na UI do ArgoCD, as 5 Applications piscam OutOfSync -> Synced (automated);"
echo "    kubectl get applications -n argocd -w"
echo "    kubectl rollout status deployment/<servico> -n feature-flags --timeout=180s"
echo
echo "Para limpar e fechar verde: bash docs/scripts/reverter-gitops.sh"