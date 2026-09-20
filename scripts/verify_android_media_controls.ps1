param(
    [string]$PackageId = "dev.arion.client"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw "adb is not available on PATH. Install Android platform-tools first."
}

$deviceState = (& adb get-state 2>&1).Trim()
if ($deviceState -ne "device") {
    throw "No ready Android device is connected (adb state: $deviceState)."
}

& adb shell am start -n "$PackageId/.MainActivity"
if ($LASTEXITCODE -ne 0) {
    throw "Could not launch $PackageId."
}

Write-Host "Start a track in Arion, add a second queue entry, then press Enter."
Read-Host

& adb shell input keyevent KEYCODE_HOME
& adb shell input keyevent KEYCODE_MEDIA_PAUSE
& adb shell input keyevent KEYCODE_MEDIA_PLAY
& adb shell input keyevent KEYCODE_MEDIA_NEXT
& adb shell input keyevent KEYCODE_MEDIA_PREVIOUS
& adb shell input keyevent KEYCODE_MEDIA_FAST_FORWARD
& adb shell input keyevent KEYCODE_MEDIA_REWIND

$mediaState = & adb shell dumpsys media_session
if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect Android media-session state."
}
if (-not ($mediaState | Select-String -SimpleMatch $PackageId)) {
    throw "Android did not report an active media session for $PackageId."
}

Write-Host "Media commands dispatched while the activity was backgrounded."
Write-Host "Verify notification metadata, queue navigation, seek position, and audio output on the device."
$mediaState | Select-String -Pattern $PackageId, "state=", "metadata:"
