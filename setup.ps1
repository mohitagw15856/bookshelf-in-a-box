#Requires -Version 5.1
<#
    bookshelf-in-a-box - interactive setup for Windows (PowerShell)

    Run it from PowerShell in the project folder:
        ./setup.ps1

    Safe to run more than once. It never overwrites your books or an
    existing .env, and it stops with a friendly message rather than a
    stack trace if something is missing.
#>

$ErrorActionPreference = 'Stop'

# --- Pretty output helpers -------------------------------------------------
function Write-Info  { param($m) Write-Host "==> $m" -ForegroundColor Blue }
function Write-Ok    { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host " !  $m" -ForegroundColor Yellow }
function Write-Err2  { param($m) Write-Host " X  $m" -ForegroundColor Red }
function Write-Step  { param($m) Write-Host ""; Write-Host $m -ForegroundColor White }
function Die         { param($m) Write-Err2 $m; exit 1 }

# Always run from the repo root (the folder this script lives in).
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host ""
Write-Host "  bookshelf-in-a-box" -ForegroundColor Cyan
Write-Host "  Your own ebook library, readable on every device." -ForegroundColor Cyan
Write-Host ""

# --- 1. Docker installed? --------------------------------------------------
Write-Step "Step 1/6 - Checking Docker"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err2 "Docker is not installed."
    Write-Host ""
    Write-Host "  Install Docker Desktop for Windows:"
    Write-Host "    https://www.docker.com/products/docker-desktop/"
    Write-Host ""
    Write-Host "  Docker Desktop needs the WSL 2 backend (the installer offers to"
    Write-Host "  set this up for you). After installing, open Docker Desktop once"
    Write-Host "  and wait until it says 'Engine running', then re-run this script."
    Die "Please install Docker, then run ./setup.ps1 again."
}
Write-Ok ("Docker is installed ({0})." -f ((docker --version) -replace ',.*',''))

# Compose v2 (plugin) vs legacy docker-compose
$Compose = $null
try {
    docker compose version *> $null
    if ($LASTEXITCODE -eq 0) { $Compose = 'docker compose' }
} catch { }
if (-not $Compose) {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $Compose = 'docker-compose'
    } else {
        Write-Err2 "Docker is installed but Docker Compose is missing."
        Write-Host "  See: https://docs.docker.com/compose/install/"
        Die "Install Docker Compose, then run ./setup.ps1 again."
    }
}
Write-Ok "Using: $Compose"

# --- 2. Docker daemon running? ---------------------------------------------
try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw "not running" }
} catch {
    Write-Err2 "Docker is installed but the Docker daemon is not running."
    Write-Host ""
    Write-Host "  Start the Docker Desktop app and wait until it reports"
    Write-Host "  'Engine running', then re-run this script."
    Die "Start Docker Desktop, then run ./setup.ps1 again."
}
Write-Ok "Docker daemon is running."

# --- 3. Architecture (informational) ---------------------------------------
Write-Step "Step 2/6 - Detecting your hardware"
$Arch = $env:PROCESSOR_ARCHITECTURE
switch ($Arch) {
    'AMD64' { $ArchLabel = 'x86-64 (Intel/AMD)' }
    'ARM64' { $ArchLabel = 'ARM64' }
    default { $ArchLabel = $Arch }
}
Write-Ok "Architecture: $ArchLabel"

# --- 4. Create data folders (never destructive) ----------------------------
Write-Step "Step 3/6 - Creating data folders"
foreach ($d in @('data/config','data/library','data/ingest','backups')) {
    if (Test-Path $d) {
        Write-Ok "$d already exists (left untouched)."
    } else {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Ok "Created $d"
    }
}

# --- 5. Generate .env (never overwrite) ------------------------------------
Write-Step "Step 4/6 - Configuration (.env)"

if (Test-Path .env) {
    Write-Ok ".env already exists - keeping your existing settings."
    Write-Warn2 "Delete .env and re-run this script if you want to reconfigure."
} else {
    if (-not (Test-Path .env.example)) { Die ".env.example is missing. Re-clone the repository." }

    # Guess timezone from Windows -> best effort, fall back to UTC.
    $DefaultTz = 'Etc/UTC'
    try {
        $winTz = (Get-TimeZone).Id
        if ($winTz) { $DefaultTz = $winTz }  # IANA-ish; user can correct if needed
    } catch { }
    $DefaultPort = '8083'

    $InputTz = Read-Host "  Timezone [$DefaultTz]"
    $InputPort = Read-Host "  Port [$DefaultPort]"

    $TzValue = if ([string]::IsNullOrWhiteSpace($InputTz)) { $DefaultTz } else { $InputTz }
    $PortValue = if ([string]::IsNullOrWhiteSpace($InputPort)) { $DefaultPort } else { $InputPort }

    if ($PortValue -notmatch '^[0-9]+$' -or [int]$PortValue -lt 1 -or [int]$PortValue -gt 65535) {
        Write-Warn2 "'$PortValue' is not a valid port. Falling back to $DefaultPort."
        $PortValue = $DefaultPort
    }

    $content = Get-Content .env.example
    $content = $content -replace '^TZ=.*', "TZ=$TzValue"
    $content = $content -replace '^PORT=.*', "PORT=$PortValue"
    # On Windows the container's PUID/PGID 1000 default is correct.
    Set-Content -Path .env -Value $content -Encoding ASCII
    Write-Ok "Wrote .env (TZ=$TzValue, PORT=$PortValue)"
}

