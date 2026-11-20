#!/bin/sh
# ─── direct/build.sh: build Sentinel's own client tools for Solana devnet, no app ───
#
# Builds sentinel-dvpnd (daemon) and sentinel-dvpn (CLI) from the PUBLIC upstream
# https://github.com/sentinel-official/sentinel-solana at a pinned commit, with the devnet
# link-time ids, then prints the SHA-256 of each binary. Compare those with direct/SHA256SUMS
# (or the release direct-v1): with the same Go version and commit, the bytes are the same.
#
#   sh direct/build.sh            # builds into ./sentinel-solana/<tool>/bin/
#   OUT=/usr/local/bin sh direct/build.sh   # also copies both binaries there (needs write access)
#
# Needs: git, make, Go 1.27.3 on PATH (https://go.dev/dl/). No CGO, no root.
set -eu

COMMIT=26de52407c5b722cfecad1772dcbeefd984ef6d0
REPO=https://github.com/sentinel-official/sentinel-solana
GO_WANT=go1.27.3
NETWORK=devnet
PROGRAM_ID=J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs
MINT=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa
SRC=${SRC:-./sentinel-solana}

run() { printf '+ %s\n' "$*" >&2; "$@"; }

GO_HAVE=$(go env GOVERSION 2>/dev/null || echo none)
if [ "$GO_HAVE" != "$GO_WANT" ]; then
  echo "warning: Go is $GO_HAVE, the recorded build used $GO_WANT; the binaries will work but SHA-256 will differ" >&2
fi

if [ ! -d "$SRC/.git" ]; then
  run git clone -q "$REPO" "$SRC"
fi
run git -C "$SRC" fetch -q origin
run git -C "$SRC" checkout -q --detach "$COMMIT"

for tool in sentinel-dvpnd sentinel-dvpn; do
  run make -C "$SRC/$tool" build \
    SENTINEL_NETWORK="$NETWORK" SENTINEL_PROGRAM_ID="$PROGRAM_ID" SENTINEL_MINT="$MINT"
done

echo "sha256 (compare with direct/SHA256SUMS):"
(cd "$SRC" && sha256sum sentinel-dvpnd/bin/sentinel-dvpnd sentinel-dvpn/bin/sentinel-dvpn)

"$SRC/sentinel-dvpn/bin/sentinel-dvpn" version

if [ -n "${OUT:-}" ]; then
  run install -m 0755 "$SRC/sentinel-dvpnd/bin/sentinel-dvpnd" "$SRC/sentinel-dvpn/bin/sentinel-dvpn" "$OUT/"
fi
