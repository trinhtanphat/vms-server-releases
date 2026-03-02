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

Helper script (auto verify + install):

```bash
cd vms-server-releases
./scripts/bootstrap-install.sh latest
```

Manual secure bootstrap:

```bash
set -euo pipefail
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

BASE_URL="https://github.com/trinhtanphat/vms-server-releases/releases/latest/download"
PUBKEY_URL="https://raw.githubusercontent.com/trinhtanphat/vms-server-releases/main/signing/release-signing.pub.pem"
PINNED_PUBKEY_SHA256="46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc"

curl -fsSLO "$BASE_URL/install.sh"
curl -fsSLO "$BASE_URL/install.sh.sig"
curl -fsSL "$PUBKEY_URL" -o release-signing.pub.pem

echo "$PINNED_PUBKEY_SHA256  release-signing.pub.pem" | sha256sum -c -
openssl dgst -sha256 -verify release-signing.pub.pem -signature install.sh.sig install.sh

sudo bash ./install.sh
```

### Windows (PowerShell as Administrator)

Helper script (auto verify + install):

```powershell
cd vms-server-releases
.\scripts\bootstrap-install.ps1 -Version latest
```

Manual secure bootstrap:

```powershell
$base = "https://github.com/trinhtanphat/vms-server-releases/releases/latest/download"
$pub = "https://raw.githubusercontent.com/trinhtanphat/vms-server-releases/main/signing/release-signing.pub.pem"
$pinned = "46b5e96366ec3198de60f39d47130e7143d351ac9a20bce32fb767117579b6bc"

Invoke-WebRequest -Uri "$base/install.ps1" -OutFile install.ps1
Invoke-WebRequest -Uri "$base/install.ps1.sig" -OutFile install.ps1.sig
Invoke-WebRequest -Uri $pub -OutFile release-signing.pub.pem

$actual = (Get-FileHash .\release-signing.pub.pem -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $pinned) { throw "Public key hash mismatch" }

openssl dgst -sha256 -verify .\release-signing.pub.pem -signature .\install.ps1.sig .\install.ps1
.\install.ps1
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
| `REQUIRE_CHECKSUMS=1` | Require SHA256 verification for release assets (default) |
| `ALLOW_UNVERIFIED=1` | Allow install without checksums (emergency only) |
| `REQUIRE_SIGNATURES=1` | Require detached signature verification for `SHA256SUMS` (default) |
| `ALLOW_UNSIGNED=1` | Allow install when checksum signature is unavailable/invalid (emergency only) |
| `REQUIRE_INSTALLER_SIGNATURE=1` | Require detached signature verification for `install.sh` (default) |
| `ALLOW_INSECURE_BOOTSTRAP=1` | Allow installer from stdin/no signature (emergency only) |
| `NX_INSECURE_TLS=1` | Disable TLS verification for NX upstream proxy (emergency only) |
| `NX_TRUST_CHAIN_URL=<url>` | Download NX trust chain PEM for nginx upstream verification |
| `NX_TRUST_CHAIN_PATH=<path>` | Use local NX trust chain PEM for nginx upstream verification |
| `AUTO_ROLLBACK=1` | Auto-rollback upgrade on installer failure (default) |
| `TRUSTED_SIGNING_PUBKEY_SHA256=<hash>` | Override pinned release signing public-key hash |

### Windows Install Options

| Parameter | Description |
|-----------|-------------|
| `-Version "v0.7.0"` | Install specific version |
| `-InstallDir "D:\VMS"` | Custom install directory |
| `-SkipService` | Skip Windows Service creation |
| `-SkipFirewall` | Skip firewall rule creation |
| `-RequireInstallerSignature:$false` | Disable `install.ps1` signature enforcement (emergency only) |
| `-AllowInsecureBootstrap` | Allow execution without signature (stdin/missing `.sig`) |
| `-TrustedSigningPubKeySha256 <hash>` | Override pinned release signing public-key hash |

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

## Uninstall (Linux)

```bash
cd vms-server-releases
sudo ./uninstall.sh
```

Optional destructive flags:

```bash
sudo ./uninstall.sh --purge-data --purge-web --yes
```

## Release Integrity (Installer + SHA256 + Signature)

Installer verifies release assets in two steps:
1. Verify `install.sh` signature (`install.sh.sig`) with pinned release public key
2. Verify `SHA256SUMS` signature (`SHA256SUMS.sig`) with pinned release public key
3. Verify each release asset hash against `SHA256SUMS`

Generate and sign manifest before publishing release:

```bash
cd vms-server-releases
chmod +x scripts/generate-checksums.sh
./scripts/generate-checksums.sh . --sign
```

Upload these release assets together with binaries/installers:
- `SHA256SUMS`
- `SHA256SUMS.sig`
- `install.sh.sig`
- `install.ps1.sig`

Quick verify example:

```bash
sha256sum -c SHA256SUMS
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature SHA256SUMS.sig SHA256SUMS
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.sh.sig install.sh
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.ps1.sig install.ps1
```

Automated release signing is available via GitHub Actions workflow:

- `.github/workflows/release-signing.yml`
- Required secret: `RELEASE_SIGNING_PRIVATE_KEY_PEM`

Local security regression check:

```bash
cd vms-server-releases
./scripts/security-regression-check.sh .
```

PowerShell regression check:

```powershell
.\scripts\security-regression-check.ps1 -Root .
```

Release operator checklist:

- `RELEASE_CHECKLIST.md`

Release governance templates:

- `templates/RELEASE_NOTES_SECURITY_TEMPLATE.md`
- `templates/SECURITY_BYPASS_INCIDENT_TEMPLATE.md`
- `SECURITY_GOVERNANCE.md`
- `BRANCH_PROTECTION_POLICY.md`
- `CODEOWNERS`

Initialize docs for a new release:

```bash
cd vms-server-releases
./scripts/init-release-docs.sh vX.Y.Z release-docs
```

CI automation for release docs:

- Workflow: `.github/workflows/release-docs.yml`
- Trigger: tag push `v*` or manual `workflow_dispatch`
- Output artifact: `release-docs-<version>`

Unified release security gate:

- Workflow: `.github/workflows/security-gate.yml`
- Includes: signing, regression checks, release-doc skeleton generation
- Output artifact: `security-gate-<version>`
- Release tags should be considered valid only when this workflow is green

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

> **Last audit:** 2026-03-02

### Known Issues
| Severity | Issue |
|----------|-------|
| 🟡 Medium | NX upstream may fail on self-signed cert unless proper trust chain is configured |
| 🟢 Low | `apt-get` hardcoded — fails on RHEL/CentOS |
| 🟢 Low | No log rotation, no backup before upgrade |
| 🟢 Low | No uninstall script |

### Recommended
1. Follow NX TLS trust playbook to keep `proxy_ssl_verify on` in production: `NX_TLS_TRUST_PLAYBOOK.md`
2. Add uninstall script and upgrade backup/rollback flow
3. Add package-manager abstraction for non-Debian Linux distributions

## Related Repositories

| Project | Description |
|---------|-------------|
| [vms-server](https://github.com/trinhtanphat/vms-server) | VMS Server source (private) |
| [vms-client-web](https://github.com/trinhtanphat/vms-client-web) | Web client |
| [vms-license-server](https://github.com/trinhtanphat/vms-license-server) | License & release management |
| [nx_open](https://github.com/networkoptix/nx_open) | NX Witness / NX Meta SDK |
