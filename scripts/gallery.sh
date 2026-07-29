#!/usr/bin/env bash
#
# bookshelf-in-a-box — build the gallery data
#
# Scans your library folder and writes data/gallery/library.json, which powers
# the visual gallery (cover wall, 3D shelf, Wrapped, insights, poster, …).
# Read-only on your library. Safe to re-run any time.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else G=""; Y=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

LIB="data/library"
OUT_DIR="data/gallery"
OUT="$OUT_DIR/library.json"
[ -d "$LIB" ] || die "No library at $LIB. Run ./setup.sh first."
mkdir -p "$OUT_DIR"

# minimal JSON string escaper (handles the characters that actually occur)
jesc(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r\n\t'; }

epoch_of(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

tmp="$(mktemp)"
count=0
printf '{\n  "generated": %s,\n  "books": [\n' "$(date +%s000)" > "$tmp"

first=1
# Calibre layout: library/<Author>/<Title (id)>/<book files> + cover.jpg
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  book="$(find "$dir" -maxdepth 1 -type f \( \
      -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.azw' \
      -o -iname '*.pdf' -o -iname '*.cbz' -o -iname '*.cbr' -o -iname '*.fb2' \
      -o -iname '*.djvu' \) 2>/dev/null | head -1)"
  [ -n "$book" ] || continue

  rel="${dir#"$LIB"/}"                 # Author/Title
  author="${rel%%/*}"
  title="${rel#*/}"; title="${title%/}"
  title="$(printf '%s' "$title" | sed -E 's/ \([0-9]+\)$//')"   # drop trailing " (123)"
  ext="${book##*.}"; fmt="$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')"
  size="$(wc -c < "$book" | tr -d ' ')"
  added="$(epoch_of "$book")000"
  cover=""
  [ -f "$dir/cover.jpg" ] && cover="/covers/${rel}/cover.jpg"

  [ "$first" -eq 1 ] || printf ',\n' >> "$tmp"
  first=0
  printf '    {"t":"%s","a":"%s","fmt":"%s","size":%s,"added":%s,"cover":%s}' \
    "$(jesc "$title")" "$(jesc "$author")" "$fmt" "$size" "$added" \
    "$([ -n "$cover" ] && printf '"%s"' "$(jesc "$cover")" || printf 'null')" >> "$tmp"
  count=$((count + 1))
done < <(find "$LIB" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)

printf '\n  ],\n  "count": %s\n}\n' "$count" >> "$tmp"
mv "$tmp" "$OUT"

printf '%s✓%s Wrote %s%s%s (%s books).\n' "$G" "$R" "$C" "$OUT" "$R" "$count"
printf '  See it:  %s./bin/bookshelf dashboard up%s  → http://localhost:%s\n' "$C" "$R" "${DASHBOARD_PORT:-8084}"
