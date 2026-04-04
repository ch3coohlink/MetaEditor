param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$MetaArgs
)

$root = $PSScriptRoot
& (Join-Path $root 'scripts\build-native.ps1') -Package service -Silent
$bin = Join-Path $root '_build\native\debug\build\service\service.exe'
& $bin @MetaArgs
exit $LASTEXITCODE
