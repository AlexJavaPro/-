param(
    [Parameter(Mandatory = $true)]
    [string]$KeystorePath,
    [Parameter(Mandatory = $true)]
    [string]$StorePassword,
    [Parameter(Mandatory = $true)]
    [string]$KeyAlias,
    [Parameter(Mandatory = $true)]
    [string]$KeyPassword
)

$ErrorActionPreference = "Stop"

function Assert-CommandExists {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Command '$Name' not found in PATH."
    }
}

function Write-KeyProperties {
    param(
        [string]$Path,
        [string]$StorePass,
        [string]$Alias,
        [string]$KeyPass
    )
    $escapedPath = $Path.Replace("\", "\\")
    @"
storeFile=$escapedPath
storePassword=$StorePass
keyAlias=$Alias
keyPassword=$KeyPass
"@ | Set-Content -Path "android\key.properties" -Encoding UTF8
}

Assert-CommandExists "flutter"

Write-KeyProperties -Path $KeystorePath -StorePass $StorePassword -Alias $KeyAlias -KeyPass $KeyPassword

flutter pub get
dart run flutter_launcher_icons
& "$PSScriptRoot\check_android_branding.ps1"
flutter build apk --release
& "$PSScriptRoot\check_android_branding.ps1" -RequireBuiltApk

Write-Host "APK built: build\app\outputs\flutter-apk\app-release.apk"
