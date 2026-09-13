#!/usr/bin/env bash
###############################################################################
# Reverte a cena GitOps (provocar-gitops.sh): git revert do commit demo(gitops)
# + push. O run volta a ficar VERDE e o ArgoCD sincroniza a versao final.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_clean_tree
git fetch origin main >/dev/null

SHA="$(commit_sha "demo(gitops):")"
[ -n "$SHA" ] || die "commit demo(gitops) nao encontrado em origin/main"

echo "==> Revertendo $SHA"
git revert --no-edit "$SHA"
remote_push

echo "==> Revertido e enviado. A nova run deve ficar VERDE."
echo "    Acompanhe: ${ACTIONS_URL}"
show_run "$(git rev-parse HEAD)"