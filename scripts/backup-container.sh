#!/bin/sh
#
# In-container backup runner (used by docker-compose.backup.yml).
#
# Runs inside a tiny Alpine/busybox container on a schedule. It tars the
# mounted /data/config and /data/library into /backups and prunes old ones.
# POSIX sh only — no bash features.
#
set -eu

KEEP="${KEEP:-7}"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
ARCHIVE="/backups/bookshelf-backup_${STAMP}.tar.gz"

echo "[$(date)] creating $ARCHIVE"
if tar -czf "$ARCHIVE" -C /data config library 2>/dev/null; then
  echo "[$(date)] backup ok"
else
  rm -f "$ARCHIVE"
  echo "[$(date)] backup FAILED" >&2
  exit 1
fi

# Prune: keep the newest $KEEP. Timestamped names sort chronologically,
# so a plain glob is oldest-first.
set -- /backups/bookshelf-backup_*.tar.gz
[ -e "$1" ] || set --
count=$#
if [ "$count" -gt "$KEEP" ]; then
  remove=$((count - KEEP))
  i=0
  for f in "$@"; do
    i=$((i + 1))
    if [ "$i" -le "$remove" ]; then
      rm -f "$f" && echo "[$(date)] pruned $(basename "$f")"
    fi
  done
fi
