#Requires -Version 7.2
[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_BIN, [switch]$Module, [switch]$Cooking, [switch]$FullKitchen)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lock = Get-Content -LiteralPath (Join-Path $root 'dependencies.lock.json') -Raw | ConvertFrom-Json
if (-not $GodotPath) { $GodotPath = $lock.godot.local_path }
$version = (& $GodotPath --headless --version | Out-String).Trim()
if (-not $version.StartsWith($lock.godot.release + '.')) { throw "Engine mismatch: $version" }
$arguments = @('--path',$root)
if ($Module) { $arguments += 'res://dev/module_test.tscn' }
if ($Cooking) { $arguments += 'res://dev/cooking_test.tscn' }
if ($FullKitchen) { $arguments += 'res://dev/full_cooking_test.tscn' }
& $GodotPath @arguments
