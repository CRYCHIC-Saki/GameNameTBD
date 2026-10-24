#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateSet('Validate', 'Status', 'Check', 'Init')]
  [string]$Action = 'Status',

  [ValidateSet('auto', 'building', 'supplier', 'town-economy', 'cook', 'economy', 'town', 'integrator')]
  [string]$Role = 'auto',

  [ValidatePattern('^[A-Za-z0-9.-]+$')]
  [string]$Phase = '4',

  [ValidatePattern('^[A-Za-z0-9.-]+$')]
  [string]$Wave = '0',

  [string]$BaseRef = '',
  [string]$TargetBranch = '',
  [string]$ConfigPath = '',
  [string]$WorktreeRoot = '',
  [switch]$IncludeWorkingTree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $ConfigPath) {
  $ConfigPath = Join-Path $root 'collaboration.config.json'
} elseif (-not [IO.Path]::IsPathRooted($ConfigPath)) {
  $ConfigPath = Join-Path $root $ConfigPath
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  throw "Collaboration config not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Invoke-Git([string[]]$GitArgs) {
  # Warnings are diagnostics, never changed-file names. Keep both streams separate.
  $errorPath = [IO.Path]::GetTempFileName()
  try {
    # Windows PowerShell 5.1 treats native stderr warnings as ErrorRecords.
    # The native exit code, checked below, determines command failure.
    $previousPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $output = @(& git -c core.quotepath=false -C $root @GitArgs 2> $errorPath)
      $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    $diagnostics = [IO.File]::ReadAllText($errorPath)
    if ($code -ne 0) {
      throw "git $($GitArgs -join ' ') failed:`n$($output -join [Environment]::NewLine)`n$diagnostics"
    }
    if ($diagnostics.Trim()) { Write-Warning $diagnostics.Trim() }
    return $output
  } finally {
    Remove-Item -LiteralPath $errorPath
  }
}

function Test-GitRef([string]$Ref) {
  & git -C $root rev-parse --verify --quiet "$Ref^{commit}" *> $null
  return $LASTEXITCODE -eq 0
}

function Expand-Template([string]$Template, [string]$RoleId = '') {
  $expanded = $Template.Replace('{phase}', $Phase)
  $expanded = $expanded.Replace('{wave}', $Wave)
  return $expanded.Replace('{role}', $RoleId)
}

