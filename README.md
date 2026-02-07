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

Connect from any VMS Client:
1. Open any VMS Client Web app (e.g., `https://vmsclient.vnso.vn`)
2. Add Server → enter your domain, Port 443, Protocol HTTPS
3. Login with your credentials

Or open `https://your-domain/` directly if web client was deployed.

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

## Related Repositories

- [vms-server](https://github.com/trinhtanphat/vms-server) — VMS Server source code
- [vms-client-web](https://github.com/trinhtanphat/vms-client-web) — VMS Web Client (React/TypeScript)
- [nx_open](https://github.com/networkoptix/nx_open) — NX Witness / NX Meta SDK
