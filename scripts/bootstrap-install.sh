#!/usr/bin/env bash
set -euo pipefail

REPO="${VMS_RELEASE_REPO:-trinhtanphat/vms-server-releases}"
VERSION="${1:-latest}"
PINNED_KEY_HASH="${TRUSTED_SIGNING_PUBKEY_SHA256:-46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc}"

TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ "$VERSION" == "latest" ]]; then
  BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
  BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi
PUBKEY_URL="https://raw.githubusercontent.com/${REPO}/main/signing/release-signing.pub.pem"

cd "$TMP_DIR"

curl -fsSLo install.sh "$BASE_URL/install.sh"
curl -fsSLo install.sh.sig "$BASE_URL/install.sh.sig"
curl -fsSLo release-signing.pub.pem "$PUBKEY_URL"

echo "${PINNED_KEY_HASH}  release-signing.pub.pem" | sha256sum -c -
openssl dgst -sha256 -verify release-signing.pub.pem -signature install.sh.sig install.sh >/dev/null

echo "[OK] Installer signature verified"

if [[ $EUID -eq 0 ]]; then
  bash ./install.sh
else
  sudo bash ./install.sh
fi
