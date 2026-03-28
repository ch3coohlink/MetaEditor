function Format-Duration {
  param([TimeSpan]$Duration)

  '{0:mm\:ss\.fff}' -f $Duration
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
    Write-Host "[timing] $TimingLabel took $(Format-Duration $stopwatch.Elapsed)"
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

  Write-Host $Label
  & $Action
}
