param(
    [string]$Version = "latest",
    [string]$Repo = "trinhtanphat/vms-server-releases",
    [string]$TrustedSigningPubKeySha256 = "46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc",
    [string[]]$InstallerArgs
)

$ErrorActionPreference = "Stop"

if ($Version -eq "latest") {
    $base = "https://github.com/$Repo/releases/latest/download"
} else {
    $base = "https://github.com/$Repo/releases/download/$Version"
}
$pub = "https://raw.githubusercontent.com/$Repo/main/signing/release-signing.pub.pem"

if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    throw "openssl is required for signature verification"
}

$tmp = Join-Path $env:TEMP "vms-bootstrap-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Push-Location $tmp

try {
    Invoke-WebRequest -Uri "$base/install.ps1" -OutFile "install.ps1"
    Invoke-WebRequest -Uri "$base/install.ps1.sig" -OutFile "install.ps1.sig"
    Invoke-WebRequest -Uri $pub -OutFile "release-signing.pub.pem"

    $actual = (Get-FileHash .\release-signing.pub.pem -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $TrustedSigningPubKeySha256.ToLowerInvariant()) {
        throw "Public key hash mismatch. Expected=$TrustedSigningPubKeySha256 Actual=$actual"
    }

    & openssl dgst -sha256 -verify .\release-signing.pub.pem -signature .\install.ps1.sig .\install.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Installer signature verification failed"
    }

    Write-Host "[OK] Installer signature verified" -ForegroundColor Green
    if ($InstallerArgs) {
        & .\install.ps1 @InstallerArgs
    } else {
        & .\install.ps1
    }
}
finally {
    Pop-Location
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
