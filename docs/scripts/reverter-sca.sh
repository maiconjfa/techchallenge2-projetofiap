#!/usr/bin/env bash
###############################################################################
# Reverte a cena SCA (provocar-sca.sh): git revert do commit demo(sca) + push.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_clean_tree
git fetch origin main >/dev/null

SHA="$(commit_sha "demo(sca):")"
[ -n "$SHA" ] || die "commit demo(sca) nao encontrado em origin/main"

echo "==> Revertendo $SHA"
git revert --no-edit "$SHA"
remote_push

echo "==> Revertido e enviado. A nova run deve ficar VERDE."
echo "    Acompanhe: ${ACTIONS_URL}"
show_run "$(git rev-parse HEAD)"