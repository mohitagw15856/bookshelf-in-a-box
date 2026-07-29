#!/usr/bin/env bash
#
# bookshelf-in-a-box — interactive setup for macOS & Linux (incl. Raspberry Pi)
#
# This script is safe to run more than once. It never overwrites your books
# or an existing .env, and it stops with a friendly message if something is
# missing rather than dumping a stack trace.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Pretty output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"; GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"; BLUE="$(printf '\033[34m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

info()  { printf '%s\n' "${BLUE}==>${RESET} $*"; }
ok()    { printf '%s\n' "${GREEN}✓${RESET} $*"; }
warn()  { printf '%s\n' "${YELLOW}!${RESET} $*"; }
err()   { printf '%s\n' "${RED}✗${RESET} $*" >&2; }
step()  { printf '\n%s\n' "${BOLD}$*${RESET}"; }

# Fail with a clear, human-readable message (no stack trace).
die() { err "$*"; exit 1; }

# Always run from the repo root (the folder this script lives in).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

cat <<'BANNER'

  📚  bookshelf-in-a-box
      Your own ebook library, readable on every device.

BANNER

# ---------------------------------------------------------------------------
# 1. Detect the operating system (used for install instructions)
# ---------------------------------------------------------------------------
OS="unknown"
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
esac

# ---------------------------------------------------------------------------
# 2. Check Docker is installed
# ---------------------------------------------------------------------------
step "Step 1/6 — Checking Docker"

if ! command -v docker >/dev/null 2>&1; then
  err "Docker is not installed."
  echo
  if [ "$OS" = "macos" ]; then
    echo "  Install Docker Desktop for Mac:"
    echo "    ${BOLD}https://www.docker.com/products/docker-desktop/${RESET}"
    echo "  Then open the Docker app once so it can finish setting up,"
    echo "  and re-run this script."
  else
    echo "  Install Docker Engine for your Linux distribution:"
    echo "    ${BOLD}https://docs.docker.com/engine/install/${RESET}"
    echo
    echo "  On a Raspberry Pi or Debian/Ubuntu the quickest way is:"
    echo "    ${DIM}curl -fsSL https://get.docker.com | sh${RESET}"
    echo "    ${DIM}sudo usermod -aG docker \"\$USER\"${RESET}   # then log out and back in"
  fi
  echo
  die "Please install Docker, then run ./setup.sh again."
fi
ok "Docker is installed ($(docker --version | sed 's/,.*//'))."

# 'docker compose' (v2) vs old 'docker-compose' (v1)
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  err "Docker is installed but the Compose plugin is missing."
  echo "  See: ${BOLD}https://docs.docker.com/compose/install/${RESET}"
  die "Install Docker Compose, then run ./setup.sh again."
fi
ok "Using: ${COMPOSE}"

# ---------------------------------------------------------------------------
# 3. Check the Docker daemon is actually running
# ---------------------------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  err "Docker is installed but the Docker daemon is not running."
  echo
  if [ "$OS" = "macos" ]; then
    echo "  Start the ${BOLD}Docker Desktop${RESET} app and wait until the whale"
    echo "  icon in the menu bar stops animating, then re-run this script."
  else
    echo "  Start it with:  ${DIM}sudo systemctl start docker${RESET}"
    echo "  If you just added yourself to the 'docker' group, log out and"
    echo "  back in (or run 'newgrp docker') so the change takes effect."
  fi
  echo
  die "Start Docker, then run ./setup.sh again."
fi
ok "Docker daemon is running."

# ---------------------------------------------------------------------------
# 4. Detect CPU architecture (informational — the image is multi-arch)
# ---------------------------------------------------------------------------
step "Step 2/6 — Detecting your hardware"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)          ARCH_LABEL="x86-64 (Intel/AMD)" ;;
  aarch64|arm64)         ARCH_LABEL="ARM64 (Raspberry Pi 4/5, Apple Silicon, etc.)" ;;
  armv7l|armv6l|arm)     ARCH_LABEL="ARM 32-bit" ;;
  *)                     ARCH_LABEL="$ARCH" ;;
