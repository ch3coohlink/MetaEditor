$ErrorActionPreference = 'Stop'

Write-Host '[test] moon test'
moon test

Write-Host '[test] native'
& "$PSScriptRoot\test-native.ps1"
