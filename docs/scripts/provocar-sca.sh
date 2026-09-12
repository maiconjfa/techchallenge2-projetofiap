#!/usr/bin/env bash
###############################################################################
# CENA DE FALHA - SCA (dependencia vulneravel).
#
# Downgrade do golang.org/x/crypto para v0.20.0 (CVE-2026-56854 - CRITICAL) e
# regenera o go.sum (via container golang:1.26-alpine). O Trivy FS - GATE CRITICAL
# para o pipeline no passo *Security Scan*. Depois rode reverter-sca.sh.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_main_clean
require_no_open_demo

echo "==> Downgrade golang.org/x/crypto para v0.20.0 (container golang:1.26-alpine)..."
docker run --rm -v "$ROOT":/src -w /src/auth-service golang:1.26-alpine \
  sh -c "go mod edit -require=golang.org/x/crypto@v0.20.0 && go mod tidy"

grep -q 'golang.org/x/crypto v0.20.0' auth-service/go.mod || die "downgrade nao aplicado ao go.mod"
git diff --quiet || git add auth-service/go.mod auth-service/go.sum || true
git diff --cached --quiet && die "nenhuma mudanca (-: nada para commitar"

git commit -m "demo(sca): golang.org/x/crypto v0.20.0 (CVE-2026-56854 CRITICAL) - demonstracao"
remote_push

echo
echo "==> Push enviado. O pipeline deve parar (run VERMELHO) em:"
echo "    Security Scan -> Trivy FS - GATE CRITICAL (CVE-2026-56854)"
show_run "$(git rev-parse HEAD)"

echo
echo "NARRATIVA SUGERIDA:"
echo "  \"Aqui o SCA encontrou uma dependencia com vulnerabilidade CRITICAL. Pela regra"
echo "   de bloqueio o pipeline NAO passa para Docker/build nem para o deploy.\""
echo
echo "Para limpar e mostrar a CORRECAO: bash docs/scripts/reverter-sca.sh"