#!/usr/bin/env bash
###############################################################################
# CENA DE FALHA - Linter / Static Analysis.
#
# Adiciona uma variavel de pacote (level) NAO USADA em auth-service/main.go.
# O compilador aceita (build-test passa), mas o golangci-lint no job *lint*
# falha com 'unused'. Depois rode reverter-lint.sh.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_main_clean
require_no_open_demo

FILE="auth-service/main.go"
[ -f "$FILE" ] || die "arquivo nao encontrado: $FILE"

echo "==> Injetando variavel de pacote nao utilizada em ${FILE}..."
grep -q 'demoUnused' "$FILE" && die "variavel 'demoUnused' ja existe; reveja o arquivo"
cat >> "$FILE" <<'EOF'

// demo(lint): variavel de pacote nao utilizada - o golangci-lint (unused) bloqueia.
var demoUnused = "ci-linter-demo-marker"
EOF

git add "$FILE"
git diff --cached --quiet && die "nenhuma mudanca (:,- nada para commitar"

git commit -m "demo(lint): variavel de pacote nao utilizada (golangci-lint unused) - demonstracao"
remote_push

echo
echo "==> Push enviado. O pipeline deve parar (run VERMELHO) em:"
echo "    Lint -> golangci-lint run --timeout=5m  (unused: demoUnused)"
show_run "$(git rev-parse HEAD)"

echo
echo "NARRATIVA SUGERIDA:"
echo "  \"O linter roda ANTES do security scan e do deploy; código que passa no compilador"
echo "   pode falhar na análise estática, garantindo qualidade mínima antes de seguir.\""
echo
echo "Para limpar e mostrar a CORRECAO: bash docs/scripts/reverter-lint.sh"