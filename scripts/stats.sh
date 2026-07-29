#!/usr/bin/env bash
#
# bookshelf-in-a-box — library stats & insights
#
# Reads your library folder (no database needed) and shows a fun summary:
# total books, formats, top authors, biggest and newest additions. Also
# writes a shareable HTML page to data/stats.html.
#
#   ./scripts/stats.sh            print + write data/stats.html
#   ./scripts/stats.sh --no-html  print only
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR" || exit 1

if [ -t 1 ]; then B="$(printf '\033[1m')"; D="$(printf '\033[2m')"; G="$(printf '\033[32m')"; C="$(printf '\033[36m')"; R="$(printf '\033[0m')"; else B=""; D=""; G=""; C=""; R=""; fi
die(){ printf '✗ %s\n' "$*" >&2; exit 1; }

LIB="data/library"
[ -d "$LIB" ] || die "No library found at $LIB. Run ./setup.sh first."

FORMATS="epub mobi azw3 azw pdf cbz cbr fb2 djvu txt"

# total + per-format counts
TOTAL=0
FMT_LINES=""
for f in $FORMATS; do
  n="$(find "$LIB" -type f -iname "*.${f}" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -gt 0 ]; then
    FMT_LINES="${FMT_LINES}${f} ${n}"$'\n'
    TOTAL=$((TOTAL + n))
  fi
done

# total size
SIZE="$(du -sh "$LIB" 2>/dev/null | cut -f1)"; SIZE="${SIZE:-0}"

# authors = immediate subfolders of the library (Calibre stores Author/Title/…)
AUTHORS=0
TOP_AUTHORS=""
if [ "$TOTAL" -gt 0 ]; then
  # count books per top-level author dir
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    base="$(basename "$dir")"
    case "$base" in .*) continue;; esac
    c="$(find "$dir" -type f \( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.pdf' -o -iname '*.cbz' -o -iname '*.fb2' \) 2>/dev/null | wc -l | tr -d ' ')"
    [ "$c" -gt 0 ] && TOP_AUTHORS="${TOP_AUTHORS}${c}|${base}"$'\n' && AUTHORS=$((AUTHORS + 1))
  done < <(find "$LIB" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi
TOP5="$(printf '%s' "$TOP_AUTHORS" | grep -v '^$' | sort -t'|' -k1 -nr | head -5)"

# newest 5 files by mtime
NEWEST="$(find "$LIB" -type f \( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.pdf' -o -iname '*.cbz' -o -iname '*.fb2' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -5 | cut -d' ' -f2-)"

# --- print ---
printf '\n  %s📊 Library stats%s\n' "$B" "$R"
printf '  %s────────────────────────────────────────%s\n' "$D" "$R"
printf '  Total books   %s%s%s\n' "$B" "$TOTAL" "$R"
printf '  Authors       %s\n' "$AUTHORS"
printf '  Library size  %s\n' "$SIZE"
printf '  Formats       '
printf '%s' "$FMT_LINES" | grep -v '^$' | awk '{printf "%s×%s  ", $1, $2}'; printf '\n'
if [ -n "$TOP5" ]; then
  printf '\n  %sTop authors%s\n' "$B" "$R"
  printf '%s\n' "$TOP5" | while IFS='|' read -r c a; do [ -n "$a" ] && printf '    %2s  %s\n' "$c" "$a"; done
fi
if [ -n "$NEWEST" ]; then
  printf '\n  %sRecently added%s\n' "$B" "$R"
  printf '%s\n' "$NEWEST" | while IFS= read -r p; do [ -n "$p" ] && printf '    %s\n' "$(basename "$p")"; done
fi
printf '  %s────────────────────────────────────────%s\n\n' "$D" "$R"

# --- HTML ---
if [ "${1:-}" != "--no-html" ] && [ "$TOTAL" -gt 0 ]; then
  OUT="data/stats.html"
  {
    cat <<HTML
<!doctype html><meta charset="utf-8"><title>bookshelf — library stats</title>
<style>body{font:16px/1.5 system-ui,sans-serif;margin:0;padding:40px;color:#e9edfb;
background:radial-gradient(900px 500px at 15% -10%,rgba(129,140,248,.22),transparent 60%),#0c1020}
.wrap{max-width:640px;margin:auto}h1{font-size:24px;margin:0 0 4px}.sub{color:#8b93b4;margin:0 0 24px}
.tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-bottom:26px}
.tile{background:#141a2e;border:1px solid #28304d;border-radius:14px;padding:18px}
.tile .n{font-size:28px;font-weight:800}.tile .l{color:#8b93b4;font-size:13px}
.card{background:#141a2e;border:1px solid #28304d;border-radius:14px;padding:18px 20px;margin-bottom:16px}
.card h2{font-size:15px;margin:0 0 12px;color:#c2c9e4}.bar{display:flex;align-items:center;gap:10px;margin:7px 0}
.bar .fill{height:10px;border-radius:6px;background:linear-gradient(90deg,#38bdf8,#818cf8)}
.bar .lab{width:auto;flex:1}.bar .v{color:#8b93b4;font-variant-numeric:tabular-nums}
small{color:#8b93b4}</style>
<div class="wrap"><h1>📊 Your library</h1><p class="sub">Snapshot of what's on your shelves.</p>
<div class="tiles">
<div class="tile"><div class="n">${TOTAL}</div><div class="l">books</div></div>
<div class="tile"><div class="n">${AUTHORS}</div><div class="l">authors</div></div>
<div class="tile"><div class="n">${SIZE}</div><div class="l">on disk</div></div>
</div>
HTML
    # formats card with bars
    echo '<div class="card"><h2>Formats</h2>'
    printf '%s' "$FMT_LINES" | grep -v '^$' | while read -r fmt n; do
      pct=$(( n * 100 / (TOTAL>0?TOTAL:1) ))
      printf '<div class="bar"><span class="lab">%s</span><span class="fill" style="width:%s%%"></span><span class="v">%s</span></div>\n' "$fmt" "$((pct<3?3:pct))" "$n"
    done
    echo '</div>'
    if [ -n "$TOP5" ]; then
      echo '<div class="card"><h2>Top authors</h2>'
      printf '%s\n' "$TOP5" | while IFS='|' read -r c a; do
        [ -n "$a" ] && printf '<div class="bar"><span class="lab">%s</span><span class="v">%s</span></div>\n' "$a" "$c"
      done
      echo '</div>'
    fi
    echo '<p><small>Generated by ./scripts/stats.sh — refresh any time.</small></p></div>'
  } > "$OUT"
  printf '  %s✓%s Wrote %s%s%s\n\n' "$G" "$R" "$C" "$OUT" "$R"
fi