function Normalize-RepoPath([string]$Path) {
  return $Path.Trim().Replace('\', '/').TrimStart('/')
}

function Test-PathPattern([string]$Path, [object[]]$Patterns) {
  foreach ($patternObject in $Patterns) {
    $pattern = [string]$patternObject
    if ($Path -like $pattern) {
      return $true
    }
  }
  return $false
}

function Get-Role([string]$RoleId) {
  return $config.roles | Where-Object { [string]$_.id -eq $RoleId } | Select-Object -First 1
}

function Get-ActiveRoles {
  if ([int]$config.schema -eq 1) { return @($config.roles) }
  foreach ($id in $config.active_roles) { Get-Role ([string]$id) }
}

function Get-CurrentBranch {
  if ($env:GITHUB_HEAD_REF) {
    return [string]$env:GITHUB_HEAD_REF
  }
  $branch = @(Invoke-Git @('branch', '--show-current'))
  if ($branch.Count -gt 0 -and [string]$branch[0]) {
    return [string]$branch[0]
  }
  return ''
}

function Resolve-Role([string]$RequestedRole, [string]$Branch) {
  if ($RequestedRole -ne 'auto') {
    return $RequestedRole
  }
  foreach ($roleConfig in $config.roles) {
    if ($Branch -like "work/$([string]$roleConfig.id)/*") {
      return [string]$roleConfig.id
    }
  }
  if ($Branch -like 'integration/*') {
    return 'integrator'
  }
  return ''
}

function Assert-BranchTopology([string]$ResolvedRole, [string]$Branch, [string]$Target) {
  if (-not $Target) {
    return
  }
  $normalizedTarget = $Target.Replace('refs/heads/', '').Replace('origin/', '')
  if ($ResolvedRole -eq 'integrator') {
    if ($Branch -notmatch '^integration/phase-[A-Za-z0-9.-]+-wave-[A-Za-z0-9.-]+$') {
      throw "Integrator branch must match integration/phase-<n>-wave-<n>: $Branch"
    }
    if ($normalizedTarget -ne 'main') {
      throw "Integration PR must target main, not '$normalizedTarget'"
    }
    Write-Host "PASS topology branch=$Branch target=$normalizedTarget"
    return
  }

  $rolePrefix = "work/$ResolvedRole/"
  if (-not $Branch.StartsWith($rolePrefix, [StringComparison]::Ordinal)) {
    throw "Role '$ResolvedRole' branch must start with ${rolePrefix}: $Branch"
  }
  $waveSuffix = $Branch.Substring($rolePrefix.Length)
  if ($waveSuffix -notmatch '^phase-[A-Za-z0-9.-]+-wave-[A-Za-z0-9.-]+$') {
    throw "Role branch must match work/$ResolvedRole/phase-<n>-wave-<n>: $Branch"
  }
  $expectedTarget = "integration/$waveSuffix"
  if ($normalizedTarget -ne $expectedTarget) {
    throw "Role PR '$Branch' must target '$expectedTarget', not '$normalizedTarget'"
  }
  Write-Host "PASS topology branch=$Branch target=$normalizedTarget"
}

function Assert-Config {
  if ([int]$config.schema -notin @(1, 2)) {
    throw "Unsupported collaboration schema: $($config.schema)"
  }
  $roles = @($config.roles)
  $expected = @('cook', 'economy', 'town')
  if ([int]$config.schema -eq 1 -and $roles.Count -ne 3) {
    throw "Expected exactly three roles, found $($roles.Count)"
  }
  $ids = @($roles | ForEach-Object { [string]$_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
    throw 'Role ids must be unique'
  }
  foreach ($id in $expected) {
    if ($id -notin $ids) {
      throw "Missing required role: $id"
    }
  }
  foreach ($roleConfig in $roles) {
    if ([string]$roleConfig.id -notmatch '^[a-z][a-z0-9-]*$') {
      throw "Invalid role id: $($roleConfig.id)"
    }
    if (-not [string]$roleConfig.name) {
      throw "Role $($roleConfig.id) has no display name"
    }
    if (@($roleConfig.owned_patterns).Count -eq 0) {
      throw "Role $($roleConfig.id) has no owned patterns"
    }
    if (@($roleConfig.required_suites).Count -eq 0) {
      throw "Role $($roleConfig.id) has no required suites"
    }
    $expanded = Expand-Template ([string]$roleConfig.branch_template) ([string]$roleConfig.id)
    if ($expanded -notlike "work/$([string]$roleConfig.id)/*") {
      throw "Invalid branch template for role $($roleConfig.id): $expanded"
    }
  }
  if (@($config.shared_patterns).Count -eq 0) {
    throw 'shared_patterns cannot be empty'
  }
  $integration = Expand-Template ([string]$config.integration_branch_template)
  if ($integration -notlike 'integration/*') {
    throw "Invalid integration branch template: $integration"
  }
  if ([int]$config.schema -eq 2) {
    $activeIds = @($config.active_roles)
    if ($activeIds.Count -ne 3 -or @($activeIds | Sort-Object -Unique).Count -ne 3) {
      throw 'This team requires exactly three distinct active_roles'
    }
    foreach ($id in $activeIds) {
      if ($id -notin $ids) { throw "Unknown active role: $id" }
    }
    $patterns = @{}
    foreach ($owner in @(Get-ActiveRoles)) {
      foreach ($pattern in $owner.owned_patterns) {
        if ($patterns.ContainsKey([string]$pattern)) { throw "Duplicate active ownership pattern: $pattern" }
        $patterns[[string]$pattern] = [string]$owner.id
      }
    }
  }
  Write-Host "VALID collaboration schema=$($config.schema) active=$(@(Get-ActiveRoles | ForEach-Object { $_.id }) -join ',')"
}

function Get-ChangedPaths([string]$AgainstRef, [bool]$WithWorkingTree) {
  if (-not (Test-GitRef $AgainstRef)) {
    throw "Base ref not found: $AgainstRef"
  }
  $mergeBase = [string](@(Invoke-Git @('merge-base', 'HEAD', $AgainstRef))[0])
  $paths = [Collections.Generic.List[string]]::new()
  foreach ($line in @(Invoke-Git @('diff', '--no-renames', '--name-only', '--diff-filter=ACDMT', "$mergeBase...HEAD"))) {
    if ([string]$line) {
      $paths.Add((Normalize-RepoPath ([string]$line)))
    }
  }
  if ($WithWorkingTree) {
    $workingCommands = [Collections.Generic.List[object]]::new()
    $workingCommands.Add([string[]]@('diff', '--no-renames', '--name-only', '--diff-filter=ACDMT'))
    $workingCommands.Add([string[]]@('diff', '--cached', '--no-renames', '--name-only', '--diff-filter=ACDMT'))
    $workingCommands.Add([string[]]@('ls-files', '--others', '--exclude-standard'))
    foreach ($command in $workingCommands) {
      foreach ($line in @(Invoke-Git ([string[]]$command))) {
        if ([string]$line) {
          $paths.Add((Normalize-RepoPath ([string]$line)))
        }
      }
    }
  }
  return @($paths | Sort-Object -Unique)
}

function Show-Status {
  $branch = Get-CurrentBranch
  $integration = Expand-Template ([string]$config.integration_branch_template)
  if (-not $WorktreeRoot) {
    $script:WorktreeRoot = [string]$config.default_worktree_root
  }
  if (-not [IO.Path]::IsPathRooted($WorktreeRoot)) {
    $script:WorktreeRoot = [IO.Path]::GetFullPath((Join-Path $root $WorktreeRoot))
  }
  Write-Host "CURRENT branch=$branch"
  Write-Host "INTEGRATION branch=$integration"
  Write-Host "WORKTREE_ROOT=$WorktreeRoot"
  foreach ($roleConfig in @(Get-ActiveRoles)) {
    $roleId = [string]$roleConfig.id
    $roleBranch = Expand-Template ([string]$roleConfig.branch_template) $roleId
    $rolePath = Join-Path $WorktreeRoot "phase-$Phase-wave-$Wave/$roleId"
    Write-Host "ROLE id=$roleId branch=$roleBranch path=$rolePath suites=$(@($roleConfig.required_suites) -join ',')"
  }
  Write-Host 'ACTIVE_WORKTREES'
  foreach ($line in @(Invoke-Git @('worktree', 'list'))) {
    Write-Host $line
  }
}

function Check-Ownership {
  $branch = Get-CurrentBranch
  $resolvedRole = Resolve-Role $Role $branch
  if (-not $resolvedRole) {
    if ($TargetBranch) { throw "Unmanaged PR branch '$branch'; use a work/<role>/phase-<n>-wave-<name> or integration branch" }
    Write-Host "SKIP ownership: branch '$branch' is not a managed collaboration branch; pass -Role explicitly to enforce locally"
    return
  }
  Assert-BranchTopology $resolvedRole $branch $TargetBranch
  if (-not $BaseRef) {
    if ($resolvedRole -eq 'integrator') {
      $script:BaseRef = 'main'
    } else {
      $script:BaseRef = Expand-Template ([string]$config.integration_branch_template)
    }
  }
  $changed = @(Get-ChangedPaths $BaseRef ([bool]$IncludeWorkingTree))
  Write-Host "CHECK role=$resolvedRole branch=$branch base=$BaseRef files=$($changed.Count)"
  if ($resolvedRole -eq 'integrator') {
    Write-Host 'PASS integrator may change shared files on the integration branch; human review still enforces glue-only scope'
    return
  }

  $roleConfig = Get-Role $resolvedRole
  if (-not $roleConfig) {
    throw "Unknown role: $resolvedRole"
  }
  $violations = [Collections.Generic.List[string]]::new()
  foreach ($path in $changed) {
    if (Test-PathPattern $path @($config.shared_patterns)) {
      $violations.Add("$path :: shared file; propose it in the handoff and let the wave integrator edit it")
      continue
    }
    if (-not (Test-PathPattern $path @($roleConfig.owned_patterns))) {
      $violations.Add("$path :: outside role '$resolvedRole' ownership")
    }
    $owners = @(Get-ActiveRoles | Where-Object { Test-PathPattern $path @($_.owned_patterns) })
    if ($owners.Count -gt 1) {
      $violations.Add("$path :: ambiguous active ownership; assign one writer before implementation")
    }
  }
  if ($violations.Count -gt 0) {
    Write-Host 'OWNERSHIP VIOLATIONS'
    foreach ($violation in $violations) {
      Write-Host " - $violation"
    }
    throw "Ownership check failed with $($violations.Count) violation(s)"
  }
  Write-Host "PASS ownership role=$resolvedRole changed=$($changed.Count) suites=$(@($roleConfig.required_suites) -join ',')"
}

function Add-CollaborationWorktree([string]$Branch, [string]$StartPoint, [string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    throw "Worktree path already exists: $Path"
  }
  if (-not (Test-GitRef $Branch)) {
    if ($PSCmdlet.ShouldProcess($Branch, "create branch from $StartPoint")) {
      [void](Invoke-Git @('branch', $Branch, $StartPoint))
    }
  }
  if ($PSCmdlet.ShouldProcess($Path, "add worktree for $Branch")) {
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [void](Invoke-Git @('worktree', 'add', $Path, $Branch))
  }
}

function Initialize-Wave {
  $dirty = @(Invoke-Git @('status', '--porcelain'))
  if ($dirty.Count -gt 0) {
    throw 'Init requires a clean committed baseline. Commit or set aside current work first; the tool never copies uncommitted files into worktrees.'
  }
  if (-not $BaseRef) {
    $script:BaseRef = 'main'
  }
  if (-not (Test-GitRef $BaseRef)) {
    throw "Base ref not found: $BaseRef"
  }
  if (-not $WorktreeRoot) {
    $script:WorktreeRoot = [string]$config.default_worktree_root
  }
  if (-not [IO.Path]::IsPathRooted($WorktreeRoot)) {
    $script:WorktreeRoot = [IO.Path]::GetFullPath((Join-Path $root $WorktreeRoot))
  }

  $waveRoot = Join-Path $WorktreeRoot "phase-$Phase-wave-$Wave"
  $integrationBranch = Expand-Template ([string]$config.integration_branch_template)
  Add-CollaborationWorktree $integrationBranch $BaseRef (Join-Path $waveRoot 'integration')
  foreach ($roleConfig in @(Get-ActiveRoles)) {
    $roleId = [string]$roleConfig.id
    $roleBranch = Expand-Template ([string]$roleConfig.branch_template) $roleId
    Add-CollaborationWorktree $roleBranch $integrationBranch (Join-Path $waveRoot $roleId)
  }
  Write-Host "READY phase=$Phase wave=$Wave integration=$integrationBranch root=$waveRoot"
  Write-Host 'No branch was pushed. Fill docs/collaboration/CURRENT_WAVE.md in the integration worktree before implementation.'
}

Assert-Config
switch ($Action) {
  'Validate' { break }
  'Status' { Show-Status; break }
  'Check' { Check-Ownership; break }
  'Init' { Initialize-Wave; break }
}
