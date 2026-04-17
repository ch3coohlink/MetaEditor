$ErrorActionPreference = 'Stop'

$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path -LiteralPath $vswhere)) {
  throw 'vswhere.exe not found'
}
$vs = & $vswhere -latest -products * `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
$vs = ($vs | Select-Object -First 1).Trim()
if (!$vs) {
  throw 'Visual Studio C++ tools not found'
}

$devCmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
if (!(Test-Path -LiteralPath $devCmd)) {
  throw 'VsDevCmd.bat not found'
}

$cmd = 'call "' + $devCmd + '" -arch=amd64 -host_arch=amd64 -no_logo && set'
$lines = & cmd.exe /d /s /c $cmd
if ($LASTEXITCODE -ne 0) {
  throw 'failed to import VS environment'
}

foreach ($line in $lines) {
  $idx = $line.IndexOf('=')
  if ($idx -le 0) {
    continue
  }
  $name = $line.Substring(0, $idx)
  $value = $line.Substring($idx + 1)
  Set-Item -Path "Env:$name" -Value $value
}

$env:METAEDITOR_VSDEV_IMPORTED = $vs
$env:CC = 'clang-cl'
