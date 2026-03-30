$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\build-native.ps1" -Package service -Test -TestPackage service -TestFilter "native:*"
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& "$PSScriptRoot\test-service-lifecycle.ps1"
exit $LASTEXITCODE
