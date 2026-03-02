# ============================================================
#  StreamKeep — setup.ps1
#  First-time setup: installs dependencies, signs scripts
#
#  Created by Nirlicnick
#  Run this once before using StreamKeep
# ============================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   S T R E A M K E E P               ║" -ForegroundColor Cyan
Write-Host "  ║   Setup — by Nirlicnick             ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Check winget ──────────────────────────────────────
Write-Host "[1/5] Checking winget..." -ForegroundColor Cyan
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "  winget not found. Please install it from the Microsoft Store (App Installer)." -ForegroundColor Red
    Write-Host "  https://aka.ms/getwinget" -ForegroundColor Yellow
    pause; exit 1
}
Write-Host "  winget OK" -ForegroundColor Green

# ── Step 2: Install Python ────────────────────────────────────
Write-Host "[2/5] Checking Python..." -ForegroundColor Cyan
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing Python..." -ForegroundColor Yellow
    winget install Python.Python.3 --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-Host "  Python OK" -ForegroundColor Green
}

# ── Step 3: Install yt-dlp and ffmpeg ────────────────────────
Write-Host "[3/5] Checking yt-dlp and ffmpeg..." -ForegroundColor Cyan
if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing yt-dlp..." -ForegroundColor Yellow
    winget install yt-dlp --silent --accept-package-agreements --accept-source-agreements
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing ffmpeg..." -ForegroundColor Yellow
    winget install ffmpeg --silent --accept-package-agreements --accept-source-agreements
}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "  yt-dlp and ffmpeg OK" -ForegroundColor Green

# ── Step 4: Install Python packages ──────────────────────────
Write-Host "[4/5] Installing Python packages..." -ForegroundColor Cyan
& python -m pip install --quiet --upgrade customtkinter psutil chat-downloader
Write-Host "  Python packages OK" -ForegroundColor Green

# ── Step 5: Sign PowerShell scripts ──────────────────────────
Write-Host "[5/5] Setting up script signing..." -ForegroundColor Cyan

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $cert) {
    Write-Host "  Creating self-signed certificate..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate `
        -Subject "CN=StreamKeep" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyUsage DigitalSignature `
        -Type CodeSigningCert

    # Trust it so scripts run without warnings
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","CurrentUser")
    $store.Open("ReadWrite")
    $store.Add($cert)
    $store.Close()
    Write-Host "  Certificate created." -ForegroundColor Green
} else {
    Write-Host "  Using existing certificate: $($cert.Subject)" -ForegroundColor Green
}

# Sign all ps1 files
Get-ChildItem $ScriptDir -Filter "*.ps1" | ForEach-Object {
    $result = Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert
    if ($result.Status -eq "Valid") {
        Write-Host "  Signed: $($_.Name)" -ForegroundColor Green
    } else {
        Write-Host "  Failed to sign: $($_.Name)" -ForegroundColor Yellow
    }
}

# ── Create default files if missing ──────────────────────────
$channelsFile = "$ScriptDir\channels.txt"
if (-not (Test-Path $channelsFile)) {
    @"
# StreamKeep — channels to monitor
# One YouTube channel URL per line
# Lines starting with # are ignored
# Example:
#   https://www.youtube.com/@SomeChannel

"@ | Set-Content $channelsFile
    Write-Host "  Created channels.txt" -ForegroundColor Green
}

$backupsDir = "$ScriptDir\StreamBackups"
New-Item -ItemType Directory -Force -Path $backupsDir | Out-Null

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║   Setup complete!                    ║" -ForegroundColor Green
Write-Host "  ║                                      ║" -ForegroundColor Green
Write-Host "  ║   Next steps:                        ║" -ForegroundColor Green
Write-Host "  ║   1. Run StreamKeep.py to open GUI   ║" -ForegroundColor Green
Write-Host "  ║   2. Add channels in the GUI         ║" -ForegroundColor Green
Write-Host "  ║   3. Click START                     ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
pause
