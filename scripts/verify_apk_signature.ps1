[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ApkPath,

    [Parameter(Position = 1)]
    [ValidateSet('github', 'play')]
    [string]$Channel = 'github',

    [string]$ExpectedCertsFile = '',

    [string]$ExpectedSha256 = $env:LIFEOS_EXPECTED_CERT_SHA256
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir '..')).Path
}

function Resolve-ApkSignerPath {
    $cmd = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    $sdkRoots = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($sdkRoot in $sdkRoots) {
        $buildToolsDir = Join-Path $sdkRoot 'build-tools'
        if (-not (Test-Path $buildToolsDir)) { continue }
        $versions = Get-ChildItem -Path $buildToolsDir -Directory | Sort-Object {
            try { [version]$_.Name } catch { [version]'0.0.0' }
        } -Descending
        foreach ($verDir in $versions) {
            foreach ($candidateName in @('apksigner.bat', 'apksigner.exe', 'apksigner')) {
                $candidate = Join-Path $verDir.FullName $candidateName
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }
    throw 'apksigner not found on PATH or inside ANDROID_HOME/ANDROID_SDK_ROOT/build-tools.'
}

function Normalize-Sha256([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $cleaned = $Raw.Trim().ToLowerInvariant()
    if ($cleaned.StartsWith('sha256:')) {
        $cleaned = $cleaned.Substring(7).Trim()
    }
    return ($cleaned -replace '[:\s-]', '')
}

function Test-IsPlaceholderOrInvalidSha256([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $true }
    $upper = $Raw.Trim().ToUpperInvariant()
    if ($upper.Contains('REPLACE_WITH') -or $upper.Contains('PLACEHOLDER') -or $upper.Contains('CHANGE_ME')) {
        return $true
    }
    $norm = Normalize-Sha256 $Raw
    return -not ($norm -match '^[0-9a-f]{64}$')
}

$repoRoot = Resolve-RepoRoot
if ([string]::IsNullOrWhiteSpace($ExpectedCertsFile)) {
    $ExpectedCertsFile = Join-Path $repoRoot 'android\signing\expected_certs.json'
}

if (-not (Test-Path -Path $ApkPath -PathType Leaf)) {
    Write-Error "FAIL: APK file not found: $ApkPath"
    exit 1
}

$resolvedApk = (Resolve-Path $ApkPath).Path
$apkSize = (Get-Item $resolvedApk).Length
if ($apkSize -le 0) {
    Write-Error "FAIL: APK file is empty: $resolvedApk"
    exit 1
}

$fileSha256 = (Get-FileHash -Path $resolvedApk -Algorithm SHA256).Hash.ToLowerInvariant()
$gitCommit = 'unknown'
try {
    $rev = (& git -C $repoRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rev)) {
        $gitCommit = $rev.Trim()
    }
} catch {}

Write-Host '=== LifeOS APK Signature Verification ==='
Write-Host "APK Path        : $resolvedApk"
Write-Host "Channel         : $Channel"
Write-Host "Git Commit      : $gitCommit"
Write-Host "APK File SHA-256: $fileSha256"

$apksigner = Resolve-ApkSignerPath
Write-Host "apksigner       : $apksigner"

$verifyOutputLines = & $apksigner verify --verbose --print-certs $resolvedApk 2>&1
$verifyExit = $LASTEXITCODE
$verifyOutputText = ($verifyOutputLines | Out-String)
Write-Host $verifyOutputText

if ($verifyExit -ne 0) {
    Write-Error "FAIL: apksigner verify failed with exit code $verifyExit."
    exit 1
}

$signerDns = @()
$signerSha256s = @()
foreach ($line in $verifyOutputLines) {
    $lineStr = "$line"
    if ($lineStr -match 'Signer\s+(?:#\d+|\([^)]+\))\s+certificate DN:\s*(.+)$') {
        $signerDns += $Matches[1].Trim()
    }
    if ($lineStr -match 'Signer\s+(?:#\d+|\([^)]+\))\s+certificate SHA-256 digest:\s*([0-9a-fA-F:]+)\s*$') {
        $signerSha256s += (Normalize-Sha256 $Matches[1])
    }
}

if ($signerSha256s.Count -eq 0) {
    Write-Error 'FAIL: Could not extract any signer certificate SHA-256 digest from apksigner output.'
    exit 1
}

$failures = New-Object System.Collections.Generic.List[string]

$rejectedDnSubstrings = @('CN=Android Debug')
$rejectedCertSha256s = @('3c1738043f4ed47e6f5f5724ab3e9fd0b24e89fde667af43670cb630e4d5176b')
$allowedLineageSha256s = @()
$expectedRaw = $ExpectedSha256

if (Test-Path -Path $ExpectedCertsFile -PathType Leaf) {
    $certConfig = Get-Content -Path $ExpectedCertsFile -Raw | ConvertFrom-Json
    if ($certConfig.rejected_signer_dn_substrings) {
        $rejectedDnSubstrings = @($certConfig.rejected_signer_dn_substrings)
    }
    if ($certConfig.rejected_cert_sha256s) {
        $rejectedCertSha256s = @($certConfig.rejected_cert_sha256s | ForEach-Object { Normalize-Sha256 "$_" })
    }
    $channelCfg = $certConfig.channels.$Channel
    if (-not $channelCfg) {
        $failures.Add("Channel '$Channel' missing from $ExpectedCertsFile.")
    } else {
        if ([string]::IsNullOrWhiteSpace($expectedRaw)) {
            $expectedRaw = "$($channelCfg.cert_sha256)"
            if ($channelCfg.lineage_cert_sha256s) {
                foreach ($lin in $channelCfg.lineage_cert_sha256s) {
                    if (Test-IsPlaceholderOrInvalidSha256 "$lin") {
                        $failures.Add("Placeholder or invalid SHA-256 found in $ExpectedCertsFile ($Channel.lineage_cert_sha256s): $lin")
                    } else {
                        $allowedLineageSha256s += (Normalize-Sha256 "$lin")
                    }
                }
            }
        }
    }
} elseif ([string]::IsNullOrWhiteSpace($expectedRaw)) {
    $failures.Add("Expected certs file not found ($ExpectedCertsFile) and no ExpectedSha256 provided.")
}

foreach ($dn in $signerDns) {
    foreach ($blockedDn in $rejectedDnSubstrings) {
        if ($dn.IndexOf("$blockedDn", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $failures.Add("REJECTED: APK carries forbidden debug/rejected signer DN '$dn' (matched '$blockedDn').")
        }
    }
}

foreach ($digest in $signerSha256s) {
    if ($rejectedCertSha256s -contains $digest) {
        $failures.Add("REJECTED: APK signer SHA-256 '$digest' is explicitly blocked (Android Debug certificate).")
    }
}

if (Test-IsPlaceholderOrInvalidSha256 $expectedRaw) {
    $failures.Add("REJECTED: Expected certificate SHA-256 for channel '$Channel' is still a placeholder or invalid hex: '$expectedRaw'. Update $ExpectedCertsFile or pass -ExpectedSha256 / LIFEOS_EXPECTED_CERT_SHA256.")
} else {
    $expectedNorm = Normalize-Sha256 $expectedRaw
    Write-Host "Expected Cert   : $expectedNorm"
    $activeSigner = $signerSha256s[$signerSha256s.Count - 1]
    if ($activeSigner -ne $expectedNorm) {
        $failures.Add("REJECTED: APK active signer SHA-256 '$activeSigner' does NOT match expected '$expectedNorm' for channel '$Channel'.")
    }
    foreach ($digest in $signerSha256s) {
        if ($digest -ne $expectedNorm -and ($allowedLineageSha256s -notcontains $digest)) {
            $failures.Add("REJECTED: APK signer SHA-256 '$digest' is neither expected '$expectedNorm' nor an approved lineage cert for channel '$Channel'.")
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) {
        Write-Host $f -ForegroundColor Red
    }
    exit 1
}

Write-Host "PASS: APK signature verified for channel '$Channel' (commit $gitCommit, file SHA-256 $fileSha256)." -ForegroundColor Green
exit 0
