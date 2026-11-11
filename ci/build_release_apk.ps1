# Build local do APK release assinado, com overlay Android obrigatorio.
# Nao publica no GitHub. Versao = pubspec.yaml (sem bump).
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
if (-not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
  throw "JAVA_HOME invalido: $env:JAVA_HOME"
}
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

$pubspec = Get-Content (Join-Path $Root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([^\s]+)') {
  throw 'version nao encontrada em pubspec.yaml'
}
$full = $Matches[1].Trim()
$versionName = $full.Split('+')[0]
$versionCode = $full.Split('+')[1]
if (-not $versionCode) { throw "versionCode ausente em version: $full" }

$keyProps = Join-Path $Root 'android\key.properties'
if (-not (Test-Path $keyProps)) {
  throw 'android/key.properties ausente - necessario para assinar com ci/unitecfv-release.p12'
}

Write-Host '==> Overlay Android'
& (Join-Path $PSScriptRoot 'apply_android_overlay.ps1')

$manifest = Join-Path $Root 'android\app\src\main\AndroidManifest.xml'
$xmlDir = Join-Path $Root 'android\app\src\main\res\xml'
foreach ($f in @(
  $manifest,
  (Join-Path $xmlDir 'backup_rules.xml'),
  (Join-Path $xmlDir 'data_extraction_rules.xml'),
  (Join-Path $xmlDir 'file_paths.xml')
)) {
  if (-not (Test-Path $f)) { throw "Overlay incompleto: falta $f" }
}
if (-not (Select-String -Path $manifest -Pattern 'android:allowBackup="false"' -Quiet)) {
  throw 'Manifest sem allowBackup=false apos overlay'
}
if (-not (Select-String -Path $manifest -Pattern 'dataExtractionRules' -Quiet)) {
  throw 'Manifest sem dataExtractionRules apos overlay'
}

Write-Host '==> flutter pub get'
flutter pub get

Write-Host "==> flutter build apk --release ($versionName+$versionCode)"
flutter build apk --release --build-name="$versionName" --build-number="$versionCode"

$apkCandidates = @(
  (Join-Path $Root "build\app\outputs\apk\release\Unitec-Forca-Vendas-$versionName.apk"),
  (Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk"),
  (Join-Path $Root "build\app\outputs\apk\release\app-release.apk")
)
$apk = $apkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $apk) {
  Get-ChildItem -Recurse (Join-Path $Root 'build\app\outputs') -Filter '*.apk' -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "  encontrado: $($_.FullName)" }
  throw 'APK release nao encontrado apos o build'
}

$merged = Join-Path $Root 'build\app\intermediates\merged_manifest\release\processReleaseMainManifest\AndroidManifest.xml'
if (Test-Path $merged) {
  Write-Host '==> Manifest mesclado (release):'
  Select-String -Path $merged -Pattern 'allowBackup|dataExtraction|fullBackup' |
    ForEach-Object { Write-Host "  $($_.Line.Trim())" }
}

Write-Host "==> APK: $apk"
Write-Host "    versionName=$versionName versionCode=$versionCode"
Get-Item $apk | Format-List FullName, Length, LastWriteTime
