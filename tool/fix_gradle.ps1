<#
.SYNOPSIS
  Ajusta as versoes de AGP/Kotlin nos arquivos Gradle gerados pelo
  `flutter create` e imprime um diagnostico.

.DESCRIPTION
  Os arquivos em android/ sao BOILERPLATE do template do Flutter, nao codigo
  deste projeto. O problema aparece quando a maquina tem um Android Gradle
  Plugin novo demais para o template:

    Line 07: android {
             ^ 'fun Project.android(...)' is deprecated. Replaced by
               com.android.build.api.dsl.ApplicationExtension.

  Isso NAO e um aviso. No Kotlin, uma API marcada com `DeprecationLevel.ERROR`
  vira erro de compilacao - por isso o Gradle conta a depreciacao entre os
  "N errors". O template do Flutter usa o bloco `android { }` classico, que o
  AGP 9 marca nesse nivel. Nenhuma edicao do build.gradle.kts resolve: e
  preciso usar um AGP 8.x.

  Acoes:

  (A) Remove `android.newDsl` de android/gradle.properties.
      Tentativa anterior que nao surtiu efeito (a depreciacao e incondicional
      nesse AGP) e que o AGP 8.x rejeitaria como opcao desconhecida.

  (B) Restaura o bloco Kotlin de android/app/build.gradle.kts para a forma
      canonica do template, `kotlin { compilerOptions { jvmTarget = ... } }`,
      que e a correta para AGP 8.x + KGP 2.1+.

  (C) Fixa as versoes de AGP e Kotlin em android/settings.gradle.kts, com o
      par escolhido conforme a versao do Gradle do wrapper.

  (D) Imprime o DIAGNOSTICO de versoes.

  Idempotente: rodar varias vezes produz sempre o mesmo resultado.

.PARAMETER NoPin
  Nao altera as versoes; apenas normaliza os arquivos e mostra o diagnostico.

.PARAMETER Agp
  Versao do Android Gradle Plugin a fixar. Padrao: escolhida pelo Gradle.

.PARAMETER Kotlin
  Versao do plugin Kotlin a fixar. Padrao: escolhida junto com o AGP.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1
  powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1 -Agp 8.7.3 -Kotlin 2.1.0
  powershell -ExecutionPolicy Bypass -File tool\fix_gradle.ps1 -NoPin
#>

param(
  [switch]$NoPin,
  [string]$Agp = '',
  [string]$Kotlin = ''
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Write-TextNoBom([string]$Path, [string]$Content) {
  # Set-Content -Encoding UTF8 grava COM BOM no Windows PowerShell 5.1, e um
  # BOM em .gradle.kts atrapalha o compilador de scripts do Gradle.
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Resolve-Path $Path), $Content, $utf8NoBom)
}

# ---------------------------------------------- (A) desfaz o android.newDsl
$props = 'android\gradle.properties'
if (Test-Path $props) {
  $keep = Get-Content $props | Where-Object {
    ($_ -notmatch '^\s*android\.newDsl') -and
    ($_ -notmatch '^\s*#.*novo DSL') -and
    ($_ -notmatch '^\s*#.*API depreciada com nivel ERROR') -and
    ($_ -notmatch '^\s*#.*quebra a compilacao do script Gradle')
  }
  $new = (($keep -join "`r`n").TrimEnd() + "`r`n")
  if ($new -ne ((Get-Content $props -Raw))) {
    Write-TextNoBom $props $new
    Write-Host '[A] android.newDsl removido de gradle.properties' -ForegroundColor Green
  } else {
    Write-Host '[A] gradle.properties ja limpo' -ForegroundColor DarkGray
  }
}

# ------------------------------------- (B) restaura o bloco Kotlin canonico
$canonical = @'
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
'@

