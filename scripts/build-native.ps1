param(
  [string]$Package = 'service',
  [switch]$Test,
  [string]$TestPackage = '',
  [string]$TestFile = '',
  [string]$TestFilter = ''
)

$ErrorActionPreference = 'Stop'
$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$completedStages = [System.Collections.Generic.List[string]]::new()

function Format-Duration {
  param([TimeSpan]$Duration)

  '{0:mm\:ss\.fff}' -f $Duration
}

function Invoke-TimedBlock {
  param(
    [string]$TimingLabel,
    [scriptblock]$Action
  )

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $succeeded = $false
  try {
    & $Action
    $succeeded = $true
  }
  finally {
    $stopwatch.Stop()
    Write-Host "[timing] $TimingLabel took $(Format-Duration $stopwatch.Elapsed)"
    if ($succeeded) {
      [void]$completedStages.Add($TimingLabel)
    }
  }
}

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

  return $true
}

function Stop-RunningNativeBinary {
  param(
    [string]$Root,
    [string]$Package
  )

  $binaryPath = Join-Path $Root "_build\native\debug\build\$Package\$Package.exe"
  if (!(Test-Path $binaryPath)) {
    return
  }

  $running = @()

  if ($Package -eq 'service') {
    $pidFile = Join-Path ([System.IO.Path]::GetTempPath()) '.meta-editor-service.pid'
    if (Test-Path $pidFile) {
      $rawPid = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
      if ($rawPid -match '^\d+$') {
        try {
          $proc = Get-Process -Id ([int]$rawPid) -ErrorAction Stop
          if ($proc.Path -eq $binaryPath) {
            $running = @($proc)
          }
        }
        catch {
        }
      }
    }
  }

  if ($running.Count -eq 0) {
    $running = @(
      Get-Process -Name $Package -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $binaryPath }
    )
  }

  if ($running.Count -eq 0) {
    return
  }

  Write-Host "[native] stop running $Package binary"
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
    [string]$Package
  )

  $escapedRoot = [Regex]::Escape($Root)
  $escapedPackage = [Regex]::Escape($Package)
  $stale = @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $cmd = $_.CommandLine
      if (!$cmd) {
        return $false
      }

      if ($_.Name -eq 'moon.exe') {
        return $cmd -match "(\s|^)build\s+--target\s+native\s+$escapedPackage(\s|$)" -or
          $cmd -match "(\s|^)test\s+--target\s+native\s+$escapedPackage(\s|$)"
      }

      $_.Name -in @('moonc.exe', 'clang.exe', 'clang-cl.exe', 'link.exe', 'lld-link.exe') -and
      $cmd -match $escapedRoot
    }
  )

  if ($stale.Count -eq 0) {
    return
  }

  Write-Host "[native] stop stale native build processes"
  foreach ($proc in $stale) {
    Stop-ProcessTree -Id $proc.ProcessId
  }
}

function Clear-NativeServiceState {
  param([string]$Package)

  if ($Package -ne 'service') {
    return
  }

  $tempRoot = [System.IO.Path]::GetTempPath()
  $paths = @(
    (Join-Path $tempRoot '.meta-editor-service.pid'),
    (Join-Path $tempRoot '.meta-editor-service.json'),
    (Join-Path $tempRoot 'metaeditor-service.stdout.log'),
    (Join-Path $tempRoot 'metaeditor-service.stderr.log')
  )

  foreach ($path in $paths) {
    if (Test-Path $path) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
  }
}

function Run-NativeStep {
  param(
    [string]$Label,
    [string]$StageLabel,
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [int]$TimeoutMs = 0
  )

  Invoke-TimedBlock $StageLabel {
    Write-Host $Label
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

    foreach ($line in $visibleOutput) {
      Write-Host $line
    }

    if ($exitCode -ne 0) {
      Write-Host "$Label failed with exit code $exitCode"
      exit $exitCode
    }
  }
}

try {
  $buildTimeoutMs = 5000
  $testBuildTimeoutMs = 5000
  $testTimeoutMs = 3000
  $root = Split-Path -Parent $PSScriptRoot
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
      Write-Host "[native] import VS environment"
      Import-Module $devShellModule -ErrorAction Stop
      Enter-VsDevShell -VsInstallPath $vs -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
      [Environment]::SetEnvironmentVariable('METAEDITOR_VSDEV_IMPORTED', $vs, 'Process')
    }
  }

  if (!($env:PATH -split ';' | Where-Object { $_ -eq $llvm })) {
    $env:PATH = "$llvm;$env:PATH"
  }

  $env:CC = 'clang-cl'

  Set-Location $root
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
    @('test', '--target', 'native', $Package)
  }

  if ($Test) {
    Invoke-TimedBlock 'cleanup before build' {
      Stop-StaleNativeBuildProcesses -Root $root -Package $Package
      Stop-RunningNativeBinary -Root $root -Package $Package
      Clear-NativeServiceState -Package $Package
    }

    if (!$TestPackage) {
      Run-NativeStep `
        -Label "[native] moon build --target native $Package" `
        -StageLabel 'build native package' `
        -FilePath $moon `
        -ArgumentList @('build', '--target', 'native', $Package) `
        -TimeoutMs $buildTimeoutMs
    }

    Invoke-TimedBlock 'cleanup before test' {
      Stop-StaleNativeBuildProcesses -Root $root -Package $Package
      Stop-RunningNativeBinary -Root $root -Package $Package
      Clear-NativeServiceState -Package $Package
    }

    Run-NativeStep `
      -Label "[native] $($testArgs -join ' ') --build-only" `
      -StageLabel 'build native tests' `
      -FilePath $moon `
      -ArgumentList @($testArgs + @('--build-only')) `
      -TimeoutMs $testBuildTimeoutMs

    Run-NativeStep `
      -Label "[native] $($testArgs -join ' ')" `
      -StageLabel 'run native tests' `
      -FilePath $moon `
      -ArgumentList $testArgs `
      -TimeoutMs $testTimeoutMs
  } else {
    Invoke-TimedBlock 'cleanup before build' {
      Stop-StaleNativeBuildProcesses -Root $root -Package $Package
      Stop-RunningNativeBinary -Root $root -Package $Package
      Clear-NativeServiceState -Package $Package
    }

    Run-NativeStep `
      -Label "[native] moon build --target native $Package" `
      -StageLabel 'build native package' `
      -FilePath $moon `
      -ArgumentList @('build', '--target', 'native', $Package) `
      -TimeoutMs $buildTimeoutMs
  }
}
catch {
  if ($completedStages.Count -gt 0) {
    Write-Host "[native] completed stages: $($completedStages -join ', ')"
  }
  throw
}
finally {
  $scriptStopwatch.Stop()
  Write-Host "[timing] total $((Format-Duration $scriptStopwatch.Elapsed))"
}
