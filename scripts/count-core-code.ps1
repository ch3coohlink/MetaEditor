param(
  [switch]$IncludeSupport
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

$targets = @(
  'app',
  'service',
  'src'
)

if ($IncludeSupport) {
  $targets += @(
    'scripts',
    'meta.ps1',
    'test-native.ps1',
    'index.html',
    'moon.mod.json'
  )
}

$extensions = @(
  '.mbt',
  '.js',
  '.mjs',
  '.c',
  '.ps1',
  '.sh',
  '.html',
  '.json',
  '.pkg'
)

$rows = @()

foreach ($target in $targets) {
  $path = Join-Path $root $target
  if (!(Test-Path $path)) {
    continue
  }

  $item = Get-Item $path
  if ($item.PSIsContainer) {
    $files = Get-ChildItem -Path $path -Recurse -File | Where-Object {
      $extensions -contains $_.Extension.ToLowerInvariant()
    }
  } else {
    $files = @($item)
  }

  foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
    $lineCount = (Get-Content -LiteralPath $file.FullName | Measure-Object -Line).Lines
    $scope = ($relative -split '/')[0]
    $rows += [pscustomobject]@{
      Scope = $scope
      File = $relative
      Ext = $file.Extension.ToLowerInvariant()
      Lines = $lineCount
    }
  }
}

$total = ($rows | Measure-Object -Property Lines -Sum).Sum
$scopeSummary = $rows |
  Group-Object Scope |
  ForEach-Object {
    [pscustomobject]@{
      Scope = $_.Name
      Files = $_.Count
      Lines = (($_.Group | Measure-Object -Property Lines -Sum).Sum)
    }
  } |
  Sort-Object Lines -Descending

$extSummary = $rows |
  Group-Object Ext |
  ForEach-Object {
    [pscustomobject]@{
      Ext = $_.Name
      Files = $_.Count
      Lines = (($_.Group | Measure-Object -Property Lines -Sum).Sum)
    }
  } |
  Sort-Object Lines -Descending

Write-Host "core_total=$total"
Write-Host ''
Write-Host 'by_scope'
$scopeSummary | Format-Table -AutoSize

Write-Host 'by_ext'
$extSummary | Format-Table -AutoSize
