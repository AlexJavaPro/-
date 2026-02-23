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

function Ensure-WingetPackage {
    param(
        [string[]]$Ids
    )

    foreach ($id in $Ids) {
        try {
            Write-Host "Installing $id..."
            winget install --id $id --silent --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -eq 0) {
                return
            }
        } catch {
        }
    }
    throw "Failed to install package from IDs: $($Ids -join ', ')"
}

function Ensure-Command {
    param([string]$Name, [string[]]$FallbackPaths)

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }
    foreach ($candidate in $FallbackPaths) {
        $resolvedPaths = @()
        if ($candidate.Contains("*")) {
            $resolvedPaths = Get-ChildItem -Path $candidate -Directory -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
        } else {
            if (Test-Path $candidate) {
                $resolvedPaths = @($candidate)
            }
        }

        foreach ($path in $resolvedPaths) {
            $env:PATH = "$path;$env:PATH"
            if (Get-Command $Name -ErrorAction SilentlyContinue) {
                return
            }
        }
    }
    throw "Command '$Name' not found."
}

function Ensure-AndroidWrapper {
    if (Test-Path "android\gradlew.bat" -and (Test-Path "android\gradle\wrapper\gradle-wrapper.jar")) {
        return
    }

    $tmp = Join-Path $env:TEMP ("photomailer_template_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        flutter create --platforms android --org ru.amajo --project-name photomailer $tmp | Out-Null
        Copy-Item "$tmp\android\gradlew" "android\gradlew" -Force
        Copy-Item "$tmp\android\gradlew.bat" "android\gradlew.bat" -Force
        New-Item -ItemType Directory -Path "android\gradle\wrapper" -Force | Out-Null
        Copy-Item "$tmp\android\gradle\wrapper\gradle-wrapper.jar" "android\gradle\wrapper\gradle-wrapper.jar" -Force
        Copy-Item "$tmp\android\gradle\wrapper\gradle-wrapper.properties" "android\gradle\wrapper\gradle-wrapper.properties" -Force
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-AndroidSdk {
    param([string]$SdkPath)

    $cmdlineToolsDir = Join-Path $SdkPath "cmdline-tools\latest"
    $sdkManager = Join-Path $cmdlineToolsDir "bin\sdkmanager.bat"

    if (-not (Test-Path $sdkManager)) {
        New-Item -ItemType Directory -Path $SdkPath -Force | Out-Null
        $zipPath = Join-Path $env:TEMP "commandlinetools-win.zip"
        $downloadUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"

        Write-Host "Downloading Android command-line tools..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath

        $extractRoot = Join-Path $env:TEMP ("android_cmdline_" + [Guid]::NewGuid().ToString("N"))
        Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
        New-Item -ItemType Directory -Path (Join-Path $SdkPath "cmdline-tools") -Force | Out-Null
        Move-Item -Path (Join-Path $extractRoot "cmdline-tools") -Destination $cmdlineToolsDir -Force
        Remove-Item -Path $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $sdkManager)) {
        throw "sdkmanager not found after cmdline-tools setup."
    }

    $env:ANDROID_SDK_ROOT = $SdkPath
    $env:ANDROID_HOME = $SdkPath
    $env:PATH = "$SdkPath\platform-tools;$cmdlineToolsDir\bin;$env:PATH"

    Write-Host "Installing Android SDK packages..."
    & $sdkManager --sdk_root=$SdkPath "platform-tools" "platforms;android-34" "build-tools;34.0.0"

    $licenseInput = ("y`n" * 200)
    $licenseInput | & $sdkManager --sdk_root=$SdkPath --licenses | Out-Null
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget not found. Install App Installer from Microsoft Store."
}

Ensure-WingetPackage -Ids @("Git.Git")
Ensure-WingetPackage -Ids @("EclipseAdoptium.Temurin.17.JDK", "Microsoft.OpenJDK.17")
Ensure-WingetPackage -Ids @("Flutter.Flutter")
Ensure-WingetPackage -Ids @("Google.AndroidStudio")

Ensure-Command -Name "git" -FallbackPaths @("C:\Program Files\Git\cmd")
Ensure-Command -Name "java" -FallbackPaths @(
    "C:\Program Files\Eclipse Adoptium\jdk-17*\bin",
    "C:\Program Files\Microsoft\jdk-17*\bin"
)
Ensure-Command -Name "flutter" -FallbackPaths @(
    "$env:LOCALAPPDATA\Programs\Flutter\bin",
    "$env:USERPROFILE\flutter\bin",
    "C:\src\flutter\bin"
)

$sdkPath = Join-Path $env:LOCALAPPDATA "Android\Sdk"
Ensure-AndroidSdk -SdkPath $sdkPath

flutter config --android-sdk $sdkPath | Out-Null
flutter doctor | Out-Null

Ensure-AndroidWrapper

powershell -ExecutionPolicy Bypass -File ".\scripts\build_release.ps1" `
    -KeystorePath $KeystorePath `
    -StorePassword $StorePassword `
    -KeyAlias $KeyAlias `
    -KeyPassword $KeyPassword
