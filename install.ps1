#
# VMS Server Installation Script for Windows
# Run as Administrator in PowerShell:
#
#   irm https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.ps1 | iex
#
# Or download and run:
#   Invoke-WebRequest -Uri https://github.com/trinhtanphat/vms-server-releases/releases/latest/download/install.ps1 -OutFile install.ps1
#   .\install.ps1
#
# Options:
#   .\install.ps1 -Version "v0.7.0"
#   .\install.ps1 -InstallDir "D:\VMS-Server"
#   .\install.ps1 -SkipService
#

param(
    [string]$Version = "",
    [string]$InstallDir = "$env:ProgramFiles\VMS-Server",
    [switch]$SkipService,
    [switch]$SkipFirewall
)

$ErrorActionPreference = "Stop"

# ============================================================
# Configuration
# ============================================================
$ServiceName = "VMSServer"
$ServiceDisplayName = "VMS Server - Video Management System"
$GithubRepo = "trinhtanphat/vms-server-releases"
$ConfigDir = "$env:ProgramData\VMS-Server"
$DataDir = "$env:ProgramData\VMS-Server\data"
$LogDir = "$env:ProgramData\VMS-Server\logs"
$PluginDir = "$env:ProgramData\VMS-Server\plugins"
$StreamDir = "$env:ProgramData\VMS-Server\streams"

# ============================================================
# Banner
# ============================================================
Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "        VMS Server - Windows Installer             " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""

# ============================================================
# 1/7 Pre-flight Checks
# ============================================================
Write-Host "`n--- 1/7 Pre-flight Checks ---" -ForegroundColor Cyan

# Check admin privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERR] Please run as Administrator" -ForegroundColor Red
    Write-Host "      Right-click PowerShell > 'Run as administrator'" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK]  Running as Administrator" -ForegroundColor Green

# OS Info
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Host "[INFO] OS: $($osInfo.Caption) $($osInfo.Version)" -ForegroundColor Blue

# Architecture
$arch = [System.Environment]::Is64BitOperatingSystem
if (-not $arch) {
    Write-Host "[ERR] 64-bit Windows required" -ForegroundColor Red
    exit 1
}
Write-Host "[INFO] Architecture: x64" -ForegroundColor Blue

# RAM
$totalRAM = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 1)
Write-Host "[INFO] RAM: ${totalRAM} GB" -ForegroundColor Blue

# GPU detection
try {
    $gpus = Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }
    if ($gpus) {
        foreach ($gpu in $gpus) {
            $vram = [math]::Round($gpu.AdapterRAM / 1GB, 1)
            Write-Host "[OK]  GPU detected: $($gpu.Name) ($vram GB)" -ForegroundColor Green
        }
        $HasGPU = $true
    } else {
        Write-Host "[INFO] No NVIDIA GPU detected - AI analytics will use CPU" -ForegroundColor Blue
        $HasGPU = $false
    }
} catch {
    $HasGPU = $false
}

# Check port conflicts
foreach ($port in @(8080, 8443)) {
    $listener = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($listener) {
        $proc = Get-Process -Id $listener[0].OwningProcess -ErrorAction SilentlyContinue
        Write-Host "[WARN] Port $port is already in use by: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
        Write-Host "       VMS Server needs ports 8080 and 8443." -ForegroundColor Yellow
        $response = Read-Host "       Continue anyway? [y/N]"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Host "[INFO] Cancelled. Free port $port and try again." -ForegroundColor Blue
            exit 0
        }
    }
}

# Check for existing installation
$Upgrading = $false
if (Test-Path "$InstallDir\vms-server.exe") {
    try {
        $currentVer = & "$InstallDir\vms-server.exe" --version 2>$null
        Write-Host "[WARN] Existing VMS Server found ($currentVer) - upgrading" -ForegroundColor Yellow
    } catch {
        Write-Host "[WARN] Existing VMS Server found - upgrading" -ForegroundColor Yellow
    }
    $Upgrading = $true
}

# ============================================================
# 2/7 Fetch Version
# ============================================================
Write-Host "`n--- 2/7 Fetching VMS Server ---" -ForegroundColor Cyan

