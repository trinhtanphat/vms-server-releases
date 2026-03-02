#!/bin/bash
#
# VMS Server Installation Script for Linux
# Installs VMS Server + Nginx + SSL + Web Client — all-in-one
#
# Usage:
#   1) Download install.sh + install.sh.sig + release signing public key
#   2) Verify public key hash and installer signature
#   3) Run: sudo bash ./install.sh
#
# Or with a specific version:
#   Use releases/download/<tag>/install.sh and matching install.sh.sig
#
# Options (environment variables):
#   DOMAIN=myserver.example.com   - Domain name for SSL (auto-detected if not set)
#   EMAIL=admin@example.com       - Email for Let's Encrypt (default: admin@$DOMAIN)
#   SKIP_NGINX=1                  - Skip nginx/SSL setup
#   SKIP_WEB_CLIENT=1             - Skip web client deployment
#   VMS_VERSION=v0.5.0            - Install specific version
#   REQUIRE_CHECKSUMS=1           - Require SHA256 verification for release assets (default: 1)
#   ALLOW_UNVERIFIED=1            - Allow install to continue when checksums are unavailable
#   REQUIRE_SIGNATURES=1          - Require signature verification for checksum manifest (default: 1)
#   ALLOW_UNSIGNED=1              - Allow install when checksum signature is missing/invalid
#   REQUIRE_INSTALLER_SIGNATURE=1 - Require install.sh signature verification (default: 1)
#   ALLOW_INSECURE_BOOTSTRAP=1    - Allow running installer from stdin without signature (emergency)
#   NX_INSECURE_TLS=1             - Disable TLS verify for NX upstream proxy (emergency only)
#   NX_TRUST_CHAIN_URL=<url>      - URL to NX upstream CA/server chain PEM
#   NX_TRUST_CHAIN_PATH=<path>    - Local path to NX upstream CA/server chain PEM
#   AUTO_ROLLBACK=1               - Auto-restore previous install on upgrade failure (default: 1)
#   TRUSTED_SIGNING_PUBKEY_SHA256 - Override pinned SHA256 of release signing public key
#

set -e

