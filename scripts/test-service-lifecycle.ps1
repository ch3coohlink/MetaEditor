$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
Write-Host "[trace] script started at $([Environment]::TickCount64)"

$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root '_build\native\debug\build\service\service.exe'
$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-service-test'
$startPort = 18120
$startBudgetMs = 2000
$stopBudgetMs = 1000
$stdoutLog = Join-Path $stateDir 'test-service-cli.out'
$stderrLog = Join-Path $stateDir 'test-service-cli.err'

function Remove-PathIfExists {
  param([string]$Path)

  if (Test-Path $Path) {
    Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue
  }
}

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

function Read-ServiceInfo {
  $stateFile = Join-Path $stateDir '.meta-editor-service.json'
  if (!(Test-Path $stateFile)) {
    throw 'expected service state file'
  }

  return Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
}

function Stop-ServiceProcessFromState {
  $stateFile = Join-Path $stateDir '.meta-editor-service.json'
  if (!(Test-Path $stateFile)) {
    return
  }

  try {
    $info = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($info.pid) {
      Stop-Process -Id $info.pid -Force -ErrorAction SilentlyContinue
    }
  }
  catch {
  }
}

function Read-CommandOutput {
  $stdout = if (Test-Path $stdoutLog) {
    Get-Content -LiteralPath $stdoutLog -Raw
  } else {
    ''
  }
  $stderr = if (Test-Path $stderrLog) {
    Get-Content -LiteralPath $stderrLog -Raw
  } else {
    ''
  }
  Remove-PathIfExists $stdoutLog
  Remove-PathIfExists $stderrLog
  return $stdout + $stderr
}

function Invoke-MetaCommand {
  param(
    [string[]]$CommandArgs,
    [int]$TimeoutMs
  )

  Remove-PathIfExists $stdoutLog
  Remove-PathIfExists $stderrLog
  $argList = @('--state-dir', $stateDir) + $CommandArgs

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process `
    -FilePath $bin `
    -ArgumentList $argList `
    -WorkingDirectory $root `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -NoNewWindow `
    -PassThru

  if (!$proc.WaitForExit($TimeoutMs)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    throw "meta command timed out: $($CommandArgs -join ' ')"
  }

  $sw.Stop()
  return @{
    ExitCode = $proc.ExitCode
    Output = Read-CommandOutput
    ElapsedMs = [int][Math]::Ceiling($sw.Elapsed.TotalMilliseconds)
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Label
  )

  if (!$Text.Contains($Expected)) {
    throw "$Label missing: $Expected`n$Text"
  }
}

function Assert-ExitCode {
  param(
    [int]$Actual,
    [int]$Expected,
    [string]$Label
  )

  if ($Actual -ne $Expected) {
    throw "$Label exit code mismatch: expected $Expected, got $Actual"
  }
}

function Assert-FastEnough {
  param(
    [int]$ElapsedMs,
    [int]$BudgetMs,
    [string]$Label
  )

  if ($ElapsedMs -gt $BudgetMs) {
    throw "$Label too slow: ${ElapsedMs}ms > ${BudgetMs}ms"
  }
}

function Wait-PageReady {
  param([int]$Port)

  $deadline = [DateTime]::UtcNow.AddMilliseconds(3000)
  while ([DateTime]::UtcNow -lt $deadline) {
    try {
      $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 1
      $body = $response.Content
      if (
        $response.StatusCode -eq 200 -and
        $body.Contains('<div id="app-info">Status: Initializing Bridge...</div>') -and
        $body.Contains('<script src="src/bridge.js"></script>')
      ) {
        return
      }
    }
    catch {
    }
    Start-Sleep -Milliseconds 50
  }

  throw "page not ready on port $Port"
}

function Write-StaleState {
  $stateFile = Join-Path $stateDir '.meta-editor-service.json'
  Set-Content -LiteralPath $stateFile -Value '{"pid":999999,"port":{"port":19199}}' -NoNewline
}

if (!(Test-Path $bin)) {
  & "$PSScriptRoot/build-native.ps1" -Package service
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

Invoke-TimedBlock 'service lifecycle script' {
  Reset-StateDir
  try {
    $null = Invoke-MetaCommand -CommandArgs @('stop') -TimeoutMs 3000
  }
  catch {
  }
  Stop-ServiceProcessFromState
  Reset-StateDir

  $idleStop = Invoke-MetaCommand -CommandArgs @('stop') -TimeoutMs 3000
  Assert-ExitCode $idleStop.ExitCode 0 'idle stop'
  Assert-Contains $idleStop.Output 'service is not running' 'idle stop'

  Write-StaleState

  $start = Invoke-MetaCommand -CommandArgs @('start', "$startPort", '--silent') -TimeoutMs 5000
  Write-Host "[lifecycle-script] start command: $($start.ElapsedMs)ms"
  Assert-ExitCode $start.ExitCode 0 'start'
  Assert-Contains $start.Output "started http://localhost:$startPort" 'start'
  Assert-FastEnough $start.ElapsedMs $startBudgetMs 'start'
  $startInfo = Read-ServiceInfo
  Wait-PageReady $startInfo.port

  $hostStop = Invoke-MetaCommand -CommandArgs @('host_stop_service') -TimeoutMs 3000
  Write-Host "[lifecycle-script] host stop service: $($hostStop.ElapsedMs)ms"
  Assert-ExitCode $hostStop.ExitCode 0 'host stop service'
  Assert-Contains $hostStop.Output 'host_stop_service' 'host stop service'
  Assert-FastEnough $hostStop.ElapsedMs $stopBudgetMs 'host stop service'

  $startAgain = Invoke-MetaCommand -CommandArgs @('start', "$startPort", '--silent') -TimeoutMs 5000
  Write-Host "[lifecycle-script] start again command: $($startAgain.ElapsedMs)ms"
  Assert-ExitCode $startAgain.ExitCode 0 'start again'
  Assert-Contains $startAgain.Output "started http://localhost:$startPort" 'start again'
  Assert-FastEnough $startAgain.ElapsedMs $startBudgetMs 'start again'
  $startAgainInfo = Read-ServiceInfo
  Wait-PageReady $startAgainInfo.port

  $restart = Invoke-MetaCommand -CommandArgs @('restart', "$startPort", '--silent') -TimeoutMs 5000
  Write-Host "[lifecycle-script] restart command: $($restart.ElapsedMs)ms"
  Assert-ExitCode $restart.ExitCode 0 'restart'
  Assert-Contains $restart.Output "restarted http://localhost:$startPort" 'restart'
  Assert-FastEnough $restart.ElapsedMs $startBudgetMs 'restart'
  $restartInfo = Read-ServiceInfo
  Wait-PageReady $restartInfo.port

  $stop = Invoke-MetaCommand -CommandArgs @('stop') -TimeoutMs 3000
  Write-Host "[lifecycle-script] stop command: $($stop.ElapsedMs)ms"
  Assert-ExitCode $stop.ExitCode 0 'stop'
  Assert-Contains $stop.Output 'stopped' 'stop'
  Assert-FastEnough $stop.ElapsedMs $stopBudgetMs 'stop'
} {
  Stop-ServiceProcessFromState
  Reset-StateDir
}
