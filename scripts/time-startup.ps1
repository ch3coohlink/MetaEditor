param(
  [int]$Port = 18120,
  [int]$Iterations = 1,
  [string]$StateDir = '',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root '_build\native\debug\build\service\service.exe'

if (!(Test-Path $bin) -or !$SkipBuild) {
  & (Join-Path $PSScriptRoot 'build-native.ps1') -Package service
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (!(Test-Path $bin)) {
  throw 'service.exe not found'
}

if ($StateDir -eq '') {
  $StateDir = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-startup-timing'
}

function Clear-StateDir {
  if (Test-Path $StateDir) {
    Get-ChildItem -LiteralPath $StateDir -Force -ErrorAction SilentlyContinue |
      ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
      }
  } else {
    New-Item -ItemType Directory -Path $StateDir | Out-Null
  }
}

function Stop-Service {
  try {
    & $bin --state-dir $StateDir stop *> $null
  } catch {
  }
}

$times = @()

for ($i = 1; $i -le $Iterations; $i++) {
  Clear-StateDir
  Stop-Service
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $output = & $bin --state-dir $StateDir start $Port --silent 2>&1
  $sw.Stop()
  $elapsed = [int][Math]::Round($sw.Elapsed.TotalMilliseconds)
  $times += $elapsed
  Write-Host "run=$i elapsed=${elapsed}ms"
  if ($output) {
    $output | ForEach-Object { Write-Host $_ }
  }
  Stop-Service
  Clear-StateDir
}

if ($times.Count -gt 1) {
  $min = ($times | Measure-Object -Minimum).Minimum
  $max = ($times | Measure-Object -Maximum).Maximum
  $avg = [int][Math]::Round((($times | Measure-Object -Average).Average))
  Write-Host "summary min=${min}ms avg=${avg}ms max=${max}ms"
}
