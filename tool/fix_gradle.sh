#!/usr/bin/env bash
#
# Equivalente Linux/macOS de tool/fix_gradle.ps1. Veja aquele arquivo para a
# explicacao completa das duas correcoes:
#
#   (A) android/gradle.properties  -> android.newDsl=false
#       (o bloco `android { }` do template e API depreciada com nivel ERROR
#        no novo DSL, padrao a partir do AGP 9.0)
#
#   (B) android/app/build.gradle.kts -> troca `kotlin { compilerOptions { } }`
#       (exige KGP 2.1+) pela forma compativel com KGP 1.8..2.x
#
# Idempotente.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHANGED=0

PROPS="android/gradle.properties"
if [ -f "$PROPS" ]; then
  if ! grep -qE '^[[:space:]]*android\.newDsl[[:space:]]*=' "$PROPS"; then
    cat >> "$PROPS" <<'PROP'

# Desliga o "novo DSL" do AGP 9. O template do Flutter ainda usa o bloco
# `android { }` classico, que no novo DSL e uma API depreciada com nivel ERROR
# e quebra a compilacao do script Gradle.
android.newDsl=false
PROP
    echo "[A] android/gradle.properties -> android.newDsl=false"
    CHANGED=1
  else
    echo "[A] android.newDsl ja definido - nada a fazer"
  fi
else
  echo "[A] $PROPS nao existe. Rode tool/setup.sh antes." >&2
fi

KTS="android/app/build.gradle.kts"
if [ -f "$KTS" ]; then
  if python3 - "$KTS" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
pattern = re.compile(r'\bkotlin\s*\{\s*compilerOptions\s*\{.*?\}\s*\}', re.S)
if not pattern.search(s):
    sys.exit(1)
replacement = (
    '// jvmTarget definido por task, em vez do DSL de topo do Kotlin, que exige\n'
    '// Kotlin Gradle Plugin 2.1+. Esta forma funciona do KGP 1.8 ao 2.x.\n'
    'tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {\n'
    '    kotlinOptions.jvmTarget = "17"\n'
    '}'
)
open(p, 'w', encoding='utf-8').write(pattern.sub(lambda _: replacement, s, count=1))
PY
  then
    echo "[B] build.gradle.kts -> jvmTarget via tasks.withType<KotlinCompile>"
    CHANGED=1
  else
    echo "[B] bloco kotlin { compilerOptions } nao encontrado - nada a fazer"
  fi
else
  echo "[B] $KTS nao existe (projeto pode usar Groovy)."
fi

echo
if [ "$CHANGED" = "1" ]; then
  echo "Correcoes aplicadas. Agora rode:"
  echo "  flutter clean && flutter run --release"
else
  echo "Nada foi alterado - o problema provavelmente e outro."
fi
