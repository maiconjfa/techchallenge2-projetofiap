#!/usr/bin/env bash
###############################################################################
# GATILHO VERDE de CD/GitOps - update da tag no repositorio GitOps.
#
# Faz uma mudanca BENIGNA em auth-service/main.go (versao do app exibida no
# log) que PASSA em todos os gates (build, golangci-lint, gosec e Trivy) - o
# run fica VERDE e o job update-gitops comita o bump de images.newTag no
# repositorio GitOps. Esse bump e o que o ArgoCD detecta e sincroniza.
#
# NUNCA usa variavel nao utilizada (isso quebraria o lint). A constante
# appVersion e REFERENCIADA no log. Use com o guia docs/gitops-argocd-demo.md.
# Depois rode reverter-gitops.sh.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_main_clean
require_no_open_demo

FILE="auth-service/main.go"
[ -f "$FILE" ] || die "arquivo nao encontrado: $FILE"

grep -q 'demo(gitops)' "$FILE" && die "marcador 'demo(gitops)' ja existe; reveja o arquivo"
grep -q 'appVersion = "1.0.0-demo"' "$FILE" && die "constante appVersion de demo ja existe"

echo "==> Aplicando mudanca benigna (versao do app no log) em ${FILE}..."
sed -i 's/log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port)/log.Printf("Serviço de Autenticação (Go) versão %s rodando na porta %s", appVersion, port)/' "$FILE"
cat >> "$FILE" <<'EOF'

// demo(gitops): versao do app exibida no log - mudanca benigna que dispara a CD.
const appVersion = "1.0.0-demo"
EOF

# Garante que a troca realmente aconteceu (narrativa honesta na tela).
grep -q 'const appVersion = "1.0.0-demo"' "$FILE" || die "troca nao aplicada; aborte e reveja o arquivo"

git add "$FILE"
git diff --cached --quiet && die "nenhuma mudanca (:,- nada para commitar"

git commit -m "demo(gitops): versao do app no log (mudanca benigna que dispara CD) - demonstracao"
remote_push

echo
echo "==> Push enviado. O run fica VERDE e o job 'Update GitOps - nova tag (auth-service)' 
     comita o bump de images.newTag no repositorio GitOps."
show_run "$(git rev-parse HEAD)"

echo
echo "==> Proximo passo (guia docs/gitops-argocd-demo.md):"
echo "    na UI do ArgoCD, auth-service pisca OutOfSync -> Synced (automated);"
echo "    kubectl rollout status deployment/auth-service -n feature-flags --timeout=180s"
echo
echo "Para limpar e fechar verde: bash docs/scripts/reverter-gitops.sh"