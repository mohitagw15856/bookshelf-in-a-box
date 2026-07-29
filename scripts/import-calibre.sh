#!/usr/bin/env bash
#
# bookshelf-in-a-box — import an existing collection
#
# Point this at a folder of ebooks (or an existing Calibre library) and it
# brings them into your bookshelf. Non-destructive: it only ever copies.
#
#   ./scripts/import-calibre.sh /path/to/books
#   ./scripts/import-calibre.sh /path/to/Calibre\ Library --adopt
#
# Two modes:
#   • default  — copy every ebook it finds into your ingest folder, so they
#                get re-imported and freshly organised.
#   • --adopt  — if the source is a real Calibre library (has metadata.db)
#                AND your library is still empty, adopt it wholesale
#                (fastest, keeps existing metadata & covers).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -t 1 ]; then B="$(printf '\033[1m')"; G="$(printf '\033[32m')"; Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; G=""; Y=""; C=""; R=""; fi
die(){ printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

SRC=""; ADOPT=0
for a in "$@"; do
  case "$a" in
    --adopt) ADOPT=1;;
    -*) die "Unknown option: $a";;
    *) SRC="$a";;
  esac
done
[ -n "$SRC" ] || die "Usage: ./scripts/import-calibre.sh <folder> [--adopt]"
[ -d "$SRC" ] || die "Source folder not found: $SRC"

LIB="$ROOT_DIR/data/library"
INGEST="$ROOT_DIR/data/ingest"
MARKER="$ROOT_DIR/data/.imported"
mkdir -p "$INGEST"

# --- adopt mode --------------------------------------------------------------
if [ "$ADOPT" -eq 1 ]; then
  [ -f "$SRC/metadata.db" ] || die "--adopt needs a real Calibre library (no metadata.db in $SRC)."
  if [ -f "$LIB/metadata.db" ]; then
    die "Your library already has books (data/library/metadata.db exists). Adopt only works on an empty library; use the default copy-to-ingest mode instead."
  fi
  printf '  %sAdopt the existing Calibre library at:%s %s\n' "$B" "$R" "$SRC"
  printf '  This copies it into data/library (your current library is empty).\n'
  if [ -t 0 ]; then read -r -p "  Continue? [y/N] " ok; case "$ok" in [yY]*) ;; *) die "Cancelled.";; esac; fi
  mkdir -p "$LIB"
  echo "==> Copying library (this can take a while for big collections)…"
  cp -a "$SRC/." "$LIB/" || die "Copy failed."
  # Best-effort ownership so the container can read/write.
  UID_N="$(id -u)"; GID_N="$(id -g)"
  if [ "$UID_N" != "0" ]; then chown -R "$UID_N:$GID_N" "$LIB" 2>/dev/null || true; fi
  printf '  %s✓%s Adopted. Restart the library:  %s./bin/bookshelf restart%s\n' "$G" "$R" "$C" "$R"
  exit 0
fi

# --- default: copy ebooks into ingest ---------------------------------------
touch "$MARKER"
# Build a list of ebook files in the source.
mapfile -t FILES < <(find "$SRC" -type f \( \
    -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.azw' \
    -o -iname '*.pdf' -o -iname '*.cbz' -o -iname '*.cbr' -o -iname '*.fb2' \
    -o -iname '*.djvu' \) 2>/dev/null)

[ "${#FILES[@]}" -gt 0 ] || die "No ebook files found under $SRC."

printf '\n  %sFound %s ebook file(s) in%s %s\n' "$B" "${#FILES[@]}" "$R" "$SRC"
printf '  They will be copied into your ingest folder and imported.\n'
if [ -t 0 ]; then read -r -p "  Continue? [Y/n] " ok; case "$ok" in [nN]*) die "Cancelled.";; esac; fi

copied=0; skipped=0
for f in "${FILES[@]}"; do
  # dedupe key: size + basename (cheap, stable, no hashing tools needed)
  size="$(wc -c < "$f" | tr -d ' ')"
  key="${size}:$(basename "$f")"
  if grep -qxF "$key" "$MARKER" 2>/dev/null; then skipped=$((skipped+1)); continue; fi
  dest="$INGEST/$(basename "$f")"
  # avoid clobbering a same-named file already queued
  if [ -e "$dest" ]; then dest="$INGEST/${size}_$(basename "$f")"; fi
  if cp -p "$f" "$dest" 2>/dev/null; then
    echo "$key" >> "$MARKER"; copied=$((copied+1))
    printf '  %s+%s %s\n' "$G" "$R" "$(basename "$f")"
  else
    printf '  %s!%s could not copy %s\n' "$Y" "$R" "$(basename "$f")"
  fi
done

printf '\n  %s✓%s Queued %s new book(s) for import (%s already imported).\n' "$G" "$R" "$copied" "$skipped"
printf '  Watch them appear:  %s./bin/bookshelf logs%s\n\n' "$C" "$R"
