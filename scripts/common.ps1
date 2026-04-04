function Format-Duration {
  param([TimeSpan]$Duration)

  '{0:mm\:ss\.fff}' -f $Duration
}

function Write-Log {
  param([string]$Message)

  if (!$Global:MetaEditorSilentLogs) {
    Write-Host $Message
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
    Write-Log "[timing] $TimingLabel took $(Format-Duration $stopwatch.Elapsed)"
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
