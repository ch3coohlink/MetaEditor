$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot 'import-vs-env.js'
$lines = & node $script
if ($LASTEXITCODE -ne 0) {
  throw 'failed to generate VS environment script'
}
foreach ($line in $lines) {
  Invoke-Expression $line
}
