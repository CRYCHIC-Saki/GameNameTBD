#Requires -Version 7.2
[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lock = Get-Content -LiteralPath (Join-Path $root 'dependencies.lock.json') -Raw | ConvertFrom-Json
if (-not $GodotPath) { $GodotPath = $lock.godot.local_path }
& (Join-Path $PSScriptRoot 'check.ps1') -GodotPath $GodotPath -ReportName ('pre-export-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
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
  if (-not $process.WaitForExit(90000)) { $process.Kill($true); throw "$Name timeout" }
  $text = $output.GetAwaiter().GetResult() + $errors.GetAwaiter().GetResult()
  [IO.File]::WriteAllText((Join-Path $evidence "$Name.log"), $text)
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
      if ($name -notmatch '^(src/|\.godot/|assets/kitchen/[^/]+\.png(\.import)?$|content/(dev_samples|cooking_prototype|cooking_system)\.json$|project\.binary$)') { throw "Non-runtime resource exported: $name" }
    }
    $names | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'runtime-manifest.json') -Encoding utf8
  } finally { $archive.Dispose() }
  # Exported games locate their adjacent PCK themselves. Do not pass a --path override.
  Run-Process (Join-Path $build 'TownDiner.exe') 'smoke' @('--headless','--quit-after','12')
  $summary = [ordered]@{status='PASS';export_exit=0;smoke_exit=0;runtime_files=$names.Count;package='build/TownDiner.exe + TownDiner.pck';kind='DEVELOPMENT_DEMO';human_playtest='PENDING';remote_ci='NOT_RUN'}
  $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
  Write-Host "EXPORT PASS; evidence=$evidence"
  exit 0
} catch {
  [ordered]@{status='FAIL';reason=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'summary.json')
  Write-Host $_.Exception.Message
  exit 1
}
