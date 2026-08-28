#!/usr/bin/env bash
#
# Equivalente Linux/macOS de tool/fix_gradle.ps1. Veja aquele arquivo para a
# explicacao completa. Resumo: o template do Flutter usa o bloco `android { }`
# classico, que o AGP 9 marca com DeprecationLevel.ERROR - o que no Kotlin e
# erro de compilacao, nao aviso. A correcao e usar um AGP 8.x.
#
# Uso:
#   tool/fix_gradle.sh                     # normaliza e fixa as versoes
#   tool/fix_gradle.sh --no-pin            # so normaliza e diagnostica
#   tool/fix_gradle.sh --agp 8.7.3 --kotlin 2.1.0

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NO_PIN=0; AGP=""; KOTLIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-pin) NO_PIN=1; shift ;;
    --agp) AGP="$2"; shift 2 ;;
    --kotlin) KOTLIN="$2"; shift 2 ;;
    *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done

GRADLE_VER=""
WRAPPER="android/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$WRAPPER" ]; then
  GRADLE_VER="$(sed -n 's/.*gradle-\([0-9][0-9.]*\)-\(all\|bin\)\.zip.*/\1/p' "$WRAPPER" | head -1)"
fi
GRADLE_MAJOR="${GRADLE_VER%%.*}"
[ -z "$GRADLE_MAJOR" ] && GRADLE_MAJOR=0

if [ -z "$AGP" ]; then
  if [ "$GRADLE_MAJOR" -ge 9 ] 2>/dev/null; then AGP="8.13.0"; else AGP="8.7.3"; fi
fi
if [ -z "$KOTLIN" ]; then
  if [ "$GRADLE_MAJOR" -ge 9 ] 2>/dev/null; then KOTLIN="2.1.20"; else KOTLIN="2.1.0"; fi
fi

export AGP KOTLIN NO_PIN
python3 - <<'PY'
import os, re, sys

agp, kotlin, no_pin = os.environ['AGP'], os.environ['KOTLIN'], os.environ['NO_PIN'] == '1'

CANONICAL = '''kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
'''

# (A) desfaz o android.newDsl
props = 'android/gradle.properties'
if os.path.exists(props):
    lines = open(props, encoding='utf-8').read().splitlines()
    drop = re.compile(r'^\s*android\.newDsl|^\s*#.*novo DSL|'
                      r'^\s*#.*API depreciada com nivel ERROR|'
                      r'^\s*#.*quebra a compilacao do script Gradle')
    kept = [l for l in lines if not drop.search(l)]
    new = '\n'.join(kept).rstrip() + '\n'
    if new != open(props, encoding='utf-8').read():
        open(props, 'w', encoding='utf-8').write(new)
        print('[A] android.newDsl removido de gradle.properties')
    else:
        print('[A] gradle.properties ja limpo')

# (B) restaura o bloco Kotlin canonico
kts = 'android/app/build.gradle.kts'
if os.path.exists(kts):
    text = before = open(kts, encoding='utf-8').read()
    text = re.sub(r'\n*(?:^//[^\n]*\n)*^tasks\.withType<[^\n]*KotlinCompile>'
                  r'\(\)\.configureEach\s*\{.*?\n\}\n?', '\n', text, flags=re.S | re.M)
    text = re.sub(r'\n*(?:^//[^\n]*\n)*^kotlin\s*\{\s*compilerOptions\s*\{.*?\n\}\n?',
                  '\n', text, flags=re.S | re.M)
    text = text.rstrip() + '\n\n' + CANONICAL
    if text != before:
        open(kts, 'w', encoding='utf-8').write(text)
        print('[B] build.gradle.kts -> bloco kotlin canonico restaurado')
    else:
        print('[B] build.gradle.kts ja canonico')
else:
    print('[B] %s nao existe. Rode tool/setup.sh antes.' % kts, file=sys.stderr)

# (C) fixa as versoes
settings = 'android/settings.gradle.kts'
agp_atual = kt_atual = '?'
if os.path.exists(settings):
    text = before = open(settings, encoding='utf-8').read()
    m = re.search(r'id\("com\.android\.application"\)\s+version\s+"([^"]+)"', text)
    if m: agp_atual = m.group(1)
    m = re.search(r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([^"]+)"', text)
    if m: kt_atual = m.group(1)
    if not no_pin:
        text = re.sub(r'(id\("com\.android\.application"\)\s+version\s+")[^"]+(")',
                      lambda mm: mm.group(1) + agp + mm.group(2), text)
        text = re.sub(r'(id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+")[^"]+(")',
                      lambda mm: mm.group(1) + kotlin + mm.group(2), text)
        if text != before:
            open(settings, 'w', encoding='utf-8').write(text)
            print('[C] settings.gradle.kts -> AGP %s => %s ; Kotlin %s => %s'
                  % (agp_atual, agp, kt_atual, kotlin))
            agp_atual, kt_atual = agp, kotlin
        else:
            print('[C] versoes ja fixadas')

open('/tmp/.fix_gradle_versions', 'w').write('%s\n%s\n' % (agp_atual, kt_atual))
PY

read -r AGP_ATUAL KT_ATUAL < <(tr '\n' ' ' < /tmp/.fix_gradle_versions) || true
rm -f /tmp/.fix_gradle_versions

echo
echo "================= DIAGNOSTICO ================="
echo "  Android Gradle Plugin : ${AGP_ATUAL:-?}"
echo "  Kotlin Gradle Plugin  : ${KT_ATUAL:-?}"
echo "  Gradle (wrapper)      : ${GRADLE_VER:-nao detectado}"
echo "  Java                  : $(java -version 2>&1 | grep -i version | head -1)"
echo "==============================================="
echo
echo "Rode agora:  flutter clean && flutter run --release"
