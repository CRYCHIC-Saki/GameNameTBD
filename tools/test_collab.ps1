#Requires -Version 7.2
[CmdletBinding()]
param([string]$ShellPath = 'pwsh')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$evidence = Join-Path $root ('artifacts/collaboration-tests/' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $evidence '中文 空格工作区'
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'tools'))
Copy-Item -LiteralPath (Join-Path $root 'tools/collab.ps1') -Destination (Join-Path $fixture 'tools/collab.ps1')
$config = Get-Content -LiteralPath (Join-Path $root 'collaboration.config.json') -Raw | ConvertFrom-Json
$configText = $config | ConvertTo-Json -Depth 10
$configPath = Join-Path $fixture 'collaboration.config.json'
[IO.File]::WriteAllText($configPath, $configText)
$shellExe = (Get-Command $ShellPath -ErrorAction Stop).Source
$cases = [Collections.Generic.List[object]]::new()

function Invoke-FixtureGit([string[]]$Arguments) {
  & git -C $fixture @Arguments *> $null
  if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $($Arguments -join ' ')" }
}
function Write-Fixture([string]$Relative, [string]$Text) {
  $path = Join-Path $fixture $Relative
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
  [IO.File]::WriteAllText($path, $Text)
}
function Check([string]$Name, [string[]]$Arguments, [bool]$Pass, [string]$Pattern) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $shellExe
  $info.WorkingDirectory = $fixture
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  [void]$info.Environment.Remove('GITHUB_HEAD_REF')
  foreach ($arg in @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $fixture 'tools/collab.ps1')) + $Arguments) { $info.ArgumentList.Add($arg) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw "$Name timed out" }
  $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
  [IO.File]::WriteAllText((Join-Path $evidence ($Name + '.log')), $text)
  $ok = (($process.ExitCode -eq 0) -eq $Pass) -and ($text -match $Pattern)
  $cases.Add(@{name=$Name;passed=$ok;exit_code=$process.ExitCode;expected_success=$Pass})
  Write-Host "$Name passed=$ok exit=$($process.ExitCode)"
  if (-not $ok) { throw "$Name failed; see $evidence" }
}

