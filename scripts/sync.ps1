param(
  [string]$OtherWorkspace = '../MetaEditor-2',
  [string]$Remote = 'origin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

function Fail {
  param([string]$Message)

  throw $Message
}

function Invoke-Git {
  param(
    [string]$Repo,
    [string[]]$GitArgs
  )

  & git -C $Repo @GitArgs
  if ($LASTEXITCODE -ne 0) {
    Fail "git $($GitArgs -join ' ') failed in $(Split-Path $Repo -Leaf)"
  }
}

function Get-GitOutput {
  param(
    [string]$Repo,
    [string[]]$GitArgs
  )

  $lines = & git -C $Repo @GitArgs
  if ($LASTEXITCODE -ne 0) {
    Fail "git $($GitArgs -join ' ') failed in $(Split-Path $Repo -Leaf)"
  }
  return @($lines)
}

function Get-GitLine {
  param(
    [string]$Repo,
    [string[]]$GitArgs
  )

  $lines = Get-GitOutput -Repo $Repo -GitArgs $GitArgs
  return ($lines -join "`n").Trim()
}

function Test-GitSuccess {
  param(
    [string]$Repo,
    [string[]]$GitArgs
  )

  & git -C $Repo @GitArgs *> $null
  return $LASTEXITCODE -eq 0
}

function Assert-Clean {
  param([string]$Repo)

  $status = Get-GitOutput -Repo $Repo -GitArgs @('status', '--porcelain')
  if ($status.Count -ne 0) {
    Fail "$(Split-Path $Repo -Leaf) has local changes"
  }
}

function Get-CurrentBranch {
  param([string]$Repo)

  $branch = Get-GitLine -Repo $Repo -GitArgs @('symbolic-ref', '--quiet', '--short', 'HEAD')
  if (!$branch) {
    Fail "$(Split-Path $Repo -Leaf) is not on a branch"
  }
  return $branch
}

function Assert-RemoteBranchReady {
  param(
    [string]$Repo,
    [string]$RemoteName,
    [string]$Branch
  )

  $remoteRef = "refs/remotes/$RemoteName/$Branch"
  if (!(Test-GitSuccess -Repo $Repo -GitArgs @('show-ref', '--verify', '--quiet', $remoteRef))) {
    Fail "$(Split-Path $Repo -Leaf) is missing $RemoteName/$Branch"
  }

  $counts = Get-GitLine -Repo $Repo -GitArgs @(
    'rev-list',
    '--left-right',
    '--count',
    "$Branch...$RemoteName/$Branch"
  )
  $parts = $counts -split '\s+'
  if ($parts.Length -ne 2) {
    Fail "failed to compare $Branch with $RemoteName/$Branch in $(Split-Path $Repo -Leaf)"
  }
  if ([int]$parts[1] -ne 0) {
    Fail "$(Split-Path $Repo -Leaf) is behind $RemoteName/$Branch"
  }
}

function Merge-Workspace {
  param(
    [string]$TargetRepo,
    [string]$SourceRepo,
    [string]$Branch
  )

  $sourceHead = Get-GitLine -Repo $SourceRepo -GitArgs @('rev-parse', 'HEAD')
  Write-Log "merge $(Split-Path $SourceRepo -Leaf) -> $(Split-Path $TargetRepo -Leaf)"
  Invoke-Git -Repo $TargetRepo -GitArgs @('fetch', $SourceRepo, $Branch)
  & git -C $TargetRepo merge '--no-ff' '--no-edit' $sourceHead
  if ($LASTEXITCODE -ne 0) {
    Write-Log "merge conflicted in $(Split-Path $TargetRepo -Leaf), stop here"
    exit $LASTEXITCODE
  }
}

$mainWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$otherWorkspacePath = Resolve-Path $OtherWorkspace -ErrorAction Stop
$otherWorkspace = $otherWorkspacePath.Path

if ($mainWorkspace -eq $otherWorkspace) {
  Fail 'the two workspaces must be different'
}

$mainBranch = Get-CurrentBranch $mainWorkspace
$otherBranch = Get-CurrentBranch $otherWorkspace

Assert-Clean $mainWorkspace
Assert-Clean $otherWorkspace

$mainRemoteUrl = Get-GitLine -Repo $mainWorkspace -GitArgs @('remote', 'get-url', $Remote)
$otherRemoteUrl = Get-GitLine -Repo $otherWorkspace -GitArgs @('remote', 'get-url', $Remote)
if ($mainRemoteUrl -ne $otherRemoteUrl) {
  Fail "remote $Remote differs between the two workspaces"
}

Invoke-Step "fetch $Remote" {
  Invoke-Git -Repo $mainWorkspace -GitArgs @('fetch', $Remote)
  Invoke-Git -Repo $otherWorkspace -GitArgs @('fetch', $Remote)
}

Invoke-Step "check remote state" {
  Assert-RemoteBranchReady $mainWorkspace $Remote $mainBranch
  Assert-RemoteBranchReady $otherWorkspace $Remote $otherBranch
}

Invoke-Step "merge both ways" {
  Merge-Workspace $mainWorkspace $otherWorkspace $otherBranch
  Merge-Workspace $otherWorkspace $mainWorkspace $mainBranch
}

Invoke-Step "push both" {
  Invoke-Git -Repo $mainWorkspace -GitArgs @('push', $Remote, $mainBranch)
  Invoke-Git -Repo $otherWorkspace -GitArgs @('push', $Remote, $otherBranch)
}
