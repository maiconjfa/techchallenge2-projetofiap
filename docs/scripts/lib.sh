#!/usr/bin/env bash
###############################################################################
# lib.sh - helpers dos scripts de apresentacao do ToggleMaster.
# Uso dentro dos pares provocar/reverter:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# CONFIGURACAO (ajuste se o repositorio mudar):
###############################################################################
set -euo pipefail

REPO="maiconjfa/techchallenge2-projetofiap"
PUSH_URL="git@github.com:${REPO}.git"                  # SSH (HTTPS nao tem credencial no WSL)
ACTIONS_URL="https://github.com/${REPO}/actions"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "ERRO: $*" >&2; exit 1; }

require_clean_tree() {
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || die "working tree suja; commit/stash antes"
}

# Exige: branch main, arvore limpa e main sincronizada com o origin.
require_main_clean() {
  require_clean_tree
  [ "$(git -C "$ROOT" branch --show-current)" = "main" ] || die "esta em $(git -C "$ROOT" branch --show-current); use a branch main"
  git -C "$ROOT" fetch origin main >/dev/null
  [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ] \
    || die "main local nao sincronizada; rode: git -C \"$ROOT\" pull --rebase origin main"
}

# Garante que nenhuma outra provocacao esteja pendente em main.
require_no_open_demo() {
  local m
  for m in "demo(sca)" "demo(sast)" "demo(lint)"; do
    if git -C "$ROOT" log origin/main --oneline --grep="$m" | grep -q .; then
      die "ja existe \"$m\" pendente em main; rode o reverter-*.sh correspondente antes de provocar de novo"
    fi
  done
}

commit_sha() { git -C "$ROOT" log origin/main --format=%H --grep="$1" -1; }

remote_push() { git -C "$ROOT" push "$PUSH_URL" main:main; }

# Localiza o run do push e acompanha ate o fim (mostra o log ao vivo, ideal p/ filmar).
# Billboarding: NAO usa --exit-status para o script nao abortar (o run vai falhar de proposito).
show_run() {
  local sha="${1:-}" id="" i conclusion
  if command -v gh >/dev/null 2>&1; then
    for i in $(seq 1 24); do
      id="$(gh api "repos/${REPO}/actions/runs?head_sha=${sha}&event=push" \
        --jq '.workflow_runs[0].id' 2>/dev/null || true)"
      [ -n "$id" ] && [ "$id" != "null" ] && break
      sleep 5
    done
    if [ -n "$id" ] && [ "$id" != "null" ]; then
      echo "==> Run no GitHub Actions: ${ACTIONS_URL}/runs/${id}"
      gh run watch "$id" --repo "$REPO" || true
      conclusion="$(gh api "repos/${REPO}/actions/runs/${id}" --jq '.conclusion' 2>/dev/null || true)"
      echo "==> conclusao do run: ${conclusion:-desconhecida}"
    else
      echo "==> Run ainda nao apareceu. Acompanhe em: ${ACTIONS_URL}"
    fi
  else
    echo "==> Cli 'gh' nao encontrado; acompanhe o run em: ${ACTIONS_URL}"
  fi
}