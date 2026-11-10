#Requires -Version 7.2
[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_BIN, [int]$CheckTimeoutSeconds = 1800, [string]$CheckSuite = 'all')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lock = Get-Content -LiteralPath (Join-Path $root 'dependencies.lock.json') -Raw | ConvertFrom-Json
if (-not $GodotPath) { $GodotPath = $lock.godot.local_path }
& (Join-Path $PSScriptRoot 'check.ps1') -GodotPath $GodotPath -Suite $CheckSuite -TimeoutSeconds $CheckTimeoutSeconds -ReportName ('pre-export-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
if ($LASTEXITCODE -ne 0) { exit 1 }
$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$evidence = Join-Path $root 'artifacts/export'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
function Run-Process([string]$Exe, [string]$Name, [string[]]$Arguments) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $Exe
  $info.WorkingDirectory = $build
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  [void]$process.Start()
  $output = $process.StandardOutput.ReadToEndAsync()
  $errors = $process.StandardError.ReadToEndAsync()
  $timedOut = -not $process.WaitForExit(90000)
  if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
  $text = $output.GetAwaiter().GetResult() + $errors.GetAwaiter().GetResult()
  [IO.File]::WriteAllText((Join-Path $evidence "$Name.log"), $text)
  if ($timedOut) { throw "$Name timeout; see $evidence/$Name.log" }
  if ($process.ExitCode -ne 0 -or $text -match '(?m)^\s*(SCRIPT ERROR|ERROR):|Parse Error:|ObjectDB.*leaked') {
    throw "$Name failed exit=$($process.ExitCode); see $evidence"
  }
  Write-Host "$Name exit=0"
}
try {
  Run-Process $GodotPath 'export' @('--headless','--path',$root,'--export-debug','Windows Framework Demo',(Join-Path $build 'TownDiner.exe'))
  Run-Process $GodotPath 'pack-manifest' @('--headless','--path',$root,'--export-pack','Windows Framework Demo',(Join-Path $evidence 'runtime.zip'))
  $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $evidence 'runtime.zip'))
  try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($name in $names) {
      if ($name -notmatch '^(src/|\.godot/|assets/characters/diners/diners-((four-directions|seated)-v1|isometric-seated-v2|occupied-seat-v4)\.png(\.import)?$|assets/characters/(aling/archive/2026-10-29/aling|ash-priest/archive/2026-10-29/ash-priest)-(idle-four-directions|dialogue-halfbody)\.png(\.import)?$|assets/characters/(aling/aling|ash-priest/ash-priest)-walk-four-directions-v1\.png(\.import)?$|assets/characters/protagonist/protagonist-((idle|walk)-four-directions-v1|dialogue-halfbody-pose-pixel-v7)\.png(\.import)?$|assets/audio/(casual|service|cooking)\.wav(\.import)?$|assets/(kitchen/(recipe-icons/)?|town/|story/|cottage/)[^/]+\.png(\.import)?$|content/(story/(opening|homecoming)|characters/roster|dev_samples|cooking_prototype|cooking_system|service_content|employees|suppliers|culinary_materials|branches|restaurant|phase3_world|pantry|ingredient_index|research/recipe_atlas|research/runtime_recipes|town_economy/(economy|meal_schedule)|towns/(chinese_layout|regions)|markets/kitchen_stock|brand/progression)\.json$|project\.binary$)') { throw "Non-runtime resource exported: $name" }
    }
    $names | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'runtime-manifest.json') -Encoding utf8
	if ('content/culinary_materials.json' -notin $names) { throw 'Missing material catalogue' }
    if ('content/town_economy/economy.json' -notin $names) { throw 'Missing exported economy configuration' }
    foreach ($resource in @('assets/town/world-atlas-v1.png.import','content/towns/regions.json','src/town/regional_layout.gd','src/town/region_migration.gd','src/town/travel_catalog.gd','src/town/travel_world.gd','src/town/travel_map_view.gd','assets/town/four-cultures-v1.png.import','assets/town/four-cultures-props-v1.png.import')) {
      if ($resource -notin $names -and ($resource + '.remap') -notin $names) { throw "Missing exported travel resource: $resource" }
    }
    $crewResource = 'src/restaurant/restaurant_crew.gd'
    foreach ($resource in @('assets/characters/diners/diners-occupied-seat-v4.png.import','assets/town/dining-table-stool-separated-v1.png.import','src/restaurant/decoration_panel.gd','src/restaurant/furniture_model.gd','src/restaurant/diner_art.gd','assets/characters/diners/diners-four-directions-v1.png.import','assets/characters/diners/diners-seated-v1.png.import','assets/characters/diners/diners-isometric-seated-v2.png.import')) {
      if ($resource -notin $names -and ($resource + '.remap') -notin $names) { throw "Missing exported decoration resource: $resource" }
    }
    if ($crewResource -notin $names -and ($crewResource + '.remap') -notin $names) { throw 'Missing exported restaurant crew script' }
    $guestResource = 'src/restaurant/guest_visit.gd'
    if ($guestResource -notin $names -and ($guestResource + '.remap') -notin $names) { throw 'Missing exported guest visit script' }
    foreach ($resource in @('src/app/debug_commands.gd','content/story/homecoming.json','assets/cottage/furniture-v1.png.import','assets/story/arrival-props-v1.png.import','src/story/arrival_cutscene.gd','src/story/arrival_cutscene.tscn','assets/story/arrival-hero-v1.png.import','assets/story/arrival-aling-v2.png.import','assets/story/arrival-coast-v1.png.import','src/town/harbor.gd','assets/town/harbor-v1.png.import','src/story/story_guide.gd','src/story/cutscene_view.gd','src/story/quest_path.gd','src/story/quest_trail.gd','src/story/opening_script.gd','content/story/opening.json','assets/story/aling-emotions-corrections-v1.png.import','assets/story/cinematic-actors-v1.png.import','assets/story/hero-emotions-v1.png.import','assets/story/aling-emotions-v1.png.import','assets/story/chen-emotions-v1.png.import','assets/story/opening-actions-v1.png.import','assets/story/opening-actions-extra-v1.png.import','assets/story/opening-backgrounds-v1.png.import','assets/story/opening-props-v1.png.import','assets/characters/aling/aling-walk-four-directions-v1.png.import','assets/characters/ash-priest/ash-priest-walk-four-directions-v1.png.import','assets/town/town-sprites-v3.png.import','assets/town/residential-houses-v2.png.import','assets/town/ground-materials-v4.png.import','src/world/npc_gait.gd','assets/town/residential-houses-v1.png.import','src/town/town_scenery.gd','src/world/interaction_range.gd','assets/town/ground-materials-v3.png.import','src/town/planned_town.gd','src/town/map_migration.gd','src/platform/daylight.gd','src/world/environment_art.gd','content/towns/chinese_layout.json','content/town_economy/meal_schedule.json','assets/town/town-sprites-v2.png.import','assets/town/diner-props-v2.png.import','assets/kitchen/kitchen-background-v2.png.import','src/platform/day_clock.gd','src/characters/character_roster.gd','content/characters/roster.json','assets/characters/protagonist/protagonist-dialogue-halfbody-pose-pixel-v7.png.import','src/story/story_art.gd','src/story/opening.gd','src/ui/dialogue.gd','src/ui/dialogue_view.gd','src/kitchen/prep_guide.gd')) {
      if ($resource -notin $names -and ($resource + '.remap') -notin $names) { throw "Missing exported story resource: $resource" }
    }
    foreach ($pose in @('idle','walk')) {
      if (('assets/characters/protagonist/protagonist-' + $pose + '-four-directions-v1.png.import') -notin $names) { throw "Missing exported protagonist $pose atlas" }
    }
    foreach ($character in @('aling','ash-priest')) {
      foreach ($kind in @('idle-four-directions','dialogue-halfbody')) {
        $resource = "assets/characters/$character/archive/2026-10-29/$character-$kind.png.import"
        if ($resource -notin $names) { throw "Missing selected story art: $resource" }
      }
    }
	foreach ($resource in @('src/business/employee_roster.gd','src/business/supplier_network.gd','src/ui/game_hud.gd','src/ui/management_panels.gd','content/employees.json','content/suppliers.json','src/business/branch_network.gd','src/business/branch_interior.gd','src/business/branch_panel.gd','content/branches.json','src/platform/game_music.gd','src/town/cottage_world.gd','src/world/chef_art.gd','assets/audio/casual.wav.import','assets/audio/service.wav.import','assets/audio/cooking.wav.import','content/brand/progression.json','src/business/level_progression.gd','src/ui/level_rewards_view.gd','content/markets/kitchen_stock.json','src/business/food_stock.gd','src/ui/ingredient_icon.gd')) {
	  if ($resource -notin $names -and ($resource + '.remap') -notin $names) { throw "Missing exported stock resource: $resource" }
	}
	foreach ($script in Get-ChildItem -LiteralPath (Join-Path $root 'src/town_economy') -Filter '*.gd' -File) {
	  $resource = 'src/town_economy/' + $script.Name
	  if ($resource -notin $names -and ($resource + '.remap') -notin $names) { throw "Missing exported economy script: $resource" }
	}
  } finally { $archive.Dispose() }
  # Exercise the real title quit action, allowing audio to shut down gracefully.
  # --quit-after destroys the engine without running the game's quit handler.
  Run-Process $GodotPath 'startup-probe-pack' @('--headless','--path',$root,'--script','res://tools/pack_title_probe.gd','--','--startup-exit')
  $startup = Join-Path $evidence 'startup-probe'
  Copy-Item -LiteralPath (Join-Path $build 'TownDiner.exe') -Destination (Join-Path $startup 'StartupProbe.exe')
  Copy-Item -LiteralPath (Join-Path $startup 'probe.pck') -Destination (Join-Path $startup 'StartupProbe.pck')
  foreach ($attempt in 1..3) {
    Run-Process (Join-Path $startup 'StartupProbe.exe') ('smoke-' + $attempt) @('--headless','--',('--probe-root=' + (Join-Path $startup ('storage-' + $attempt))))
    if ((Get-Content -LiteralPath (Join-Path $evidence ('smoke-' + $attempt + '.log')) -Raw) -notmatch 'STARTUP_EXIT success=true checks=4') { throw 'Real startup and quit did not complete' }
  }
  # Editor runs can resolve missing res:// dependencies from the checkout. Exercise
  # the actual exported executable with a sibling disposable PCK instead. Preserve
  # every production resource, replacing only the entry scene with the mouse driver.
  Run-Process $GodotPath 'title-probe-pack' @('--headless','--path',$root,'--script','res://tools/pack_title_probe.gd')
  $probe = Join-Path $evidence 'title-probe'
  Copy-Item -LiteralPath (Join-Path $build 'TownDiner.exe') -Destination (Join-Path $probe 'TitleProbe.exe')
  Copy-Item -LiteralPath (Join-Path $probe 'probe.pck') -Destination (Join-Path $probe 'TitleProbe.pck')
  Run-Process (Join-Path $probe 'TitleProbe.exe') 'title-input' @('--headless','--',('--probe-root=' + $probe))
  $probeLog = Get-Content -LiteralPath (Join-Path $evidence 'title-input.log') -Raw
  if ($probeLog -notmatch 'TITLE_PROBE success=true checks=(\d+)' -or [int]$Matches[1] -lt 29) { throw 'Exported title and movement regression did not complete its checks' }
  $titleChecks = [int]$Matches[1]
  $summary = [ordered]@{status='PASS';check_suite=$CheckSuite;export_exit=0;smoke_exit=0;title_input_exit=0;title_input_checks=$titleChecks;runtime_files=$names.Count;package='build/TownDiner.exe + TownDiner.pck';kind='DEVELOPMENT_DEMO';human_playtest='PENDING';remote_ci='NOT_RUN'}
  $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
  Write-Host "EXPORT PASS; evidence=$evidence"
  exit 0
} catch {
  [ordered]@{status='FAIL';reason=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'summary.json')
  Write-Host $_.Exception.Message
  exit 1
}
