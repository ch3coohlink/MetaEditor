$ErrorActionPreference = 'Stop'

$name = if ($args.Count -gt 0) { $args[0] } else { '' }
if (!$name) {
  throw 'usage: ./run.ps1 <script> [args...]'
}

$script = Join-Path $PSScriptRoot 'scripts' "$name.js"
if (!(Test-Path -LiteralPath $script)) {
  throw "script not found: scripts/$name.js"
}

& node $script @($args | Select-Object -Skip 1)
exit $LASTEXITCODE
