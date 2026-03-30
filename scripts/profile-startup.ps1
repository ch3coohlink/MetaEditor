$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"

$root = Split-Path -Parent $PSScriptRoot
$pkgPath = Join-Path $root 'service\moon.pkg.json'
$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-service-profile'
$profilePath = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-start-silent-profile.json.gz'
$tracePath = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-runtime-trace.log'
$symbolDir = Join-Path $root '_build\native\debug\build\service'
$symbolFlags = '/Z7'

function Reset-StateDir {
  if (!(Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
    return
  }

  Get-ChildItem -LiteralPath $stateDir -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Stop-ServiceIfPresent {
  $bin = Join-Path $root '_build\native\debug\build\service\service.exe'
  if (!(Test-Path $bin)) {
    return
  }

  try {
    & $bin --state-dir $stateDir stop | Out-Null
  }
  catch {
  }

  $stateFile = Join-Path $stateDir '.meta-editor-service.json'
  if (Test-Path $stateFile) {
    try {
      $info = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
      if ($info.pid) {
        Stop-Process -Id $info.pid -Force -ErrorAction SilentlyContinue
      }
    }
    catch {
    }
  }
}

function Enable-NativeSymbols {
  $raw = Get-Content -LiteralPath $pkgPath -Raw
  $json = $raw | ConvertFrom-Json -AsHashtable
  if (!$json.ContainsKey('link')) {
    $json['link'] = @{}
  }
  if (!$json['link'].ContainsKey('native')) {
    $json['link']['native'] = @{}
  }
  $json['link']['native']['cc-flags'] = $symbolFlags
  $json['link']['native']['stub-cc-flags'] = $symbolFlags
  $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $pkgPath
  return $raw
}

function Restore-PackageFile {
  param([string]$Raw)

  Set-Content -LiteralPath $pkgPath -Value $Raw
}

Invoke-TimedBlock 'profile startup' {
  $pkgRaw = Enable-NativeSymbols
  try {
    Reset-StateDir
    Stop-ServiceIfPresent
    if (Test-Path $profilePath) {
      Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $tracePath) {
      Remove-Item -LiteralPath $tracePath -Force -ErrorAction SilentlyContinue
    }

    Invoke-Step '[profile] build native service with /Z7' {
      & "$PSScriptRoot/build-native.ps1" -Package service
      if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
      }
    }

    $bin = Join-Path $root '_build\native\debug\build\service\service.exe'
    if (!(Test-Path $bin)) {
      throw 'service.exe not found after build'
    }

    Invoke-Step '[profile] record start --silent with samply' {
      samply record --save-only --no-open --unstable-presymbolicate `
        --symbol-dir $symbolDir -o $profilePath -- `
        $bin --state-dir $stateDir start 18120 --silent
      if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
      }
    }

    Write-Host "[profile] output: $profilePath"
    $symbolsPath = $profilePath -replace '\.json\.gz$', '.json.syms.json'
    Write-Host "[profile] symbols: $symbolsPath"
    Write-Host "[profile] trace: $tracePath"
  }
  finally {
    Restore-PackageFile $pkgRaw
    Stop-ServiceIfPresent
    Reset-StateDir
  }
}
