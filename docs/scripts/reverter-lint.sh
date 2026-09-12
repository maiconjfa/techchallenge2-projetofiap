#!/usr/bin/env bash
###############################################################################
# Reverte a cena Lint (provocar-lint.sh): git revert do commit demo(lint) + push.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_clean_tree
git fetch origin main >/dev/null

SHA="$(commit_sha "demo(lint):")"
[ -n "$SHA" ] || die "commit demo(lint) nao encontrado em origin/main"

echo "==> Revertendo $SHA"
git revert --no-edit "$SHA"
remote_push

echo "==> Revertido e enviado. A nova run deve ficar VERDE."
echo "    Acompanhe: ${ACTIONS_URL}"
show_run "$(git rev-parse HEAD)"