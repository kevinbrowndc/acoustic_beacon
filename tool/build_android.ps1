param([string]$JdkPath)

$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $JdkPath) {
    $localTools = Join-Path (Split-Path $projectPath -Parent) '.tooling'
    $localJdk = Get-ChildItem -LiteralPath $localTools -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Select-Object -First 1
    $JdkPath = if ($localJdk) { $localJdk.FullName } else { $env:JAVA_HOME }
}
if (-not $JdkPath -or -not (Test-Path -LiteralPath (Join-Path $JdkPath 'bin/java.exe'))) {
    throw 'Provide -JdkPath pointing to a Windows JDK 17 or 21 installation.'
}
$jdkRelease = Get-Content -LiteralPath (Join-Path $JdkPath 'release') -Raw
if ($jdkRelease -notmatch 'JAVA_VERSION="(17|21)\.') {
    throw 'This build uses Gradle 8.12. Select JDK 17 or 21.'
}

# Avoid Windows packaged-process TEMP redirection affecting Java's local sockets.
# This is a build-process-only setting, not a system networking change.
$socketDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\acoustic-beacon-tmp'
New-Item -ItemType Directory -Path $socketDirectory -Force | Out-Null
$oldJavaHome = $env:JAVA_HOME
$oldJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
    $env:JAVA_HOME = (Resolve-Path -LiteralPath $JdkPath).Path
    $env:JAVA_TOOL_OPTIONS = ($oldJavaOptions + ' -Djdk.net.unixdomain.tmpdir="' + $socketDirectory + '"').Trim()
    Push-Location $projectPath
    try {
        # Flutter 3.32's cached depfile parsing can misread spaces in Windows paths.
        # Regenerate build outputs rather than reusing those malformed cached paths.
        & flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'Flutter clean failed.' }
        & flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Locked dependency restoration failed.' }
    } finally { Pop-Location }
    Push-Location (Join-Path $projectPath 'android')
    try {
        & .\gradlew.bat --no-daemon --console=plain '-Ptarget-platform=android-arm,android-arm64,android-x64' assembleDebug
        if ($LASTEXITCODE -ne 0) { throw "Android build failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
    $apk = Join-Path $projectPath 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'Build returned without the expected APK.' }
    Write-Output "Debug APK: $apk"
    Get-FileHash -LiteralPath $apk -Algorithm SHA256
} finally {
    $env:JAVA_HOME = $oldJavaHome
    $env:JAVA_TOOL_OPTIONS = $oldJavaOptions
}
