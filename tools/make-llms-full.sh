#!/usr/bin/env sh
# ─── make-llms-full.sh: build llms-full.txt from the files llms.txt links ───
# Reads llms.txt, takes every relative Markdown link target ](path) in the order it first appears (no
# http(s) links, no #anchors), and writes llms-full.txt: llms.txt itself first, then each file under a
# "# file: <path>" header. Deterministic: same tree in, same bytes out (CR removed, one trailing newline
# per file, LC_ALL=C, no dates, no absolute paths).
#
# Usage: tools/make-llms-full.sh [--check]
#   --check   build to a temp file and exit 1 when it differs from the committed llms-full.txt
# Exit: 0 ok · 1 a linked file is missing, or --check found a difference · 3 wrong usage.
# A missing file fails (it names the file): every file llms.txt links must exist in the tree.
set -eu
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CHECK=0
case "${1:-}" in
  '') ;;
  --check) CHECK=1 ;;
  *) echo "usage: $0 [--check]" >&2; exit 3 ;;
esac
[ -f llms.txt ] || { echo "make-llms-full: llms.txt not found in $ROOT" >&2; exit 1; }

# ─── The linked files, first appearance order ───
LIST="$(grep -o '](\([^)#]*\))' llms.txt | sed 's/^](//; s/)$//' | grep -v -E '^(https?:|mailto:)' | awk 'NF && !seen[$0]++')"
[ -n "$LIST" ] || { echo "make-llms-full: no relative links in llms.txt" >&2; exit 1; }

missing=0
for f in $LIST; do
  [ -f "$f" ] || { echo "make-llms-full: missing: $f" >&2; missing=1; }
done
[ "$missing" = 0 ] || exit 1

# ─── emit <path>: header, the file with CR removed, exactly one trailing newline ───
emit() {
  printf '# file: %s\n\n' "$1"
  tr -d '\r' < "$1" | awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }'
  printf '\n'
}

OUT="llms-full.txt"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
{
  emit llms.txt
  for f in $LIST; do emit "$f"; done
} > "$TMP"

if [ "$CHECK" = 1 ]; then
  if cmp -s "$TMP" "$OUT"; then echo "make-llms-full: $OUT is up to date"; exit 0; fi
  echo "make-llms-full: $OUT differs from llms.txt's files; run tools/make-llms-full.sh and commit it" >&2
  exit 1
fi
cp "$TMP" "$OUT"
echo "make-llms-full: wrote $OUT ($(printf '%s\n' "$LIST" | wc -l | tr -d ' ') files + llms.txt, $(wc -c < "$OUT" | tr -d ' ') bytes)"
