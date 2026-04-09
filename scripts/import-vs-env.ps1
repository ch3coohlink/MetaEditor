param(
  [switch]$DebugTiming,
  [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Global:MetaEditorSilentLogs = $Silent
$Global:MetaEditorDebugTimingLogs = $DebugTiming
. "$PSScriptRoot/common.ps1"
Initialize-Utf8Console

try {
  $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
  if (!(Test-Path $vswhere)) {
    throw 'vswhere.exe not found'
  }

  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (!$vs) {
    throw 'Visual Studio C++ tools not found'
  }

  $devShellModule = Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
  if (!(Test-Path $devShellModule)) {
    throw 'Microsoft.VisualStudio.DevShell.dll not found'
  }

  $llvm = Join-Path $vs 'VC\Tools\Llvm\x64\bin'
  if (!(Test-Path (Join-Path $llvm 'clang.exe'))) {
    throw 'clang.exe not found in Visual Studio LLVM tools'
  }

  $reuseVsEnv =
    $env:METAEDITOR_VSDEV_IMPORTED -eq $vs -and
    $env:VSCMD_VER -and
    ($env:PATH -split ';' | Where-Object { $_ -eq $llvm })

  if (!$reuseVsEnv) {
    Invoke-TimedBlock 'import VS environment' {
      if ($DebugTiming) {
        Write-Log "[native] import VS environment"
      }
      Import-Module $devShellModule -ErrorAction Stop
      Enter-VsDevShell -VsInstallPath $vs -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
      [Environment]::SetEnvironmentVariable('METAEDITOR_VSDEV_IMPORTED', $vs, 'Process')
    }
  }

  if (!($env:PATH -split ';' | Where-Object { $_ -eq $llvm })) {
    $env:PATH = "$llvm;$env:PATH"
  }

  $env:CC = 'clang-cl'
}
finally {
  $scriptStopwatch.Stop()
  Write-TimingLog "[timing] total $((Format-Duration $scriptStopwatch.Elapsed))"
}