try {
  Invoke-FixtureGit @('init','-q','-b','baseline')
  $paths = @('src/buildings/example.gd','src/buildings/special.gd','src/suppliers/example.gd','src/town_economy/example.gd','src/cooking/example.gd','src/app/main.gd','src/business/game_profile.gd','src/town/town_map.gd.uid')
  foreach ($path in $paths) { Write-Fixture $path "baseline`n" }
  Invoke-FixtureGit @('add','.')
  Invoke-FixtureGit @('-c','user.name=Collaboration test','-c','user.email=collab-test@example.invalid','commit','-qm','isolated baseline')
  Check 'schema2' @('-Action','Validate') $true 'schema=2 active=building,supplier,town-economy'
  Check 'status' @('-Action','Status','-Wave','test') $true 'ROLE id=town-economy'
  $checkArgs = @('-Action','Check','-BaseRef','baseline','-TargetBranch','integration/phase-4-wave-test','-IncludeWorkingTree')
  foreach ($entry in @(@('building','src/buildings/example.gd'),@('supplier','src/suppliers/example.gd'),@('town-economy','src/town_economy/example.gd'))) {
    $role = $entry[0]; $path = $entry[1]
    Invoke-FixtureGit @('switch','-qc',"work/$role/phase-4-wave-test")
    Write-Fixture $path "own change`n"
    Check ($role+'-own') $checkArgs $true "PASS ownership role=$role"
    Check ($role+'-wrong-target') @('-Action','Check','-BaseRef','baseline','-TargetBranch','main','-IncludeWorkingTree') $false 'must target'
    Write-Fixture $path "baseline`n"
    Write-Fixture 'src/app/main.gd' "shared change`n"
    Check ($role+'-shared') $checkArgs $false 'shared file'
    Write-Fixture 'src/app/main.gd' "baseline`n"
    Write-Fixture 'src/business/game_profile.gd' "save change`n"
    Check ($role+'-save') $checkArgs $false 'outside role'
    Write-Fixture 'src/business/game_profile.gd' "baseline`n"
  }
  Write-Fixture 'src/suppliers/example.gd' "foreign change`n"
  Check 'economy-cannot-edit-supplier' $checkArgs $false 'outside role'
  Write-Fixture 'src/suppliers/example.gd' "baseline`n"
  Invoke-FixtureGit @('switch','work/building/phase-4-wave-test')
  Write-Fixture 'src/town/town_map.gd.uid' "uid://example`n"
  Check 'uid-retained' $checkArgs $true 'PASS ownership role=building'
  Write-Fixture 'src/town/town_map.gd.uid' "baseline`n"
  $ambiguous = $configText | ConvertFrom-Json
  ($ambiguous.roles | Where-Object id -eq 'supplier').owned_patterns += 'src/buildings/special*'
  [IO.File]::WriteAllText((Join-Path $evidence 'ambiguous.json'), ($ambiguous | ConvertTo-Json -Depth 10))
  Write-Fixture 'src/buildings/special.gd' "overlap`n"
  Check 'overlapping-globs' ($checkArgs + @('-ConfigPath',(Join-Path $evidence 'ambiguous.json'))) $false 'ambiguous active ownership'
  Write-Fixture 'src/buildings/special.gd' "baseline`n"
  Invoke-FixtureGit @('switch','-qc','feature/unmanaged')
  Check 'unmanaged-pr-rejected' $checkArgs $false 'Unmanaged PR branch'
  Invoke-FixtureGit @('switch','-qc','integration/phase-4-wave-test')
  Write-Fixture 'src/app/main.gd' "integration glue`n"
  Check 'integrator-shared' @('-Action','Check','-BaseRef','baseline','-TargetBranch','main','-IncludeWorkingTree') $true 'PASS integrator'
  Write-Fixture 'src/app/main.gd' "baseline`n"
  Invoke-FixtureGit @('switch','-qc','work/cook/phase-4-wave-test')
  Write-Fixture 'src/cooking/example.gd' "legacy change`n"
  Check 'legacy-role' $checkArgs $true 'PASS ownership role=cook'
  Write-Fixture 'src/cooking/example.gd' "baseline`n"
  $legacy = $configText | ConvertFrom-Json
  $legacy.schema = 1
  $legacy.roles = @($legacy.roles | Where-Object id -in @('cook','economy','town'))
  $legacy.PSObject.Properties.Remove('active_roles')
  [IO.File]::WriteAllText((Join-Path $evidence 'legacy.json'), ($legacy | ConvertTo-Json -Depth 10))
  Check 'legacy-schema' @('-Action','Validate','-ConfigPath',(Join-Path $evidence 'legacy.json')) $true 'schema=1 active=cook,economy,town'
  Check 'init-preview' @('-Action','Init','-BaseRef','baseline','-Wave','preview','-WorktreeRoot',(Join-Path $evidence 'preview'),'-WhatIf') $true 'READY phase=4 wave=preview'
  $preview = [IO.File]::ReadAllText((Join-Path $evidence 'init-preview.log'))
  if ($preview -match 'work/(cook|economy|town)/' -or $preview -notmatch 'work/town-economy/' -or (Test-Path -LiteralPath (Join-Path $evidence 'preview'))) { throw 'Init preview created files or selected legacy roles' }
  if ($cases.Count -eq 0) { throw 'Zero tests' }
  @{status='PASS';executed=$cases.Count;passed=$cases.Count;failed=0;shell=$shellExe;cases=$cases} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json')
  Write-Host "COLLAB TEST PASS count=$($cases.Count) evidence=$evidence"
} catch {
  @{status='FAIL';executed=$cases.Count;cases=$cases;reason=$_.Exception.Message} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json')
  Write-Error $_ -ErrorAction Continue
  exit 1
}
