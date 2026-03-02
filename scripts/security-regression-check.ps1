param(
    [string]$Root = ".",
    [string]$PinnedPubKeyHash = "46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc"
)

$ErrorActionPreference = "Stop"
Set-Location $Root

function Require-File([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "Missing file: $Path"
    }
}

Require-File "install.ps1"
Require-File "install.ps1.sig"
Require-File "install.sh"
Require-File "install.sh.sig"
Require-File "SHA256SUMS"
Require-File "SHA256SUMS.sig"
Require-File "signing/release-signing.pub.pem"

if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    throw "openssl is required"
}

$pubHash = (Get-FileHash "signing/release-signing.pub.pem" -Algorithm SHA256).Hash.ToLowerInvariant()
if ($pubHash -ne $PinnedPubKeyHash.ToLowerInvariant()) {
    throw "Public key hash mismatch. expected=$PinnedPubKeyHash actual=$pubHash"
}

& openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.ps1.sig install.ps1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "install.ps1 signature verify failed" }

& openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.sh.sig install.sh | Out-Null
if ($LASTEXITCODE -ne 0) { throw "install.sh signature verify failed" }

& openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature SHA256SUMS.sig SHA256SUMS | Out-Null
if ($LASTEXITCODE -ne 0) { throw "SHA256SUMS signature verify failed" }

$ps1 = Get-Content install.ps1 -Raw
if ($ps1 -notmatch 'Refusing to run unsigned installer from stdin/pipe') {
    throw "Missing stdin/pipe protection message in install.ps1"
}
if ($ps1 -notmatch 'RequireInstallerSignature = \$true') {
    throw "RequireInstallerSignature default missing"
}

$sh = Get-Content install.sh -Raw
if ($sh -notmatch 'AUTO_ROLLBACK="\$\{AUTO_ROLLBACK:-1\}"') {
    throw "AUTO_ROLLBACK default missing"
}
if ($sh -notmatch 'NX_TRUST_CHAIN_URL') {
    throw "NX trust-chain option missing"
}

Write-Host "[PASS] PowerShell security regression checks completed" -ForegroundColor Green
