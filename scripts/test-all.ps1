param(
  [switch]$DebugTiming
)

$ErrorActionPreference = 'Stop'
$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
. "$PSScriptRoot/common.ps1"
$Global:MetaEditorSilentLogs = $false
$Global:MetaEditorDebugTimingLogs = $DebugTiming

function Get-BranchFlagText {
  param([switch]$DebugTiming)

  if ($DebugTiming) { '-DebugTiming' } else { '' }
}

function Ensure-VsEnvironment {
  $needsImport = [string]::IsNullOrEmpty($env:METAEDITOR_VSDEV_IMPORTED) -or
    [string]::IsNullOrEmpty($env:VSCMD_VER) -or
    $env:CC -ne 'clang-cl'
  if (!$needsImport) {
    return
  }
  & (Join-Path $PSScriptRoot 'import-vs-env.ps1') -DebugTiming:$DebugTiming
}

function Start-BranchProcess {
  param(
    [string]$FileName,
    [string[]]$ArgumentList
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FileName
  foreach ($arg in $ArgumentList) {
    $startInfo.ArgumentList.Add($arg)
  }
  $startInfo.WorkingDirectory = (Get-Location).Path
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $startInfo
  [void]$proc.Start()
  [pscustomobject]@{
    Process = $proc
    StdoutTask = $proc.StandardOutput.ReadToEndAsync()
    StderrTask = $proc.StandardError.ReadToEndAsync()
    ExitTask = $proc.WaitForExitAsync()
  }
}

function Start-TestBranch {
  param(
    [string]$Name,
    [object[]]$Steps
  )

  $label = switch ($Name) {
    'moon' { 'core' }
    'native' { 'nati' }
    'browser' { 'brow' }
    default { $Name }
  }
  $first = Start-BranchProcess -FileName $Steps[0].FileName -ArgumentList $Steps[0].ArgumentList
  [pscustomobject]@{
    Name = $Name
    Label = $label
    StartedAt = Get-Date
    Steps = $Steps
    StepIndex = 0
    Process = $first.Process
    StdoutTask = $first.StdoutTask
    StderrTask = $first.StderrTask
    ExitTask = $first.ExitTask
    Lines = [System.Collections.Generic.List[string]]::new()
    ExitCode = $null
    Done = $false
  }
}

function Get-BranchLines {
  param([System.Threading.Tasks.Task[string]]$Task)

  if ($null -eq $Task) {
    return @()
  }
  $Task.Wait()
  if ([string]::IsNullOrEmpty($Task.Result)) {
    return @()
  }
  ($Task.Result -split "`r?`n")
}

function Collect-BranchProcessOutput {
  param([object]$Branch)

  $collectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $stdout = Get-BranchLines $Branch.StdoutTask
  $stderr = Get-BranchLines $Branch.StderrTask
  $collectStopwatch.Stop()
  Write-TimingLog "[timing] collect $($Branch.Label) logs took $(Format-Duration $collectStopwatch.Elapsed)"
  foreach ($line in @($stdout + $stderr)) {
    if (![string]::IsNullOrWhiteSpace($line)) {
      $Branch.Lines.Add($line)
    }
  }
  Write-TimingLog "[timing] cleanup $($Branch.Label) logs took 00:00.000"
}

function Advance-TestBranch {
  param([object]$Branch)

  if ($Branch.Done -or !$Branch.Process.HasExited) {
    return $false
  }

  Invoke-TimedBlock "wait $($Branch.Label) exit" {
    $Branch.Process.WaitForExit()
  }
  Collect-BranchProcessOutput $Branch
  $code = $Branch.Process.ExitCode
  if ($code -ne 0) {
    $Branch.ExitCode = $code
    $Branch.Done = $true
    return $true
  }

  if ($Branch.StepIndex + 1 -ge $Branch.Steps.Count) {
    $Branch.ExitCode = 0
    $Branch.Done = $true
    return $true
  }

  $Branch.StepIndex += 1
  $next = $Branch.Steps[$Branch.StepIndex]
  $started = Start-BranchProcess -FileName $next.FileName -ArgumentList $next.ArgumentList
  $Branch.Process = $started.Process
  $Branch.StdoutTask = $started.StdoutTask
  $Branch.StderrTask = $started.StderrTask
  $Branch.ExitTask = $started.ExitTask
  return $false
}

function Complete-TestBranch {
  param([object]$Branch)

  $branchElapsed = (Get-Date) - $Branch.StartedAt
  Write-TimingLog "[timing] branch $($Branch.Label) wall took $(Format-Duration $branchElapsed)"
  foreach ($line in $Branch.Lines) {
    Write-Host "[$($Branch.Label)] $line"
  }
  if ($Branch.ExitCode -ne 0) {
    throw "$($Branch.Name) failed with exit code $($Branch.ExitCode)"
  }
}

$branchFlag = Get-BranchFlagText -DebugTiming:$DebugTiming
$browserTiming = if ($DebugTiming) { '--timing' } else { '' }
Ensure-VsEnvironment
$moon = Start-TestBranch 'moon' @(
  [pscustomobject]@{
    FileName = 'moon'
    ArgumentList = @('test')
  }
)
$browserArgs = @(
  '-NoLogo',
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  (Join-Path $PSScriptRoot 'build-native.ps1'),
  '-Package',
  'service',
  '-TargetDir',
  '_build_browser'
)
if ($branchFlag) {
  $browserArgs += $branchFlag
}
$browserTestArgs = @(
  'scripts/test-browser.js',
  '--target-dir',
  '_build_browser',
  '--start',
  '--stop'
)
if ($browserTiming) {
  $browserTestArgs += $browserTiming
}
$browser = Start-TestBranch 'browser' @(
  [pscustomobject]@{
    FileName = 'pwsh'
    ArgumentList = $browserArgs
  },
  [pscustomobject]@{
    FileName = 'node'
    ArgumentList = $browserTestArgs
  }
)
$nativeArgs = @(
  '-NoLogo',
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  (Join-Path $PSScriptRoot 'build-native.ps1'),
  '-Package',
  'service',
  '-Test',
  '-TestPackage',
  'service',
  '-TestFilter',
  'native:*',
  '-TargetDir',
  '_build_test'
)
if ($branchFlag) {
  $nativeArgs += $branchFlag
}
$native = Start-TestBranch 'native' @(
  [pscustomobject]@{
    FileName = 'pwsh'
    ArgumentList = $nativeArgs
  }
)

$branches = @($moon, $browser, $native)
$failed = @()
try {
  while ($branches.Count -gt 0) {
    $done = $null
    while ($null -eq $done) {
      $active = @($branches | Where-Object { !$_.Done })
      $index = [System.Threading.Tasks.Task]::WaitAny(
        [System.Threading.Tasks.Task[]]($active | ForEach-Object { $_.ExitTask })
      )
      if ($index -lt 0) {
        throw 'wait for test branch exit failed'
      }
      if (Advance-TestBranch $active[$index]) {
        $done = $active[$index]
      }
    }
    try {
      Complete-TestBranch $done
    } catch {
      $failed += "$($done.Label)(exit $($done.Process.ExitCode))"
    }
    $branches = @($branches | Where-Object { $_.Process.Id -ne $done.Process.Id })
  }
} finally {
  $scriptStopwatch.Stop()
  $summary = "[test] total $(Format-Duration $scriptStopwatch.Elapsed)"
  if ($failed.Count -gt 0) {
    Write-Host "$summary failed: $($failed -join ', ')"
  } else {
    Write-Host "$summary ok"
  }
}
if ($failed.Count -gt 0) {
  exit 1
}