esac
ok "Architecture: ${ARCH_LABEL}"
if [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "armv6l" ]; then
  warn "32-bit ARM is unusual for this image. A 64-bit OS (Raspberry Pi OS"
  warn "64-bit) is strongly recommended for best results."
fi

# ---------------------------------------------------------------------------
# 5. Create the data folders (never destructive)
# ---------------------------------------------------------------------------
step "Step 3/6 — Creating data folders"
for d in data/config data/library data/ingest backups; do
  if [ -d "$d" ]; then
    ok "$d already exists (left untouched)."
  else
    mkdir -p "$d"
    ok "Created $d"
  fi
done

# Best-effort ownership fix so the container (PUID/PGID below) can write.
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"
if [ "$CURRENT_UID" != "0" ]; then
  chown -R "$CURRENT_UID:$CURRENT_GID" data 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 6. Generate .env (never overwrite an existing one)
# ---------------------------------------------------------------------------
step "Step 4/6 — Configuration (.env)"

# Try to guess the system timezone.
detect_tz() {
  if [ -f /etc/timezone ]; then
    cat /etc/timezone
  elif [ -L /etc/localtime ]; then
    # e.g. /var/db/timezone/zoneinfo/Europe/London -> Europe/London
    readlink /etc/localtime | sed -E 's#.*/zoneinfo/##'
  elif command -v timedatectl >/dev/null 2>&1; then
    timedatectl show -p Timezone --value 2>/dev/null
  else
    echo "Etc/UTC"
  fi
}

if [ -f .env ]; then
  ok ".env already exists — keeping your existing settings."
  warn "Delete .env and re-run this script if you want to reconfigure."
else
  [ -f .env.example ] || die ".env.example is missing. Re-clone the repository."

  DEFAULT_TZ="$(detect_tz)"
  [ -n "$DEFAULT_TZ" ] || DEFAULT_TZ="Etc/UTC"
  DEFAULT_PORT="8083"

  # Only prompt when we have an interactive terminal; otherwise use defaults.
  if [ -t 0 ]; then
    printf '%s' "  Timezone [${DEFAULT_TZ}]: "
    read -r INPUT_TZ || INPUT_TZ=""
    printf '%s' "  Port [${DEFAULT_PORT}]: "
    read -r INPUT_PORT || INPUT_PORT=""
  else
    INPUT_TZ=""; INPUT_PORT=""
    warn "No interactive terminal detected — using defaults."
  fi

  TZ_VALUE="${INPUT_TZ:-$DEFAULT_TZ}"
  PORT_VALUE="${INPUT_PORT:-$DEFAULT_PORT}"

  # Validate the port is a sensible number.
  if ! printf '%s' "$PORT_VALUE" | grep -Eq '^[0-9]+$' || [ "$PORT_VALUE" -lt 1 ] || [ "$PORT_VALUE" -gt 65535 ]; then
    warn "'$PORT_VALUE' is not a valid port. Falling back to ${DEFAULT_PORT}."
    PORT_VALUE="$DEFAULT_PORT"
  fi

  cp .env.example .env
  # Substitute values portably (works with both GNU and BSD sed).
  sed -i.bak "s|^TZ=.*|TZ=${TZ_VALUE}|" .env && rm -f .env.bak
  sed -i.bak "s|^PORT=.*|PORT=${PORT_VALUE}|" .env && rm -f .env.bak
  sed -i.bak "s|^PUID=.*|PUID=${CURRENT_UID}|" .env && rm -f .env.bak
  sed -i.bak "s|^PGID=.*|PGID=${CURRENT_GID}|" .env && rm -f .env.bak

  ok "Wrote .env (TZ=${TZ_VALUE}, PORT=${PORT_VALUE}, PUID=${CURRENT_UID}, PGID=${CURRENT_GID})"
fi

# Load the values we just wrote (or that already existed) for later messages.
# shellcheck disable=SC1091
set -a; . ./.env; set +a
PORT="${PORT:-8083}"

