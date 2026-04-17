param(
  [switch]$DebugTiming
)

$ErrorActionPreference = 'Stop'
$args = @('scripts/test-all.js')
if ($DebugTiming) {
  $args += '--debug-timing'
}
& node $args
exit $LASTEXITCODE