# ============================================================
# Colors & Helpers
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC}  $*"; }
step()  { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${NC}"; }

# ============================================================
# Configuration
# ============================================================
INSTALL_DIR="/opt/vms-server"
CONFIG_DIR="/etc/vms-server"
DATA_DIR="/var/lib/vms-server"
LOG_DIR="/var/log/vms-server"
PLUGIN_DIR="/usr/lib/vms-server/plugins"
WEB_DIR="/var/www/html/vms-client"
SERVICE_NAME="vms-server"
GITHUB_REPO="trinhtanphat/vms-server-releases"
WEB_CLIENT_REPO="trinhtanphat/vms-client-web"
REQUIRE_CHECKSUMS="${REQUIRE_CHECKSUMS:-1}"
ALLOW_UNVERIFIED="${ALLOW_UNVERIFIED:-0}"
REQUIRE_SIGNATURES="${REQUIRE_SIGNATURES:-1}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"
REQUIRE_INSTALLER_SIGNATURE="${REQUIRE_INSTALLER_SIGNATURE:-1}"
ALLOW_INSECURE_BOOTSTRAP="${ALLOW_INSECURE_BOOTSTRAP:-0}"
NX_INSECURE_TLS="${NX_INSECURE_TLS:-0}"
NX_TRUST_CHAIN_URL="${NX_TRUST_CHAIN_URL:-}"
NX_TRUST_CHAIN_PATH="${NX_TRUST_CHAIN_PATH:-}"
AUTO_ROLLBACK="${AUTO_ROLLBACK:-1}"
TRUSTED_SIGNING_PUBKEY_SHA256="${TRUSTED_SIGNING_PUBKEY_SHA256:-46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc}"
CHECKSUM_FILE=""
CHECKSUM_ASSET_NAME=""
SIGNATURE_FILE=""
SIGNING_PUBKEY_FILE=""
BACKUP_ROOT="/var/backups/vms-server"
BACKUP_DIR=""
UPGRADING=false
INSTALL_COMPLETED=0

cleanup_security_artifacts() {
    [ -n "${CHECKSUM_FILE}" ] && [ -f "${CHECKSUM_FILE}" ] && rm -f "${CHECKSUM_FILE}" || true
    [ -n "${SIGNATURE_FILE}" ] && [ -f "${SIGNATURE_FILE}" ] && rm -f "${SIGNATURE_FILE}" || true
    [ -n "${SIGNING_PUBKEY_FILE}" ] && [ -f "${SIGNING_PUBKEY_FILE}" ] && rm -f "${SIGNING_PUBKEY_FILE}" || true
}
trap cleanup_security_artifacts EXIT

backup_path() {
    local src_path="$1"
    local label="$2"
    if [ -e "$src_path" ]; then
        tar -C / -czf "$BACKUP_DIR/${label}.tgz" "${src_path#/}" 2>/dev/null || true
    fi
}

restore_path() {
    local archive="$1"
    local target_path="$2"
    if [ -f "$archive" ]; then
        rm -rf "$target_path" 2>/dev/null || true
        tar -C / -xzf "$archive" 2>/dev/null || true
    fi
}

create_upgrade_backup() {
    if [ "$UPGRADING" != true ]; then
        return 0
    fi

    BACKUP_DIR="$BACKUP_ROOT/upgrade-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    info "Creating upgrade backup at $BACKUP_DIR"
    backup_path "$INSTALL_DIR" "install_dir"
    backup_path "$CONFIG_DIR" "config_dir"
    backup_path "$PLUGIN_DIR" "plugin_dir"
    backup_path "/etc/systemd/system/${SERVICE_NAME}.service" "service_unit"
    backup_path "/etc/nginx/sites-available/vms-server" "nginx_site"
    ok "Upgrade backup created"
}

on_install_error() {
    local line_no="$1"
    if [ "$INSTALL_COMPLETED" = "1" ]; then
        return 0
    fi

    err "Installer failed at line ${line_no}"

    if [ "$AUTO_ROLLBACK" = "1" ] && [ "$UPGRADING" = true ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        warn "Attempting automatic rollback from $BACKUP_DIR"
        set +e
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        restore_path "$BACKUP_DIR/install_dir.tgz" "$INSTALL_DIR"
        restore_path "$BACKUP_DIR/config_dir.tgz" "$CONFIG_DIR"
        restore_path "$BACKUP_DIR/plugin_dir.tgz" "$PLUGIN_DIR"
        restore_path "$BACKUP_DIR/service_unit.tgz" "/etc/systemd/system/${SERVICE_NAME}.service"
        restore_path "$BACKUP_DIR/nginx_site.tgz" "/etc/nginx/sites-available/vms-server"
        systemctl daemon-reload 2>/dev/null || true
        systemctl start "$SERVICE_NAME" 2>/dev/null || true
        nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true
        set -e
        warn "Rollback attempt completed. Verify service state manually."
    fi
}
trap 'on_install_error $LINENO' ERR

download_release_checksums() {
    local version="$1"
    local tmp_file=""
    local candidates=("sha256sums.txt" "SHA256SUMS" "checksums.txt")

    for name in "${candidates[@]}"; do
        tmp_file=$(mktemp)
        local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${name}"
        if curl -fsSL "$url" -o "$tmp_file" 2>/dev/null; then
            CHECKSUM_FILE="$tmp_file"
            CHECKSUM_ASSET_NAME="$name"
            ok "Loaded checksum manifest: ${name}"
            return 0
        fi
        rm -f "$tmp_file"
    done

    return 1
}

download_checksum_signature() {
    local version="$1"
    local tmp_file=""
    local candidates=()

    if [ -n "$CHECKSUM_ASSET_NAME" ]; then
        candidates+=("${CHECKSUM_ASSET_NAME}.sig")
    fi
    candidates+=("SHA256SUMS.sig" "sha256sums.txt.sig" "checksums.txt.sig")

    for name in "${candidates[@]}"; do
        tmp_file=$(mktemp)
        local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${name}"
        if curl -fsSL "$url" -o "$tmp_file" 2>/dev/null; then
            SIGNATURE_FILE="$tmp_file"
            ok "Loaded checksum signature: ${name}"
            return 0
        fi
        rm -f "$tmp_file"
    done

    return 1
}

write_trusted_signing_pubkey() {
    SIGNING_PUBKEY_FILE=$(mktemp)
    cat > "$SIGNING_PUBKEY_FILE" << 'PUBKEYEOF'
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAx9byxHJX7faK9CbAtQ7S
7Qf9uqKBcvr/6tMGPIC2hK9WnW7WLWC79vJT6XcAEI0G3ylRhvO14Ao8lsZW6R/l
H6Hi1TZE9xcDTihXttkZv3ep4YfjnXlihzJsqi3pOdQ26yHj9d3hw4K2q9pqbvEO
Kqc8bidijN8nuDpSM0Mj9X6A36GrwaaS1Aazqv5r34GcEP9004zrvGikQ3z0tkqx
IIDSW+JaXDnalP3oXLSCLRIzP2BXiZjlo6UUBJ2zT7cxlmKtnroLRa+3WtCOVQZC
ZH8GNyGZgErJVULAnnzSYWj89K5KrzFDjiDfY+Xm4gBXpd0t8bEFa5/X4XibELJQ
70nXdvxjo45/hLVd2BLPnZjpWmOBR61vwqfMHKo72iubt3Di4hufN5Z65S9+Yhu/
7cQoLzi4FXfL2BCfEZBsWGfXM4iSuCIout9wIKv+MDHUxYXHbxora/tC7fsnBhoj
AVqrkUVrNpONOiM4BDStGatFrg/G5xnmNaOxCSdB5yGDAgMBAAE=
-----END PUBLIC KEY-----
PUBKEYEOF

    local pub_hash
    pub_hash=$(sha256sum "$SIGNING_PUBKEY_FILE" | awk '{print $1}')
    if [ "$pub_hash" != "$TRUSTED_SIGNING_PUBKEY_SHA256" ]; then
        err "Trusted signing key hash mismatch"
        err "Expected: $TRUSTED_SIGNING_PUBKEY_SHA256"
        err "Actual:   $pub_hash"
        exit 1
    fi
}

verify_checksum_signature() {
    if [ -z "$CHECKSUM_FILE" ] || [ ! -f "$CHECKSUM_FILE" ]; then
        err "Cannot verify signature: checksum manifest missing"
        exit 1
    fi

    if [ -z "$SIGNATURE_FILE" ] || [ ! -f "$SIGNATURE_FILE" ]; then
        if [ "$REQUIRE_SIGNATURES" = "1" ] && [ "$ALLOW_UNSIGNED" != "1" ]; then
            err "Checksum signature missing. Refusing untrusted install."
            err "Set ALLOW_UNSIGNED=1 only for emergency/non-production installs."
            exit 1
        fi
        warn "Checksum signature missing — skipping signature verification"
        return 0
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        if [ "$REQUIRE_SIGNATURES" = "1" ] && [ "$ALLOW_UNSIGNED" != "1" ]; then
            err "openssl is required for signature verification"
            exit 1
        fi
        warn "openssl not found — skipping signature verification"
        return 0
    fi

    write_trusted_signing_pubkey

    if ! openssl dgst -sha256 -verify "$SIGNING_PUBKEY_FILE" -signature "$SIGNATURE_FILE" "$CHECKSUM_FILE" >/dev/null 2>&1; then
        if [ "$REQUIRE_SIGNATURES" = "1" ] && [ "$ALLOW_UNSIGNED" != "1" ]; then
            err "Checksum signature verification failed"
            err "Set ALLOW_UNSIGNED=1 only for emergency/non-production installs."
            exit 1
        fi
        warn "Checksum signature verification failed — continuing because ALLOW_UNSIGNED=1"
        return 0
    fi

    ok "Checksum signature verified"
}

verify_installer_signature() {
    local script_source="${BASH_SOURCE[0]:-}"

    if [ -z "$script_source" ] || [ ! -f "$script_source" ]; then
        if [ "$REQUIRE_INSTALLER_SIGNATURE" = "1" ] && [ "$ALLOW_INSECURE_BOOTSTRAP" != "1" ]; then
            err "Refusing to run unsigned installer from stdin/pipe."
            err "Use secure bootstrap: download install.sh + install.sh.sig and verify before running."
            err "Set ALLOW_INSECURE_BOOTSTRAP=1 only for emergency/non-production installs."
            exit 1
        fi
        warn "Installer running from stdin/pipe — signature check skipped"
        return 0
    fi

    local installer_sig="${script_source}.sig"
    if [ ! -f "$installer_sig" ]; then
        if [ "$REQUIRE_INSTALLER_SIGNATURE" = "1" ] && [ "$ALLOW_INSECURE_BOOTSTRAP" != "1" ]; then
            err "Missing installer signature file: $installer_sig"
            err "Set ALLOW_INSECURE_BOOTSTRAP=1 only for emergency/non-production installs."
            exit 1
        fi
        warn "Installer signature file not found — skipping installer signature verification"
        return 0
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        if [ "$REQUIRE_INSTALLER_SIGNATURE" = "1" ] && [ "$ALLOW_INSECURE_BOOTSTRAP" != "1" ]; then
            err "openssl is required for installer signature verification"
            exit 1
        fi
        warn "openssl not found — skipping installer signature verification"
        return 0
    fi

    write_trusted_signing_pubkey

    if ! openssl dgst -sha256 -verify "$SIGNING_PUBKEY_FILE" -signature "$installer_sig" "$script_source" >/dev/null 2>&1; then
        if [ "$REQUIRE_INSTALLER_SIGNATURE" = "1" ] && [ "$ALLOW_INSECURE_BOOTSTRAP" != "1" ]; then
            err "Installer signature verification failed"
            exit 1
        fi
        warn "Installer signature verification failed — continuing because ALLOW_INSECURE_BOOTSTRAP=1"
        return 0
    fi

    ok "Installer signature verified"
}

verify_asset_checksum() {
    local file_path="$1"
    local asset_name="$2"

    if [ ! -f "$file_path" ]; then
        err "Cannot verify checksum: file not found ($file_path)"
        exit 1
    fi

    if [ -z "$CHECKSUM_FILE" ] || [ ! -f "$CHECKSUM_FILE" ]; then
        if [ "$REQUIRE_CHECKSUMS" = "1" ] && [ "$ALLOW_UNVERIFIED" != "1" ]; then
            err "Checksum manifest missing. Refusing unverified install."
            err "Set ALLOW_UNVERIFIED=1 only for emergency/non-production installs."
            exit 1
        fi
        warn "Checksum manifest missing — skipping verification for ${asset_name}"
        return 0
    fi

    local expected
    expected=$(awk -v name="$asset_name" 'NF>=2 && $NF==name {print $1; exit}' "$CHECKSUM_FILE")
    if [ -z "$expected" ]; then
        expected=$(grep -F "$asset_name" "$CHECKSUM_FILE" | awk '{print $1}' | head -1)
    fi

    if [ -z "$expected" ]; then
        if [ "$REQUIRE_CHECKSUMS" = "1" ] && [ "$ALLOW_UNVERIFIED" != "1" ]; then
            err "Missing checksum entry for ${asset_name}. Refusing install."
            exit 1
        fi
        warn "No checksum entry for ${asset_name} — skipping verification"
        return 0
    fi

    local actual
    actual=$(sha256sum "$file_path" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        err "Checksum mismatch for ${asset_name}"
        err "Expected: ${expected}"
        err "Actual:   ${actual}"
        exit 1
    fi

    ok "Checksum verified: ${asset_name}"
}

# ============================================================
# Banner
# ============================================================
verify_installer_signature

NX_PROXY_SSL_VERIFY="on"
if [ "$NX_INSECURE_TLS" = "1" ]; then
    NX_PROXY_SSL_VERIFY="off"
    warn "NX_INSECURE_TLS=1 enabled — NX upstream TLS verification is disabled"
fi
NX_TRUST_DIRECTIVES=""

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         VMS Server — All-in-One Installer       ║${NC}"
echo -e "${GREEN}║                                                  ║${NC}"
echo -e "${GREEN}║  VMS Server + Nginx + SSL + Web Client           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# Pre-flight Checks
# ============================================================
step "1/8 Pre-flight Checks"

# Must be root
if [ "$EUID" -ne 0 ]; then
    err "Please run as root: curl ... | sudo bash"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    info "OS: $PRETTY_NAME"
else
    err "Cannot detect OS"
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)  ARCH_LABEL="x64" ;;
    aarch64) ARCH_LABEL="arm64" ;;
    *)
        err "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
