#!/usr/bin/env bash
#
# Baixa o three.js e os addons usados pela cena para `assets/web/vendor/`,
# tornando o app 100% offline (sem CDN em runtime).
#
# Uso:
#   tool/fetch_web_deps.sh                 # three + GLTFLoader + SkeletonUtils
#   tool/fetch_web_deps.sh --with-draco    # inclui o decodificador Draco
#   THREE_VERSION=0.160.1 tool/fetch_web_deps.sh
#
# Todos os arquivos vao para a RAIZ de vendor/, sem subpastas: o Flutter nao
# inclui assets recursivamente, e a pasta plana ja e coberta pela unica linha
# `- assets/web/vendor/` do pubspec.yaml. O import map em index.html mapeia
# cada addon explicitamente para esses nomes.
#
# Sem este script o app ainda funciona: `index.html` cai para o CDN jsDelivr,
# mas ai exige rede no dispositivo no primeiro carregamento.
#
# No Windows use tool/fetch_web_deps.ps1 (PowerShell).

set -euo pipefail

THREE_VERSION="${THREE_VERSION:-0.160.1}"
BASE="https://cdn.jsdelivr.net/npm/three@${THREE_VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/assets/web/vendor"

WITH_DRACO=0
for arg in "$@"; do
  [ "$arg" = "--with-draco" ] && WITH_DRACO=1
done

mkdir -p "$VENDOR"

fetch() {
  local url="$1" dest="$2"
  echo "  -> $(basename "$dest")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -qO "$dest" "$url"
  fi
}

echo "three.js ${THREE_VERSION} -> assets/web/vendor/"
fetch "${BASE}/build/three.module.js"                "${VENDOR}/three.module.js"
fetch "${BASE}/examples/jsm/loaders/GLTFLoader.js"   "${VENDOR}/GLTFLoader.js"
fetch "${BASE}/examples/jsm/utils/SkeletonUtils.js"  "${VENDOR}/SkeletonUtils.js"

if [ "$WITH_DRACO" = "1" ]; then
  echo "Draco:"
  fetch "${BASE}/examples/jsm/loaders/DRACOLoader.js" "${VENDOR}/DRACOLoader.js"
  for f in draco_decoder.js draco_decoder.wasm draco_wasm_wrapper.js; do
    fetch "${BASE}/examples/jsm/libs/draco/${f}"      "${VENDOR}/${f}"
  done
fi

echo
du -sh "${VENDOR}" 2>/dev/null || true
echo "OK - nenhuma alteracao no pubspec.yaml e necessaria."
