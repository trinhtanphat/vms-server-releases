#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/vms-server"
CONFIG_DIR="/etc/vms-server"
DATA_DIR="/var/lib/vms-server"
LOG_DIR="/var/log/vms-server"
PLUGIN_DIR="/usr/lib/vms-server/plugins"
WEB_SITE="/etc/nginx/sites-available/vms-server"
WEB_ENABLED="/etc/nginx/sites-enabled/vms-server"
PROXY_PARAMS="/etc/nginx/vms-proxy-params.conf"
SERVICE_NAME="vms-server"
REMOVE_DATA=0
REMOVE_WEB=0

usage() {
  cat <<'EOF'
Usage: sudo ./uninstall.sh [--purge-data] [--purge-web] [--yes]

Options:
  --purge-data   Remove /var/lib/vms-server data and recordings
  --purge-web    Remove /var/www/html/vms-client and nginx site config
  --yes          Non-interactive mode
EOF
}

CONFIRM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-data) REMOVE_DATA=1 ;;
    --purge-web) REMOVE_WEB=1 ;;
    --yes) CONFIRM=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if [[ $EUID -ne 0 ]]; then
  echo "[ERR] Run as root" >&2
  exit 1
fi

if [[ $CONFIRM -ne 1 ]]; then
  echo "This will uninstall VMS Server service and binaries."
  [[ $REMOVE_DATA -eq 1 ]] && echo "Data purge enabled: $DATA_DIR"
  [[ $REMOVE_WEB -eq 1 ]] && echo "Web/nginx purge enabled"
  read -r -p "Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 0
fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload 2>/dev/null || true

rm -f /usr/local/bin/vms-server
rm -f /etc/ld.so.conf.d/vms-server.conf
ldconfig 2>/dev/null || true

rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$PLUGIN_DIR"

if [[ $REMOVE_DATA -eq 1 ]]; then
  rm -rf "$DATA_DIR"
fi

if [[ $REMOVE_WEB -eq 1 ]]; then
  rm -f "$WEB_ENABLED" "$WEB_SITE" "$PROXY_PARAMS"
  rm -rf /var/www/html/vms-client
  nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true
fi

echo "[OK] VMS Server uninstalled"
[[ $REMOVE_DATA -eq 0 ]] && echo "[INFO] Data kept at $DATA_DIR (use --purge-data to remove)"
