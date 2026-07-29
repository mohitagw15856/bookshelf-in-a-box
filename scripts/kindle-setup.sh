#!/usr/bin/env bash
#
# bookshelf-in-a-box — Send-to-Kindle helper
#
# Walks you through your email (SMTP) details and sends a REAL test email so
# you know they work *before* you paste them into the Calibre-Web settings.
# Sending mail is the single most fiddly bit of Send-to-Kindle — this de-risks it.
#
# Nothing is stored unless you explicitly ask. Uses a throwaway curl container,
# so no mail tools are needed on your machine.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then B="$(printf '\033[1m')"; D="$(printf '\033[2m')"; G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; D=""; G=""; Y=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is needed to send the test email."
[ -t 0 ] || die "Run this in an interactive terminal."

cat <<EOF

  ${B}📨 Send-to-Kindle setup helper${R}

  We'll check your email settings by sending yourself a test message.
  For Gmail, use an ${B}App Password${R} (not your normal password):
    ${D}https://myaccount.google.com/apppasswords${R}

EOF

read -r -p "  SMTP server (e.g. smtp.gmail.com): " SMTP_HOST
[ -n "$SMTP_HOST" ] || die "SMTP server is required."
read -r -p "  SMTP port [587]: " SMTP_PORT; SMTP_PORT="${SMTP_PORT:-587}"
read -r -p "  SMTP username (your email): " SMTP_USER
[ -n "$SMTP_USER" ] || die "Username is required."
read -r -s -p "  SMTP password / app password: " SMTP_PASS; echo
[ -n "$SMTP_PASS" ] || die "Password is required."
read -r -p "  From address [$SMTP_USER]: " FROM; FROM="${FROM:-$SMTP_USER}"
read -r -p "  Send the test to [$SMTP_USER]: " TESTTO; TESTTO="${TESTTO:-$SMTP_USER}"

# Choose scheme by port: 465 = implicit TLS (smtps), else STARTTLS on smtp://
if [ "$SMTP_PORT" = "465" ]; then URL="smtps://${SMTP_HOST}:${SMTP_PORT}"; else URL="smtp://${SMTP_HOST}:${SMTP_PORT}"; fi

echo
printf '  Sending a test email to %s%s%s … ' "$C" "$TESTTO" "$R"

MAIL="$(printf 'From: bookshelf-in-a-box <%s>\nTo: <%s>\nSubject: bookshelf test email\n\nIf you can read this, your SMTP settings work. You can now paste them into Calibre-Web.\n' "$FROM" "$TESTTO")"

if printf '%s' "$MAIL" | docker run --rm -i curlimages/curl:latest \
      --silent --show-error --ssl-reqd \
      --url "$URL" \
      --mail-from "$FROM" --mail-rcpt "$TESTTO" \
      --user "${SMTP_USER}:${SMTP_PASS}" \
      --upload-file - >/tmp/kindle_test_err 2>&1; then
  printf '%s✓ sent!%s\n' "$G" "$R"
  echo "  Check your inbox. If it arrived, these settings are good."
else
  printf '%s✗ failed%s\n' "$Y" "$R"
  echo "  Error from the mail server:"
  sed 's/^/      /' /tmp/kindle_test_err 2>/dev/null | tail -6 || true
  echo "  Common causes: wrong port, needing an App Password, or 2FA blocking basic login."
fi
rm -f /tmp/kindle_test_err

MASK="$(printf '%s' "$SMTP_PASS" | sed 's/./*/g')"
cat <<EOF

  ${B}Now put these into your library${R} (Admin → Edit SMTP Settings):
     SMTP host:      ${SMTP_HOST}
     SMTP port:      ${SMTP_PORT}
     Encryption:     $( [ "$SMTP_PORT" = "465" ] && echo "SSL/TLS" || echo "STARTTLS" )
     From address:   ${FROM}
     Username:       ${SMTP_USER}
     Password:       ${MASK}  ${D}(the app password you typed)${R}

  Then, per user (Admin → edit user), set the ${B}Send-to-Kindle email${R}
  to the device's @kindle.com address, and on Amazon add ${FROM} to your
  ${B}Approved Personal Document E-mail List${R}.

EOF

read -r -p "  Save a reminder (WITHOUT the password) to data/kindle-smtp.txt? [y/N] " SAVE
case "$SAVE" in
  [yY]*)
    mkdir -p data
    {
      echo "# bookshelf Send-to-Kindle settings (password intentionally omitted)"
      echo "SMTP host:   $SMTP_HOST"
      echo "SMTP port:   $SMTP_PORT"
      echo "From:        $FROM"
      echo "Username:    $SMTP_USER"
    } > data/kindle-smtp.txt
    echo "  Saved to data/kindle-smtp.txt (gitignored)."
    ;;
esac
echo
