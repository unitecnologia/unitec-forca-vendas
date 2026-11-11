# Copia overlays versionados em ci/ para o android/ gerado pelo flutter create.
# Deve rodar SEMPRE antes do flutter build apk (equivalente Windows do .sh).
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AppMain = Join-Path $Root 'android\app\src\main'
$XmlDir = Join-Path $AppMain 'res\xml'

if (-not (Test-Path $AppMain)) {
  throw "ERRO: $AppMain nao existe. Rode flutter create --platforms=android . antes."
}

New-Item -ItemType Directory -Force -Path $XmlDir | Out-Null
Copy-Item -Force (Join-Path $Root 'ci\AndroidManifest.xml') (Join-Path $AppMain 'AndroidManifest.xml')
Copy-Item -Force (Join-Path $Root 'ci\file_paths.xml') (Join-Path $XmlDir 'file_paths.xml')
Copy-Item -Force (Join-Path $Root 'ci\backup_rules.xml') (Join-Path $XmlDir 'backup_rules.xml')
Copy-Item -Force (Join-Path $Root 'ci\data_extraction_rules.xml') (Join-Path $XmlDir 'data_extraction_rules.xml')

$dest = Get-ChildItem -Path (Join-Path $Root 'android') -Recurse -Filter 'MainActivity.kt' |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $dest) {
  throw 'ERRO: MainActivity.kt nao encontrado sob android/'
}
$rel = $dest -replace '\\', '/'
$pkg = if ($rel -match '/kotlin/(.+)/MainActivity\.kt$') {
  ($Matches[1] -replace '/', '.')
} else { '' }
Copy-Item -Force (Join-Path $Root 'ci\MainActivity.kt') $dest
if ($pkg) {
  $lines = Get-Content $dest
  if ($lines.Count -gt 0 -and $lines[0] -match '^package ') {
    $lines[0] = "package $pkg"
    Set-Content -Path $dest -Value $lines -Encoding utf8
  }
}

Write-Host 'Overlay Android aplicado:'
Write-Host '  - AndroidManifest.xml (allowBackup=false + regras de backup)'
Write-Host '  - res/xml/file_paths.xml'
Write-Host '  - res/xml/backup_rules.xml'
Write-Host '  - res/xml/data_extraction_rules.xml'
Write-Host "  - MainActivity.kt -> $dest (package $(if ($pkg) { $pkg } else { '?' }))"
