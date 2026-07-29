#!/bin/sh
#
# bookshelf-in-a-box — send a notification
#
# Sends a short message to whatever channel you've configured in .env
# (ntfy, Discord, Slack, Telegram, or a plain webhook). If nothing is
# configured it does nothing and exits quietly — so it's always safe to call.
#
#   ./scripts/notify.sh "Title" "Message"
#   ./scripts/notify.sh --test
#
# POSIX sh; uses curl or wget, whichever is available. Never fails its caller.
#
set -eu

SELF_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(cd -- "$SELF_DIR/.." && pwd)"

# Load .env if present (for NOTIFY_* settings).
if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env"
  set +a
fi

KIND="${NOTIFY_KIND:-}"

if [ "${1:-}" = "--test" ]; then
  TITLE="bookshelf test"
  MSG="If you can read this, notifications are working. 🎉"
else
  TITLE="${1:-bookshelf}"
  MSG="${2:-}"
fi

# Nothing configured → quietly succeed.
if [ -z "$KIND" ] || [ "$KIND" = "none" ]; then
  [ "${1:-}" = "--test" ] && echo "No notifications configured. Set NOTIFY_KIND in .env (ntfy|discord|slack|telegram|webhook)."
  exit 0
fi

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r' '  '; }

post_json() { # url json
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -m 15 -H 'Content-Type: application/json' -d "$2" "$1" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --header='Content-Type: application/json' --post-data="$2" "$1" >/dev/null 2>&1
  else
    return 1
  fi
}

ok=0
case "$KIND" in
  ntfy)
    if [ -n "${NOTIFY_URL:-}" ]; then
      if command -v curl >/dev/null 2>&1; then
        curl -fsS -m 15 -H "Title: $TITLE" -d "$MSG" "$NOTIFY_URL" >/dev/null 2>&1 && ok=1
      elif command -v wget >/dev/null 2>&1; then
        wget -qO- --header="Title: $TITLE" --post-data="$MSG" "$NOTIFY_URL" >/dev/null 2>&1 && ok=1
      fi
    fi
    ;;
  discord)
    [ -n "${NOTIFY_URL:-}" ] && post_json "$NOTIFY_URL" "{\"content\":\"**$(json_escape "$TITLE")**  $(json_escape "$MSG")\"}" && ok=1
    ;;
  slack)
    [ -n "${NOTIFY_URL:-}" ] && post_json "$NOTIFY_URL" "{\"text\":\"*$(json_escape "$TITLE")*  $(json_escape "$MSG")\"}" && ok=1
    ;;
  telegram)
    if [ -n "${NOTIFY_TELEGRAM_TOKEN:-}" ] && [ -n "${NOTIFY_TELEGRAM_CHAT:-}" ]; then
      post_json "https://api.telegram.org/bot${NOTIFY_TELEGRAM_TOKEN}/sendMessage" \
        "{\"chat_id\":\"${NOTIFY_TELEGRAM_CHAT}\",\"text\":\"$(json_escape "$TITLE"): $(json_escape "$MSG")\"}" && ok=1
    fi
    ;;
  webhook|*)
    [ -n "${NOTIFY_URL:-}" ] && post_json "$NOTIFY_URL" "{\"title\":\"$(json_escape "$TITLE")\",\"message\":\"$(json_escape "$MSG")\"}" && ok=1
    ;;
esac

if [ "${1:-}" = "--test" ]; then
  if [ "$ok" = "1" ]; then echo "✓ Sent a test notification via '$KIND'."; else echo "✗ Could not send. Check NOTIFY_URL / NOTIFY_KIND in .env."; fi
fi
exit 0
