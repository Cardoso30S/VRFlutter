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
# Sem este script o app ainda funciona: `index.html` cai para o CDN jsDelivr,
# mas ai exige rede no dispositivo no primeiro carregamento.

set -euo pipefail

THREE_VERSION="${THREE_VERSION:-0.160.1}"
BASE="https://cdn.jsdelivr.net/npm/three@${THREE_VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/assets/web/vendor"

WITH_DRACO=0
for arg in "$@"; do
  [ "$arg" = "--with-draco" ] && WITH_DRACO=1
done

fetch() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  echo "  -> $(basename "$dest")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -qO "$dest" "$url"
  fi
}

echo "three.js ${THREE_VERSION} -> assets/web/vendor/"

# O import map de `index.html` mapeia:
#   "three"          -> ./vendor/three.module.js
#   "three/addons/"  -> ./vendor/
# Por isso os addons precisam manter a subpasta original (loaders/, utils/).
fetch "${BASE}/build/three.module.js"                      "${VENDOR}/three.module.js"
fetch "${BASE}/examples/jsm/loaders/GLTFLoader.js"         "${VENDOR}/loaders/GLTFLoader.js"
fetch "${BASE}/examples/jsm/utils/SkeletonUtils.js"        "${VENDOR}/utils/SkeletonUtils.js"

if [ "$WITH_DRACO" = "1" ]; then
  echo "Draco:"
  fetch "${BASE}/examples/jsm/loaders/DRACOLoader.js"       "${VENDOR}/loaders/DRACOLoader.js"
  for f in draco_decoder.js draco_decoder.wasm draco_wasm_wrapper.js; do
    fetch "${BASE}/examples/jsm/libs/draco/${f}"            "${VENDOR}/libs/draco/${f}"
  done
fi

echo
echo "OK. Tamanho embutido:"
du -sh "${VENDOR}" 2>/dev/null || true
echo
echo "Lembre-se: 'assets/web/vendor/' ja esta declarado no pubspec.yaml."
echo "Subpastas novas (loaders/, utils/, libs/draco/) precisam ser declaradas"
echo "tambem - o script tool/sync_pubspec_assets.sh faz isso por voce."