# Read the port back for later messages.
$Port = '8083'
foreach ($line in (Get-Content .env)) {
    if ($line -match '^PORT=(.+)$') { $Port = $Matches[1].Trim() }
}

# --- 6. Start the container -------------------------------------------------
Write-Step "Step 5/6 - Starting your library"
Write-Info "Pulling the latest image and starting up (first run can take a few minutes)..."
if ($Compose -eq 'docker compose') {
    docker compose up -d
} else {
    docker-compose up -d
}
if ($LASTEXITCODE -ne 0) {
    Write-Err2 "Docker Compose failed to start the container."
    Write-Host "  A common cause is port $Port already being in use -"
    Write-Host "  change PORT in .env and run ./setup.ps1 again."
    Die "Startup failed."
}
Write-Ok "Container started."

# --- 7. Wait for health -----------------------------------------------------
Write-Step "Step 6/6 - Waiting for the library to be ready"
$Container = 'bookshelf-in-a-box'
$Ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { $Ready = $true; break }
    } catch {
        $state = (docker inspect -f '{{.State.Status}}' $Container 2>$null)
        if ($state -eq 'exited' -or $state -eq 'dead') {
            Write-Err2 "The container stopped unexpectedly. Recent logs:"
            docker logs --tail 30 $Container
            Die "Startup failed - see logs above."
        }
    }
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 3
}
Write-Host ""

if (-not $Ready) {
    Write-Warn2 "The library did not answer within the expected time."
    Write-Warn2 "It may still be finishing its first-time setup. Check with:"
    Write-Host "    $Compose logs -f"
} else {
    Write-Ok "Your library is up and running!"
}

# --- 8. Local IP for other devices -----------------------------------------
$LocalIp = $null
try {
    $LocalIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Sort-Object -Property SkipAsSource |
        Select-Object -First 1 -ExpandProperty IPAddress)
} catch { }

# --- 9. Final summary -------------------------------------------------------
$IngestPath = Join-Path $ScriptDir 'data\ingest'
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Green
Write-Host "  All done! Your bookshelf is ready." -ForegroundColor Green
Write-Host "------------------------------------------------------------" -ForegroundColor Green
Write-Host ""
Write-Host "  Open your library:"
Write-Host "     On this computer:  http://localhost:$Port" -ForegroundColor Blue
if ($LocalIp) {
    Write-Host "     Other devices on the same WiFi:  http://${LocalIp}:$Port" -ForegroundColor Blue
    Write-Host "     (phones, tablets, e-readers - same network only)"
} else {
    Write-Host "     (Could not auto-detect your local IP - see the README to find it.)"
}
Write-Host ""
Write-Host "  First login:"
Write-Host "     Username:  admin"
Write-Host "     Password:  admin123"
Write-Host ""
Write-Host "  CHANGE THIS PASSWORD IMMEDIATELY." -ForegroundColor Yellow
Write-Host "  Go to  Admin -> Edit User 'admin'  and set a strong password" -ForegroundColor Yellow
Write-Host "  before anyone else can reach this server." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Add your first book:"
Write-Host "     Drop any .epub / .mobi / .pdf into this folder and it imports itself:"
Write-Host "       $IngestPath" -ForegroundColor Blue
Write-Host ""
$ipForOpds = if ($LocalIp) { $LocalIp } else { 'SERVER-IP' }
Write-Host "  Read on your phone / tablet / e-reader (OPDS):"
Write-Host "     http://${ipForOpds}:$Port/opds" -ForegroundColor Blue
Write-Host ""
Write-Host "  Handy commands:"
Write-Host "     Update:   $Compose pull; $Compose up -d"
Write-Host "     Logs:     $Compose logs -f"
Write-Host "     Stop:     $Compose down"
Write-Host ""
Write-Host "  Full guide (reading apps, remote access, troubleshooting): README.md"
Write-Host ""
