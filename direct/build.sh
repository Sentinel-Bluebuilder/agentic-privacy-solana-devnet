#!/bin/sh
# ─── direct/build.sh: build Sentinel's own client tools for Solana devnet yourself, then compare ───
#
# Builds sentinel-dvpnd (daemon) and sentinel-dvpn (CLI) from the PUBLIC upstream
# https://github.com/sentinel-official/sentinel-solana at the pinned commit
# 26de52407c5b722cfecad1772dcbeefd984ef6d0 with the devnet link-time ids, for linux/amd64 and
# linux/arm64, into dist-build/ with the release file names. Then it compares every SHA-256 with
# direct/SHA256SUMS (the same lines as the release direct-v1). With Go 1.27.3 the bytes are the same:
# the upstream Makefile builds with -trimpath and CGO_ENABLED=0.
#
#   sh direct/build.sh                      # both arches; prints MATCH or MISMATCH per file
#   ARCHES=amd64 sh direct/build.sh         # one arch only
#   OUT=/usr/local/bin sh direct/build.sh   # also installs this machine's arch there
#   VERIFY_ONLY=1 sh direct/build.sh        # on macOS (or another non-Linux host): build the Linux files and compare only
#
# Path B runs on Linux only today. On any other host (macOS, Windows) build.sh refuses with code unsupported-os
# (exit 1, nothing built) and next shows the app (Path A). VERIFY_ONLY=1 still cross-builds the Linux files there
# to check their SHA-256 (sha256sum, or shasum -a 256 on macOS); it never installs them.
#
# Needs: git, make, Go 1.27.3 on PATH (https://go.dev/dl/; check its SHA-256 on that page). No root.
# Exit: 0 all MATCH (or Go is not 1.27.3: built, with a warning, not compared strictly) · 5 a MISMATCH
# with Go 1.27.3 (do not use those bytes; report it) · 1 the build failed (build-failed) · 3 usage / tool-missing.
# The last stdout line is JSON: {"ok":…,"step":"build","result":"MATCH"|"MISMATCH"|"UNCHECKED",…}, or on a
# failure {"ok":false,"step":"build","code":…,"next":…} (direct/schema/failure.json).
set -eu
# bfail <exit> <code> <message> <next>: the one failure line, then exit (build.sh does not load lib.sh: it needs
# no wallet and no daemon). Message and next are JSON-escaped like lib.sh's jstr (they carry SRC / DIST / OUT, which
# are yours: a " becomes ', a \ becomes /, a newline or tab a space), so the line stays valid JSON.
bjs() { printf '%s' "$1" | tr '"\\\n\t' "'/  "; }
bfail() {
  echo "error: $3" >&2
  printf '{"ok":false,"step":"build","code":"%s","money":"none","moneyNote":"Nothing was paid.","error":"%s","next":"%s"}\n' "$2" "$(bjs "$3")" "$(bjs "$4")"
  exit "$1"
}
# --help / -h: print this header and exit, before anything runs; any other argument is usage (settings are env)
for a in "$@"; do case $a in --help|-h) sed -n '2,/^set -/p' "$0" | sed -e '/^set -/d' -e 's/^# \{0,1\}//'
  echo '{"ok":true,"step":"help","next":"sh direct/build.sh"}'; exit 0 ;; esac; done
for a in "$@"; do
  bfail 3 usage "unknown option or argument: $(printf '%s' "$a" | tr -d '"\\' | cut -c1-40) (build.sh takes settings as env: ARCHES, OUT, VERIFY_ONLY, SRC, DIST)" "sh direct/build.sh --help"
done
HERE=$(cd "$(dirname "$0")" && pwd)

# ─── host: Path B runs on Linux only today (macOS / Windows: the app) ───
OS=$(uname -s)
APP_NEXT="grep -n -A6 'Two paths' AGENTS.md"   # the two-paths box: the app's install line for this OS
if [ "$OS" != Linux ] && [ "${VERIFY_ONLY:-0}" != 1 ]; then
  msg="this host is $OS: Path B (direct/) runs on Linux only today, so nothing was built. Use the app (Path A); VERIFY_ONLY=1 only cross-builds the Linux files to compare their SHA-256"
  echo "error: $msg" >&2
  printf '{"ok":false,"step":"build","code":"unsupported-os","money":"none","moneyNote":"Nothing was paid.","error":"%s","next":"%s"}\n' "$msg" "$APP_NEXT"
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$@"; }; else sha256() { shasum -a 256 "$@"; }; fi

COMMIT=26de52407c5b722cfecad1772dcbeefd984ef6d0
REPO=https://github.com/sentinel-official/sentinel-solana
GO_WANT=go1.27.3
NETWORK=devnet
PROGRAM_ID=J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs
MINT=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa
SRC=${SRC:-./sentinel-solana}
DIST=${DIST:-./dist-build}
ARCHES=${ARCHES:-amd64 arm64}

run() { printf '+ %s\n' "$*" >&2; "$@"; }

for t in git make go; do
  command -v "$t" >/dev/null 2>&1 && continue
  case $t in go) nx="sh direct/build.sh --help" ;; *) nx="sudo apt-get install -y $t" ;; esac   # go: 1.27.3 from go.dev/dl, not apt
  bfail 3 tool-missing "$t not found on PATH (needs git, make and Go 1.27.3 from https://go.dev/dl/)" "$nx"
done