$kts = 'android\app\build.gradle.kts'
if (Test-Path $kts) {
  $text = Get-Content $kts -Raw
  $before = $text
  # Remove o bloco tasks.withType<...KotlinCompile> (e os comentarios acima).
  $text = $text -replace '(?sm)\n*(?:^//[^\n]*\n)*^tasks\.withType<[^\n]*KotlinCompile>\(\)\.configureEach\s*\{.*?\n\}\n?', "`n"
  # Remove o bloco de topo kotlin { compilerOptions { ... } }.
  $text = $text -replace '(?sm)\n*(?:^//[^\n]*\n)*^kotlin\s*\{\s*compilerOptions\s*\{.*?\n\}\n?', "`n"
  $text = $text.TrimEnd() + "`r`n`r`n" + $canonical

  if ($text -ne $before) {
    Write-TextNoBom $kts $text
    Write-Host '[B] build.gradle.kts -> bloco kotlin canonico restaurado' -ForegroundColor Green
  } else {
    Write-Host '[B] build.gradle.kts ja canonico' -ForegroundColor DarkGray
  }
} else {
  Write-Warning "[B] $kts nao existe. Rode tool\setup.ps1 antes."
}

# --------------------------------------------------- versao do Gradle (wrapper)
$gradleVer = ''
$wrapper = 'android\gradle\wrapper\gradle-wrapper.properties'
if (Test-Path $wrapper) {
  if ((Get-Content $wrapper -Raw) -match 'gradle-([0-9]+(?:\.[0-9]+)*)-(?:all|bin)\.zip') {
    $gradleVer = $Matches[1]
  }
}
$gradleMajor = 0
if ($gradleVer -match '^([0-9]+)') { $gradleMajor = [int]$Matches[1] }

# Pares AGP/Kotlin conhecidos por funcionarem com o template do Flutter.
# AGP 8.11+ e o primeiro que suporta Gradle 9; abaixo disso, Gradle 8.x.
if (-not $Agp)    { $Agp    = if ($gradleMajor -ge 9) { '8.13.0' } else { '8.7.3' } }
if (-not $Kotlin) { $Kotlin = if ($gradleMajor -ge 9) { '2.1.20' } else { '2.1.0' } }

# ------------------------------------------------------- (C) fixa as versoes
$settings = 'android\settings.gradle.kts'
$agpAtual = '?'; $ktAtual = '?'
if (Test-Path $settings) {
  $text = Get-Content $settings -Raw
  if ($text -match 'id\("com\.android\.application"\)\s+version\s+"([^"]+)"')    { $agpAtual = $Matches[1] }
  if ($text -match 'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([^"]+)"') { $ktAtual  = $Matches[1] }

  if (-not $NoPin) {
    $before = $text
    $text = $text -replace '(id\("com\.android\.application"\)\s+version\s+")[^"]+(")',    ('${1}' + $Agp + '${2}')
    $text = $text -replace '(id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+")[^"]+(")', ('${1}' + $Kotlin + '${2}')
    if ($text -ne $before) {
      Write-TextNoBom $settings $text
      Write-Host "[C] settings.gradle.kts -> AGP $agpAtual => $Agp ; Kotlin $ktAtual => $Kotlin" -ForegroundColor Green
      $agpAtual = $Agp; $ktAtual = $Kotlin
    } else {
      Write-Host '[C] versoes ja fixadas' -ForegroundColor DarkGray
    }
  }
} else {
  Write-Warning "[C] $settings nao existe."
}

# ----------------------------------------------------------- (D) diagnostico
Write-Host ''
Write-Host '================= DIAGNOSTICO =================' -ForegroundColor Cyan
Write-Host "  Android Gradle Plugin : $agpAtual"
Write-Host "  Kotlin Gradle Plugin  : $ktAtual"
Write-Host "  Gradle (wrapper)      : $(if ($gradleVer) { $gradleVer } else { 'nao detectado' })"
# `java -version` escreve na saida de ERRO. Com $ErrorActionPreference='Stop',
# o 2>&1 de um comando nativo vira ErrorRecord e o PowerShell aborta - por isso
# baixamos o nivel so aqui.
$javaVer = 'nao detectado'
try {
  $prevEA = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $raw = (& java -version 2>&1 | Out-String)
  $ErrorActionPreference = $prevEA
  $line = ($raw -split "`r?`n" | Where-Object { $_ -match 'version' } | Select-Object -First 1)
  if ($line) { $javaVer = $line.Trim() }
} catch {
  $ErrorActionPreference = 'Stop'
}
Write-Host "  Java                  : $javaVer"
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Rode agora:' -ForegroundColor Green
Write-Host '  flutter clean'
Write-Host '  flutter run --release'
Write-Host ''
Write-Host 'Se falhar de novo, me mande a saida deste script junto com o erro,' -ForegroundColor Yellow
Write-Host 'e tambem:  type android\settings.gradle.kts' -ForegroundColor Yellow
