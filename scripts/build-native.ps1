param(
  [string]$Package = 'native_ws',
  [switch]$Test
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path $vswhere)) {
  throw 'vswhere.exe not found'
}

$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) {
  throw 'Visual Studio C++ tools not found'
}

$vsdev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
if (!(Test-Path $vsdev)) {
  throw 'VsDevCmd.bat not found'
}

$llvm = Join-Path $vs 'VC\Tools\Llvm\x64\bin'
if (!(Test-Path (Join-Path $llvm 'clang.exe'))) {
  throw 'clang.exe not found in Visual Studio LLVM tools'
}

Write-Host "[native] import VS environment"
$dump = cmd /d /s /c "call ""$vsdev"" -arch=x64 >nul && set"
if ($LASTEXITCODE -ne 0) {
  throw 'failed to import Visual Studio environment'
}

foreach ($line in $dump) {
  $idx = $line.IndexOf('=')
  if ($idx -le 0) {
    continue
  }
  $name = $line.Substring(0, $idx)
  $value = $line.Substring($idx + 1)
  [Environment]::SetEnvironmentVariable($name, $value, 'Process')
}

if (!($env:PATH -split ';' | Where-Object { $_ -eq $llvm })) {
  $env:PATH = "$llvm;$env:PATH"
}

$env:CC = 'clang-cl'

Set-Location $root

Write-Host "[native] clang version"
& clang --version
if ($LASTEXITCODE -ne 0) {
  throw 'clang check failed'
}

Write-Host "[native] moon build --target native $Package"
& moon build --target native $Package
if ($LASTEXITCODE -ne 0) {
  throw "native build failed with exit code $LASTEXITCODE"
}

if ($Test) {
  Write-Host "[native] moon test --target native $Package"
  & moon test --target native $Package
  if ($LASTEXITCODE -ne 0) {
    throw "native test failed with exit code $LASTEXITCODE"
  }
}
