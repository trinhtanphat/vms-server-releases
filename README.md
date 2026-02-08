# VMS Server Releases

Pre-built binaries and installer for VMS Server.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Any VPS / Server                  │
│                                                     │
│  ┌──────────┐    ┌─────────────┐    ┌───────────┐  │
│  │  Nginx   │───▶│ VMS Server  │    │NX Witness │  │
│  │ :443 SSL │    │   :8080     │    │  :7001    │  │
│  │          │───▶│             │    │ (optional)│  │
│  │          │───▶└─────────────┘    └───────────┘  │
│  │          │                            ▲          │
│  │          │────────────────────────────┘          │
│  └──────────┘                                       │
│       ▲                                             │
│  Web Client                                         │
│  (static files)                                     │
└───────┬─────────────────────────────────────────────┘
        │ HTTPS
        ▼
┌──────────────────┐
│  Browser / VMS   │  ◀── User connects from ANY
│  Client Web App  │      VMS Client to this domain
└──────────────────┘
```

Each VPS is **self-contained**: nginx + SSL + VMS Server + optional NX Witness + optional Web Client.
Any VMS Client Web app can connect to any VMS Server by entering its domain in the login page.

## Quick Install

Install VMS Server on any Linux VPS with a single command:

```bash
curl -fsSL https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.sh | sudo bash
```

This will:
1. Download and install the latest VMS Server binary
2. Create a systemd service (`vms-server`)
3. Install nginx with SSL (Let's Encrypt)
4. Deploy the VMS Web Client
5. Configure firewall rules
6. Auto-detect GPU (NVIDIA) for AI plugin support

### Install Options

```bash
# Install with a specific domain
DOMAIN=myserver.example.com curl -fsSL .../install.sh | sudo bash

# Install a specific version
VMS_VERSION=v0.5.0 curl -fsSL .../install.sh | sudo bash

# Skip nginx/SSL setup (server only, no web client)
SKIP_NGINX=1 curl -fsSL .../install.sh | sudo bash

# Skip web client deployment
SKIP_WEB_CLIENT=1 curl -fsSL .../install.sh | sudo bash

# Custom email for Let's Encrypt
EMAIL=admin@example.com DOMAIN=myserver.example.com curl -fsSL .../install.sh | sudo bash
```

### After Installation

**First-Time Setup (Required):**

After installation, you must create an admin account before you can use the server:

```bash
# Check if setup is required
curl -sk https://localhost:8443/rest/v2/system/setup

# Create admin account
curl -sk -X POST https://localhost:8443/rest/v2/system/setup \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"your-secure-password"}'
```

Or open `https://your-domain/` in a browser — the VMS Web Client will detect that setup is required and guide you through admin account creation.

**Connect from any VMS Client:**
1. Open any VMS Client Web app (e.g., `https://vmsclient.vnso.vn`)
2. Add Server → enter your domain, Port 443, Protocol HTTPS
3. Login with the admin credentials you created during setup

**VMS Ports:**
| Port | Protocol | Description |
|------|----------|-------------|
| 443 | HTTPS | Main access (via nginx reverse proxy) |
| 8080 | HTTP | VMS Server direct (internal only) |
| 8443 | HTTPS | VMS Server direct SSL (internal only) |
| 8554 | RTSP | RTSP streaming |

## Manual Download

Download binaries from the [Releases](../../releases) page:

| File | Description |
|------|-------------|
| `install.sh` | All-in-one installer script |
| `vms-server-linux-x64.tar.gz` | VMS Server binary (x86_64) |
| `vms-server-linux-arm64.tar.gz` | VMS Server binary (ARM64) |

## Service Management

```bash
sudo systemctl status vms-server     # Check status
sudo systemctl restart vms-server    # Restart
sudo systemctl stop vms-server       # Stop
sudo journalctl -u vms-server -f     # View logs
```

## Upgrade

Re-run the install script to upgrade to the latest version:

```bash
curl -fsSL https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.sh | sudo bash
```

The installer detects existing installations and upgrades in place.

## File Layout

```
/opt/vms-server/          # Server binary & libs
/etc/vms-server/          # Configuration (server.json)
/var/lib/vms-server/      # Data (recordings, plugins DB)
/var/log/vms-server/      # Logs
/usr/lib/vms-server/plugins/  # Analytics plugins
/var/www/html/vms-client/ # Web client (if deployed)
```

## GPU Support

The installer auto-detects NVIDIA GPUs. For AI analytics plugins (object detection, people counting, etc.), ensure:
- NVIDIA drivers are installed
- CUDA toolkit is available
- `nvidia-smi` works

---

## ⚠️ Security Audit

> **Ngày kiểm tra:** 2026-02-07

### 🔴 Critical

