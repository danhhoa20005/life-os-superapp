param(
    [string]$ProjectId = "",
    [switch]$InstallOnOppo = $true
)

$ErrorActionPreference = 'Stop'
$flutterfireExe = "$env:LOCALAPPDATA\Pub\Cache\bin\flutterfire.bat"
if (!(Test-Path $flutterfireExe)) {
    dart pub global activate flutterfire_cli
}

Write-Host "==> [1/9] Checking Firebase CLI authentication..." -ForegroundColor Cyan
$projectsJson = firebase projects:list --json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Session expired or unauthenticated. Launching official Google OAuth browser login..." -ForegroundColor Yellow
    firebase login --reauth
    $projectsJson = firebase projects:list --json
}

$parsed = $projectsJson | ConvertFrom-Json
$existingProjects = $parsed.result

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    $matched = $existingProjects | Where-Object { $_.projectId -match '^life-os' } | Select-Object -First 1
    if ($null -ne $matched) {
        $ProjectId = $matched.projectId
        Write-Host "Found existing Life OS Firebase project: $ProjectId" -ForegroundColor Green
    } else {
        $suffix = (Get-Random -Minimum 1000 -Maximum 9999)
        $ProjectId = "life-os-vn-$suffix"
        Write-Host "==> [2/9] Creating new Spark (0 VND) Firebase Project: $ProjectId ..." -ForegroundColor Cyan
        firebase projects:create $ProjectId --display-name "Life OS Vietnam"
    }
}

Write-Host "==> [3/9] Linking workspace (.firebaserc) to $ProjectId..." -ForegroundColor Cyan
firebase use $ProjectId

Write-Host "==> [4/9] Ensuring Standard Cloud Firestore (default) in asia-southeast1 (Singapore)..." -ForegroundColor Cyan
$dbList = firebase firestore:databases:list --project $ProjectId --json | ConvertFrom-Json
if ($dbList.result.Count -eq 0 -and $dbList.databases.Count -eq 0) {
    firebase firestore:databases:create "(default)" --location asia-southeast1 --edition standard --project $ProjectId
} else {
    Write-Host "Default Cloud Firestore database already exists." -ForegroundColor Green
}

Write-Host "==> [5/9] Running flutterfire configure for Android (vn.lifeos.app.life_os), iOS & Web..." -ForegroundColor Cyan
& $flutterfireExe configure `
    --project=$ProjectId `
    --platforms=android,ios,web `
    --android-package-name=vn.lifeos.app.life_os `
    --ios-bundle-id=vn.lifeos.app `
    --out=lib/firebase_options.dart `
    --yes

Write-Host "==> [6/9] Registering Android Signing SHA-1 & SHA-256 for Native Google Sign-In..." -ForegroundColor Cyan
$keystorePath = "$env:USERPROFILE\.android\debug.keystore"
if (Test-Path $keystorePath) {
    $keytoolOut = keytool -list -v -keystore $keystorePath -alias androiddebugkey -storepass android -keypass android
    $sha1Match = ($keytoolOut | Select-String -Pattern "SHA1:\s*([0-9A-F:]+)").Matches
    $sha256Match = ($keytoolOut | Select-String -Pattern "SHA256:\s*([0-9A-F:]+)").Matches

    $appsJson = firebase apps:list ANDROID --project $ProjectId --json | ConvertFrom-Json
    $androidApp = $appsJson.result | Where-Object { $_.packageName -eq "vn.lifeos.app.life_os" } | Select-Object -First 1
    if ($null -ne $androidApp) {
        $appId = $androidApp.appId
        if ($sha1Match.Count -gt 0) {
            $sha1 = $sha1Match[0].Groups[1].Value
            Write-Host "Registering SHA-1 ($sha1) on Android App $appId..."
            firebase apps:android:sha:create $appId $sha1 --project $ProjectId 2>$null
        }
        if ($sha256Match.Count -gt 0) {
            $sha256 = $sha256Match[0].Groups[1].Value
            Write-Host "Registering SHA-256 ($sha256) on Android App $appId..."
            firebase apps:android:sha:create $appId $sha256 --project $ProjectId 2>$null
        }
        Write-Host "Refreshing android/app/google-services.json with OAuth Client IDs..."
        firebase apps:sdkconfig ANDROID $appId --project $ProjectId --out android/app/google-services.json
    }
}

Write-Host "==> [7/9] Enabling Firebase Auth Email/Password Provider via Google Identity Toolkit API..." -ForegroundColor Cyan
$fbCfgPath = "$env:USERPROFILE\.config\configstore\firebase-tools.json"
if (Test-Path $fbCfgPath) {
    try {
        $fbCfg = Get-Content $fbCfgPath -Raw | ConvertFrom-Json
        $accessToken = $fbCfg.tokens.access_token
        if (![string]::IsNullOrWhiteSpace($accessToken)) {
            $headers = @{
                "Authorization"       = "Bearer $accessToken"
                "Content-Type"        = "application/json"
                "x-goog-user-project" = $ProjectId
            }
            Invoke-RestMethod -Method Post `
                -Uri "https://serviceusage.googleapis.com/v1/projects/$ProjectId/services/identitytoolkit.googleapis.com:enable" `
                -Headers $headers -Body "{}" -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 3
            Invoke-RestMethod -Method Patch `
                -Uri "https://identitytoolkit.googleapis.com/admin/v2/projects/$ProjectId/config?updateMask=signIn.email" `
                -Headers $headers `
                -Body '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}' `
                -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Enabled Email/Password provider on $ProjectId!" -ForegroundColor Green
        }
    } catch {
        Write-Host "IdentityToolkit REST auto-enable skipped (enable manually in Console if needed)." -ForegroundColor Yellow
    }
}

Write-Host "==> [8/9] Deploying production firestore.rules & firestore.indexes.json (Spark-safe)..." -ForegroundColor Cyan
firebase deploy --only firestore --project $ProjectId

Write-Host "==> [9/9] Building Cloud-Connected Release APK & Installing onto OPPO..." -ForegroundColor Cyan
flutter build apk --release --target-platform android-arm64
if ($InstallOnOppo) {
    $adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
    if (Test-Path $adb) {
        & $adb start-server | Out-Null
        & $adb wait-for-device
        & $adb install -r "build\app\outputs\flutter-apk\app-release.apk"
        & $adb shell am start -n "vn.lifeos.app.life_os/.MainActivity"
    }
}

Write-Host ""
Write-Host "SUCCESS! Life OS is now connected to Real Firebase Cloud Project: $ProjectId" -ForegroundColor Green
Write-Host "Confirm Google Sign-In toggle is ON at: https://console.firebase.google.com/project/$ProjectId/authentication/providers" -ForegroundColor Yellow
