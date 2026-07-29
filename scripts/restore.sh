#!/usr/bin/env bash
#
# bookshelf-in-a-box — restore from a backup
#
# Lists the backups in ./backups, lets you pick one, and restores the
# library + config from it. Before overwriting anything it takes a safety
# snapshot of your current data, so a mistaken restore is always undoable.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then B="$(printf '\033[1m')"; Y="$(printf '\033[33m')"; G="$(printf '\033[32m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; Y=""; G=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

BACKUP_DIR="$ROOT_DIR/backups"
DATA_DIR="$ROOT_DIR/data"

# Collect backups via a glob (timestamped names sort oldest→newest).
shopt -s nullglob
BACKUPS=( "$BACKUP_DIR"/bookshelf-backup_*.tar.gz )
shopt -u nullglob
[ "${#BACKUPS[@]}" -gt 0 ] || die "No backups found in $BACKUP_DIR. Run ./scripts/backup.sh first."

# Optional argument: an explicit archive path.
CHOICE=""
if [ "${1:-}" != "" ]; then
  [ -f "$1" ] || die "Backup file not found: $1"
  CHOICE="$1"
else
  printf '%s\n' "${B}Available backups (newest last):${R}"
  i=1
  for f in "${BACKUPS[@]}"; do
    SIZE="$(du -h "$f" | cut -f1)"
    printf '  %2d) %s  (%s)\n' "$i" "$(basename "$f")" "$SIZE"
    i=$((i + 1))
  done
  DEFAULT=${#BACKUPS[@]}   # newest
  if [ -t 0 ]; then
    printf '%s' "Restore which number? [${DEFAULT} = newest] "
    read -r NUM || NUM=""
  else
    NUM=""
  fi
  NUM="${NUM:-$DEFAULT}"
  printf '%s' "$NUM" | grep -Eq '^[0-9]+$' || die "That wasn't a number."
  if [ "$NUM" -lt 1 ] || [ "$NUM" -gt "${#BACKUPS[@]}" ]; then die "Choice out of range."; fi
  CHOICE="${BACKUPS[$((NUM - 1))]}"
fi

printf '\n%sAbout to restore:%s %s\n' "$B" "$R" "$(basename "$CHOICE")"
printf '%s⚠  This replaces your current library and config.%s\n' "$Y" "$R"
if [ -t 0 ]; then
  printf 'Type %syes%s to continue: ' "$B" "$R"
  read -r CONFIRM || CONFIRM=""
  [ "$CONFIRM" = "yes" ] || die "Cancelled — nothing was changed."
fi

# Stop the container if it's running (ignore errors if compose/docker absent).
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^bookshelf-in-a-box$'; then
  echo "==> Stopping the library while we restore…"
  if docker compose version >/dev/null 2>&1; then docker compose stop >/dev/null 2>&1 || true
  else docker stop bookshelf-in-a-box >/dev/null 2>&1 || true; fi
fi

# Safety snapshot of current data before we touch it.
if [ -d "$DATA_DIR/library" ] || [ -d "$DATA_DIR/config" ]; then
  SNAP="$BACKUP_DIR/pre-restore-snapshot_$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
  echo "==> Saving a safety snapshot of your current data:"
  echo "    $SNAP"
  tar -czf "$SNAP" -C "$ROOT_DIR" --exclude='data/ingest' data/config data/library 2>/dev/null || \
    echo "    (nothing to snapshot yet — continuing)"
fi

echo "==> Restoring from backup…"
mkdir -p "$DATA_DIR"
# The archive stores paths as data/config and data/library.
tar -xzf "$CHOICE" -C "$ROOT_DIR" || die "Restore failed while extracting the archive."

echo "${G}✓${R} Restore complete."
echo "  Start the library again with:  ${C}./bin/bookshelf up${R}  (or ./setup.sh)"
