#Requires -Version 7.2
[CmdletBinding()]
param([switch]$Check, [string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $root 'doc/source/ingredients.json'
if (-not $OutputPath) { $OutputPath = Join-Path $root 'content/ingredient_index.json' }
$raw = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
$index = [ordered]@{
  schema_version = 1
  source = 'doc/source/ingredients.json'
  source_version = $raw.meta.version
  source_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
  purpose = 'Identity and display index only; no flavor or recipe balancing data.'
  categories = @($raw.categories | ForEach-Object {
    [ordered]@{ id=$_.id; name=$_.name; items=@($_.items | ForEach-Object {
      [ordered]@{ id=$_.id; name=$_.name; sub=[string]$_.sub }
    }) }
  })
}
$text = ($index | ConvertTo-Json -Depth 8).Replace("`r`n", "`n") + "`n"
if ($Check) {
  if (-not (Test-Path -LiteralPath $OutputPath) -or [IO.File]::ReadAllText($OutputPath).Replace("`r`n", "`n") -cne $text) {
    throw 'Runtime ingredient index is missing or stale. Run tools/build_ingredient_index.ps1.'
  }
  Write-Host 'Ingredient runtime index matches its read-only source.'
} else {
  [IO.File]::WriteAllText($OutputPath, $text, [Text.UTF8Encoding]::new($false))
  Write-Host "Runtime ingredient index written: $OutputPath"
}
