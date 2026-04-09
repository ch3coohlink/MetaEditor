param(
  [string]$Package = 'service',
  [string]$TargetDir = '_build',
  [switch]$Test,
  [string]$TestPackage = '',
  [string]$TestFile = '',
  [string]$TestFilter = '',
  [switch]$CleanupOnly,
  [string]$CleanupStageLabel = '',
  [switch]$DebugTiming,
  [switch]$BuildOnly,
  [switch]$SkipBuild,
  [switch]$SkipCleanup,
  [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$completedStages = [System.Collections.Generic.List[string]]::new()
$Global:MetaEditorSilentLogs = $Silent
$Global:MetaEditorDebugTimingLogs = $DebugTiming
. "$PSScriptRoot/common.ps1"

function Get-RemainingTimeoutMs {
  param(
    [System.Diagnostics.Stopwatch]$Stopwatch,
    [int]$BudgetMs
  )

  $remaining = $BudgetMs - [int][Math]::Ceiling($Stopwatch.Elapsed.TotalMilliseconds)
  if ($remaining -lt 1) {
    return 1
  }

  return $remaining
}

function Resolve-ExecutablePath {
  param([string]$Name)

  $command = Get-Command $Name -CommandType Application -ErrorAction Stop | Select-Object -First 1
  if (!$command -or !$command.Source) {
    throw "$Name not found in PATH"
  }

  return $command.Source
}

function Join-NativeArguments {
  param([string[]]$ArgumentList)

  if (!$ArgumentList -or $ArgumentList.Count -eq 0) {
    return ''
  }

  $escaped = foreach ($arg in $ArgumentList) {
    if ($arg -notmatch '[\s"]') {
      $arg
      continue
    }

    '"' + ($arg -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
  }

  return ($escaped -join ' ')
}

function Get-LogLines {
  param([string]$Text)

  if ([string]::IsNullOrEmpty($Text)) {
    return @()
  }

  return $Text -split "`r?`n"
}

function Should-DisplayNativeLine {
  param([string]$Line)

  if ([string]::IsNullOrWhiteSpace($Line)) {
    return $true
  }

  if ($Line -match '^[^\\/\s][^\\/:]*\.c$') {
    return $false
  }

  if ($Line -match '\.lib\b' -and $Line -match '\.exp\b') {
    return $false
  }

  if ($Line -match '"artifacts_path"\s*:') {
    return $false
  }

  return $true
}

function Stop-RunningNativeBinary {
  param(
    [string]$Root,
    [string]$Package,
    [string]$TargetDir
  )

  $binaryPath = Join-Path $Root "$TargetDir\native\debug\build\$Package\$Package.exe"
  if (!(Test-Path $binaryPath)) {
    return
  }

  $running = @()

  if ($Package -eq 'service') {
    $stateRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-service-test'
    $stateFile = Join-Path $stateRoot '.meta-editor-service.json'
    if (Test-Path $stateFile) {
      try {
        $state = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json)
        $rawPid = "$($state.pid)".Trim()
        if ($rawPid -match '^\d+$') {
          $proc = Get-Process -Id ([int]$rawPid) -ErrorAction Stop
          if ($proc.Path -eq $binaryPath) {
            $running = @($proc)
          }
        }
      } catch {
      }
    }
  }

  if ($running.Count -eq 0) {
    $byName = @(
      Get-Process -Name $Package -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Path -and $_.Path -eq $binaryPath
      }
    )
    if ($byName.Count -gt 0) {
      $running += $byName
    }
  }
  if ($running.Count -gt 1) {
    $running = @($running | Sort-Object Id -Unique)
  }

  if ($running.Count -eq 0) {
    return
  }

  Write-Log "[native] stop running $Package binary"
  foreach ($proc in $running) {
    Stop-ProcessTree -Id $proc.Id
  }
}

function Stop-ProcessTree {
  param([int]$Id)

  if ($Id -le 0) {
    return
  }

  if ($IsWindows) {
    & taskkill /PID $Id /T /F *> $null
    return
  }

  Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue
}

function Stop-StaleNativeBuildProcesses {
  param(
    [string]$Root,
    [string]$Package,
    [string]$TargetDir
  )

  $escapedRoot = [Regex]::Escape($Root)
  $escapedPackage = [Regex]::Escape($Package)
  $escapedTargetDir = [Regex]::Escape((Join-Path $Root $TargetDir))
  $stale = @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $cmd = $_.CommandLine
      if (!$cmd) {
        return $false
      }

      if ($_.Name -eq 'moon.exe') {
        return (
          ($cmd -match "(\s|^)build\s+--target\s+native\s+$escapedPackage(\s|$)" -or
            $cmd -match "(\s|^)test\s+--target\s+native\s+.*(\s|^)-p\s+$escapedPackage(\s|$)" -or
            $cmd -match "(\s|^)test\s+--target\s+native\s+$escapedPackage(\s|$)") -and
          $cmd -match "--target-dir\s+$escapedTargetDir(\s|$)"
        )
      }

      $_.Name -in @('moonc.exe', 'clang.exe', 'clang-cl.exe', 'link.exe', 'lld-link.exe') -and
      $cmd -match $escapedTargetDir
    }
  )

  if ($stale.Count -eq 0) {
    return
  }

  Write-Log "[native] stop stale native build processes"
  foreach ($proc in $stale) {
    Stop-ProcessTree -Id $proc.ProcessId
  }
}

