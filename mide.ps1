param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

if ($Args.Length -eq 0) {
  throw 'usage: .\moon-ide.ps1 <ide-subcommand> [args...]'
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$drive = $root.Substring(0, 1).ToLower()
$rest = $root.Substring(2) -replace '\\', '/'
$bashRoot = "/$drive$rest"
$git = Get-Command git.exe -ErrorAction SilentlyContinue
$bashCandidates = @()
if ($git) {
  $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
  $bashCandidates += (Join-Path $gitRoot 'bin\bash.exe')
}
$bashCandidates += 'C:\Program Files\Git\bin\bash.exe'
$bashCandidates += 'C:\Program Files\Git\usr\bin\bash.exe'
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (!$bash) {
  throw 'bash.exe not found, install Git for Windows first'
}

$bashArgs = $Args | ForEach-Object {
  "'" + ($_ -replace "'", "'\\''") + "'"
}
$cmd = "command -v moon >/dev/null || { echo 'moon not found in Git Bash PATH' >&2; exit 127; }; " +
  "cd '$bashRoot' && moon ide " + ($bashArgs -join ' ')

& $bash -lc $cmd
