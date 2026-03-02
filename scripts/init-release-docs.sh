#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
OUT_DIR="${2:-release-docs}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: ./scripts/init-release-docs.sh <version> [output-dir]" >&2
  exit 1
fi

DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$OUT_DIR"

copy_template() {
  local src="$1"
  local dst="$2"
  cp "$src" "$dst"
  sed -i "s/{{VERSION}}/$VERSION/g" "$dst"
  sed -i "s/{{DATE_UTC}}/$DATE_UTC/g" "$dst"
}

copy_template "templates/RELEASE_NOTES_SECURITY_TEMPLATE.md" "$OUT_DIR/RELEASE_NOTES_SECURITY_${VERSION}.md"
copy_template "templates/SECURITY_BYPASS_INCIDENT_TEMPLATE.md" "$OUT_DIR/SECURITY_BYPASS_INCIDENT_${VERSION}.md"

echo "[OK] Created release docs in $OUT_DIR"
ls -1 "$OUT_DIR"
