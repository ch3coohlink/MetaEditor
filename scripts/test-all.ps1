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

function Start-TestBranch {
  param(
    [string]$Name,
    [string]$Command
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'pwsh'
  $startInfo.ArgumentList.Add('-NoLogo')
  $startInfo.ArgumentList.Add('-NoProfile')
  $startInfo.ArgumentList.Add('-ExecutionPolicy')
  $startInfo.ArgumentList.Add('Bypass')
  $startInfo.ArgumentList.Add('-Command')
  $startInfo.ArgumentList.Add($Command)
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
  $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
  $stderrTask = $proc.StandardError.ReadToEndAsync()
  [pscustomobject]@{
    Name = $Name
    Label = switch ($Name) {
      'moon' { 'core' }
      'native' { 'nati' }
      'browser' { 'brow' }
      default { $Name }
    }
    StartedAt = Get-Date
    Process = $proc
    StdoutTask = $stdoutTask
    StderrTask = $stderrTask
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

function Complete-TestBranch {
  param([object]$Branch)

  Invoke-TimedBlock "wait $($Branch.Label) exit" {
    $Branch.Process.WaitForExit()
  }
  $branchElapsed = (Get-Date) - $Branch.StartedAt
  Write-TimingLog "[timing] branch $($Branch.Label) wall took $(Format-Duration $branchElapsed)"
  $collectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $stdout = Get-BranchLines $Branch.StdoutTask
  $stderr = Get-BranchLines $Branch.StderrTask
  $collectStopwatch.Stop()
  Write-TimingLog "[timing] collect $($Branch.Label) logs took $(Format-Duration $collectStopwatch.Elapsed)"
  $lines = @($stdout + $stderr)
  foreach ($line in $lines) {
    if (![string]::IsNullOrWhiteSpace($line)) {
      Write-Host "[$($Branch.Label)] $line"
    }
  }
  $code = $Branch.Process.ExitCode
  Write-TimingLog "[timing] cleanup $($Branch.Label) logs took 00:00.000"
  if ($code -ne 0) {
    throw "$($Branch.Name) failed with exit code $code"
  }
}

$branchFlag = Get-BranchFlagText -DebugTiming:$DebugTiming
$browserTiming = if ($DebugTiming) { '--timing' } else { '' }
$moon = Start-TestBranch 'moon' 'moon test'
$browser = Start-TestBranch 'browser' "& '$PSScriptRoot\build-native.ps1' -Package service -TargetDir _build_browser $branchFlag; if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }; node scripts/test-browser.js --target-dir _build_browser --start --stop $browserTiming; exit `$LASTEXITCODE"
$native = Start-TestBranch 'native' "& '$PSScriptRoot\build-native.ps1' -Package service -Test -TestPackage service -TestFilter 'native:*' -TargetDir _build_test $branchFlag"

$branches = @($moon, $browser, $native)
$failed = @()
try {
  while ($branches.Count -gt 0) {
    $done = $null
    while ($null -eq $done) {
      $done = $branches | Where-Object { $_.Process.HasExited } | Select-Object -First 1
      if ($null -eq $done) {
        Start-Sleep -Milliseconds 50
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
