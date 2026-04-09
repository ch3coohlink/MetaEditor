function Initialize-Utf8Console {
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  [Console]::OutputEncoding = $utf8
  [Console]::InputEncoding = $utf8
  $OutputEncoding = $utf8
}

function Normalize-LogLine {
  param([string]$Message)

  if ([string]::IsNullOrEmpty($Message)) {
    return $Message
  }

  $normalized = $Message
  $cwd = (Get-Location).Path
  if (![string]::IsNullOrEmpty($cwd)) {
    $normalized = $normalized.Replace($cwd, '.')
  }

  $userProfile = [Environment]::GetFolderPath('UserProfile')
  if (![string]::IsNullOrEmpty($userProfile)) {
    $moonHome = Join-Path $userProfile '.moon'
    $normalized = $normalized.Replace($moonHome, '~\.moon')
  }

  return $normalized
}

function Format-Duration {
  param([TimeSpan]$Duration)

  '{0:mm\:ss\.fff}' -f $Duration
}

function Write-Log {
  param([string]$Message)

  if (!$Global:MetaEditorSilentLogs) {
    Write-Host (Normalize-LogLine $Message)
  }
}

function Write-TimingLog {
  param([string]$Message)

  if ($Global:MetaEditorDebugTimingLogs -and !$Global:MetaEditorSilentLogs) {
    Write-Host (Normalize-LogLine $Message)
  }
}

function Invoke-TimedBlock {
  param(
    [string]$TimingLabel,
    [scriptblock]$Action,
    [scriptblock]$OnSuccess = $null
  )

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $succeeded = $false
  try {
    & $Action
    $succeeded = $true
  }
  finally {
    $stopwatch.Stop()
    Write-TimingLog "[timing] $TimingLabel took $(Format-Duration $stopwatch.Elapsed)"
    if ($succeeded -and $OnSuccess) {
      & $OnSuccess
    }
  }
}

function Invoke-Step {
  param(
    [string]$Label,
    [scriptblock]$Action
  )

  Write-Log $Label
  & $Action
}
