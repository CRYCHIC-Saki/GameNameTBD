#Requires -Version 7.2
[CmdletBinding()]
param(
  [string]$GodotPath = $env:GODOT_BIN,
  [ValidateSet('condiment-rules','materials','materials-regression','supplier-release','supplier-lines','supplier-compat','sync-current','sync-remainder','sync-migration','construction-regression','construction','console','management','management-regression','pull-core','pull-scenes','regions','travel-core','travel','branch-core','branches','seated-art','restaurant-feedback','diners','decoration','all','content','cooking','qte','platform','scoring','integration','business','service','research','profiles','game','title','movement','commerce','stock','progression','habitat','protagonist','locomotion','story','characters','town-renewal','town-polish','residential','visual-unity','story-expansion','arrival-coast','story-fixes','homecoming')]
  [string]$Suite = 'all',
  [int]$TimeoutSeconds = 1800,
  [ValidateRange(1,16)][int]$ShardCount = 1,
  [ValidateRange(0,15)][int]$ShardIndex = 0,
  [string]$ReportName = ''
)
$ErrorActionPreference = 'Stop'
if ($ShardIndex -ge $ShardCount) { throw 'ShardIndex must be less than ShardCount' }
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
    'condiment-rules' = @('tests/unit/test_shop_profiles.gd','tests/unit/test_supplier_network.gd','tests/unit/test_season_hold.gd','tests/unit/test_shop_stock.gd','tests/unit/test_supply_lines.gd','tests/integration/test_supply_lines.gd')
    'materials' = @('tests/unit/test_regional_materials.gd','tests/integration/test_regional_materials.gd')
    'materials-regression' = @('tests/unit/test_shop_profiles.gd','tests/unit/test_supplier_network.gd','tests/unit/test_season_hold.gd','tests/unit/test_shop_stock.gd','tests/integration/test_shop_application.gd')
    'supplier-release' = @('tests/unit/test_supply_lines.gd','tests/integration/test_supply_lines.gd','tests/unit/test_supplier_network.gd','tests/unit/test_game_hud.gd','tests/integration/test_management_system.gd','tests/integration/test_checkpoint_save.gd','tests/unit/test_branch_construction.gd','tests/integration/test_store_management.gd')
    'supplier-lines' = @('tests/unit/test_supply_lines.gd','tests/integration/test_supply_lines.gd')
    'supplier-compat' = @('tests/unit/test_supplier_network.gd','tests/unit/test_game_hud.gd','tests/integration/test_management_system.gd','tests/integration/test_checkpoint_save.gd','tests/unit/test_branch_construction.gd')
    'sync-migration' = @('tests/unit/test_town_renewal.gd','tests/integration/test_town_renewal_world.gd','tests/unit/test_region_migration.gd')
    'sync-remainder' = @('tests/integration/test_guided_kitchen.gd','tests/integration/test_story_kitchen.gd','tests/integration/test_town_motion.gd','tests/integration/test_town_renewal_world.gd','tests/integration/test_world_travel.gd') + @(Get-ChildItem -LiteralPath (Join-Path $root 'tests/unit') -Filter 'test_*.gd' -File | ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\','/') })
    'sync-current' = @('tests/integration/test_pull_current.gd','tests/integration/test_kitchen_world.gd','tests/integration/test_restaurant_world.gd','tests/integration/test_pull_merge.gd','tests/unit/test_shop_stock.gd','tests/unit/test_shop_profiles.gd','tests/unit/test_supplier_network.gd','tests/unit/test_branch_construction.gd','tests/integration/test_branch_visit.gd')
    'management-regression' = @('tests/unit/test_shop_profiles.gd','tests/integration/test_checkpoint_save.gd','tests/integration/test_level_progression.gd','tests/integration/test_game_shell.gd','tests/integration/test_branch_panel.gd','tests/integration/test_world_travel.gd','tests/integration/test_diner_flow.gd')
    management = @('tests/unit/test_employee_roster.gd','tests/unit/test_supplier_network.gd','tests/unit/test_game_hud.gd','tests/integration/test_management_system.gd')
    'pull-core' = @('tests/unit/test_restaurant_crew.gd','tests/unit/test_phase4_branch.gd','tests/unit/test_restaurant_layout.gd','tests/unit/test_town_polish.gd','tests/unit/test_research_rules.gd','tests/unit/test_regional_layout.gd','tests/unit/test_region_migration.gd','tests/unit/test_player_branches.gd','tests/unit/test_shop_profiles.gd')
    'pull-scenes' = @('tests/integration/test_pull_merge.gd','tests/integration/test_restaurant_world.gd','tests/integration/test_diner_flow.gd','tests/integration/test_restaurant_feedback.gd','tests/integration/test_world_travel.gd','tests/integration/test_checkpoint_save.gd','tests/integration/test_branch_panel.gd')
    'regions' = @('tests/unit/test_regional_layout.gd','tests/unit/test_region_migration.gd')
    'travel-core' = @('tests/integration/test_world_travel.gd')
    travel = @('tests/unit/test_regional_layout.gd','tests/unit/test_region_migration.gd','tests/integration/test_world_travel.gd','tests/integration/test_branch_panel.gd','tests/integration/test_checkpoint_save.gd','tests/integration/test_habitat.gd','tests/integration/test_game_shell.gd')
    'construction-regression' = @('tests/unit/test_employee_roster.gd','tests/unit/test_supplier_network.gd','tests/unit/test_game_hud.gd','tests/integration/test_management_system.gd','tests/integration/test_world_travel.gd','tests/integration/test_checkpoint_save.gd','tests/integration/test_level_progression.gd','tests/integration/test_debug_console.gd')
    construction = @('tests/unit/test_branch_construction.gd','tests/integration/test_branch_visit.gd')
    console = @('tests/integration/test_debug_console.gd','tests/unit/test_research_rules.gd')
    'branch-core' = @('tests/unit/test_player_branches.gd','tests/integration/test_branch_panel.gd','tests/integration/test_store_management.gd')
    branches = @('tests/unit/test_player_branches.gd','tests/integration/test_branch_panel.gd','tests/unit/test_shop_profiles.gd','tests/integration/test_level_progression.gd','tests/integration/test_checkpoint_save.gd','tests/unit/test_town_economy_rules.gd','tests/unit/test_phase4_branch.gd','tests/integration/test_habitat.gd','tests/integration/test_homecoming.gd','tests/integration/test_town_economy_integration.gd','tests/integration/test_town_renewal_world.gd')
    'seated-art' = @('tests/integration/test_restaurant_feedback.gd','tests/integration/test_diner_flow.gd','tests/integration/test_decoration_ui.gd')
    'restaurant-feedback' = @('tests/integration/test_restaurant_feedback.gd','tests/integration/test_game_shell.gd','tests/integration/test_level_progression.gd','tests/integration/test_checkpoint_save.gd','tests/unit/test_shop_profiles.gd','tests/integration/test_habitat.gd','tests/integration/test_homecoming.gd','tests/integration/test_player_motion.gd','tests/integration/test_protagonist.gd','tests/integration/test_diner_flow.gd')
    diners = @('tests/integration/test_diner_flow.gd','tests/unit/test_diner_arrival.gd','tests/unit/test_shop_session.gd','tests/unit/test_guest_visit.gd','tests/unit/test_npc_gait.gd','tests/integration/test_restaurant_world.gd','tests/integration/test_game_shell.gd')
    decoration = @('tests/unit/test_restaurant_layout.gd','tests/integration/test_restaurant_world.gd','tests/integration/test_decoration_ui.gd')
    'homecoming' = @('tests/integration/test_homecoming.gd','tests/integration/test_title_entry.gd','tests/unit/test_profile_deletion.gd')
    'story-fixes' = @('tests/integration/test_story_playtest_fixes.gd','tests/integration/test_story_kitchen.gd','tests/integration/test_story_expansion.gd','tests/integration/test_arrival_coast.gd','tests/unit/test_opening.gd','tests/unit/test_dialogue.gd','tests/integration/test_protagonist.gd','tests/integration/test_player_motion.gd')
    'arrival-coast' = @('tests/integration/test_arrival_coast.gd','tests/integration/test_story_expansion.gd','tests/unit/test_story_expansion.gd','tests/integration/test_town_polish_world.gd','tests/unit/test_town_polish.gd','tests/integration/test_game_shell.gd','tests/integration/test_habitat.gd','tests/integration/test_title_entry.gd')
    'story-expansion' = @('tests/unit/test_story_expansion.gd','tests/integration/test_story_expansion.gd','tests/unit/test_opening.gd','tests/unit/test_dialogue.gd','tests/integration/test_story_kitchen.gd','tests/integration/test_character_world.gd','tests/integration/test_visual_unity.gd')
    'visual-unity' = @('tests/unit/test_npc_gait.gd','tests/integration/test_visual_unity.gd','tests/integration/test_habitat.gd','tests/integration/test_player_motion.gd','tests/integration/test_character_world.gd','tests/integration/test_residential_neighbourhood.gd','tests/integration/test_restaurant_world.gd')
    'residential' = @('tests/integration/test_residential_neighbourhood.gd','tests/integration/test_town_polish_world.gd','tests/integration/test_habitat.gd','tests/unit/test_town_renewal.gd')
    'town-polish' = @('tests/unit/test_town_polish.gd','tests/integration/test_town_polish_world.gd','tests/integration/test_town_renewal_world.gd','tests/unit/test_characters.gd','tests/integration/test_character_world.gd','tests/integration/test_restaurant_world.gd')
    'town-renewal' = @('tests/unit/test_town_renewal.gd','tests/integration/test_town_renewal_world.gd')
    story = @('tests/integration/test_story_kitchen.gd','tests/unit/test_opening.gd','tests/unit/test_dialogue.gd')
    locomotion = @('tests/integration/test_player_motion.gd')
    protagonist = @('tests/integration/test_protagonist.gd','tests/integration/test_habitat.gd','tests/integration/test_town_motion.gd','tests/integration/test_kitchen_world.gd')
    habitat = @('tests/integration/test_habitat.gd')
    progression = @('tests/unit/test_shop_progression.gd','tests/integration/test_level_progression.gd')
    characters = @('tests/integration/test_character_world.gd','tests/unit/test_characters.gd','tests/unit/test_dialogue.gd','tests/unit/test_opening.gd')
    stock = @('tests/unit/test_shop_stock.gd','tests/unit/test_season_hold.gd')
    commerce = @('tests/unit/test_town_economy_contracts.gd','tests/unit/test_town_economy_rules.gd','tests/unit/test_town_economy_society.gd','tests/integration/test_town_economy_integration.gd')
    movement = @('tests/integration/test_player_motion.gd','tests/integration/test_town_motion.gd','tests/integration/test_restaurant_world.gd','tests/unit/test_restaurant_layout.gd')
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
  $allFiles = @($files | Sort-Object -CaseSensitive)
  $files = @(for ($i = 0; $i -lt $allFiles.Count; $i++) {
    if (($i % $ShardCount) -eq $ShardIndex) { $allFiles[$i] }
  })
  [ordered]@{suite=$Suite;shard_index=$ShardIndex;shard_count=$ShardCount;total_files=$allFiles.Count;files=$files} |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $report 'selection.json') -Encoding utf8
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
  $summary = [ordered]@{status='PASS';engine=$version;suite=$Suite;shard_index=$ShardIndex;shard_count=$ShardCount;discovered=$discovered;executed=$executed;passed=$executed;failed=$failures;skipped=$skipped;exit_code=0;stages=$stages}
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
