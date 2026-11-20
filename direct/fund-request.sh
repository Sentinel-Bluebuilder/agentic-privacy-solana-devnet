#!/bin/sh
# ─── direct/fund-request.sh: print the one funding message to send, then read both balances back ───
#
#   sh direct/fund-request.sh            # prints the message + current balances
#   sh direct/fund-request.sh --wait     # also waits (up to 30 min) until both are funded
#
# Two addresses need money, and you ask for both in ONE message:
#   owner  (your wallet key):  tDVPN to spend + about 0.01 SOL for the grant / user / delegate rent
#   device (the daemon's key): about 0.03 SOL; it pays every transaction fee and the channel rent.
#                              That rent comes back to the device when the channel closes.
# No Solana CLI is needed: the readback uses sentinel-dvpn, and a plain curl line is printed too.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=fund-request
need sentinel-dvpn; need jq; need curl

WANT_DVPN=${WANT_DVPN:-20000000}        # ask: 20 tDVPN (6 decimals); also the "funded" minimum
# "funded" = enough to work (the ask is 0.01 / 0.03 SOL): owner 0.005 SOL, device 0.01 SOL, in lamports
MIN_OWNER_SOL=${MIN_OWNER_SOL:-5000000}
MIN_DEVICE_SOL=${MIN_DEVICE_SOL:-10000000}

OWNER=$(owner_address)
DEVICE=$(device_address)

cat <<EOF
──── send this to whoever funds you ────
Please fund my Sentinel devnet client (Solana devnet):
  owner  $OWNER : $((WANT_DVPN / 1000000)) tDVPN (mint Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa) + 0.01 SOL
  device $DEVICE : 0.03 SOL
────────────────────────────────────────
Read back with plain JSON-RPC (lamports):
  curl -s $NODE_RPC -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$OWNER"]}'
  curl -s $NODE_RPC -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$DEVICE"]}'
EOF

check() {
  O=$(sentinel-dvpn wallet balance --owner "$OWNER")
  D=$(sentinel-dvpn wallet balance --owner "$DEVICE")
  OD=$(echo "$O" | jq -r .dvpn_base_units); OL=$(echo "$O" | jq -r .lamports); DL=$(echo "$D" | jq -r .lamports)
  echo "+ sentinel-dvpn wallet balance --owner $OWNER  -> dvpn_base_units=$OD lamports=$OL" >&2
  echo "+ sentinel-dvpn wallet balance --owner $DEVICE -> lamports=$DL" >&2
  [ "$OD" -ge "$WANT_DVPN" ] && [ "$OL" -ge "$MIN_OWNER_SOL" ] && [ "$DL" -ge "$MIN_DEVICE_SOL" ]
}

if check; then
  summary true fund-request "sh direct/connect.sh (preview), then sh direct/connect.sh --yes" "\"owner\":\"$OWNER\",\"device\":\"$DEVICE\",\"funded\":true"
  exit 0
fi
if [ "${1:-}" = --wait ]; then
  i=0
  while [ $i -lt 60 ]; do sleep 30; i=$((i + 1)); if check; then
    summary true fund-request "sh direct/connect.sh (preview), then sh direct/connect.sh --yes" "\"owner\":\"$OWNER\",\"device\":\"$DEVICE\",\"funded\":true"; exit 0; fi
  done
fi
printf '{"ok":false,"step":"fund-request","code":"not-funded","money":"none","moneyNote":"Nothing was paid.","owner":"%s","device":"%s","funded":false,"next":"send the message above, then: sh direct/fund-request.sh --wait"}\n' "$OWNER" "$DEVICE"
exit "$E_OPERATOR"