| # | Vấn đề | Chi tiết |
|---|--------|---------|
| 1 | **`curl \| sudo bash`** anti-pattern — code chạy trước khi review | Line 7 |
| 2 | **Không checksum verification** — binary `.tar.gz` và web client tải về không verify SHA256/GPG | Lines 143-149, 534-541 |
| 3 | **Service chạy root** + `NoNewPrivileges=false` | Line 196, 202 |
| 4 | **Port 8080 mở firewall** — bypass nginx TLS, truy cập HTTP trực tiếp | Lines 568-569 |

### 🟡 Medium

| # | Vấn đề | Chi tiết |
|---|--------|---------|
| 5 | CORS reflect origin + credentials → CSRF/session theft | Lines 377-380 |
| 6 | CORS wildcard `*` trên `/api/`, `/hls/`, `/streams/` | Lines 433, 472 |
| 7 | `proxy_ssl_verify off` trên mọi upstream → MITM risk | Lines 430, 448, 467, 487 |
| 8 | Command injection via `$DOMAIN` (unsanitized input) | Lines 237-240 |
| 9 | Self-signed cert fallback không cảnh báo rõ | Lines 300-306 |
| 10 | File permissions lỏng (server.json world-readable) | Lines 126-127 |
| 11 | Missing CSP, Referrer-Policy, Permissions-Policy headers | Lines 350-352 |
| 12 | nginx security headers bị override trong location blocks | nginx `add_header` behavior |
| 13 | Không rate limiting trên API endpoints | Entire nginx config |

### 🟢 Low / Bugs

| # | Vấn đề | Chi tiết |
|---|--------|---------|
| 14 | `set -e` không có `trap` cleanup — fail mid-way để lại trạng thái hỏng | Line 22 |
| 15 | `apt-get` hardcode — fail trên RHEL/CentOS | Lines 288-289 |
| 16 | Không log rotation | Service config |
| 17 | Không backup trước upgrade | Upgrade flow |
| 18 | Không uninstall script | Architecture |
| 19 | Crontab dedup fragile (`sort -u`) | Line 560 |
| 20 | Streams directory world-accessible, không auth | nginx config |

### Khắc phục ưu tiên

1. **Ngay lập tức:** Thêm SHA256 checksum verification cho tất cả downloads
2. **Ngay lập tức:** Tạo dedicated service user (`User=vms`), `NoNewPrivileges=true`
3. **Sớm:** Đóng port 8080 trên firewall (chỉ expose qua nginx)
4. **Sớm:** Fix CORS — explicit allowlist thay wildcard/reflection
5. **Sớm:** Validate `$DOMAIN` input bằng regex
6. **Sớm:** `chmod 600` cho `server.json`, `chmod 700` cho config/data dirs
7. **Khi có thời gian:** Thêm log rotation, backup trước upgrade, uninstall script

---

## CI/CD & Release Pipeline

```
vms-server (private repo)                vms-server-releases (public repo)
┌─────────────────────┐                  ┌────────────────────────────┐
│  Developer commits  │                  │  GitHub Releases           │
│  git tag vX.Y.Z     │──── CI/CD ──────▶│  install.sh                │
│  git push --tags    │   (auto build)   │  vms-server-linux-x64.tar.gz│
└─────────────────────┘                  └─────────────┬──────────────┘
                                                       │
                                         ┌─────────────┘
                                         ▼
                               VMS Server (mỗi VPS)
                               GET /api/update/check
                               GET /api/update/list
                                         │
                                         ▼
                               VMS Client Web
                               Version picker UI
                               Chọn version → cài đặt
```

### Quy trình release

1. **Developer** commit code + update version trong `include/vms/core/version.h`
2. **Tag** version: `git tag v0.5.0 && git push origin --tags`
3. **CI/CD** (GitHub Actions) tự động:
   - Build binary từ source (cmake + make)
   - Package thành `vms-server-linux-x64.tar.gz`
   - Tạo GitHub Release với tag version
   - Upload binary + `install.sh`
4. **VMS Server** trên mỗi VPS kiểm tra bản mới:
   - Primary: License Server API (`license.vnso.vn/api/releases`)
   - Fallback: GitHub Releases API (`api.github.com/repos/trinhtanphat/vms-server-releases/releases`)
5. **VMS Client Web** hiển thị danh sách version để user chọn cập nhật

### User nhận update như thế nào?

- Mở VMS Client Web → Settings → Cập nhật hệ thống
- Hệ thống hiển thị version hiện tại + danh sách tất cả version có sẵn
- User chọn version muốn cài → nhấn "Nâng cấp" hoặc "Cài đặt"
- Server tự động tải binary, verify checksum SHA256, khởi động lại

## Related Repositories

- [vms-server](https://github.com/trinhtanphat/vms-server) — VMS Server source code (private)
- [vms-client-web](https://github.com/trinhtanphat/vms-client-web) — VMS Web Client (React/TypeScript)
- [vms-license-server](https://github.com/trinhtanphat/vms-license-server) — License & release management server
- [nx_open](https://github.com/networkoptix/nx_open) — NX Witness / NX Meta SDK
