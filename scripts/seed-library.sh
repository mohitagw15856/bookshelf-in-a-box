#!/usr/bin/env bash
#
# bookshelf-in-a-box — starter library
#
# Downloads a handful of much-loved, 100% public-domain books from
# Project Gutenberg straight into your ingest folder, so a brand-new
# library looks full and inviting instead of empty.
#
# Safe to re-run: it skips anything it already fetched.
#
#   ./scripts/seed-library.sh          ask before downloading
#   ./scripts/seed-library.sh --yes    no prompt (for scripts)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then B="$(printf '\033[1m')"; D="$(printf '\033[2m')"; G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; D=""; G=""; Y=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

INGEST="$ROOT_DIR/data/ingest"
MARKER="$ROOT_DIR/data/.seeded"

command -v curl >/dev/null 2>&1 || die "This needs 'curl' (it comes with macOS and most Linux)."
mkdir -p "$INGEST"
touch "$MARKER"

# id | filename | Title — Author  (Project Gutenberg public-domain EPUBs)
BOOKS="
1342|pride-and-prejudice.epub|Pride and Prejudice — Jane Austen
84|frankenstein.epub|Frankenstein — Mary Shelley
1661|sherlock-holmes.epub|The Adventures of Sherlock Holmes — Arthur Conan Doyle
11|alice-in-wonderland.epub|Alice's Adventures in Wonderland — Lewis Carroll
2701|moby-dick.epub|Moby-Dick — Herman Melville
345|dracula.epub|Dracula — Bram Stoker
98|a-tale-of-two-cities.epub|A Tale of Two Cities — Charles Dickens
1952|the-yellow-wallpaper.epub|The Yellow Wallpaper — Charlotte Perkins Gilman
"

COUNT="$(printf '%s\n' "$BOOKS" | grep -c '|' || true)"

printf '\n  %s📚 Starter library%s\n' "$B" "$R"
printf '  I can drop these %s free, public-domain books into your ingest folder:\n\n' "$COUNT"
printf '%s\n' "$BOOKS" | while IFS='|' read -r id file title; do [ -n "$id" ] && printf '     • %s\n' "$title"; done
printf '\n  They will auto-import into your library within a minute.\n'
printf '  %sSource: Project Gutenberg — always free to share.%s\n\n' "$D" "$R"

if [ "${1:-}" != "--yes" ] && [ -t 0 ]; then
  printf '  Download them now? [Y/n] '
  read -r ANS || ANS=""
  case "$ANS" in [nN]*) die "No problem — nothing downloaded.";; esac
fi

printf '%s\n' "$BOOKS" | while IFS='|' read -r id file title; do
  [ -n "$id" ] || continue
  dest="$INGEST/$file"
  if grep -qx "$id" "$MARKER" 2>/dev/null; then
    printf '  %s•%s already fetched: %s\n' "$D" "$R" "$title"; continue
  fi
  url="https://www.gutenberg.org/cache/epub/${id}/pg${id}.epub"
  printf '  %s↓%s %s… ' "$C" "$R" "$title"
  if curl -fsSL --retry 3 --retry-delay 2 -o "$dest.part" "$url" 2>/dev/null && [ -s "$dest.part" ]; then
    mv "$dest.part" "$dest"
    echo "$id" >> "$MARKER"
    printf '%sok%s\n' "$G" "$R"
  else
    rm -f "$dest.part"
    printf '%sskipped (couldn'\''t download)%s\n' "$Y" "$R"
  fi
done

printf '\n  %s✓%s Done. Watch them appear in your library — or check the ingest folder:\n' "$G" "$R"
printf '    %s%s%s\n\n' "$C" "$INGEST" "$R"