info "Architecture: $ARCH ($ARCH_LABEL)"

# Detect GPU
GPU_INFO=""
if command -v nvidia-smi &>/dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || true)
    if [ -n "$GPU_INFO" ]; then
        ok "GPU detected: $GPU_INFO"
    fi
elif [ -d /proc/driver/nvidia ]; then
    warn "NVIDIA GPU detected but nvidia-smi not found. Install NVIDIA drivers for GPU plugin support."
fi

# Check for existing installation
if [ -f "$INSTALL_DIR/vms-server" ]; then
    CURRENT_VERSION=$("$INSTALL_DIR/vms-server" --version 2>/dev/null || echo "unknown")
    warn "Existing VMS Server found (version: $CURRENT_VERSION) — upgrading"
    UPGRADING=true
else
    UPGRADING=false
fi

if [ "$UPGRADING" = true ]; then
    create_upgrade_backup
fi

# ============================================================
# Determine Version
# ============================================================
step "2/8 Fetching VMS Server"

if [ -n "$VMS_VERSION" ]; then
    LATEST_VERSION="$VMS_VERSION"
    info "Using specified version: $LATEST_VERSION"
else
    info "Fetching latest version from GitHub..."
    if command -v curl &>/dev/null; then
        LATEST_VERSION=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    elif command -v wget &>/dev/null; then
        LATEST_VERSION=$(wget -qO- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        err "curl or wget is required"
        exit 1
    fi

    if [ -z "$LATEST_VERSION" ]; then
        err "Failed to fetch latest version. Check network connectivity."
        exit 1
    fi
    ok "Latest version: $LATEST_VERSION"
fi

# ============================================================
# Install Runtime Dependencies (FFmpeg)
# ============================================================
step "2.5/8 Installing Runtime Dependencies"

info "Installing FFmpeg runtime libraries..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq libavformat58 libavcodec58 libavutil56 libswscale5 libswresample3 > /dev/null 2>&1 || {
    # Ubuntu 24.04+ uses different package versions
    apt-get install -y -qq libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev > /dev/null 2>&1 || {
        warn "Could not install FFmpeg packages automatically."
        warn "Please install FFmpeg runtime libraries manually: apt-get install ffmpeg"
        apt-get install -y -qq ffmpeg > /dev/null 2>&1 || true
    }
}
ok "FFmpeg runtime libraries installed"

