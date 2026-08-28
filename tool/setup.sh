#!/usr/bin/env bash
#
# Gera os projetos nativos (android/ e ios/).
#
# Este repo versiona apenas o que e ESPECIFICO da experiencia VR:
#   android/app/src/main/AndroidManifest.xml
#   android/app/src/main/res/xml/network_security_config.xml
#   android/app/src/main/kotlin/.../MainActivity.kt
#   ios/Runner/Info.plist
#
# Todo o resto (Gradle, projeto Xcode, icones, LaunchScreen) e boilerplate que
# o proprio Flutter gera e que varia com a versao do SDK.
#
# IMPORTANTE: `flutter create` SEM `--overwrite` pula qualquer arquivo que ja
# exista. E exatamente o que queremos: ele cria o que falta e preserva o nosso
# pubspec.yaml, lib/, README.md e os arquivos de plataforma acima.
# NUNCA acrescente `--overwrite` aqui - isso apagaria o projeto inteiro.
#
# No Windows use tool/setup.ps1 (PowerShell), que faz o mesmo.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v flutter >/dev/null 2>&1 || { echo "Flutter SDK nao encontrado no PATH."; exit 1; }

echo "1/4 flutter create (android + ios)"
flutter create . \
  --platforms=android,ios \
  --org com.example \
  --project-name vr_dino_cardboard

echo "2/4 Removendo o teste de widget gerado pelo template"
# O template cria um teste do app contador padrao, que falha neste projeto.
rm -f test/widget_test.dart

echo "3/4 Ajustando minSdk do Android"
GRADLE_KTS="android/app/build.gradle.kts"
GRADLE_GROOVY="android/app/build.gradle"
if [ -f "$GRADLE_KTS" ]; then
  # flutter_inappwebview 6 exige minSdk 21+; usamos 24 pelo WebGL 2 e pelo
  # WebView moderno.
  sed -i.bak 's/minSdk = flutter.minSdkVersion/minSdk = 24/' "$GRADLE_KTS" && rm -f "$GRADLE_KTS.bak"
elif [ -f "$GRADLE_GROOVY" ]; then
  sed -i.bak 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' "$GRADLE_GROOVY" && rm -f "$GRADLE_GROOVY.bak"
fi

echo "4/4 flutter pub get"
flutter pub get

echo
echo "Pronto. Proximos passos:"
echo "  tool/fetch_web_deps.sh   # embute o three.js (opcional, recomendado)"
echo "  flutter analyze && flutter test"
echo "  flutter run --release    # SEMPRE em release para medir FPS real"
