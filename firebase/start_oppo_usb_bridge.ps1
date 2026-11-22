$ErrorActionPreference = 'Stop'
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"

Write-Host "==> Starting ADB server & configuring USB reverse tunnel (9199 Auth, 8188 Firestore)..." -ForegroundColor Cyan
& $adb start-server
& $adb reverse tcp:9199 tcp:9199
& $adb reverse tcp:8188 tcp:8188
& $adb reverse --list

Write-Host "==> Starting Persistent Firebase Auth + Cloud Firestore Local Server..." -ForegroundColor Green
firebase emulators:start --only auth,firestore --project demo-life-os --import=./firebase/emulator_data --export-on-exit=./firebase/emulator_data
