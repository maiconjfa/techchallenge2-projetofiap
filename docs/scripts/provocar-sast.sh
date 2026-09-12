#!/usr/bin/env bash
###############################################################################
# CENA DE FALHA - SAST (vulnerabilidade no codigo-fonte).
#
# Remove os comentarios '#nosec G704' do evaluation-service/evaluator.go.
# O codigo JA contem 4 requests SSRF (variavel de origem externa); sem o nosec
# o gosec volta a acusar 4x G704 (SSRF, HIGH) e o pipeline para no
# *Security Scan -> gosec - SAST Go*. Depois rode reverter-sast.sh.
###############################################################################
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

require_main_clean
require_no_open_demo

FILE="evaluation-service/evaluator.go"
[ -f "$FILE" ] || die "arquivo nao encontrado: $FILE"

echo "==> Removendo '#nosec G704' de ${FILE}..."
sed -i -E 's@[[:space:]]*// #nosec G704.*@@' "$FILE"

if grep -q '#nosec G704' "$FILE"; then
  die "aviso: ainda restam comentarios '#nosec G704'; revise o arquivo manualmente"
fi

git add "$FILE"
git diff --cached --quiet && die "nenhuma mudanca (:- nada para commitar"

git commit -m "demo(sast): remove #nosec G704 (4x SSRF no evaluator) - demonstracao"
remote_push

echo
echo "==> Push enviado. O pipeline deve parar (run VERMELHO) em:"
echo "    Security Scan -> gosec - SAST Go (G704 SSRF, HIGH -> exit 1)"
show_run "$(git rev-parse HEAD)"

echo
echo "NARRATIVA SUGERIDA:"
echo "  \"O SAST analisa o codigo-fonte, nao as dependencias. Aqui o gosec flagrou 4 trechos"
echo "   com risco de SSRF; o nosec que mascarava foi removido para demonstrar o bloqueio.\""
echo
echo "Para limpar e mostrar a CORRECAO: bash docs/scripts/reverter-sast.sh"