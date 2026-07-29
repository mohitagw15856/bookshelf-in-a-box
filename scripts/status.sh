#!/usr/bin/env bash
#
# bookshelf-in-a-box — status dashboard
#
# A quick health check: is the server up, how many books, disk space, and
# when did we last back up. Read-only — it never changes anything.
#
#   ./scripts/status.sh          pretty terminal output
#   ./scripts/status.sh --html   also write a snapshot to data/status-report.html
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then B="$(printf '\033[1m')"; D="$(printf '\033[2m')"; G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; RED="$(printf '\033[31m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; D=""; G=""; Y=""; RED=""; C=""; R=""; fi

CONTAINER="bookshelf-in-a-box"
WANT_HTML=0
[ "${1:-}" = "--html" ] && WANT_HTML=1

# PORT from .env
PORT="8083"
[ -f .env ] && PORT="$(grep -E '^PORT=' .env | tail -1 | cut -d= -f2 || echo 8083)"
PORT="${PORT:-8083}"

# --- gather facts ---
STATE="not created"; HEALTH="-"
if command -v docker >/dev/null 2>&1; then
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    STATE="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo unknown)"
    HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$CONTAINER" 2>/dev/null || echo -)"
  fi
fi

# book count: count ebook files in the library
BOOK_COUNT=0
if [ -d data/library ]; then
  BOOK_COUNT="$(find data/library -type f \( \
      -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.azw' \
      -o -iname '*.pdf' -o -iname '*.cbz' -o -iname '*.cbr' -o -iname '*.fb2' \
      -o -iname '*.djvu' -o -iname '*.txt' \) 2>/dev/null | wc -l | tr -d ' ')"
fi

# ingest queue
INGEST_COUNT=0
[ -d data/ingest ] && INGEST_COUNT="$(find data/ingest -type f 2>/dev/null | wc -l | tr -d ' ')"

# library size
LIB_SIZE="-"; [ -d data/library ] && LIB_SIZE="$(du -sh data/library 2>/dev/null | cut -f1)"

# disk free on the data volume
DISK_FREE="-"; DISK_USE="-"
if command -v df >/dev/null 2>&1; then
  DISK_FREE="$(df -h . 2>/dev/null | awk 'NR==2{print $4}')"
  DISK_USE="$(df -h . 2>/dev/null | awk 'NR==2{print $5}')"
fi

# last backup
LAST_BACKUP="never"
shopt -s nullglob
BK=( backups/bookshelf-backup_*.tar.gz )
shopt -u nullglob
if [ "${#BK[@]}" -gt 0 ]; then
  NEWEST="${BK[$(( ${#BK[@]} - 1 ))]}"
  LAST_BACKUP="$(basename "$NEWEST" | sed -E 's/bookshelf-backup_([0-9-]+)_([0-9-]+)\.tar\.gz/\1 \2/; s/-/:/3g')"
fi

# reachable?
REACH="no"
if command -v curl >/dev/null 2>&1 && curl -fsS "http://localhost:${PORT}/" >/dev/null 2>&1; then REACH="yes"; fi

# --- health verdict ---
if [ "$HEALTH" = "healthy" ] || { [ "$STATE" = "running" ] && [ "$REACH" = "yes" ]; }; then
  VERDICT="${G}● healthy${R}"; PLAIN="healthy"
elif [ "$STATE" = "running" ]; then
  VERDICT="${Y}● starting / running${R}"; PLAIN="running"
elif [ "$STATE" = "not created" ]; then
  VERDICT="${D}○ not set up yet${R}"; PLAIN="not set up"
else
  VERDICT="${RED}● ${STATE}${R}"; PLAIN="$STATE"
fi

# --- print ---
printf '\n  %s📚 bookshelf-in-a-box — status%s\n' "$B" "$R"
printf '  %s────────────────────────────────────────%s\n' "$D" "$R"
printf '  Server        %s\n' "$VERDICT"
printf '  Web UI        %shttp://localhost:%s%s  (reachable: %s)\n' "$C" "$PORT" "$R" "$REACH"
printf '  Books         %s%s%s\n' "$B" "$BOOK_COUNT" "$R"
printf '  In ingest     %s waiting to import\n' "$INGEST_COUNT"
printf '  Library size  %s\n' "$LIB_SIZE"
printf '  Disk free     %s (used %s)\n' "$DISK_FREE" "$DISK_USE"
printf '  Last backup   %s\n' "$LAST_BACKUP"
printf '  %s────────────────────────────────────────%s\n\n' "$D" "$R"

if [ "$WANT_HTML" -eq 1 ]; then
  OUT="data/status-report.html"
  cat > "$OUT" <<HTML
<!doctype html><meta charset="utf-8"><title>bookshelf status</title>
<style>body{font:15px system-ui,sans-serif;background:#0f1424;color:#e9edfb;margin:0;padding:40px}
.card{max-width:520px;margin:auto;background:#141a2e;border:1px solid #28304d;border-radius:16px;padding:26px}
h1{font-size:20px;margin:0 0 16px}.row{display:flex;justify-content:space-between;padding:9px 0;border-bottom:1px solid #28304d}
.row:last-child{border:0}.k{color:#8b93b4}.ok{color:#34d399}small{color:#8b93b4}</style>
<div class="card"><h1>📚 bookshelf-in-a-box</h1>
<div class="row"><span class="k">Server</span><b class="ok">${PLAIN}</b></div>
<div class="row"><span class="k">Books</span><b>${BOOK_COUNT}</b></div>
<div class="row"><span class="k">In ingest</span><b>${INGEST_COUNT}</b></div>
<div class="row"><span class="k">Library size</span><b>${LIB_SIZE}</b></div>
<div class="row"><span class="k">Disk free</span><b>${DISK_FREE}</b></div>
<div class="row"><span class="k">Last backup</span><b>${LAST_BACKUP}</b></div>
</div>
<p style="text-align:center"><small>Snapshot — re-run ./scripts/status.sh --html to refresh</small></p>
HTML
  printf '  %s✓%s Wrote snapshot to %s\n\n' "$G" "$R" "$OUT"
fi
