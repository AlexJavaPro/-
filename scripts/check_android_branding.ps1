param(
    [string]$ExpectedAppName = '',
    [switch]$RequireBuiltApk
)

$ErrorActionPreference = 'Stop'

$defaultAppName = [string]::Concat(
    [char]0x0424, # Ф
    [char]0x043E, # о
    [char]0x0442, # т
    [char]0x043E, # о
    [char]0x041F, # П
    [char]0x043E, # о
    [char]0x0447, # ч
    [char]0x0442, # т
    [char]0x0430  # а
)

if ([string]::IsNullOrWhiteSpace($ExpectedAppName)) {
    $ExpectedAppName = $defaultAppName
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$androidRoot = Join-Path $projectRoot 'android\app\src\main'

$manifestPath = Join-Path $androidRoot 'AndroidManifest.xml'
$stringsPath = Join-Path $androidRoot 'res\values\strings.xml'
$anyDpiLauncherPath = Join-Path $androidRoot 'res\mipmap-anydpi-v26\ic_launcher.xml'
$sourceIconPath = Join-Path $projectRoot 'assets\icons\app_icon.png'

$requiredMipmapDirs = @(
    'mipmap-mdpi',
    'mipmap-hdpi',
    'mipmap-xhdpi',
    'mipmap-xxhdpi',
    'mipmap-xxxhdpi'
)

function Assert-Exists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    if (-not (Test-Path $Path)) {
        throw "$Description not found: $Path"
    }
}

Assert-Exists -Path $manifestPath -Description 'AndroidManifest.xml'
Assert-Exists -Path $stringsPath -Description 'strings.xml'
Assert-Exists -Path $sourceIconPath -Description 'source launcher icon'
Assert-Exists -Path $anyDpiLauncherPath -Description 'adaptive launcher icon xml'

[xml]$stringsXml = Get-Content -Raw -Path $stringsPath
$appNameNode = $stringsXml.resources.string | Where-Object { $_.name -eq 'app_name' } | Select-Object -First 1
if ($null -eq $appNameNode) {
    throw "strings.xml must contain <string name='app_name'>...</string>"
}

$resolvedAppName = [string]$appNameNode.'#text'
if ([string]::IsNullOrWhiteSpace($resolvedAppName)) {
    throw "app_name value is empty in strings.xml"
}
if ($resolvedAppName.Trim() -ne $ExpectedAppName.Trim()) {
    throw "app_name mismatch. Expected '$ExpectedAppName', actual '$resolvedAppName'"
}

[xml]$manifestXml = Get-Content -Raw -Path $manifestPath
$applicationNode = $manifestXml.manifest.application
if ($null -eq $applicationNode) {
    throw 'AndroidManifest.xml must contain <application> node'
}

$androidNs = 'http://schemas.android.com/apk/res/android'
$manifestLabel = $applicationNode.GetAttribute('label', $androidNs)
$manifestIcon = $applicationNode.GetAttribute('icon', $androidNs)
$manifestRoundIcon = $applicationNode.GetAttribute('roundIcon', $androidNs)

if ($manifestLabel -ne '@string/app_name') {
    throw "application label must be @string/app_name, actual: '$manifestLabel'"
}
if ($manifestIcon -ne '@mipmap/ic_launcher') {
    throw "application icon must be @mipmap/ic_launcher, actual: '$manifestIcon'"
}
if ($manifestRoundIcon -ne '@mipmap/ic_launcher') {
    throw "application roundIcon must be @mipmap/ic_launcher, actual: '$manifestRoundIcon'"
}

foreach ($mipmapDir in $requiredMipmapDirs) {
    $absoluteDir = Join-Path $androidRoot "res\$mipmapDir"
    Assert-Exists -Path $absoluteDir -Description "launcher mipmap directory ($mipmapDir)"
    $launcherFiles = Get-ChildItem -Path $absoluteDir -Filter 'ic_launcher.*' -File -ErrorAction SilentlyContinue
    if ($launcherFiles.Count -eq 0) {
        throw "No ic_launcher.* file found in $absoluteDir"
    }
}

if ($RequireBuiltApk) {
    $apkPath = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    Assert-Exists -Path $apkPath -Description 'release APK'
}

Write-Host '[OK] Android branding check passed'
Write-Host " - app_name: $resolvedAppName"
Write-Host ' - manifest label/icon/roundIcon: OK'
Write-Host ' - launcher resources (mipmap + adaptive icon): OK'
