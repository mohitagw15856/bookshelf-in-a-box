#!/usr/bin/env bash
#
# bookshelf-in-a-box — doctor
#
# Checks the things beginners most often trip over and tells you exactly how
# to fix each one. Read-only: it never changes anything.
#
set -uo pipefail   # (no -e: we want to run every check and summarise)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR" || exit 1

if [ -t 1 ]; then B="$(printf '\033[1m')"; D="$(printf '\033[2m')"; G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; RED="$(printf '\033[31m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; D=""; G=""; Y=""; RED=""; C=""; R=""; fi

PASS=0; WARN=0; FAIL=0
pass(){ printf '  %s✓%s %s\n' "$G" "$R" "$1"; PASS=$((PASS+1)); }
warn(){ printf '  %s!%s %s\n' "$Y" "$R" "$1"; [ -n "${2:-}" ] && printf '      %s↳ %s%s\n' "$D" "$2" "$R"; WARN=$((WARN+1)); }
fail(){ printf '  %s✗%s %s\n' "$RED" "$R" "$1"; [ -n "${2:-}" ] && printf '      %s↳ %s%s\n' "$D" "$2" "$R"; FAIL=$((FAIL+1)); }

PORT="8083"
[ -f .env ] && PORT="$(grep -E '^PORT=' .env | tail -1 | cut -d= -f2 || echo 8083)"
PORT="${PORT:-8083}"
CONTAINER="bookshelf-in-a-box"

printf '\n  %s🩺 bookshelf doctor%s\n\n' "$B" "$R"

# 1. Docker installed
if command -v docker >/dev/null 2>&1; then
  pass "Docker is installed ($(docker --version | sed 's/,.*//'))."
else
  fail "Docker is not installed." "Install it: https://www.docker.com/products/docker-desktop/  then re-run ./setup.sh"
fi

# 2. Docker daemon running
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then pass "Docker daemon is running."
  else fail "Docker is installed but not running." "Start Docker Desktop (or 'sudo systemctl start docker') and try again."; fi
fi

# 3. Compose available
if docker compose version >/dev/null 2>&1; then pass "Docker Compose v2 is available."
elif command -v docker-compose >/dev/null 2>&1; then warn "Using legacy docker-compose v1." "Consider upgrading to Docker Compose v2."
else fail "Docker Compose not found." "See https://docs.docker.com/compose/install/"; fi

# 4. .env sanity
if [ -f .env ]; then
  pass ".env exists."
  if ! printf '%s' "$PORT" | grep -Eq '^[0-9]+$'; then
    fail "PORT in .env isn't a number ('$PORT')." "Set PORT=8083 (or another free port)."
  fi
  TZv="$(grep -E '^TZ=' .env | tail -1 | cut -d= -f2 || true)"
  if [ -n "$TZv" ]; then pass "Timezone is set (TZ=$TZv)."; else warn "TZ not set in .env." "Add TZ=Region/City for correct timestamps."; fi
else
  warn ".env not found — defaults will be used." "Run ./setup.sh to create one."
fi

# 5. Data folders + permissions
for d in data/config data/library data/ingest; do
  if [ -d "$d" ]; then
    if [ -w "$d" ]; then pass "$d exists and is writable."
    else fail "$d is not writable by you." "Fix: sudo chown -R \$(id -u):\$(id -g) data"; fi
  else
    warn "$d does not exist yet." "It's created by ./setup.sh on first run."
  fi
done

# 6. Ownership vs PUID/PGID
if [ -d data/library ] && command -v stat >/dev/null 2>&1; then
  OWNER="$(stat -c '%u' data/library 2>/dev/null || stat -f '%u' data/library 2>/dev/null || echo '')"
  PUID="1000"; [ -f .env ] && PUID="$(grep -E '^PUID=' .env | tail -1 | cut -d= -f2 || echo 1000)"
  if [ -n "$OWNER" ] && [ "$OWNER" != "$PUID" ] && [ "$OWNER" != "0" ]; then
    warn "data/ is owned by uid $OWNER but PUID=$PUID." "If imports fail: sudo chown -R $PUID:$PUID data"
  fi
fi

# 7. Disk space
if command -v df >/dev/null 2>&1; then
  AVAIL_K="$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "$AVAIL_K" ]; then
    if [ "$AVAIL_K" -lt 2097152 ]; then fail "Low disk space ($(df -Ph . | awk 'NR==2{print $4}') free)." "Free up space or delete old backups."
    else pass "Disk space OK ($(df -Ph . | awk 'NR==2{print $4}') free)."; fi
  fi
fi

# 8. Windows/WSL path hint
case "$ROOT_DIR" in
  /mnt/[a-z]/*) warn "Project is on a Windows drive via WSL ($ROOT_DIR)." "Books may not import and it's slow. Move it under your Linux home (e.g. ~/bookshelf-in-a-box).";;
esac

# 9. Port conflict (only if daemon up)
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  OURS="$(docker ps --filter "name=^${CONTAINER}$" --format '{{.Names}}' 2>/dev/null || true)"
  if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
    if [ -n "$OURS" ]; then pass "Port ${PORT} is in use by bookshelf (expected)."
    else warn "Port ${PORT} is in use by something else." "Change PORT in .env, then ./bin/bookshelf up."; fi
  else
    pass "Port ${PORT} is free."
  fi
fi

# 10. Container status + recent errors
if command -v docker >/dev/null 2>&1 && docker inspect "$CONTAINER" >/dev/null 2>&1; then
  ST="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)"
  HE="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$CONTAINER" 2>/dev/null)"
  case "$ST" in
    running) if [ "$HE" = "unhealthy" ]; then fail "Container is running but unhealthy." "Check logs: ${C}docker compose logs --tail 50${R}"; else pass "Container is running (health: $HE)."; fi;;
    exited|dead) fail "Container is $ST." "Start it: ./bin/bookshelf up  — or check logs.";;
    *) warn "Container status: $ST.";;
  esac
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  warn "Container not created yet." "Run ./setup.sh (or ./bin/bookshelf up)."
fi

# 11. Stuck ingest files
if [ -d data/ingest ]; then
  N="$(find data/ingest -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$N" -gt 0 ] && warn "$N file(s) sitting in data/ingest." "They should import within a minute. If stuck, check logs and file permissions."
fi

# --- summary ---
printf '\n  %s────────────────────────────────────────%s\n' "$D" "$R"
printf '  %s%s passed%s · %s%s warnings%s · %s%s problems%s\n\n' "$G" "$PASS" "$R" "$Y" "$WARN" "$R" "$RED" "$FAIL" "$R"
if [ "$FAIL" -gt 0 ]; then
  printf '  %sSome checks failed — fix the ↳ items above, then run doctor again.%s\n\n' "$RED" "$R"
  exit 1
fi
printf '  %sLooking healthy!%s\n\n' "$G" "$R"
