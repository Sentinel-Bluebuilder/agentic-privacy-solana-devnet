#!/usr/bin/env sh
# ─── secret-scan.sh: fail when a tracked file holds a secret-shaped string ───
# Generic shapes only (this file is public): a Solana key file (a JSON array of 64 bytes, on one line or split
# over many, as a JSON formatter writes it), a PEM private key,
# Anthropic / OpenAI / GitHub / AWS / Slack tokens. Scans `git ls-files` (or the files given), skipping this file.
# Before scanning it plants one string of each shape in a temp file and fails if any is missed (exit 4), so a
# broken pattern cannot pass silently.
#
# Usage: tools/secret-scan.sh [file …]   (names may contain spaces)
# Exit: 0 clean · 1 a hit (file:line printed, the match itself never printed) · 4 the control failed.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."

SELF='tools/secret-scan.sh'
PATTERNS='\[[[:space:]]*([0-9]{1,3}[[:space:]]*,[[:space:]]*){63}[0-9]{1,3}[[:space:]]*\]
-----BEGIN ([A-Z]+ )?PRIVATE KEY-----
sk-ant-[A-Za-z0-9_-]{20,}
sk-(proj-)?[A-Za-z0-9]{32,}
gh[pousr]_[A-Za-z0-9]{36,}
github_pat_[A-Za-z0-9_]{40,}
AKIA[0-9A-Z]{16}
xox[abprs]-[A-Za-z0-9-]{10,}'
# Shape 9: a key file split over lines (a JSON formatter writes one number per line, which shape 1, read line by
# line, never sees). Matched on the file with every space and newline removed; reported only when shape 1 did not hit.
KEYJOINED='\[([0-9]{1,3},){63}[0-9]{1,3}\]'
KEYLINE=$(printf '%s\n' "$PATTERNS" | head -1)

# scan <file>…: prints "file:line: <pattern number>" per hit, never the secret itself
scan() {
  hits=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=0
    printf '%s\n' "$PATTERNS" | while IFS= read -r p; do
      n=$((n + 1))
      tr -d '\r' < "$f" | grep -nE -e "$p" | cut -d: -f1 | while read -r line; do printf '%s:%s: secret shape %s\n' "$f" "$line" "$n"; done
    done
    if ! tr -d '\r' < "$f" | grep -qE -e "$KEYLINE" && tr -d ' \t\r\n' < "$f" | grep -qE -e "$KEYJOINED"; then
      printf '%s:%s: secret shape 9\n' "$f" 'multi-line'
    fi
  done
}

# ─── Control: one planted string per shape must be found ───
CTRL="$(mktemp)"
trap 'rm -f "$CTRL"' EXIT
# rep <char> <n>: n copies, built at run time, so no secret-shaped literal sits in this public file
rep() { r=0; while [ "$r" -lt "$2" ]; do printf '%s' "$1"; r=$((r + 1)); done; }
{
  printf '['; i=0; while [ $i -lt 63 ]; do printf '%s,' $((i % 250)); i=$((i + 1)); done; printf '7]\n'
  printf -- '-----BEGIN %s-----\n' 'PRIVATE KEY'
  printf 'sk-ant-api03-%s\n' "$(rep A 28)"
  printf 'sk-proj-%s\n' "$(rep A 36)"
  printf 'ghp_%s\n' "$(rep A 36)"
  printf 'github_pat_%s\n' "$(rep A 42)"
  printf 'AKIA%s\n' "$(rep A 16)"
  printf 'xoxb-%s\n' "$(rep 0 10)-AAAA"
} > "$CTRL"
# shape 9 needs a file of its own (in CTRL, shape 1's one-line array would mask it)
CTRL9="$(mktemp)"
trap 'rm -f "$CTRL" "$CTRL9"' EXIT
{ printf '[\n'; i=0; while [ $i -lt 63 ]; do printf '  %s,\n' $((i % 250)); i=$((i + 1)); done; printf '  7\n]\n'; } > "$CTRL9"
want=$(( $(printf '%s\n' "$PATTERNS" | wc -l | tr -d ' ') + 1 ))
got=$(scan "$CTRL" "$CTRL9" | awk '{ print $NF }' | sort -u | wc -l | tr -d ' ')
if [ "$got" != "$want" ]; then
  echo "secret-scan: control found $got of $want planted shapes; do not trust this scan" >&2
  exit 4
fi
echo "secret-scan: control $got of $want planted shapes found"

# ─── The real scan ───
# One name per line (a name with a space stays one file); this file itself is skipped.
LIST="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "$CTRL" "$CTRL9" "$LIST" "$OUT"' EXIT
if [ $# -gt 0 ]; then printf '%s\n' "$@"; else git -c core.quotepath=off ls-files; fi | grep -v -x -F "$SELF" > "$LIST" || true
while IFS= read -r f; do scan "$f"; done < "$LIST" > "$OUT"
if [ -s "$OUT" ]; then
  cat "$OUT" >&2
  echo "secret-scan: $(wc -l < "$OUT" | tr -d ' ') hit(s)" >&2
  exit 1
fi
echo "secret-scan: clean ($(grep -c . "$LIST") files)"
