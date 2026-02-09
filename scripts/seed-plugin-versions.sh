#!/bin/bash
# ============================================================
# seed-plugin-versions.sh
# Upload pre-built plugin binaries to the VMS License Server
# 
# This script takes the pre-built .so files from 
# vms-server-releases/analytics-plugins/plugins/ and uploads
# them to the license server's plugin version API.
#
# Usage:
#   ./scripts/seed-plugin-versions.sh <LICENSE_SERVER_URL> <ADMIN_TOKEN> [VERSION]
#
# Example:
#   ./scripts/seed-plugin-versions.sh https://license.example.com eyJhbGc... 1.2.0
# ============================================================

set -e

LICENSE_SERVER="${1:?Usage: $0 <LICENSE_SERVER_URL> <ADMIN_TOKEN> [VERSION]}"
TOKEN="${2:?Usage: $0 <LICENSE_SERVER_URL> <ADMIN_TOKEN> [VERSION]}"
VERSION="${3:-1.2.0}"
PLUGINS_DIR="$(dirname "$0")/../analytics-plugins/plugins"

if [ ! -d "$PLUGINS_DIR" ]; then
  echo "Error: Plugin directory not found: $PLUGINS_DIR"
  echo "Run this script from the vms-server-releases directory"
  exit 1
fi

# Mapping: .so filename → license server plugin slug
declare -A SLUG_MAP=(
  ["libobject_detection_analytics_plugin.so"]="analytics"
  ["libface_detection_analytics_plugin.so"]="face-recognition"
  ["liblicense_plate_analytics_plugin.so"]="license-plate"
  ["libblister_pack_analytics_plugin.so"]="blister-pack"
  ["libfall_detection_analytics_plugin.so"]="fall-detection"
  ["libperson_recognition_analytics_plugin.so"]="person-recognition"
  ["libpeople_counter_analytics_plugin.so"]="people-counting"
  ["libroi_analytics_plugin.so"]="intrusion-detection"
)

echo "=== VMS Plugin Version Seeder ==="
echo "License Server: $LICENSE_SERVER"
echo "Version: $VERSION"
echo "Plugins Dir: $PLUGINS_DIR"
echo ""

# Fetch plugin catalog from license server
echo "Fetching plugin catalog..."
CATALOG=$(curl -s -H "Authorization: Bearer $TOKEN" "$LICENSE_SERVER/api/plugins")
if echo "$CATALOG" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  PLUGIN_COUNT=$(echo "$CATALOG" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  echo "Found $PLUGIN_COUNT plugins in license server"
else
  echo "Error: Failed to fetch plugin catalog"
  echo "Response: $CATALOG"
  exit 1
fi

uploaded=0
skipped=0
failed=0

for so_file in "$PLUGINS_DIR"/lib*.so; do
  [ -f "$so_file" ] || continue
  
  filename=$(basename "$so_file")
  slug="${SLUG_MAP[$filename]:-}"
  
  if [ -z "$slug" ]; then
    echo "SKIP: No slug mapping for $filename"
    skipped=$((skipped + 1))
    continue
  fi
  
  # Get plugin ID from slug
  plugin_id=$(echo "$CATALOG" | python3 -c "
import sys,json
plugins = json.load(sys.stdin)
for p in plugins:
    if p.get('slug') == '$slug':
        print(p['id'])
        break
" 2>/dev/null)
  
  if [ -z "$plugin_id" ]; then
    echo "SKIP: Plugin '$slug' not found in license server"
    skipped=$((skipped + 1))
    continue
  fi
  
  filesize=$(stat -c%s "$so_file" 2>/dev/null || stat -f%z "$so_file" 2>/dev/null)
  echo -n "Uploading $filename → $slug ($plugin_id) v$VERSION ($(( filesize / 1024 ))KB)... "
  
  result=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@$so_file" \
    -F "version=$VERSION" \
    -F "platform=linux_x64" \
    -F "is_latest=1" \
    -F "changelog=Seeded from pre-built binaries" \
    "$LICENSE_SERVER/api/plugins/$plugin_id/versions")
  
  http_code=$(echo "$result" | tail -1)
  body=$(echo "$result" | sed '$d')
  
  if [ "$http_code" = "201" ]; then
    echo "OK ✓"
    uploaded=$((uploaded + 1))
  elif [ "$http_code" = "409" ]; then
    echo "ALREADY EXISTS (skip)"
    skipped=$((skipped + 1))
  else
    echo "FAILED (HTTP $http_code)"
    echo "  Response: $body"
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== Summary ==="
echo "Uploaded: $uploaded"
echo "Skipped:  $skipped"
echo "Failed:   $failed"
echo ""

if [ $uploaded -gt 0 ]; then
  echo "Plugin binaries are now available for auto-download by VMS servers!"
  echo "When an admin adds a plugin to a customer's license, the VMS server"
  echo "will automatically download the binary from the license server."
fi
