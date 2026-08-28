#!/usr/bin/env bash
#
# Gera os projetos nativos (android/ e ios/) sem sobrescrever os arquivos de
# plataforma versionados neste repositorio.
#
# Este repo versiona apenas o que e ESPECIFICO da experiencia VR:
#   android/app/src/main/AndroidManifest.xml
#   android/app/src/main/res/xml/network_security_config.xml
#   android/app/src/main/kotlin/.../MainActivity.kt
#   ios/Runner/Info.plist
#
# Todo o resto (Gradle, Xcode project, icones, LaunchScreen) e boilerplate
# gerado pelo proprio Flutter e varia com a versao do SDK - versionar isso
# so cria conflito.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v flutter >/dev/null 2>&1 || { echo "Flutter SDK nao encontrado no PATH."; exit 1; }

BACKUP="$(mktemp -d)"
echo "1/5 Preservando arquivos de plataforma em $BACKUP"
for f in \
  android/app/src/main/AndroidManifest.xml \
  android/app/src/main/res/xml/network_security_config.xml \
  android/app/src/main/kotlin/com/example/vr_dino_cardboard/MainActivity.kt \
  ios/Runner/Info.plist
do
  [ -f "$f" ] && { mkdir -p "$BACKUP/$(dirname "$f")"; cp "$f" "$BACKUP/$f"; }
done

echo "2/5 flutter create (android + ios)"
flutter create . \
  --platforms=android,ios \
  --org com.example \
  --project-name vr_dino_cardboard \
  --overwrite

echo "3/5 Restaurando arquivos de plataforma"
(cd "$BACKUP" && find . -type f -print0) | while IFS= read -r -d '' f; do
  rel="${f#./}"
  mkdir -p "$(dirname "$rel")"
  cp "$BACKUP/$rel" "$rel"
done
rm -rf "$BACKUP"

echo "4/5 Ajustando minSdk do Android"
GRADLE_KTS="android/app/build.gradle.kts"
GRADLE_GROOVY="android/app/build.gradle"
if [ -f "$GRADLE_KTS" ]; then
  # flutter_inappwebview 6 exige minSdk 21+; usamos 24 pelo suporte a WebGL 2
  # e ao WebView moderno.
  sed -i.bak 's/minSdk = flutter.minSdkVersion/minSdk = 24/' "$GRADLE_KTS" && rm -f "$GRADLE_KTS.bak"
elif [ -f "$GRADLE_GROOVY" ]; then
  sed -i.bak 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' "$GRADLE_GROOVY" && rm -f "$GRADLE_GROOVY.bak"
fi

echo "5/5 flutter pub get"
flutter pub get

echo
echo "Pronto. Proximos passos:"
echo "  tool/fetch_web_deps.sh      # embute o three.js (opcional, recomendado)"
echo "  tool/sync_pubspec_assets.sh # atualiza o pubspec com as novas pastas"
echo "  flutter run --release       # SEMPRE em release para medir FPS real"
