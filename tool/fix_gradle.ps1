<#
.SYNOPSIS
  Corrige incompatibilidades entre o Android Gradle Plugin (AGP) e o Kotlin
  Gradle Plugin (KGP) nos arquivos que o `flutter create` gerou.

.DESCRIPTION
  Estes arquivos sao BOILERPLATE do template do Flutter, nao codigo deste
  projeto. Dependendo da combinacao versao do Flutter x AGP x KGP x Gradle
  instalada na maquina, o template sai com um DSL que o plugin presente nao
  entende. Sintomas tipicos ao rodar `flutter run`:

    e: android/app/build.gradle.kts:37:1: None of the following candidates
       is applicable: fun DependencyHandler.kotlin(module: String, ...)
    e: android/app/build.gradle.kts:38:5: Unresolved reference 'compilerOptions'
    e: android/app/build.gradle.kts:39:9: Unresolved reference 'jvmTarget'

    Line 07: android {
             ^ 'fun Project.android(...)' is deprecated. Replaced by
               com.android.build.api.dsl.ApplicationExtension.

  Duas correcoes independentes sao aplicadas:

  (A) android/gradle.properties  ->  android.newDsl=false
      A partir do AGP 9.0 o "novo DSL" e o padrao, e nele o bloco `android { }`
      classico - que o template do Flutter usa - vira uma API depreciada com
      nivel ERROR, o que quebra a compilacao do script. Desligar o novo DSL
      restaura o comportamento contra o qual o template foi escrito.

  (B) android/app/build.gradle.kts
      Troca o bloco de topo

          kotlin { compilerOptions { jvmTarget = ...JvmTarget.JVM_17 } }

      que exige KGP 2.1+, pela forma equivalente

          tasks.withType<KotlinCompile>().configureEach {
              kotlinOptions.jvmTarget = "17"
          }

      que funciona do KGP 1.8 ao 2.x.

  O script e idempotente: rodar duas vezes nao causa dano.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-TextNoBom([string]$Path, [string]$Content) {
  # Set-Content -Encoding UTF8 grava COM BOM no Windows PowerShell 5.1, e um
  # BOM em .gradle.kts atrapalha o compilador de scripts do Gradle.
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Resolve-Path $Path), $Content, $utf8NoBom)
}

$changed = $false

# --------------------------------------------------------------- (A) newDsl
$props = "android\gradle.properties"
if (Test-Path $props) {
  $text = Get-Content $props -Raw
  if ($text -notmatch '(?m)^\s*android\.newDsl\s*=') {
    if ($text -notmatch '\r?\n$') { $text += "`r`n" }
    $text += @"

# Desliga o "novo DSL" do AGP 9. O template do Flutter ainda usa o bloco
# `android { }` classico, que no novo DSL e uma API depreciada com nivel ERROR
# e quebra a compilacao do script Gradle.
android.newDsl=false
"@
    Write-TextNoBom $props $text
    Write-Host "[A] android/gradle.properties -> android.newDsl=false" -ForegroundColor Green
    $changed = $true
  } else {
    Write-Host "[A] android.newDsl ja definido - nada a fazer" -ForegroundColor DarkGray
  }
} else {
  Write-Warning "[A] android\gradle.properties nao existe. Rode tool\setup.ps1 antes."
}

# ------------------------------------------------------------ (B) jvmTarget
$kts = "android\app\build.gradle.kts"
if (Test-Path $kts) {
  $text = Get-Content $kts -Raw
  $pattern = '(?s)\bkotlin\s*\{\s*compilerOptions\s*\{.*?\}\s*\}'
  if ($text -match $pattern) {
    $replacement = @'
// jvmTarget definido por task, em vez do DSL de topo do Kotlin, que exige
// Kotlin Gradle Plugin 2.1+. Esta forma funciona do KGP 1.8 ao 2.x.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "17"
}
'@
    $text = [regex]::Replace($text, $pattern, { $replacement }, 'Singleline')
    Write-TextNoBom $kts $text
    Write-Host "[B] build.gradle.kts -> jvmTarget via tasks.withType<KotlinCompile>" -ForegroundColor Green
    $changed = $true
  } else {
    Write-Host "[B] bloco kotlin { compilerOptions } nao encontrado - nada a fazer" -ForegroundColor DarkGray
  }
} else {
  Write-Warning "[B] $kts nao existe (projeto pode usar Groovy). Rode tool\setup.ps1 antes."
}

Write-Host ""
if ($changed) {
  Write-Host "Correcoes aplicadas. Agora rode:" -ForegroundColor Green
  Write-Host "  flutter clean"
  Write-Host "  flutter run --release"
  Write-Host ""
  Write-Host "Se AINDA falhar, me mande a saida de:" -ForegroundColor Yellow
  Write-Host "  flutter --version"
  Write-Host "  type android\settings.gradle.kts"
  Write-Host "  type android\app\build.gradle.kts"
} else {
  Write-Host "Nada foi alterado - o problema provavelmente e outro." -ForegroundColor Yellow
  Write-Host "Me mande a saida de 'flutter --version' e o conteudo de"
  Write-Host "android\settings.gradle.kts para eu fixar as versoes exatas."
}
