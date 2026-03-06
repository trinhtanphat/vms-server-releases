#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build/repackage Linux release asset with version synchronized to release tag.

Usage:
  scripts/build-linux-release-asset.sh \
    --version v0.0.2 \
    [--source-ref v0.0.2] \
    [--source-repo https://github.com/trinhtanphat/vms-server.git] \
    [--work-dir /tmp/vms-release-build]

Outputs:
  - vms-server-linux-x64/vms-server (updated)
  - vms-server-linux-x64/lib/libvms-*.so* (updated)
  - vms-server-linux-x64.tar.gz (repacked)
EOF
}

VERSION_TAG=""
SOURCE_REF=""
SOURCE_REPO="https://github.com/trinhtanphat/vms-server.git"
WORK_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION_TAG="$2"
      shift 2
      ;;
    --source-ref)
      SOURCE_REF="$2"
      shift 2
      ;;
    --source-repo)
      SOURCE_REPO="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION_TAG" ]]; then
  echo "Missing required --version" >&2
  usage
  exit 1
fi

if [[ -z "$SOURCE_REF" ]]; then
  SOURCE_REF="$VERSION_TAG"
fi

VERSION_NUM="${VERSION_TAG#v}"
if [[ ! "$VERSION_NUM" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version format: $VERSION_TAG (expected vX.Y.Z or X.Y.Z)" >&2
  exit 1
fi

IFS='.' read -r VMAJ VMIN VPAT <<< "$VERSION_NUM"

if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="$(mktemp -d)"
  CLEANUP_WORK=1
else
  mkdir -p "$WORK_DIR"
  CLEANUP_WORK=0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$WORK_DIR/vms-server-src"
BUILD_DIR="$WORK_DIR/vms-server-build"
INSTALL_DIR="$WORK_DIR/vms-server-install"

cleanup() {
  if [[ "$CLEANUP_WORK" == "1" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

echo "[build-release] version tag: $VERSION_TAG"
echo "[build-release] source ref:  $SOURCE_REF"
echo "[build-release] source repo: $SOURCE_REPO"
echo "[build-release] work dir:    $WORK_DIR"

rm -rf "$SRC_DIR" "$BUILD_DIR" "$INSTALL_DIR"

git clone "$SOURCE_REPO" "$SRC_DIR"
git -C "$SRC_DIR" checkout "$SOURCE_REF"

# Force source metadata to match release tag to avoid version drift in runtime APIs/UI.
sed -i -E "s/project\(vms-server VERSION [0-9]+\.[0-9]+\.[0-9]+ LANGUAGES CXX\)/project(vms-server VERSION ${VERSION_NUM} LANGUAGES CXX)/" "$SRC_DIR/CMakeLists.txt"
sed -i -E "s/#define VMS_VERSION_MAJOR .*/#define VMS_VERSION_MAJOR ${VMAJ}/" "$SRC_DIR/include/vms/core/version.h"
sed -i -E "s/#define VMS_VERSION_MINOR .*/#define VMS_VERSION_MINOR ${VMIN}/" "$SRC_DIR/include/vms/core/version.h"
sed -i -E "s/#define VMS_VERSION_PATCH .*/#define VMS_VERSION_PATCH ${VPAT}/" "$SRC_DIR/include/vms/core/version.h"
sed -i -E "s/#define VMS_VERSION_STRING \".*\"/#define VMS_VERSION_STRING \"${VERSION_NUM}\"/" "$SRC_DIR/include/vms/core/version.h"

cmake -S "$SRC_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" -j"$(nproc)"
cmake --install "$BUILD_DIR" --prefix "$INSTALL_DIR"

if [[ ! -f "$INSTALL_DIR/bin/vms-server" ]]; then
  echo "Build output missing: $INSTALL_DIR/bin/vms-server" >&2
  exit 1
fi

if [[ ! -d "$RELEASE_REPO_DIR/vms-server-linux-x64/lib" ]]; then
  echo "Release folder missing: $RELEASE_REPO_DIR/vms-server-linux-x64/lib" >&2
  exit 1
fi

cp -f "$INSTALL_DIR/bin/vms-server" "$RELEASE_REPO_DIR/vms-server-linux-x64/vms-server"
rm -f "$RELEASE_REPO_DIR/vms-server-linux-x64/lib/libvms-"*.so*
cp -a "$BUILD_DIR/lib/libvms-"*.so* "$RELEASE_REPO_DIR/vms-server-linux-x64/lib/"

cd "$RELEASE_REPO_DIR"
rm -f vms-server-linux-x64.tar.gz
tar -czf vms-server-linux-x64.tar.gz vms-server-linux-x64

echo "[build-release] Verifying embedded server version..."
if ! strings vms-server-linux-x64/vms-server | grep -q "${VERSION_NUM}"; then
  echo "[build-release] ERROR: built binary does not contain expected version ${VERSION_NUM}" >&2
  exit 1
fi
echo "[build-release] OK: binary contains version ${VERSION_NUM}"

echo "[build-release] SHA256:"
sha256sum vms-server-linux-x64/vms-server vms-server-linux-x64.tar.gz

echo "[build-release] Done. Artifact: $RELEASE_REPO_DIR/vms-server-linux-x64.tar.gz"