if ($Version) {
    $LatestVersion = $Version
    Write-Host "[INFO] Using specified version: $LatestVersion" -ForegroundColor Blue
} else {
    Write-Host "[INFO] Fetching latest version from GitHub..." -ForegroundColor Blue
    try {
        # Use TLS 1.2 for GitHub API
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$GithubRepo/releases/latest"
        $LatestVersion = $releaseInfo.tag_name
        Write-Host "[OK]  Latest version: $LatestVersion" -ForegroundColor Green
    } catch {
        Write-Host "[ERR] Failed to fetch version: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================
# 3/7 Download & Install
# ============================================================
Write-Host "`n--- 3/7 Downloading & Installing ---" -ForegroundColor Cyan

$DownloadUrl = "https://github.com/$GithubRepo/releases/download/$LatestVersion/vms-server-windows-x64.zip"
Write-Host "[INFO] Downloading from: $DownloadUrl" -ForegroundColor Blue

# Create directories
foreach ($dir in @($InstallDir, $ConfigDir, $DataDir, "$DataDir\recordings", $LogDir, $PluginDir, "$PluginDir\models", $StreamDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# Stop existing service if upgrading
if ($Upgrading) {
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService -and $existingService.Status -eq 'Running') {
        Write-Host "[INFO] Stopping existing service..." -ForegroundColor Blue
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
}

# Download
$TempDir = Join-Path $env:TEMP "vms-server-install-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$ZipPath = "$TempDir\vms-server.zip"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'  # Speed up download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
    $ProgressPreference = 'Continue'
    Write-Host "[OK]  Downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "[ERR] Failed to download: $_" -ForegroundColor Red
    Write-Host "      URL: $DownloadUrl" -ForegroundColor Red
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Extract
Write-Host "[INFO] Extracting..." -ForegroundColor Blue
try {
    Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force

    # Find the extracted directory (could be nested)
    $SourceDir = Get-ChildItem -Path $TempDir -Directory | Where-Object { $_.Name -like "vms-server*" } | Select-Object -First 1
    if (-not $SourceDir) {
        $SourceDir = Get-Item $TempDir
    }

    # Copy files
    Copy-Item -Path "$($SourceDir.FullName)\*" -Destination $InstallDir -Recurse -Force
    Write-Host "[OK]  Installed to $InstallDir" -ForegroundColor Green
} catch {
    Write-Host "[ERR] Extract failed: $_" -ForegroundColor Red
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Copy config if not present
if (-not (Test-Path "$ConfigDir\server.json") -and (Test-Path "$InstallDir\config\server.json")) {
    Copy-Item -Path "$InstallDir\config\server.json" -Destination "$ConfigDir\server.json"
    Write-Host "[OK]  Default config copied to $ConfigDir\server.json" -ForegroundColor Green
}

# Copy plugins  
if (Test-Path "$InstallDir\plugins") {
    Copy-Item -Path "$InstallDir\plugins\*" -Destination $PluginDir -Recurse -Force -ErrorAction SilentlyContinue
    $pluginCount = (Get-ChildItem -Path $PluginDir -Filter "*.dll" -ErrorAction SilentlyContinue).Count
    if ($pluginCount -gt 0) {
        Write-Host "[OK]  $pluginCount analytics plugin(s) installed" -ForegroundColor Green
    }
}

# Copy models
if (Test-Path "$InstallDir\models") {
    Copy-Item -Path "$InstallDir\models\*" -Destination "$PluginDir\models" -Force -ErrorAction SilentlyContinue
    $modelCount = (Get-ChildItem -Path "$PluginDir\models" -ErrorAction SilentlyContinue).Count
    if ($modelCount -gt 0) {
        Write-Host "[OK]  $modelCount AI model(s) installed" -ForegroundColor Green
    }
}

# Add to PATH
$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not $envPath.Contains($InstallDir)) {
    [Environment]::SetEnvironmentVariable("Path", "$envPath;$InstallDir", "Machine")
    Write-Host "[OK]  Added to system PATH" -ForegroundColor Green
}

# Cleanup
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# 4/7 Analytics Plugins
# ============================================================
Write-Host "`n--- 4/7 Analytics Plugins ---" -ForegroundColor Cyan

$PluginUrl = "https://github.com/$GithubRepo/releases/download/$LatestVersion/analytics-plugins-windows-x64.zip"
$TempPlugin = Join-Path $env:TEMP "vms-plugins-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TempPlugin | Out-Null

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $PluginUrl -OutFile "$TempPlugin\plugins.zip" -UseBasicParsing -ErrorAction Stop
    $ProgressPreference = 'Continue'
    Expand-Archive -Path "$TempPlugin\plugins.zip" -DestinationPath $TempPlugin -Force

    # Copy plugin DLLs
    Get-ChildItem -Path $TempPlugin -Filter "*.dll" -Recurse | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $PluginDir -Force
    }
    # Copy models
    if (Test-Path "$TempPlugin\models") {
        Copy-Item -Path "$TempPlugin\models\*" -Destination "$PluginDir\models" -Force -ErrorAction SilentlyContinue
    }

    $pluginCount = (Get-ChildItem -Path $PluginDir -Filter "*.dll" -ErrorAction SilentlyContinue).Count
    Write-Host "[OK]  $pluginCount analytics plugin(s) available" -ForegroundColor Green

    if ($HasGPU) {
        Write-Host "[INFO] GPU detected - plugins will use GPU acceleration" -ForegroundColor Blue
    }
} catch {
    Write-Host "[WARN] Analytics plugin package not available for Windows in this release" -ForegroundColor Yellow
    Write-Host "       Plugins from main package will be used (if any)" -ForegroundColor Yellow
}
Remove-Item -Path $TempPlugin -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# 5/7 Windows Service
# ============================================================
if (-not $SkipService) {
    Write-Host "`n--- 5/7 Windows Service ---" -ForegroundColor Cyan

    $ExePath = "$InstallDir\vms-server.exe"

    if (-not (Test-Path $ExePath)) {
        Write-Host "[ERR] vms-server.exe not found at $ExePath" -ForegroundColor Red
        exit 1
    }

    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        # Update existing service
        & sc.exe config $ServiceName binPath= "`"$ExePath`"" | Out-Null
        Write-Host "[OK]  Service updated" -ForegroundColor Green
    } else {
        # Create new service
        New-Service -Name $ServiceName `
                    -DisplayName $ServiceDisplayName `
                    -Description "Video Management System Server - Camera management, recording, analytics" `
                    -BinaryPathName "`"$ExePath`"" `
                    -StartupType Automatic | Out-Null
        Write-Host "[OK]  Service created: $ServiceName" -ForegroundColor Green
    }

    # Configure service recovery (restart on failure)
    & sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
    Write-Host "[OK]  Service recovery policy configured (auto-restart on failure)" -ForegroundColor Green

    # Start service
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop

        # Wait for service to be running
        $maxWait = 10
        for ($i = 0; $i -lt $maxWait; $i++) {
            Start-Sleep -Seconds 1
            $svc = Get-Service -Name $ServiceName
            if ($svc.Status -eq 'Running') {
                Write-Host "[OK]  VMS Server is running" -ForegroundColor Green
                break
            }
            if ($i -eq ($maxWait - 1)) {
                Write-Host "[WARN] Service may not have started yet" -ForegroundColor Yellow
                Write-Host "       Check: Get-Service $ServiceName" -ForegroundColor Yellow
                Write-Host "       Logs:  Get-EventLog -LogName Application -Source $ServiceName -Newest 10" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "[WARN] Failed to start service: $_" -ForegroundColor Yellow
        Write-Host "       Try: Start-Service $ServiceName" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n--- 5/7 Windows Service (skipped) ---" -ForegroundColor Cyan
}

# ============================================================
# 6/7 Firewall
# ============================================================
if (-not $SkipFirewall) {
    Write-Host "`n--- 6/7 Firewall ---" -ForegroundColor Cyan

    $rules = @(
        @{ Name = "VMS Server HTTP";  Port = 8080; Protocol = "TCP" },
        @{ Name = "VMS Server HTTPS"; Port = 8443; Protocol = "TCP" },
        @{ Name = "VMS Server RTSP";  Port = 8554; Protocol = "TCP" }
    )

    foreach ($rule in $rules) {
        $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $rule.Name `
                                -Direction Inbound `
                                -Protocol $rule.Protocol `
                                -LocalPort $rule.Port `
                                -Action Allow | Out-Null
        }
    }
    Write-Host "[OK]  Firewall rules configured (8080, 8443, 8554)" -ForegroundColor Green
} else {
    Write-Host "`n--- 6/7 Firewall (skipped) ---" -ForegroundColor Cyan
}

# ============================================================
# 7/7 Installation Complete
# ============================================================
Write-Host "`n--- 7/7 Installation Complete ---" -ForegroundColor Cyan

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "      VMS Server - Installation Complete           " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Version:      $LatestVersion"
Write-Host "  Install Dir:  $InstallDir"
Write-Host "  Config:       $ConfigDir\server.json"
Write-Host "  Data:         $DataDir"
Write-Host "  Plugins:      $PluginDir"
Write-Host "  Logs:         $LogDir"

if ($HasGPU) {
    Write-Host ""
    Write-Host "  GPU:          $($gpus[0].Name)"
}

Write-Host ""
Write-Host "Service Commands (PowerShell as Admin):" -ForegroundColor White
Write-Host "  Get-Service $ServiceName            # Check status"
Write-Host "  Restart-Service $ServiceName         # Restart"
Write-Host "  Stop-Service $ServiceName            # Stop"
Write-Host "  Get-EventLog -LogName Application -Source $ServiceName -Newest 20  # Logs"

Write-Host ""
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host "       FIRST-TIME SETUP (IMPORTANT!)               " -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  You must create an admin account before using VMS Server."
Write-Host ""
Write-Host "  Option 1 - PowerShell:" -ForegroundColor White
Write-Host '  Invoke-RestMethod -Method POST -Uri "https://localhost:8443/rest/v2/system/setup" `'
Write-Host '    -ContentType "application/json" -SkipCertificateCheck `'
Write-Host '    -Body ''{"username":"admin","password":"your-secure-password"}'''
Write-Host ""
Write-Host "  Option 2 - Web Browser:" -ForegroundColor White
Write-Host "  Open any VMS Client Web and connect to this server"
Write-Host ""
Write-Host "Connect from VMS Client:" -ForegroundColor White
Write-Host "  1. Open any VMS Client Web (e.g., https://vmsclient.vnso.vn)"
Write-Host "  2. Add Server -> Host: <this-pc-ip>, Port: 8080"
Write-Host "  3. Login with the admin account you created"
Write-Host ""
Write-Host "Health check: http://localhost:8080/api/health" -ForegroundColor Blue
Write-Host ""
Write-Host "Done! Your VMS Server is ready." -ForegroundColor Green
