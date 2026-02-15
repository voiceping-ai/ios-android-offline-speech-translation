param(
  [ValidateSet("Debug","Release")]
  [string]$Config = "Release",
  [ValidateSet("x64")]
  [string]$Arch = "x64",
  # Directory containing installed CMake packages for:
  # - ctranslate2 (ctranslate2Config.cmake)
  # - sentencepiece (sentencepieceConfig.cmake)
  [string]$CMakePrefixPath = "C:\\deps\\install"
)

$ErrorActionPreference = "Stop"

$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $thisDir "..\\..")
$buildDir = Join-Path $thisDir "build"

Write-Host "=== Building OfflineSpeechTranslation.NativeTranslation ($Config, $Arch) ===" -ForegroundColor Cyan
Write-Host "Source: $thisDir"
Write-Host "Build:  $buildDir"
Write-Host "Prefix: $CMakePrefixPath"

cmake -S $thisDir -B $buildDir -A $Arch `
  -DCMAKE_BUILD_TYPE=$Config `
  -DCMAKE_PREFIX_PATH="$CMakePrefixPath"

cmake --build $buildDir --config $Config

$dll = Get-ChildItem -Path $buildDir -Recurse -Filter "OfflineSpeechTranslation.NativeTranslation.dll" | Select-Object -First 1
if (-not $dll) {
  throw "Built DLL not found under $buildDir"
}

$destDir = Join-Path $repoRoot "libs\\runtimes\\win-x64"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item $dll.FullName $destDir -Force

Write-Host "Copied: $($dll.FullName) -> $destDir" -ForegroundColor Green
Write-Host "NOTE: If your build links dynamically, also copy any dependent DLLs (ctranslate2/sentencepiece runtime DLLs) into $destDir." -ForegroundColor Yellow

