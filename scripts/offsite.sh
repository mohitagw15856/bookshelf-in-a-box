#!/usr/bin/env bash
#
# bookshelf-in-a-box — off-site backups (rclone)
#
# Copy your local backups to the cloud (Google Drive, Backblaze B2, S3,
# Dropbox, …) so a dead disk or a house fire doesn't lose your library.
# Uses the official rclone container — nothing to install on your machine.
#
#   ./scripts/offsite.sh setup     configure a cloud remote (one time)
#   ./scripts/offsite.sh remotes   list configured remotes
#   ./scripts/offsite.sh sync      push ./backups to the cloud now
#   ./scripts/offsite.sh pull      fetch cloud backups back into ./backups
#
# For encryption, create an rclone "crypt" remote during setup (recommended)
# and point OFFSITE_REMOTE at it, e.g.  OFFSITE_REMOTE=bookshelf-crypt:
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else G=""; Y=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is required (it runs rclone for you)."
[ -f .env ] && { set -a; # shellcheck disable=SC1091
  . ./.env; set +a; }

CONF_DIR="$ROOT_DIR/data/rclone"
BACKUPS="$ROOT_DIR/backups"
mkdir -p "$CONF_DIR" "$BACKUPS"
IMAGE="rclone/rclone:latest"
REMOTE="${OFFSITE_REMOTE:-}"

rclone_it() { docker run --rm -it -v "$CONF_DIR:/config/rclone" "$IMAGE" "$@"; }
rclone_run() { docker run --rm -v "$CONF_DIR:/config/rclone" -v "$BACKUPS:/backups" "$IMAGE" "$@"; }

CMD="${1:-help}"
case "$CMD" in
  setup)
    echo "==> Opening rclone's interactive setup."
    echo "    Follow the prompts to add your cloud (choose 'n' for new remote)."
    echo "    Tip: for encrypted backups, also add a 'crypt' remote wrapping it."
    rclone_it config
    echo
    echo "${G}✓${R} Done. Now set your remote in .env, e.g.:"
    echo "    ${C}OFFSITE_REMOTE=myremote:bookshelf-backups${R}"
    ;;
  remotes)
    rclone_run listremotes || die "No remotes yet — run: ./scripts/offsite.sh setup"
    ;;
  sync|now)
    [ -n "$REMOTE" ] || die "Set OFFSITE_REMOTE in .env first (see: ./scripts/offsite.sh setup)."
    echo "==> Copying ./backups → ${REMOTE}"
    rclone_run copy /backups "$REMOTE" --progress || die "Sync failed. Check OFFSITE_REMOTE and your rclone config."
    printf '%s✓%s Off-site backup complete.\n' "$G" "$R"
    "$SCRIPT_DIR/notify.sh" "Off-site backup complete" "Backups copied to ${REMOTE}" >/dev/null 2>&1 || true
    ;;
  pull)
    [ -n "$REMOTE" ] || die "Set OFFSITE_REMOTE in .env first."
    echo "==> Fetching ${REMOTE} → ./backups"
    rclone_run copy "$REMOTE" /backups --progress || die "Pull failed."
    printf '%s✓%s Pulled cloud backups into ./backups. Restore with ./bin/bookshelf restore.\n' "$G" "$R"
    ;;
  help|-h|--help|*)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