# ---------------------------------------------------------------------------
# 7. Start the container
# ---------------------------------------------------------------------------
step "Step 5/6 — Starting your library"
info "Pulling the latest image and starting up (first run can take a few minutes)…"
if ! $COMPOSE up -d; then
  err "Docker Compose failed to start the container."
  echo "  Check the output above. A common cause is port ${PORT} already"
  echo "  being in use — change PORT in .env and run ./setup.sh again."
  die "Startup failed."
fi
ok "Container started."

# ---------------------------------------------------------------------------
# 8. Wait for health
# ---------------------------------------------------------------------------
step "Step 6/6 — Waiting for the library to be ready"
CONTAINER="bookshelf-in-a-box"
READY=0
for _ in $(seq 1 60); do
  STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || echo "starting")"
  case "$STATUS" in
    healthy|running)
      # 'running' with no healthcheck, or 'healthy' — good enough to try.
      if curl -fsS "http://localhost:${PORT}/" >/dev/null 2>&1; then
        READY=1; break
      fi
      ;;
    exited|dead)
      err "The container stopped unexpectedly. Recent logs:"
      docker logs --tail 30 "$CONTAINER" 2>&1 | sed 's/^/    /' || true
      die "Startup failed — see logs above."
      ;;
  esac
  printf '.'
  sleep 3
done
printf '\n'

if [ "$READY" -ne 1 ]; then
  warn "The library did not answer within the expected time."
  warn "It may still be finishing its first-time setup. Check with:"
  echo "    ${DIM}$COMPOSE logs -f${RESET}"
else
  ok "Your library is up and running!"
fi

# ---------------------------------------------------------------------------
# 9. Find the local IP for other-device access
# ---------------------------------------------------------------------------
detect_ip() {
  local ip=""
  if [ "$OS" = "macos" ]; then
    for iface in en0 en1; do
      ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
      [ -n "$ip" ] && break
    done
  fi
  if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
  fi
  if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  fi
  printf '%s' "$ip"
}
LOCAL_IP="$(detect_ip)"

# ---------------------------------------------------------------------------
# 10. Final summary
# ---------------------------------------------------------------------------
INGEST_PATH="$SCRIPT_DIR/data/ingest"
cat <<EOF

${GREEN}${BOLD}────────────────────────────────────────────────────────────${RESET}
${GREEN}${BOLD}  🎉  All done! Your bookshelf is ready.${RESET}
${GREEN}${BOLD}────────────────────────────────────────────────────────────${RESET}

  ${BOLD}Open your library:${RESET}
     On this computer:  ${BLUE}http://localhost:${PORT}${RESET}
EOF

if [ -n "$LOCAL_IP" ]; then
  cat <<EOF
     Other devices on the same WiFi:  ${BLUE}http://${LOCAL_IP}:${PORT}${RESET}
     (phones, tablets, e-readers — same network only)
EOF
else
  echo "     (Could not auto-detect your local IP — see the README to find it.)"
fi

cat <<EOF

  ${BOLD}First login:${RESET}
     Username:  ${BOLD}admin${RESET}
     Password:  ${BOLD}admin123${RESET}

  ${YELLOW}${BOLD}⚠  CHANGE THIS PASSWORD IMMEDIATELY.${RESET}
  ${YELLOW}   Go to  Admin → Edit User 'admin'  and set a strong password${RESET}
  ${YELLOW}   before anyone else can reach this server.${RESET}

  ${BOLD}Add your first book:${RESET}
     Drop any .epub / .mobi / .pdf into this folder and it imports itself:
       ${BLUE}${INGEST_PATH}${RESET}

  ${BOLD}Read on your phone / tablet / e-reader (OPDS):${RESET}
     ${BLUE}http://${LOCAL_IP:-SERVER-IP}:${PORT}/opds${RESET}

  Handy commands:
     Update:   ${DIM}./scripts/update.sh${RESET}
     Back up:  ${DIM}./scripts/backup.sh${RESET}
     Logs:     ${DIM}${COMPOSE} logs -f${RESET}
     Stop:     ${DIM}${COMPOSE} down${RESET}

  Full guide (reading apps, remote access, troubleshooting): ${BOLD}README.md${RESET}

EOF
