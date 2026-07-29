#!/usr/bin/env bash
#
# bookshelf-in-a-box — backup script
#
# Creates a timestamped .tar.gz of your library + config into ./backups
# and keeps only the most recent 7 backups. Safe to run any time; it only
# reads your data, it never changes it.
#
# ── Run it nightly with cron ───────────────────────────────────────────────
# Edit your crontab with:  crontab -e
# and add a line like this (runs every night at 3:00 AM). Use ABSOLUTE paths:
#
#   0 3 * * * /home/pi/bookshelf-in-a-box/scripts/backup.sh >> /home/pi/bookshelf-in-a-box/backups/backup.log 2>&1
#
# On macOS, cron works too, or you can use launchd if you prefer.
# ---------------------------------------------------------------------------
set -euo pipefail

# Number of backups to keep.
KEEP=7

# Resolve the repo root regardless of where the script is called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

DATA_DIR="$ROOT_DIR/data"
BACKUP_DIR="$ROOT_DIR/backups"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# Sanity checks with friendly messages.
[ -d "$DATA_DIR/library" ] || die "No library found at $DATA_DIR/library. Run ./setup.sh first."
[ -d "$DATA_DIR/config" ]  || die "No config found at $DATA_DIR/config. Run ./setup.sh first."

mkdir -p "$BACKUP_DIR"

# %Y-%m-%d_%H-%M-%S — sortable and filesystem-safe.
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
ARCHIVE="$BACKUP_DIR/bookshelf-backup_${STAMP}.tar.gz"

echo "==> Backing up library + config to:"
echo "    $ARCHIVE"

# -C so paths inside the archive are relative to ./data (config/, library/).
# Exclude the ingest folder — those are just staging files, not your library.
if tar -czf "$ARCHIVE" -C "$ROOT_DIR" \
      --exclude='data/ingest' \
      data/config data/library; then
  SIZE="$(du -h "$ARCHIVE" | cut -f1)"
  echo "✓ Backup complete (${SIZE})."
  # Best-effort notification (silent if not configured).
  "$SCRIPT_DIR/notify.sh" "Backup complete" "New backup ${SIZE}: $(basename "$ARCHIVE")" >/dev/null 2>&1 || true
else
  # Don't leave a half-written archive behind.
  rm -f "$ARCHIVE"
  "$SCRIPT_DIR/notify.sh" "⚠️ Backup FAILED" "Could not create $(basename "$ARCHIVE")" >/dev/null 2>&1 || true
  die "Backup failed while creating the archive."
fi

# ── Prune old backups, keep the newest $KEEP ───────────────────────────────
# Collect backups via a glob (no fragile `ls` parsing). Our timestamp format
# (%Y-%m-%d_%H-%M-%S) sorts chronologically as plain text, so the glob's
# default alphabetical order is oldest-first.
shopt -s nullglob
ALL_BACKUPS=( "$BACKUP_DIR"/bookshelf-backup_*.tar.gz )
shopt -u nullglob

COUNT="${#ALL_BACKUPS[@]}"
if [ "$COUNT" -gt "$KEEP" ]; then
  REMOVE=$(( COUNT - KEEP ))
  echo "==> Pruning ${REMOVE} old backup(s), keeping the newest ${KEEP}:"
  for (( i = 0; i < REMOVE; i++ )); do
    rm -f "${ALL_BACKUPS[i]}" && echo "    removed $(basename "${ALL_BACKUPS[i]}")"
  done
fi

echo "✓ Done. Backups live in: $BACKUP_DIR"