# ============================================================
# Download & Install VMS Server Binary
# ============================================================
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}/vms-server-linux-${ARCH_LABEL}.tar.gz"
ASSET_SERVER="vms-server-linux-${ARCH_LABEL}.tar.gz"

info "Downloading from: $DOWNLOAD_URL"

if download_release_checksums "$LATEST_VERSION"; then
    info "Release checksum verification enabled"
else
    if [ "$REQUIRE_CHECKSUMS" = "1" ] && [ "$ALLOW_UNVERIFIED" != "1" ]; then
        err "Failed to download release checksums for ${LATEST_VERSION}."
        err "Set ALLOW_UNVERIFIED=1 only for emergency/non-production installs."
        exit 1
    fi
    warn "Could not download release checksums. Continuing without verification."
fi

if [ -n "$CHECKSUM_FILE" ] && [ -f "$CHECKSUM_FILE" ]; then
    if download_checksum_signature "$LATEST_VERSION"; then
        info "Release signature verification enabled"
    fi
    verify_checksum_signature
fi

# Create directories
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR/recordings" "$DATA_DIR/plugins" "$LOG_DIR" "$PLUGIN_DIR"

# Download
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

if command -v curl &>/dev/null; then
    curl -fsSL "$DOWNLOAD_URL" -o vms-server.tar.gz
else
    wget -q "$DOWNLOAD_URL" -O vms-server.tar.gz
fi

verify_asset_checksum "vms-server.tar.gz" "$ASSET_SERVER"

# Stop service if upgrading
if [ "$UPGRADING" = true ]; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
fi

# Extract and install
info "Extracting..."
tar -xzf vms-server.tar.gz

# Find the extracted directory
EXTRACT_DIR=$(find . -maxdepth 1 -type d -name "vms-server*" | head -1)
if [ -z "$EXTRACT_DIR" ]; then
    EXTRACT_DIR="."
fi

