#!/bin/bash
#
# VMS Server Installation Script for Linux
# Installs VMS Server + Nginx + SSL + Web Client — all-in-one
#
# Usage:
#   curl -fsSL https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.sh | sudo bash
#
# Or with a specific version:
#   curl -fsSL https://github.com/trinhtanphat/vms-server-releases/releases/download/v0.5.0/install.sh | sudo bash
#
# Options (environment variables):
#   DOMAIN=myserver.example.com   - Domain name for SSL (auto-detected if not set)
#   EMAIL=admin@example.com       - Email for Let's Encrypt (default: admin@$DOMAIN)
#   SKIP_NGINX=1                  - Skip nginx/SSL setup
#   SKIP_WEB_CLIENT=1             - Skip web client deployment
#   VMS_VERSION=v0.5.0            - Install specific version
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

# ============================================================
# Banner
# ============================================================
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

info "Downloading from: $DOWNLOAD_URL"

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

# Download pre-built analytics plugin from release
PLUGIN_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}/analytics-plugins.tar.gz"
info "Downloading analytics plugins..."

TEMP_PLUGIN=$(mktemp -d)
if curl -fsSL "$PLUGIN_URL" -o "$TEMP_PLUGIN/analytics-plugins.tar.gz" 2>/dev/null; then
    tar -xzf "$TEMP_PLUGIN/analytics-plugins.tar.gz" -C "$PLUGIN_DIR/" 2>/dev/null
    ok "Analytics plugins installed to $PLUGIN_DIR"
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

# List installed plugins
PLUGIN_COUNT=$(find "$PLUGIN_DIR" -name "*.so" | wc -l)
if [ "$PLUGIN_COUNT" -gt 0 ]; then
    ok "$PLUGIN_COUNT analytics plugin(s) installed:"
    find "$PLUGIN_DIR" -name "*.so" -exec basename {} \; | while read f; do
        echo -e "    ${CYAN}→${NC} $f"
    done
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
    apt-get install -y -qq libopencv-dev > /dev/null 2>&1 && \
        ok "OpenCV installed" || \
        warn "OpenCV installation failed. Some analytics plugins may not work."
else
    ok "OpenCV runtime already available"
fi

# ============================================================
# Create Systemd Service
# ============================================================
step "3/8 Systemd Service"

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=VMS Server - Video Management System
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/vms-server
Restart=always
RestartSec=5
User=root
Environment=LD_LIBRARY_PATH=${INSTALL_DIR}/lib:${INSTALL_DIR}
WorkingDirectory=${INSTALL_DIR}
StandardOutput=append:${LOG_DIR}/vms-server.log
StandardError=append:${LOG_DIR}/vms-server.log

# Hardening
ProtectSystem=strict
ReadWritePaths=${DATA_DIR} ${LOG_DIR} ${CONFIG_DIR} ${PLUGIN_DIR}
ProtectHome=true
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Wait for server to start
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "VMS Server is running"
else
    warn "VMS Server may not have started yet. Check: journalctl -u $SERVICE_NAME -f"
fi

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
        proxy_ssl_verify off;

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
        proxy_ssl_verify off;
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
        proxy_ssl_verify off;
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
        proxy_ssl_verify off;
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
    ufw allow 8080/tcp > /dev/null 2>&1 || true
    ok "Firewall rules configured (22, 80, 443, 8080)"
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=http  > /dev/null 2>&1 || true
    firewall-cmd --permanent --add-service=https > /dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=8080/tcp > /dev/null 2>&1 || true
    firewall-cmd --reload > /dev/null 2>&1 || true
    ok "Firewall rules configured"
else
    info "No firewall manager detected — skipping"
fi

# ============================================================
# Summary
# ============================================================
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
echo -e "${BOLD}Connect from VMS Client:${NC}"
if [ -n "$DOMAIN" ] && [ "${SKIP_NGINX}" != "1" ]; then
    echo "  1. Open any VMS Client Web (e.g., https://vmsclient.vnso.vn)"
    echo "  2. Add Server → Host: $DOMAIN, Port: 443, Protocol: HTTPS"
    echo "  3. Login with your credentials"
    echo ""
    echo "  Or open https://$DOMAIN directly if web client is deployed."
else
    echo "  1. Open any VMS Client Web"
    echo "  2. Add Server → Host: <this-server-ip>, Port: 8080, Protocol: HTTP"
    echo "  3. Login with your credentials"
fi
echo ""
echo -e "${GREEN}Done! Your VMS Server is ready.${NC}"
