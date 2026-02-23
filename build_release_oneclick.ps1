$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
Set-Location $projectRoot

$flutterBin = 'C:\src\flutter\bin'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue) -and (Test-Path "$flutterBin\flutter.bat")) {
    $env:PATH = "$flutterBin;$env:PATH"
}

$preferredKeystore = 'C:\keys\upload-keystore.jks'
$fallbackKeystore = Join-Path $env:USERPROFILE 'Desktop\upload-keystore.jks'
$keystorePath = if (Test-Path $preferredKeystore) {
    $preferredKeystore
} elseif (Test-Path $fallbackKeystore) {
    $fallbackKeystore
} else {
    $preferredKeystore
}

& "$projectRoot\scripts\build_release.ps1" `
  -KeystorePath $keystorePath `
  -StorePassword "Test123456" `
  -KeyAlias "upload" `
  -KeyPassword "Test123456"