cp -r "$EXTRACT_DIR"/* "$INSTALL_DIR/" 2>/dev/null || true
chmod +x "$INSTALL_DIR/vms-server"

# Copy config if not exists
if [ ! -f "$CONFIG_DIR/server.json" ] && [ -f "$INSTALL_DIR/config/server.json" ]; then
    cp "$INSTALL_DIR/config/server.json" "$CONFIG_DIR/"
fi

# Copy plugins
if [ -d "$INSTALL_DIR/plugins" ]; then
    cp -r "$INSTALL_DIR/plugins/"* "$PLUGIN_DIR/" 2>/dev/null || true
fi

# Copy models from main package (includes YOLOv8, MobileNet SSD, face models)
if [ -d "$INSTALL_DIR/models" ]; then
    mkdir -p "$PLUGIN_DIR/models"
    cp -f "$INSTALL_DIR/models/"* "$PLUGIN_DIR/models/" 2>/dev/null || true
    ok "AI models installed from main package"
fi

# Copy dashboard web UI
if [ -d "$INSTALL_DIR/www" ]; then
    mkdir -p /var/www/html
    cp -r "$INSTALL_DIR/www/"* /var/www/html/ 2>/dev/null || true
    ok "Dashboard web UI installed to /var/www/html/"
fi

# Create symlink
ln -sf "$INSTALL_DIR/vms-server" /usr/local/bin/vms-server

# Set LD_LIBRARY_PATH for shared libs
echo -e "$INSTALL_DIR\n$INSTALL_DIR/lib" > /etc/ld.so.conf.d/vms-server.conf
ldconfig 2>/dev/null || true

# Cleanup
rm -rf "$TEMP_DIR"

ok "VMS Server $LATEST_VERSION installed to $INSTALL_DIR"

# ============================================================
# Install Analytics Plugins + AI Models
# ============================================================
step "2.7/8 Analytics Plugins & AI Models"

MODELS_DIR="$PLUGIN_DIR/models"
mkdir -p "$MODELS_DIR"

# Detect GPU for choosing the right plugin binary
HAS_GPU=false
if command -v nvidia-smi &>/dev/null && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -qi nvidia; then
    HAS_GPU=true
fi

# Download pre-built analytics plugin from release
PLUGIN_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}/analytics-plugins.tar.gz"
ASSET_PLUGINS="analytics-plugins.tar.gz"
info "Downloading analytics plugins..."

TEMP_PLUGIN=$(mktemp -d)
if curl -fsSL "$PLUGIN_URL" -o "$TEMP_PLUGIN/analytics-plugins.tar.gz" 2>/dev/null; then
    verify_asset_checksum "$TEMP_PLUGIN/analytics-plugins.tar.gz" "$ASSET_PLUGINS"
    tar -xzf "$TEMP_PLUGIN/analytics-plugins.tar.gz" -C "$TEMP_PLUGIN/" 2>/dev/null

    # Find the extracted directory (could be analytics-plugins/ or flat)
    AP_DIR="$TEMP_PLUGIN"
    [ -d "$TEMP_PLUGIN/analytics-plugins" ] && AP_DIR="$TEMP_PLUGIN/analytics-plugins"

    # Copy models
    if [ -d "$AP_DIR/models" ]; then
        cp -f "$AP_DIR/models/"* "$MODELS_DIR/" 2>/dev/null
        ok "AI models installed to $MODELS_DIR ($(ls "$AP_DIR/models/" | wc -l) files)"
    fi

    # Install plugin binaries
    # First try GPU/CPU variants (legacy format), then unified .so files
    SUFFIX="cpu"
    if [ "$HAS_GPU" = true ]; then
        SUFFIX="gpu"
    fi

    INSTALLED=0
    for GPU_SO in "$AP_DIR/plugins/"*_${SUFFIX}.so; do
        [ -f "$GPU_SO" ] || continue
        FINAL_NAME=$(basename "$GPU_SO" | sed "s/_${SUFFIX}\.so/.so/")
        cp -f "$GPU_SO" "$PLUGIN_DIR/$FINAL_NAME"
        INSTALLED=$((INSTALLED + 1))
    done

    if [ "$INSTALLED" -gt 0 ]; then
        ok "$INSTALLED analytics plugin(s) installed (${SUFFIX^^} variant)"
    else
        # Unified plugins (no cpu/gpu suffix) — copy all .so directly
        INSTALLED=$(find "$AP_DIR/plugins" -maxdepth 1 -name "*.so" 2>/dev/null | wc -l)
        find "$AP_DIR/plugins" -maxdepth 1 -name "*.so" -exec cp -f {} "$PLUGIN_DIR/" \;
        if [ "$INSTALLED" -gt 0 ]; then
            ok "$INSTALLED analytics plugin(s) installed (unified, auto-detect GPU at runtime)"
        else
            warn "No analytics plugins found in package"
        fi
    fi
else
    warn "Analytics plugin package not found in release."
    info "Downloading individual model files..."

    # Download MobileNet SSD model (for object detection — required for most analytics features)
    MOBILENET_PROTO="https://raw.githubusercontent.com/chuanqi305/MobileNet-SSD/master/deploy.prototxt"
    MOBILENET_MODEL="https://github.com/chuanqi305/MobileNet-SSD/raw/master/mobilenet_iter_73000.caffemodel"

    if [ ! -f "$MODELS_DIR/MobileNetSSD_deploy.prototxt" ]; then
        curl -fsSL "$MOBILENET_PROTO" -o "$MODELS_DIR/MobileNetSSD_deploy.prototxt" 2>/dev/null && \
            ok "MobileNet SSD prototxt downloaded" || \
            warn "Failed to download MobileNet SSD prototxt"
    fi

    if [ ! -f "$MODELS_DIR/MobileNetSSD_deploy.caffemodel" ]; then
        info "Downloading MobileNet SSD model (23 MB)..."
        curl -fsSL -L "$MOBILENET_MODEL" -o "$MODELS_DIR/MobileNetSSD_deploy.caffemodel" 2>/dev/null && \
            ok "MobileNet SSD model downloaded" || \
            warn "Failed to download MobileNet SSD model"
    fi
fi
rm -rf "$TEMP_PLUGIN"

cleanup_security_artifacts

# List installed plugins
PLUGIN_COUNT=$(find "$PLUGIN_DIR" -name "*.so" | wc -l)
if [ "$PLUGIN_COUNT" -gt 0 ]; then
    ok "$PLUGIN_COUNT analytics plugin(s) installed:"
    find "$PLUGIN_DIR" -name "*.so" -exec basename {} \; | while read f; do
        echo -e "    ${CYAN}→${NC} $f"
    done
    if [ "$HAS_GPU" = true ]; then
        info "GPU detected — using GPU-accelerated plugin"
    else
        info "No GPU detected — using CPU plugin"
    fi
fi

# ============================================================
# GPU + CUDA Setup (if NVIDIA GPU detected)
# ============================================================
if [ -n "$GPU_INFO" ] || [ -d /proc/driver/nvidia ]; then
    step "2.8/8 GPU / CUDA Setup"

    # Check if CUDA toolkit is installed
    if ! command -v nvcc &>/dev/null && [ ! -f /usr/local/cuda/bin/nvcc ]; then
        info "NVIDIA GPU detected but CUDA toolkit not installed."
        info "Installing CUDA toolkit for GPU-accelerated AI analytics..."

        # Add NVIDIA repo
        if [ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ] && [ ! -f /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list ]; then
            wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb 2>/dev/null
            dpkg -i /tmp/cuda-keyring.deb > /dev/null 2>&1 || true
            apt-get update -qq 2>/dev/null
        fi

        # Install CUDA toolkit (minimal)
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            cuda-toolkit-12-6 libcudnn9-cuda-12 libcudnn9-dev-cuda-12 > /dev/null 2>&1 && \
            ok "CUDA 12.6 + cuDNN installed" || \
            warn "CUDA installation failed. GPU analytics will use CPU fallback."
    else
        ok "CUDA toolkit already installed"
    fi

    # Install OpenCV with CUDA (for GPU-accelerated AI inference)
    # Check if OpenCV has CUDA DNN support
    HAS_CUDA_OPENCV=false
    if pkg-config --exists opencv4 2>/dev/null; then
        # Check if the installed OpenCV has CUDA
        if ldconfig -p | grep -q libopencv_dnn_cuda 2>/dev/null; then
            HAS_CUDA_OPENCV=true
            ok "OpenCV with CUDA DNN already installed"
        fi
    fi

    if [ "$HAS_CUDA_OPENCV" = false ] && command -v nvcc &>/dev/null; then
        info "OpenCV without CUDA. GPU AI will use runtime CUDA detection."
        info "For optimal GPU performance, build OpenCV with CUDA support:"
        echo -e "    ${CYAN}See: https://docs.opencv.org/4.x/d6/d15/tutorial_building_tegra_cuda.html${NC}"
    fi
else
    info "No NVIDIA GPU detected — analytics will use CPU inference"
fi

# Install OpenCV runtime (if not already present)
if ! ldconfig -p | grep -q libopencv_dnn 2>/dev/null; then
    info "Installing OpenCV runtime libraries..."
    # Try multiple package names — differs between Ubuntu versions
    if apt-get install -y -qq libopencv-dev > /dev/null 2>&1; then
        ok "OpenCV installed"
    elif apt-get install -y -qq python3-opencv libopencv-core-dev libopencv-dnn-dev > /dev/null 2>&1; then
        ok "OpenCV installed (minimal)"
    elif apt-get install -y -qq libopencv-core4.5d libopencv-dnn4.5d libopencv-imgcodecs4.5d libopencv-imgproc4.5d > /dev/null 2>&1; then
        ok "OpenCV runtime libs installed"
    else
        warn "OpenCV installation failed. Trying to install from source packages..."
        apt-get install -y -qq libopencv-dev 2>&1 | tail -5 || true
        warn "Some analytics plugins may not work without OpenCV."
        warn "Manual fix: apt-get update && apt-get install -y libopencv-dev"
    fi
else
    ok "OpenCV runtime already available"
fi

# ============================================================
# Pre-create Required Directories
# ============================================================
# These must exist BEFORE systemd starts, because the service uses
# ProtectSystem=strict + ReadWritePaths — systemd's mount namespacing
# fails if any ReadWritePaths directory doesn't exist.
mkdir -p /var/www/html/streams
mkdir -p "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR" "$PLUGIN_DIR" /tmp

# ============================================================
# Check Port Conflicts
# ============================================================
for CHECK_PORT in 8080 8443; do
    PORT_PID=$(ss -tlnp "sport = :${CHECK_PORT}" 2>/dev/null | grep -v '^State' | head -1)
    if [ -n "$PORT_PID" ]; then
        PORT_PROC=$(echo "$PORT_PID" | grep -oP 'users:\(\("\K[^"]+' || echo "unknown")
        warn "Port $CHECK_PORT is already in use by: $PORT_PROC"
        warn "VMS Server needs ports 8080 and 8443. Please free them first:"
        warn "  ss -tlnp sport = :$CHECK_PORT"
        if echo "$PORT_PROC" | grep -qi docker; then
            warn "  → Docker container detected. Run: docker ps | grep $CHECK_PORT"
            warn "  → Then: docker stop <container_name>"
        fi
        err "Cannot start VMS Server — port $CHECK_PORT conflict. Fix and re-run installer."
        exit 1
    fi
done

# ============================================================
# Verify Shared Libraries
# ============================================================
info "Checking shared library dependencies..."
MISSING_LIBS=$(ldd "$INSTALL_DIR/vms-server" 2>/dev/null | grep 'not found' || true)
if [ -n "$MISSING_LIBS" ]; then
    warn "Missing shared libraries detected:"
    echo "$MISSING_LIBS" | while read -r line; do echo "    $line"; done
    info "Attempting to install missing dependencies..."
    apt-get install -y -qq libssl-dev libsqlite3-dev libcurl4-openssl-dev > /dev/null 2>&1 || true
    # Re-check
    STILL_MISSING=$(ldd "$INSTALL_DIR/vms-server" 2>/dev/null | grep 'not found' || true)
    if [ -n "$STILL_MISSING" ]; then
        warn "Some libraries still missing — VMS Server may fail to start:"
        echo "$STILL_MISSING" | while read -r line; do echo "    $line"; done
    else
        ok "All shared library dependencies resolved"
    fi
else
    ok "All shared library dependencies satisfied"
fi

# ============================================================
# Create Systemd Service
# ============================================================
step "3/8 Systemd Service"

# Create dedicated service user
if ! id -u vms >/dev/null 2>&1; then
    useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin vms
    ok "Created service user: vms"
fi

mkdir -p /var/www/html/streams
chown -R vms:vms "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$PLUGIN_DIR" /var/www/html/streams

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=VMS Server - Video Management System
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p ${DATA_DIR} ${LOG_DIR} ${CONFIG_DIR} /var/www/html/streams
ExecStart=${INSTALL_DIR}/vms-server
Restart=always
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=10
User=vms
Group=vms
Environment=LD_LIBRARY_PATH=${INSTALL_DIR}/lib:${INSTALL_DIR}
WorkingDirectory=${INSTALL_DIR}
StandardOutput=append:${LOG_DIR}/vms-server.log
StandardError=append:${LOG_DIR}/vms-server.log

# Security Hardening
ProtectSystem=strict
ReadWritePaths=${DATA_DIR} ${LOG_DIR} ${CONFIG_DIR} ${PLUGIN_DIR} /var/www/html/streams /tmp
ProtectHome=true
NoNewPrivileges=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Wait for server to start (with retry)
MAX_WAIT=10
for i in $(seq 1 $MAX_WAIT); do
    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        ok "VMS Server is running"
        break
    fi
    if [ "$i" -eq "$MAX_WAIT" ]; then
        warn "VMS Server failed to start after ${MAX_WAIT}s"
        warn "Check logs: journalctl -u $SERVICE_NAME --no-pager -n 20"
        # Show actual error
        journalctl -u "$SERVICE_NAME" --no-pager -n 5 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    fi
done

# ============================================================
# Detect / Configure Domain
# ============================================================
step "4/8 Domain Configuration"

if [ -n "$DOMAIN" ]; then
    info "Using specified domain: $DOMAIN"
elif [ -t 0 ]; then
    # Interactive mode — ask user
    echo -e "${YELLOW}Enter the domain name pointing to this server's IP (or press Enter to skip):${NC}"
    read -r DOMAIN
    if [ -z "$DOMAIN" ]; then
        warn "No domain set. Skipping nginx/SSL setup."
        warn "VMS Server is accessible at http://<server-ip>:8080"
        SKIP_NGINX=1
    fi
else
    # Non-interactive — try to auto-detect from hostname
    HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)
    if echo "$HOSTNAME_FQDN" | grep -qE '\.[a-z]{2,}$'; then
        DOMAIN="$HOSTNAME_FQDN"
        info "Auto-detected domain: $DOMAIN"
    else
        warn "No domain detected. Skipping nginx/SSL."
        warn "VMS Server is accessible at http://<server-ip>:8080"
        warn "Re-run with DOMAIN=your.domain.com to set up nginx/SSL later."
        SKIP_NGINX=1
    fi
fi

EMAIL="${EMAIL:-admin@${DOMAIN:-localhost}}"

if [ "${SKIP_NGINX}" != "1" ]; then
    if ! [[ "$DOMAIN" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ || "$DOMAIN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        err "Invalid DOMAIN format: $DOMAIN"
        err "Use a valid FQDN like camera.example.com (recommended)"
        exit 1
    fi
fi

# ============================================================
# Install & Configure Nginx
# ============================================================
if [ "${SKIP_NGINX}" != "1" ]; then
    step "5/8 Nginx + SSL"

    # Install nginx and certbot
    info "Installing nginx and certbot..."
    apt-get update -qq
    apt-get install -y -qq nginx certbot python3-certbot-nginx > /dev/null 2>&1
    ok "Nginx installed"

    # Get SSL certificate
    info "Obtaining SSL certificate for $DOMAIN..."
    if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        systemctl stop nginx 2>/dev/null || true
        certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
            --email "$EMAIL" --no-eff-email 2>/dev/null || {
            warn "Let's Encrypt failed — creating self-signed certificate"
            mkdir -p "/etc/letsencrypt/live/$DOMAIN"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
                -out "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
                -subj "/CN=$DOMAIN" 2>/dev/null
            ok "Self-signed certificate created"
        }
    else
        ok "SSL certificate already exists"
    fi

    if [ "$NX_INSECURE_TLS" != "1" ]; then
        mkdir -p /etc/nginx/trust
        if [ -n "$NX_TRUST_CHAIN_URL" ]; then
            if curl -fsSL "$NX_TRUST_CHAIN_URL" -o /etc/nginx/trust/nx-upstream-chain.pem 2>/dev/null; then
                ok "NX trust chain downloaded from NX_TRUST_CHAIN_URL"
            else
                warn "Failed to download NX trust chain from NX_TRUST_CHAIN_URL"
            fi
        elif [ -n "$NX_TRUST_CHAIN_PATH" ]; then
            if [ -f "$NX_TRUST_CHAIN_PATH" ]; then
                cp -f "$NX_TRUST_CHAIN_PATH" /etc/nginx/trust/nx-upstream-chain.pem
                ok "NX trust chain copied from NX_TRUST_CHAIN_PATH"
            else
                warn "NX_TRUST_CHAIN_PATH not found: $NX_TRUST_CHAIN_PATH"
            fi
        fi

        if [ -f /etc/nginx/trust/nx-upstream-chain.pem ]; then
            NX_TRUST_DIRECTIVES=$'        proxy_ssl_trusted_certificate /etc/nginx/trust/nx-upstream-chain.pem;\n        proxy_ssl_server_name on;'
        else
            warn "NX trust chain not configured; self-signed NX upstream may fail with TLS verify on"
        fi
    fi

    # Generate nginx config
    info "Configuring nginx for $DOMAIN..."

    cat > /etc/nginx/sites-available/vms-server << NGINXEOF
# ============================================================
# VMS Server — Nginx Reverse Proxy
# Domain: $DOMAIN
# Auto-generated by VMS Server install.sh
# ============================================================

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Web client root
    root $WEB_DIR;
    index index.html;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Static file cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # SPA routing — serve index.html for client-side routes
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # ============ VMS Server API (localhost:8080) ============
    location /vms-api/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # CORS
        add_header Access-Control-Allow-Origin \$http_origin always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    # ============ VMS Server REST endpoints ============
    # /api/update, /api/plugins, /api/analytics, /api/peoplecounting etc.
    location ^~ /api/update    { proxy_pass http://127.0.0.1:8080; include /etc/nginx/vms-proxy-params.conf; }
    location ^~ /api/plugins   { proxy_pass http://127.0.0.1:8080; include /etc/nginx/vms-proxy-params.conf; }
    location ^~ /api/analytics { proxy_pass http://127.0.0.1:8080; include /etc/nginx/vms-proxy-params.conf; }
    location ^~ /api/peoplecounting { proxy_pass http://127.0.0.1:8080; include /etc/nginx/vms-proxy-params.conf; }

    # ============ VMS Server REST v2 endpoints ============
    location ^~ /rest/v2/license { proxy_pass http://127.0.0.1:8080; include /etc/nginx/vms-proxy-params.conf; }
    location ^~ /rest/v2/servers { proxy_pass http://127.0.0.1:8080; include /etc/nginx/vms-proxy-params.conf; }

    # ============ Stream Proxy API (RTSP→HLS, port 3456) ============
    location /stream-api/ {
        proxy_pass http://127.0.0.1:3456/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;

        add_header Access-Control-Allow-Origin \$http_origin always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods "GET, POST, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    # ============ HLS Stream files ============
    location /streams/ {
        alias /var/www/html/streams/;
        add_header Cache-Control "no-cache, no-store";
        add_header Access-Control-Allow-Origin * always;
        types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }
    }

    # ============ NX Witness / Media Server (localhost:7001) ============
    # Only active if NX Witness is installed on this server

    location /api/ {
        proxy_pass https://127.0.0.1:7001/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify ${NX_PROXY_SSL_VERIFY};
    ${NX_TRUST_DIRECTIVES}

        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    location /rest/ {
        proxy_pass https://127.0.0.1:7001/rest/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify ${NX_PROXY_SSL_VERIFY};
    ${NX_TRUST_DIRECTIVES}
        proxy_pass_header Set-Cookie;
        proxy_set_header Cookie \$http_cookie;

        add_header Access-Control-Allow-Origin \$http_origin always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    location /hls/ {
        proxy_pass https://127.0.0.1:7001/hls/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_ssl_verify ${NX_PROXY_SSL_VERIFY};
    ${NX_TRUST_DIRECTIVES}
        proxy_buffering off;
        proxy_read_timeout 300s;

        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    location /media/ {
        proxy_pass https://127.0.0.1:7001/media/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify ${NX_PROXY_SSL_VERIFY};
    ${NX_TRUST_DIRECTIVES}
        proxy_pass_header Set-Cookie;
        proxy_set_header Cookie \$http_cookie;

        # WebSocket
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Streaming
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;
        proxy_max_temp_file_size 0;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 30s;
        chunked_transfer_encoding off;

        add_header Access-Control-Allow-Origin \$http_origin always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, Range" always;
        add_header Access-Control-Expose-Headers "Content-Length, Content-Range" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    # ============ People Counter Dashboard ============
    location /peoplecounting/ {
        alias /var/www/html/peoplecounting/;
        try_files \$uri \$uri/ /peoplecounting/index.html;
    }
}
NGINXEOF

    # Create shared proxy params snippet
    cat > /etc/nginx/vms-proxy-params.conf << 'PROXYEOF'
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;

add_header Access-Control-Allow-Origin $http_origin always;
add_header Access-Control-Allow-Credentials true always;
add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;

if ($request_method = OPTIONS) { return 204; }
PROXYEOF

    # Enable site
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/vms-server /etc/nginx/sites-enabled/vms-server

    # Create stream directory
    mkdir -p /var/www/html/streams

    # Test nginx config
    if nginx -t 2>/dev/null; then
        systemctl start nginx
        systemctl enable nginx
        ok "Nginx configured and running"
        ok "HTTPS: https://$DOMAIN"
    else
        warn "Nginx config test failed. Check: nginx -t"
    fi

    # Setup auto-renewal for SSL
    if command -v certbot &>/dev/null; then
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | sort -u | crontab -
        ok "SSL auto-renewal configured"
    fi
else
    step "5/8 Nginx + SSL (skipped)"
    warn "Skipping nginx/SSL setup. VMS Server is accessible at http://<server-ip>:8080"
fi

# ============================================================
# Deploy Web Client
# ============================================================
if [ "${SKIP_WEB_CLIENT}" != "1" ] && [ "${SKIP_NGINX}" != "1" ]; then
    step "6/8 Web Client"

    mkdir -p "$WEB_DIR"

    # Try to download pre-built web client from releases
    WEB_CLIENT_URL="https://github.com/${WEB_CLIENT_REPO}/releases/latest/download/vms-client-dist.tar.gz"
    info "Downloading web client..."

    TEMP_WEB=$(mktemp -d)
    if curl -fsSL "$WEB_CLIENT_URL" -o "$TEMP_WEB/web-client.tar.gz" 2>/dev/null; then
        tar -xzf "$TEMP_WEB/web-client.tar.gz" -C "$WEB_DIR/" --strip-components=1 2>/dev/null || \
        tar -xzf "$TEMP_WEB/web-client.tar.gz" -C "$WEB_DIR/" 2>/dev/null
        ok "Web client deployed to $WEB_DIR"
    else
        warn "Web client download failed."
        warn "You can deploy manually later:"
        warn "  1. Build: cd vms-client-web && npm run build"
        warn "  2. Copy: cp -r dist/* $WEB_DIR/"
    fi
    rm -rf "$TEMP_WEB"
else
    step "6/8 Web Client (skipped)"
fi

# ============================================================
# Firewall
# ============================================================
step "7/8 Firewall"

if command -v ufw &>/dev/null; then
    ufw allow 22/tcp   > /dev/null 2>&1 || true
    ufw allow 80/tcp   > /dev/null 2>&1 || true
    ufw allow 443/tcp  > /dev/null 2>&1 || true
    if [ "${SKIP_NGINX}" = "1" ]; then
        # No nginx — clients connect directly to VMS server ports
        ufw allow 8080/tcp > /dev/null 2>&1 || true
        ufw allow 8443/tcp > /dev/null 2>&1 || true
        ok "Firewall rules configured (22, 80, 443, 8080, 8443)"
    else
        # Nginx handles SSL termination — port 8080/8443 kept internal
        ok "Firewall rules configured (22, 80, 443) — port 8080 kept internal"
    fi
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=http  > /dev/null 2>&1 || true
    firewall-cmd --permanent --add-service=https > /dev/null 2>&1 || true
    if [ "${SKIP_NGINX}" = "1" ]; then
        firewall-cmd --permanent --add-port=8080/tcp > /dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=8443/tcp > /dev/null 2>&1 || true
    fi
    firewall-cmd --reload > /dev/null 2>&1 || true
    ok "Firewall rules configured"
else
    info "No firewall manager detected — skipping"
fi

# ============================================================
# Summary
# ============================================================
INSTALL_COMPLETED=1

step "8/8 Installation Complete"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         VMS Server — Installation Complete       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Version:${NC}      $LATEST_VERSION"
echo -e "  ${BOLD}Install Dir:${NC}  $INSTALL_DIR"
echo -e "  ${BOLD}Config:${NC}       $CONFIG_DIR/server.json"
echo -e "  ${BOLD}Data:${NC}         $DATA_DIR"
echo -e "  ${BOLD}Plugins:${NC}      $PLUGIN_DIR"
echo -e "  ${BOLD}Logs:${NC}         $LOG_DIR"

if [ -n "$DOMAIN" ] && [ "${SKIP_NGINX}" != "1" ]; then
    echo ""
    echo -e "  ${BOLD}Domain:${NC}       https://$DOMAIN"
    echo -e "  ${BOLD}Web Client:${NC}   https://$DOMAIN/"
    echo -e "  ${BOLD}Health API:${NC}   https://$DOMAIN/vms-api/api/health"
fi

if [ -n "$GPU_INFO" ]; then
    echo ""
    echo -e "  ${BOLD}GPU:${NC}          $GPU_INFO"
fi

echo ""
echo -e "${BOLD}Service Commands:${NC}"
echo "  sudo systemctl status  $SERVICE_NAME"
echo "  sudo systemctl restart $SERVICE_NAME"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║           FIRST-TIME SETUP (IMPORTANT!)          ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  You must create an admin account before using VMS Server."
echo ""
echo -e "  ${BOLD}Option 1 — Web Browser:${NC}"
if [ -n "$DOMAIN" ] && [ "${SKIP_NGINX}" != "1" ]; then
    echo "    Open https://$DOMAIN — the web client will guide you"
else
    echo "    Open the web client and connect to this server"
fi
echo ""
echo -e "  ${BOLD}Option 2 — Command line:${NC}"
echo "    curl -sk -X POST https://localhost:8443/rest/v2/system/setup \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"username\":\"admin\",\"password\":\"your-secure-password\"}'"
echo ""
echo -e "${BOLD}Connect from VMS Client:${NC}"
if [ -n "$DOMAIN" ] && [ "${SKIP_NGINX}" != "1" ]; then
    echo "  1. Open any VMS Client Web (e.g., https://vmsclient.vnso.vn)"
    echo "  2. Add Server → Host: $DOMAIN, Port: 443, Protocol: HTTPS"
    echo "  3. Login with the admin account you created"
    echo ""
    echo "  Or open https://$DOMAIN directly if web client is deployed."
else
    echo "  1. Open any VMS Client Web"
    echo "  2. Add Server → Host: <this-server-ip>, Port: 8080, Protocol: HTTP"
    echo "  3. Login with the admin account you created"
fi
echo ""
echo -e "${GREEN}Done! Your VMS Server is ready.${NC}"
