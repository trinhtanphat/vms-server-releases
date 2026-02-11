# VMS Server Releases

Pre-built binaries, installer scripts, and analytics plugins for VMS Server.

## Supported Platforms

| Platform | Architecture | Installer | Package |
|----------|-------------|-----------|---------|
| Linux (Ubuntu 20.04+, Debian 11+) | x64 | `install.sh` | `.tar.gz` |
| Windows (10/11, Server 2019+) | x64 | `install.ps1` | `.zip` |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│               Any VPS / Server / PC                 │
│  ┌──────────┐    ┌─────────────┐    ┌───────────┐  │
│  │  Nginx   │───▶│ VMS Server  │    │NX Witness │  │
│  │ :443 SSL │    │   :8080     │    │  :7001    │  │
│  └──────────┘    └─────────────┘    │ (optional)│  │
│       ▲                             └───────────┘  │
│  Web Client (static) ──────────────────────────────│
└───────┬─────────────────────────────────────────────┘
        │ HTTPS
        ▼
┌──────────────────┐
│  Browser / VMS   │  ◀── Connect from ANY VMS Client
│  Client Web App  │
└──────────────────┘
```

Each server is **self-contained**: VMS Server + optional nginx/SSL + Web Client.

## Quick Install

### Linux

```bash
curl -fsSL https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.sh | sudo bash
```

### Windows (PowerShell as Administrator)

```powershell
irm https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.ps1 | iex
```

Or download and run:

```powershell
Invoke-WebRequest -Uri https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.ps1 -OutFile install.ps1
.\install.ps1
```

This will:
1. Download and install VMS Server binary
2. Install analytics plugins (GPU/CPU auto-select)
3. Create systemd service (`vms-server`) / Windows Service (`VMSServer`)
4. (Linux) Install nginx with SSL (Let's Encrypt + self-signed fallback)
5. (Linux) Deploy VMS Web Client
6. Configure firewall
7. Auto-detect NVIDIA GPU for AI plugins

### Linux Install Options

| Variable | Description |
|----------|-------------|
| `DOMAIN=myserver.com` | Set domain for SSL |
| `VMS_VERSION=v0.5.0` | Install specific version |
| `SKIP_NGINX=1` | Skip nginx/SSL setup |
| `SKIP_WEB_CLIENT=1` | Skip web client deployment |
| `EMAIL=admin@example.com` | Let's Encrypt email |

### Windows Install Options

| Parameter | Description |
|-----------|-------------|
| `-Version "v0.7.0"` | Install specific version |
| `-InstallDir "D:\VMS"` | Custom install directory |
| `-SkipService` | Skip Windows Service creation |
| `-SkipFirewall` | Skip firewall rule creation |

### After Installation

**Create admin account (required):**

Linux:
```bash
curl -sk -X POST https://localhost:8443/rest/v2/system/setup \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"your-secure-password"}'
```

Windows (PowerShell):
```powershell
Invoke-RestMethod -Method POST -Uri "https://localhost:8443/rest/v2/system/setup" `
  -ContentType "application/json" -SkipCertificateCheck `
  -Body '{"username":"admin","password":"your-secure-password"}'
```

Or open `https://your-domain/` — the web client guides through admin setup.

### Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 443 | HTTPS | Main access (nginx proxy) |
| 8080 | HTTP | VMS Server direct (internal only) |
| 8443 | HTTPS | VMS Server direct SSL (internal only) |
| 8554 | RTSP | RTSP streaming |

## What Gets Installed

### Linux
```
/opt/vms-server/              # Server binary & libs
/etc/vms-server/              # Configuration (server.json)
/var/lib/vms-server/          # Data (recordings, plugins DB)
/var/log/vms-server/          # Logs
/usr/lib/vms-server/plugins/  # Analytics plugins
/var/www/html/vms-client/     # Web client (if deployed)
```

### Windows
```
%ProgramFiles%\VMS-Server\          # Server binary (vms-server.exe)
%ProgramData%\VMS-Server\           # Configuration (server.json)
%ProgramData%\VMS-Server\data\      # Data (recordings, plugins DB)
%ProgramData%\VMS-Server\logs\      # Logs
%ProgramData%\VMS-Server\plugins\   # Analytics plugins (.dll)
```

## Service Management

### Linux
```bash
sudo systemctl status vms-server     # Check status
sudo systemctl restart vms-server    # Restart
sudo systemctl stop vms-server       # Stop
sudo journalctl -u vms-server -f     # View logs
```

### Windows (PowerShell as Admin)
```powershell
Get-Service VMSServer                # Check status
Restart-Service VMSServer            # Restart
Stop-Service VMSServer               # Stop
Get-EventLog -LogName Application -Source VMSServer -Newest 20  # Logs
```

## Upgrade

### Linux
```bash
curl -fsSL https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.sh | sudo bash
```

### Windows
```powershell
irm https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.ps1 | iex
```

Detects existing installations and upgrades in place.

## GPU Support

For AI analytics plugins, ensure:
- NVIDIA drivers installed
- CUDA toolkit available (auto-installed if GPU detected)
- `nvidia-smi` works

## CI/CD Pipeline

```
vms-server (private)              vms-server-releases (public)
┌─────────────────┐              ┌────────────────────────────┐
│ git tag vX.Y.Z  │── CI/CD ──▶ │ GitHub Releases            │
│ git push --tags │  (auto)     │ ├── install.sh (Linux)     │
└─────────────────┘              │ ├── install.ps1 (Windows)  │
                                 │ ├── vms-server-linux-x64   │
                                 │ └── vms-server-windows-x64 │
                                 └────────────┬───────────────┘
                                              │
                                    VMS Server → /api/update/check
                                    VMS Client Web → Version picker
```

## Systemd Security Hardening

The installer creates a hardened systemd unit with:
- `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`
- `ProtectKernelTunables=true`, `ProtectKernelModules=true`
- `RestrictNamespaces=true`, `NoNewPrivileges=true`
- Read-write access only to `/var/lib/vms-server`, `/var/log/vms-server`, `/usr/lib/vms-server`

## Security Status

> **Last audit:** 2026-02-09

### Known Issues
| Severity | Issue |
|----------|-------|
| 🔴 Critical | `curl \| sudo bash` — no checksum/GPG verification of script |
| 🔴 Critical | Downloaded binaries (`tar.gz`) have no SHA256 verification |
| 🟡 Medium | Service runs as `User=root` (despite hardening) |
| 🟡 Medium | CORS wildcard `*` on some nginx proxy routes |
| 🟡 Medium | `proxy_ssl_verify off` on NX Witness upstream |
| 🟡 Medium | Command injection via unsanitized `$DOMAIN` |
| 🟢 Low | `apt-get` hardcoded — fails on RHEL/CentOS |
| 🟢 Low | No log rotation, no backup before upgrade |
| 🟢 Low | No uninstall script |

### Recommended
1. Add SHA256 checksum verification for all downloads
2. Create dedicated `vms` service user instead of root
3. Validate `$DOMAIN` input with regex
4. Add explicit CORS allowlist instead of wildcard
5. Add uninstall script and upgrade backup

## Related Repositories

| Project | Description |
|---------|-------------|
| [vms-server](https://github.com/trinhtanphat/vms-server) | VMS Server source (private) |
| [vms-client-web](https://github.com/trinhtanphat/vms-client-web) | Web client |
| [vms-license-server](https://github.com/trinhtanphat/vms-license-server) | License & release management |
| [nx_open](https://github.com/networkoptix/nx_open) | NX Witness / NX Meta SDK |