function Clear-NativeServiceState {
  param([string]$Package)

  if ($Package -ne 'service') {
    return
  }

  $rootPath = Join-Path ([System.IO.Path]::GetTempPath()) 'metaeditor-service-test'
  $paths = @(
    (Join-Path $rootPath '.meta-editor-service.pid'),
    (Join-Path $rootPath '.meta-editor-service.json'),
    (Join-Path $rootPath 'metaeditor-service.stdout.log'),
    (Join-Path $rootPath 'metaeditor-service.stderr.log'),
    (Join-Path $rootPath 'test-service-cli.out'),
    (Join-Path $rootPath 'test-service-cli.err')
  )

  foreach ($path in $paths) {
    if (Test-Path $path) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-CleanupStep {
  param(
    [string]$Root,
    [string]$Package,
    [string]$TargetDir,
    [string]$StageLabel
  )

  if ($SkipCleanup) {
    Write-Log "[native] skip $StageLabel"
    return
  }

  Invoke-TimedBlock $StageLabel {
    Stop-StaleNativeBuildProcesses -Root $Root -Package $Package -TargetDir $TargetDir
    Stop-RunningNativeBinary -Root $Root -Package $Package -TargetDir $TargetDir
    Clear-NativeServiceState -Package $Package
  } {
    [void]$completedStages.Add($StageLabel)
  }
}

function Start-CleanupBranch {
  param(
    [string]$Package,
    [string]$TargetDir,
    [string]$StageLabel,
    [switch]$DebugTiming,
    [switch]$Silent
  )

  if ($SkipCleanup) {
    Write-Log "[native] skip $StageLabel"
    return $null
  }

  $stdout = Join-Path $env:TEMP "metaeditor-native-cleanup-stdout.log"
  $stderr = Join-Path $env:TEMP "metaeditor-native-cleanup-stderr.log"
  Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
  $args = @(
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $PSCommandPath,
    '-Package', $Package,
    '-TargetDir', $TargetDir,
    '-CleanupOnly',
    '-CleanupStageLabel', $StageLabel
  )
  if ($DebugTiming) {
    $args += '-DebugTiming'
  }
  if ($Silent) {
    $args += '-Silent'
  }
  $proc = Start-Process pwsh -ArgumentList (Join-NativeArguments $args) `
    -WorkingDirectory (Get-Location).Path `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -WindowStyle Hidden `
    -PassThru
  [pscustomobject]@{
    StageLabel = $StageLabel
    Process = $proc
    Stdout = $stdout
    Stderr = $stderr
  }
}

function Complete-CleanupBranch {
  param([object]$Branch)

  if ($null -eq $Branch) {
    return
  }

  $Branch.Process.WaitForExit()
  $stdout = if (Test-Path $Branch.Stdout) { (Get-Content -LiteralPath $Branch.Stdout -Raw) -split "`r?`n" } else { @() }
  $stderr = if (Test-Path $Branch.Stderr) { (Get-Content -LiteralPath $Branch.Stderr -Raw) -split "`r?`n" } else { @() }
  foreach ($line in @($stdout + $stderr)) {
    if (![string]::IsNullOrWhiteSpace($line)) {
      Write-Log $line
    }
  }
  $code = $Branch.Process.ExitCode
  Remove-Item -LiteralPath $Branch.Stdout, $Branch.Stderr -Force -ErrorAction SilentlyContinue
  if ($code -ne 0) {
    throw "$($Branch.StageLabel) failed with exit code $code"
  }
  [void]$completedStages.Add($Branch.StageLabel)
}

function Run-NativeStep {
  param(
    [string]$Label,
    [string]$StageLabel,
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [int]$TimeoutMs = 0,
    [switch]$QuietOnSuccess
  )

  Invoke-TimedBlock $StageLabel {
    if (!$QuietOnSuccess) {
      Write-Log $Label
    }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = (Get-Location).Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.Arguments = Join-NativeArguments $ArgumentList

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $exited = if ($TimeoutMs -gt 0) {
      $process.WaitForExit($TimeoutMs)
    } else {
      $process.WaitForExit([int]::MaxValue)
    }

    if (!$exited) {
      Stop-ProcessTree -Id $process.Id
      [void]$process.WaitForExit(200)
      [void]$stdoutTask.Wait(200)
      [void]$stderrTask.Wait(200)
      $timedOutOutput = @(
        @(Get-LogLines $stdoutTask.Result)
        @(Get-LogLines $stderrTask.Result)
      )
      foreach ($line in $timedOutOutput) {
        Write-Log $line
      }
      throw "$Label timed out after $TimeoutMs ms"
    }

    [void]$process.WaitForExit(200)
    [void]$stdoutTask.Wait(200)
    [void]$stderrTask.Wait(200)

    $exitCode = $process.ExitCode
    $output = @(
      @(Get-LogLines $stdoutTask.Result)
      @(Get-LogLines $stderrTask.Result)
    )

    $visibleOutput = if ($exitCode -eq 0) {
      @($output | Where-Object { Should-DisplayNativeLine $_ })
    } else {
      $output
    }

    if (!$QuietOnSuccess -or $exitCode -ne 0) {
      foreach ($line in $visibleOutput) {
        Write-Log $line
      }
    }

    if ($exitCode -ne 0) {
      Write-Log "$Label failed with exit code $exitCode"
      exit $exitCode
    }
  }
}

try {
  $buildTimeoutMs = 120000
  $testBuildTimeoutMs = 120000
  $testTimeoutMs = 5000
  $root = Split-Path -Parent $PSScriptRoot
  Set-Location $root
  if ($CleanupOnly) {
    Invoke-CleanupStep -Root $root -Package $Package -TargetDir $TargetDir -StageLabel $CleanupStageLabel
    return
  }

  $cleanupStageLabel = if ($Test) { 'cleanup before test' } else { 'cleanup before build' }
  $cleanupBranch = Start-CleanupBranch `
    -Package $Package `
    -TargetDir $TargetDir `
    -StageLabel $cleanupStageLabel `
    -DebugTiming:$DebugTiming `
    -Silent:$Silent
  $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
  if (!(Test-Path $vswhere)) {
    throw 'vswhere.exe not found'
  }

  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (!$vs) {
    throw 'Visual Studio C++ tools not found'
  }

  $vsdev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
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
    } {
      [void]$completedStages.Add('import VS environment')
    }
  }

  if (!($env:PATH -split ';' | Where-Object { $_ -eq $llvm })) {
    $env:PATH = "$llvm;$env:PATH"
  }

  $env:CC = 'clang-cl'
  if ($DebugTiming) {
    $env:METAEDITOR_DEBUG_TIMING = '1'
  } else {
    Remove-Item Env:METAEDITOR_DEBUG_TIMING -ErrorAction SilentlyContinue
  }

  Complete-CleanupBranch $cleanupBranch
  $moon = Resolve-ExecutablePath 'moon'
  $testArgs = if ($TestPackage) {
    $args = @('test', '--target', 'native', '-p', $TestPackage)
    if ($TestFile) {
      $args += @('--file', $TestFile)
    }
    if ($TestFilter) {
      $args += @('--filter', $TestFilter)
    }
    $args
  } else {
    $args = @('test', '--target', 'native', $Package)
    $args
  }

  if ($Test) {
    Run-NativeStep `
      -Label "[native] $($testArgs -join ' ') --build-only" `
      -StageLabel 'build native tests' `
      -FilePath $moon `
      -ArgumentList @($testArgs + @('--build-only', '--target-dir', $TargetDir)) `
      -TimeoutMs $testBuildTimeoutMs `
      -QuietOnSuccess

    if ($BuildOnly) {
      Write-Log '[native] skip run native tests'
    } else {
      Run-NativeStep `
        -Label "[native] $($testArgs -join ' ')" `
        -StageLabel 'run native tests' `
        -FilePath $moon `
        -ArgumentList @($testArgs + @('--target-dir', $TargetDir)) `
        -TimeoutMs $testTimeoutMs
    }
  } else {
    if ($SkipBuild) {
      Write-Log '[native] skip build native package'
    } else {
      Run-NativeStep `
        -Label "[native] moon build --target native $Package" `
        -StageLabel 'build native package' `
        -FilePath $moon `
        -ArgumentList @('build', '--target', 'native', $Package, '--target-dir', $TargetDir) `
        -TimeoutMs $buildTimeoutMs `
        -QuietOnSuccess
    }
  }
}
catch {
  if ($completedStages.Count -gt 0) {
    Write-Log "[native] completed stages: $($completedStages -join ', ')"
  }
  throw
}
finally {
  $scriptStopwatch.Stop()
  if (!$CleanupOnly) {
    Write-TimingLog "[timing] total $((Format-Duration $scriptStopwatch.Elapsed))"
  }
}
