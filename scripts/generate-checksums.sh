#!/usr/bin/env bash
set -euo pipefail

# Generate SHA256SUMS for release assets in current directory.
# Usage:
#   ./scripts/generate-checksums.sh
#   ./scripts/generate-checksums.sh /path/to/release-dir
#   ./scripts/generate-checksums.sh /path/to/release-dir --sign
#
# Optional env vars for signing:
#   VMS_SIGNING_KEY=/secure/path/release-signing-private.pem
#   VMS_SIGNING_PUBKEY=/path/to/signing/release-signing.pub.pem

TARGET_DIR="${1:-.}"
DO_SIGN="${2:-}"
cd "$TARGET_DIR"

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "[ERR] sha256sum not found" >&2
  exit 1
fi

assets=(
  "vms-server-linux-x64.tar.gz"
  "vms-server-linux-arm64.tar.gz"
  "vms-server-windows-x64.zip"
  "analytics-plugins.tar.gz"
  "install.sh"
  "install.ps1"
)

: > SHA256SUMS
found=0
for file in "${assets[@]}"; do
  if [[ -f "$file" ]]; then
    sha256sum "$file" >> SHA256SUMS
    found=$((found + 1))
  fi
done

if [[ $found -eq 0 ]]; then
  echo "[ERR] No known release assets found in $TARGET_DIR" >&2
  rm -f SHA256SUMS
  exit 1
fi

echo "[OK] Generated SHA256SUMS with $found entries"
sha256sum SHA256SUMS | awk '{print "[INFO] SHA256SUMS digest: "$1}'

if [[ "$DO_SIGN" == "--sign" ]]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "[ERR] openssl not found (required for signing)" >&2
    exit 1
  fi

  SIGNING_KEY="${VMS_SIGNING_KEY:-/root/.vms-signing/release-signing-private.pem}"
  SIGNING_PUBKEY="${VMS_SIGNING_PUBKEY:-signing/release-signing.pub.pem}"

  if [[ ! -f "$SIGNING_KEY" ]]; then
    echo "[ERR] Signing key not found: $SIGNING_KEY" >&2
    exit 1
  fi
  if [[ ! -f "$SIGNING_PUBKEY" ]]; then
    echo "[ERR] Signing public key not found: $SIGNING_PUBKEY" >&2
    exit 1
  fi

  openssl dgst -sha256 -sign "$SIGNING_KEY" -out SHA256SUMS.sig SHA256SUMS
  openssl dgst -sha256 -verify "$SIGNING_PUBKEY" -signature SHA256SUMS.sig SHA256SUMS >/dev/null
  echo "[OK] Signed SHA256SUMS -> SHA256SUMS.sig"

  if [[ -f "install.sh" ]]; then
    openssl dgst -sha256 -sign "$SIGNING_KEY" -out install.sh.sig install.sh
    openssl dgst -sha256 -verify "$SIGNING_PUBKEY" -signature install.sh.sig install.sh >/dev/null
    echo "[OK] Signed install.sh -> install.sh.sig"
  else
    echo "[WARN] install.sh not found, skipped install.sh.sig"
  fi

  if [[ -f "install.ps1" ]]; then
    openssl dgst -sha256 -sign "$SIGNING_KEY" -out install.ps1.sig install.ps1
    openssl dgst -sha256 -verify "$SIGNING_PUBKEY" -signature install.ps1.sig install.ps1 >/dev/null
    echo "[OK] Signed install.ps1 -> install.ps1.sig"
  else
    echo "[WARN] install.ps1 not found, skipped install.ps1.sig"
  fi
fi
