param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$bin = Join-Path $root '_build\native\debug\build\service\service.exe'

if (!(Test-Path $bin)) {
  & (Join-Path $root 'scripts\build-native.ps1') -Package service
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

& $bin @Args
exit $LASTEXITCODE