GO_HAVE=$(go env GOVERSION 2>/dev/null || echo none)
STRICT=1
if [ "$GO_HAVE" != "$GO_WANT" ]; then
  STRICT=0
  echo "warning: Go is $GO_HAVE, the recorded build used $GO_WANT; the binaries will work but SHA-256 will differ" >&2
fi

for arch in $ARCHES; do
  case $arch in amd64|arm64) ;; *) bfail 3 usage "ARCHES holds $(printf '%s' "$arch" | tr -d '"\\' | cut -c1-20): only amd64 and arm64 are built" "env -u ARCHES sh direct/build.sh" ;; esac
done   # before any clone or fetch
# Every step below fails with ONE JSON line (build-failed), never a bare set -e stop with git's or make's exit code.
if [ ! -d "$SRC/.git" ]; then
  run git clone -q "$REPO" "$SRC" || bfail 1 build-failed "git clone of $REPO into $SRC failed (network?)" "sh direct/build.sh"
fi
run git -C "$SRC" fetch -q origin || bfail 1 build-failed "git fetch in $SRC failed (network, or $SRC is not a clone of $REPO)" "sh direct/build.sh"
run git -C "$SRC" checkout -q --detach "$COMMIT" || bfail 1 build-failed "git checkout $COMMIT in $SRC failed" "sh direct/build.sh"
[ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$COMMIT" ] || bfail 1 build-failed "the checkout in $SRC is not $COMMIT" "sh direct/build.sh"

mkdir -p "$DIST" || bfail 1 build-failed "cannot create $DIST" "sh direct/build.sh"
for arch in $ARCHES; do
  for tool in sentinel-dvpnd sentinel-dvpn; do
    run env GOOS=linux GOARCH="$arch" make -C "$SRC/$tool" build \
      SENTINEL_NETWORK="$NETWORK" SENTINEL_PROGRAM_ID="$PROGRAM_ID" SENTINEL_MINT="$MINT" >&2 \
      || bfail 1 build-failed "make build of $tool for linux/$arch failed (see the make output above)" "sh direct/build.sh"
    run cp "$SRC/$tool/bin/$tool" "$DIST/$tool-linux-$arch" || bfail 1 build-failed "make left no $SRC/$tool/bin/$tool" "sh direct/build.sh"
  done
done

# ─── compare with direct/SHA256SUMS ───
RESULT=MATCH
(cd "$DIST" && sha256 sentinel-dvpn*-linux-*) > "$DIST/SHA256SUMS"
echo "sha256 of this build (dist-build/SHA256SUMS):" >&2
cat "$DIST/SHA256SUMS" >&2
while read -r sum name; do
  want=$(awk -v n="$name" '$2 == n {print $1}' "$HERE/SHA256SUMS")
  if [ "$sum" = "$want" ]; then
    echo "MATCH    $name" >&2
  else
    echo "MISMATCH $name: built $sum, direct/SHA256SUMS says ${want:-nothing}" >&2
    RESULT=MISMATCH
  fi
done < "$DIST/SHA256SUMS"

# a plain case, not $(case …): bash 3.2 (macOS /bin/sh) cannot parse a bare `pattern)` inside $( )
case $(uname -m) in x86_64) NATIVE=amd64 ;; aarch64|arm64) NATIVE=arm64 ;; *) NATIVE=none ;; esac
[ "$OS" = Linux ] || NATIVE=none   # VERIFY_ONLY on another OS: Linux files cannot run or be installed here
if [ -x "$DIST/sentinel-dvpn-linux-$NATIVE" ]; then "$DIST/sentinel-dvpn-linux-$NATIVE" version >&2; fi

if [ -n "${OUT:-}" ] && [ -x "$DIST/sentinel-dvpnd-linux-$NATIVE" ]; then
  for tool in sentinel-dvpnd sentinel-dvpn; do
    run install -m 0755 "$DIST/$tool-linux-$NATIVE" "$OUT/$tool" \
      || bfail 1 build-failed "built, but installing $tool into $OUT failed (root needed there?)" "sudo OUT=$OUT sh direct/build.sh"
  done
fi

if [ "$RESULT" = MISMATCH ] && [ "$STRICT" = 0 ]; then RESULT=UNCHECKED; fi
OK=true; [ "$RESULT" = MISMATCH ] && OK=false
case $RESULT in
  MATCH) NX='sudo BUILD=1 sh direct/install.sh'; NOTE='the bytes match direct/SHA256SUMS' ;;
  UNCHECKED) NX='sh direct/build.sh'; NOTE='install Go 1.27.3 from https://go.dev/dl/ first: another Go gives other bytes' ;;
  *) NX='sh direct/build.sh'; NOTE='do not use these bytes; report the MISMATCH lines above' ;;
esac
if [ "$OS" != Linux ] && [ "$RESULT" != MISMATCH ]; then
  NX=$APP_NEXT; NOTE="$NOTE. These are Linux files, checked only: on $OS use the app (Path A)"
fi
# A MISMATCH is a failure: one failure.json line, the same code and exit as install.sh's checksum-mismatch.
[ "$RESULT" = MISMATCH ] && bfail 5 checksum-mismatch "built files differ from direct/SHA256SUMS with Go $GO_HAVE at $COMMIT (MISMATCH lines above; the files are in $DIST): do not use these bytes, report it" "sh direct/build.sh"
printf '{"ok":%s,"step":"build","result":"%s","go":"%s","commit":"%s","dist":"%s","next":"%s","note":"%s"}\n' \
  "$OK" "$RESULT" "$GO_HAVE" "$COMMIT" "$DIST" "$NX" "$NOTE"
exit 0
