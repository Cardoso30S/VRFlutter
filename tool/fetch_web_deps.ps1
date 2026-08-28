<#
.SYNOPSIS
  Baixa o three.js e os addons para assets\web\vendor\, deixando o app 100%
  offline (sem CDN em runtime).

.DESCRIPTION
  Todos os arquivos vao para a RAIZ de vendor\, sem subpastas: o Flutter nao
  inclui assets recursivamente, e a pasta plana ja e coberta pela unica linha
  `- assets/web/vendor/` do pubspec.yaml. O import map em index.html mapeia
  cada addon explicitamente para esses nomes, entao nenhum ajuste no pubspec
  e necessario.

  Sem este script o app ainda funciona: index.html detecta a ausencia da pasta
  e cai para o CDN jsDelivr - mas ai exige rede no celular no primeiro
  carregamento.

.PARAMETER WithDraco
  Tambem baixa o decodificador Draco (para modelos .glb comprimidos).

.PARAMETER ThreeVersion
  Versao do three.js. Padrao: 0.160.1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\fetch_web_deps.ps1
  powershell -ExecutionPolicy Bypass -File tool\fetch_web_deps.ps1 -WithDraco
#>

param(
  [switch]$WithDraco,
  [string]$ThreeVersion = '0.160.1'
)

$ErrorActionPreference = 'Stop'

$root   = Split-Path -Parent $PSScriptRoot
$vendor = Join-Path $root 'assets\web\vendor'
$base   = "https://cdn.jsdelivr.net/npm/three@$ThreeVersion"

New-Item -ItemType Directory -Force -Path $vendor | Out-Null

function Get-Dep([string]$Url, [string]$Name) {
  $dest = Join-Path $vendor $Name
  Write-Host "  -> $Name"
  # Invoke-WebRequest e lento por padrao por causa da barra de progresso.
  $prev = $ProgressPreference
  $ProgressPreference = 'SilentlyContinue'
  try {
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
  } finally {
    $ProgressPreference = $prev
  }
}

Write-Host "three.js $ThreeVersion -> assets\web\vendor\" -ForegroundColor Cyan
Get-Dep "$base/build/three.module.js"                'three.module.js'
Get-Dep "$base/examples/jsm/loaders/GLTFLoader.js"   'GLTFLoader.js'
Get-Dep "$base/examples/jsm/utils/SkeletonUtils.js"  'SkeletonUtils.js'

if ($WithDraco) {
  Write-Host "Draco:" -ForegroundColor Cyan
  Get-Dep "$base/examples/jsm/loaders/DRACOLoader.js" 'DRACOLoader.js'
  foreach ($f in @('draco_decoder.js', 'draco_decoder.wasm', 'draco_wasm_wrapper.js')) {
    Get-Dep "$base/examples/jsm/libs/draco/$f" $f
  }
}

$size = (Get-ChildItem $vendor -File | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host ("OK - {0:N1} KB em assets\web\vendor\ (nenhuma alteracao no pubspec.yaml necessaria)" -f ($size / 1KB)) -ForegroundColor Green
