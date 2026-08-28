<#
.SYNOPSIS
  Gera os projetos nativos (android/ e ios/) do VR Dino Cardboard no Windows.

.DESCRIPTION
  Este repositorio versiona apenas o que e ESPECIFICO da experiencia VR:

    android/app/src/main/AndroidManifest.xml
    android/app/src/main/res/xml/network_security_config.xml
    android/app/src/main/kotlin/.../MainActivity.kt
    ios/Runner/Info.plist

  Todo o resto (Gradle, projeto Xcode, icones, LaunchScreen) e boilerplate que
  o proprio Flutter gera e que muda conforme a versao do SDK.

  IMPORTANTE: `flutter create` SEM `--overwrite` PULA qualquer arquivo que ja
  exista. E exatamente o comportamento desejado: cria o que falta e preserva o
  pubspec.yaml, o lib/, o README.md e os arquivos de plataforma acima.
  NUNCA acrescente `--overwrite` - isso apagaria o projeto inteiro.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\setup.ps1
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error "Flutter SDK nao encontrado no PATH. Rode 'flutter doctor' primeiro."
  exit 1
}

Write-Host "1/4 flutter create (android + ios)" -ForegroundColor Cyan
flutter create . --platforms=android,ios --org com.example --project-name vr_dino_cardboard
if ($LASTEXITCODE -ne 0) { Write-Error "flutter create falhou."; exit 1 }

Write-Host "2/4 Removendo o teste de widget gerado pelo template" -ForegroundColor Cyan
# O template cria um teste do app contador padrao, que falha neste projeto.
Remove-Item -Force -ErrorAction SilentlyContinue "test\widget_test.dart"

Write-Host "3/4 Ajustando minSdk do Android" -ForegroundColor Cyan
# flutter_inappwebview 6 exige minSdk 21+; usamos 24 pelo WebGL 2 e pelo
# WebView moderno.
# Set-Content -Encoding UTF8 grava COM BOM no Windows PowerShell 5.1, e um BOM
# em arquivo .gradle.kts atrapalha o compilador de scripts do Gradle. Gravamos
# UTF-8 sem BOM explicitamente.
function Write-TextNoBom([string]$Path, [string]$Content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Resolve-Path $Path), $Content, $utf8NoBom)
}

$kts    = "android\app\build.gradle.kts"
$groovy = "android\app\build.gradle"
if (Test-Path $kts) {
  Write-TextNoBom $kts ((Get-Content $kts -Raw) -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24')
  Write-Host "    build.gradle.kts -> minSdk = 24"
} elseif (Test-Path $groovy) {
  Write-TextNoBom $groovy ((Get-Content $groovy -Raw) -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24')
  Write-Host "    build.gradle -> minSdkVersion 24"
} else {
  Write-Warning "    build.gradle nao encontrado - ajuste o minSdk para 24 na mao."
}

Write-Host "4/4 flutter pub get" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Error "flutter pub get falhou."; exit 1 }

Write-Host ""
Write-Host "Pronto. Proximos passos:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File tool\fetch_web_deps.ps1"
Write-Host "  powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1   # se o Gradle reclamar"
Write-Host "  flutter analyze"
Write-Host "  flutter test"
Write-Host "  flutter run --release      # SEMPRE em release para medir FPS real"
