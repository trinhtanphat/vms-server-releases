#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"
cd "$ROOT_DIR"

PINNED_KEY_HASH="46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc"

require_file() {
  local f="$1"
  [[ -f "$f" ]] || { echo "[ERR] Missing file: $f" >&2; exit 1; }
}

echo "[INFO] Running security regression checks in $PWD"

require_file "install.sh"
require_file "install.ps1"
require_file "SHA256SUMS"
require_file "SHA256SUMS.sig"
require_file "install.sh.sig"
require_file "install.ps1.sig"
require_file "signing/release-signing.pub.pem"

actual_hash=$(sha256sum signing/release-signing.pub.pem | awk '{print $1}')
if [[ "$actual_hash" != "$PINNED_KEY_HASH" ]]; then
  echo "[ERR] Public key hash mismatch" >&2
  echo "      expected=$PINNED_KEY_HASH" >&2
  echo "      actual=$actual_hash" >&2
  exit 1
fi

echo "[OK] Public key hash matches pinned value"

openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.sh.sig install.sh >/dev/null
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.ps1.sig install.ps1 >/dev/null
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature SHA256SUMS.sig SHA256SUMS >/dev/null

echo "[OK] Detached signatures verified"

sha256sum -c SHA256SUMS >/dev/null

echo "[OK] SHA256SUMS entries verified"

bash -n install.sh

grep -q 'Refusing to run unsigned installer from stdin/pipe' install.sh
grep -q 'Refusing to run unsigned installer from stdin/pipe' install.ps1
grep -q 'REQUIRE_INSTALLER_SIGNATURE="\${REQUIRE_INSTALLER_SIGNATURE:-1}"' install.sh
grep -q 'RequireInstallerSignature = \$true' install.ps1
grep -q 'AUTO_ROLLBACK="\${AUTO_ROLLBACK:-1}"' install.sh
grep -q 'NX_TRUST_CHAIN_URL=' install.sh

set +e
cat install.sh | bash >/tmp/vms-stdin-block-test.log 2>&1
stdin_exit=$?
set -e
if [[ $stdin_exit -eq 0 ]]; then
  echo "[ERR] install.sh unexpectedly allowed stdin execution" >&2
  exit 1
fi
grep -q 'Refusing to run unsigned installer from stdin/pipe' /tmp/vms-stdin-block-test.log

echo "[OK] Insecure bootstrap protections present"

echo "[PASS] Security regression checks completed"
