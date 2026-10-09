#Requires -Version 7.2
[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$base = Join-Path $root ('artifacts/gate-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $base | Out-Null
$copy = Join-Path $base '干净 副本'
New-Item -ItemType Directory -Path $copy | Out-Null
# Copy only source/toolchain inputs. Never delete or modify the real project.
foreach ($item in @('project.godot','dependencies.lock.json','.editorconfig','.gitignore','.gitattributes','src','content','dev','tests','tools','addons','assets')) {
  Copy-Item -LiteralPath (Join-Path $root $item) -Destination $copy -Recurse
}
$results = [Collections.Generic.List[object]]::new()
function Run-Check([string]$Name, [bool]$ShouldPass) {
  $arguments = @('-NoProfile','-File',(Join-Path $copy 'tools/check.ps1'),'-ReportName',$Name)
  if ($GodotPath) { $arguments += @('-GodotPath',$GodotPath) }
  & pwsh @arguments
  $exitCode = $LASTEXITCODE
  $report = Get-Content -LiteralPath (Join-Path $copy "artifacts/check/$Name/summary.json") -Raw | ConvertFrom-Json
  $results.Add([ordered]@{case=$Name;exit_code=$exitCode;expected_pass=$ShouldPass;report=$report})
  if (($exitCode -eq 0) -ne $ShouldPass) { throw "Gate proof failed: $Name exit=$exitCode" }
}
try {
  Run-Check 'clean' $true
  $fault = Join-Path $copy 'tests/unit/test_gate_fault.gd'
  [IO.File]::WriteAllText($fault, "extends GutTest`nfunc test_deliberate_failure() -> void:`n`tassert_eq(1, 2)`n")
  Run-Check 'deliberate-failure' $false
  [IO.File]::WriteAllText($fault, "extends GutTest`nfunc test_required_skip() -> void:`n`tpending('deliberate gate proof')`n")
  Run-Check 'required-skip' $false
  [IO.File]::WriteAllText($fault, "extends GutTest`nfunc test_parse_failure(`n")
  Run-Check 'parse-failure' $false
  [IO.File]::WriteAllText($fault, "extends GutTest`n")
  # Zero-test proof uses only this isolated copy; preserve file contents to restore.
  $saved = @{}
  Get-ChildItem -LiteralPath (Join-Path $copy 'tests') -Filter 'test_*.gd' -Recurse | ForEach-Object {
    $saved[$_.FullName] = [IO.File]::ReadAllText($_.FullName)
    [IO.File]::WriteAllText($_.FullName, "extends GutTest`n")
  }
  Run-Check 'zero-tests' $false
  foreach ($path in $saved.Keys) { [IO.File]::WriteAllText($path, $saved[$path]) }
  Run-Check 'restored' $true
  $results | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $base 'gate-proof.json') -Encoding utf8
  Write-Host "GATE_PROOF PASS; evidence=$base"
  exit 0
} catch {
  $results | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $base 'gate-proof.json') -Encoding utf8
  Write-Error $_
  exit 1
}
