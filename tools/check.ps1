#Requires -Version 7.2
[CmdletBinding()]
param(
  [string]$GodotPath = $env:GODOT_BIN,
  [ValidateSet('all','content','cooking','qte','platform','scoring','integration','business','service','research','profiles','game','title','movement','commerce','stock','progression','habitat')]
  [string]$Suite = 'all',
  [int]$TimeoutSeconds = 1800,
  [string]$ReportName = ''
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lock = Get-Content -LiteralPath (Join-Path $root 'dependencies.lock.json') -Raw | ConvertFrom-Json
if (-not $GodotPath) { $GodotPath = $lock.godot.local_path }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
if (-not $ReportName) { $ReportName = Get-Date -Format 'yyyyMMdd-HHmmss-fff' }
if ($ReportName -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid report name' }
$report = Join-Path $root "artifacts/check/$ReportName"
New-Item -ItemType Directory -Path $report -Force | Out-Null
$stages = [Collections.Generic.List[object]]::new()

function Invoke-Engine([string]$Stage, [string[]]$EngineArgs) {
  $log = Join-Path $report "$Stage.engine.log"
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $GodotPath
  $info.WorkingDirectory = $root
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  foreach ($arg in $EngineArgs) { $info.ArgumentList.Add($arg) }
  if ($Stage -ne 'version') {
    $info.ArgumentList.Add('--log-file')
    $info.ArgumentList.Add($log)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill($true)
    $process.WaitForExit()
    throw "$Stage TIMEOUT after $TimeoutSeconds seconds"
  }
  $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
  [IO.File]::WriteAllText((Join-Path $report "$Stage.console.log"), $output)
  $engineLog = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  $stages.Add([ordered]@{stage=$Stage; exit_code=$process.ExitCode; log="$Stage.console.log"})
  Write-Host "$Stage exit=$($process.ExitCode)"
  if ($process.ExitCode -ne 0 -or ($output + $engineLog) -match '(?m)^\s*(SCRIPT ERROR|ERROR):|Parse Error:|ObjectDB.*leaked') {
    Write-Host $output
    throw "$Stage failed; see $report"
  }
  return $output
}

try {
  & (Join-Path $PSScriptRoot 'build_ingredient_index.ps1') -Check
  $version = (Invoke-Engine 'version' @('--headless','--version')).Trim()
  if (-not $version.StartsWith($lock.godot.release + '.')) { throw "Engine version mismatch: $version" }
  if ([IO.Path]::GetFullPath($GodotPath) -eq [IO.Path]::GetFullPath($lock.godot.local_path)) {
    if ($version -ne $lock.godot.local_version) { throw "Local engine build changed: $version" }
    $hash = (Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $lock.godot.local_sha256) { throw 'Local engine binary changed' }
  }
  $plugin = Get-Content -LiteralPath (Join-Path $root 'addons/gut/plugin.cfg') -Raw
  if ($plugin -notmatch ('version="' + [regex]::Escape($lock.gut.version) + '"')) { throw 'GUT version mismatch' }

  $testMap = @{
    habitat = @('tests/integration/test_habitat.gd')
    progression = @('tests/unit/test_shop_progression.gd','tests/integration/test_level_progression.gd')
    stock = @('tests/unit/test_shop_stock.gd','tests/unit/test_season_hold.gd')
    commerce = @('tests/unit/test_town_economy_contracts.gd','tests/unit/test_town_economy_rules.gd','tests/unit/test_town_economy_society.gd','tests/integration/test_town_economy_integration.gd')
    movement = @('tests/integration/test_town_motion.gd','tests/integration/test_restaurant_world.gd','tests/unit/test_restaurant_layout.gd')
    title = @('tests/integration/test_title_entry.gd','tests/unit/test_economy_ingredients.gd')
    game = @('tests/integration/test_game_shell.gd')
    profiles = @('tests/unit/test_shop_profiles.gd')
    research = @('tests/unit/test_research_rules.gd','tests/integration/test_kitchen_research.gd')
    business = @('tests/unit/test_shop_session.gd','tests/unit/test_shop_store.gd','tests/unit/test_kitchen_freedom.gd')
    service = @('tests/integration/test_shop_application.gd')
    content = @('tests/unit/test_content.gd','tests/unit/test_recipe_content.gd','tests/unit/test_full_catalog.gd')
    cooking = @('tests/unit/test_session.gd','tests/unit/test_cooking_prototype.gd','tests/unit/test_full_cooking.gd','tests/unit/test_pc_cooking.gd')
    qte = @('tests/unit/test_time_qte.gd','tests/unit/test_cooking_qte.gd','tests/unit/test_full_qte.gd','tests/unit/test_pc_operations.gd','tests/unit/test_document_operations.gd','tests/unit/test_recipe_performance.gd','tests/unit/test_season_hold.gd')
    platform = @('tests/unit/test_storage_scoring.gd','tests/unit/test_full_storage_scoring.gd')
    scoring = @('tests/unit/test_customer_scoring.gd','tests/unit/test_full_storage_scoring.gd')
    integration = @('tests/integration/test_application.gd','tests/integration/test_cooking_application.gd','tests/integration/test_kitchen_world.gd','tests/integration/test_cooking_action_view.gd','tests/integration/test_full_kitchen.gd','tests/integration/test_pc_kitchen.gd','tests/integration/test_guided_kitchen.gd','tests/integration/test_shop_application.gd')
  }
  $files = if ($Suite -eq 'all') {
    @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter 'test_*.gd' -File -Recurse | ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\','/') })
  } else { @($testMap[$Suite]) }
  $discovered = 0
  foreach ($file in $files) {
    $text = Get-Content -LiteralPath (Join-Path $root $file) -Raw
    $discovered += [regex]::Matches($text, '(?m)^func test_[A-Za-z0-9_]+\(').Count
  }
  if ($discovered -eq 0) { throw 'ZERO_TESTS: no required tests discovered' }
  [void](Invoke-Engine 'import' @('--headless','--path',$root,'--editor','--import','--quit'))
  [void](Invoke-Engine 'load' @('--headless','--path',$root,'--script','res://tools/load_check.gd'))
  $testPaths = ($files | ForEach-Object { 'res://' + $_ }) -join ','
  $junit = Join-Path $report 'junit.xml'
  $testArgs = @('--headless','--path',$root,'--script','res://addons/gut/gut_cmdln.gd',
    "-gtest=$testPaths",'-gexit',"-gjunit_xml_file=$junit")
  [void](Invoke-Engine 'tests' $testArgs)
  if (-not (Test-Path -LiteralPath $junit)) { throw 'MISSING_TEST_REPORT' }
  [xml]$xml = Get-Content -LiteralPath $junit -Raw
  $executed = [int]$xml.testsuites.tests
  $failures = [int]$xml.testsuites.failures
  $skipped = @($xml.SelectNodes('//skipped')).Count
  $errors = @($xml.SelectNodes('//error')).Count
  if ($executed -ne $discovered -or $executed -eq 0 -or $failures -gt 0 -or $skipped -gt 0 -or $errors -gt 0) {
    throw "TEST_GATE: discovered=$discovered executed=$executed failures=$failures skipped=$skipped errors=$errors"
  }
  $summary = [ordered]@{status='PASS';engine=$version;suite=$Suite;discovered=$discovered;executed=$executed;passed=$executed;failed=$failures;skipped=$skipped;exit_code=0;stages=$stages}
  $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $report 'summary.json') -Encoding utf8
  Write-Host "PASS discovered=$discovered executed=$executed failed=0 skipped=0 exit=0"
  Write-Host "REPORT=$report"
  exit 0
} catch {
  [ordered]@{status='FAIL';exit_code=1;reason=$_.Exception.Message;stages=$stages} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $report 'summary.json') -Encoding utf8
  Write-Host "FAIL $($_.Exception.Message)"
  Write-Host "REPORT=$report"
  exit 1
}
