$ErrorActionPreference = 'Stop'

Write-Host '[test] moon test'
moon test

Write-Host '[test] native'
& "$PSScriptRoot\test-native.ps1"

Write-Host '[test] browser'
npm run test-browser