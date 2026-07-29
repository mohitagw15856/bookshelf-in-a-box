#!/usr/bin/env bash
#
# bookshelf-in-a-box — run as a system service (Linux / systemd)
#
# Installs a systemd unit so your library starts automatically on boot and
# restarts cleanly — ideal for a headless mini-PC or Raspberry Pi.
#
#   sudo ./scripts/install-service.sh            install & enable
#   sudo ./scripts/install-service.sh --uninstall
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -t 1 ]; then B="$(printf '\033[1m')"; G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; G=""; Y=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

command -v systemctl >/dev/null 2>&1 || die "This machine doesn't use systemd. On macOS/Windows, Docker Desktop already starts on login."

UNIT="/etc/systemd/system/bookshelf.service"

if [ "$(id -u)" -ne 0 ]; then
  echo "This needs root to write $UNIT. Re-run with sudo:"
  echo "    ${C}sudo $0 $*${R}"
  exit 1
fi

if [ "${1:-}" = "--uninstall" ]; then
  systemctl disable --now bookshelf.service 2>/dev/null || true
  rm -f "$UNIT"
  systemctl daemon-reload
  printf '%s✓%s Service removed.\n' "$G" "$R"
  exit 0
fi

DOCKER_BIN="$(command -v docker || echo /usr/bin/docker)"
# Prefer the invoking user so the container's PUID/PGID stay consistent.
RUN_USER="${SUDO_USER:-root}"

cat > "$UNIT" <<UNITEOF
[Unit]
Description=bookshelf-in-a-box (self-hosted ebook library)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${ROOT_DIR}
User=${RUN_USER}
ExecStart=${DOCKER_BIN} compose up -d
ExecStop=${DOCKER_BIN} compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now bookshelf.service

printf '\n%s✓%s Installed and started as a service.\n' "$G" "$R"
printf '  Runs as user: %s%s%s   Working dir: %s%s%s\n' "$B" "$RUN_USER" "$R" "$B" "$ROOT_DIR" "$R"
printf '  Manage it with:\n'
printf '    %ssystemctl status bookshelf%s\n' "$C" "$R"
printf '    %ssudo systemctl restart bookshelf%s\n' "$C" "$R"
printf '    %ssudo ./scripts/install-service.sh --uninstall%s\n\n' "$C" "$R"
