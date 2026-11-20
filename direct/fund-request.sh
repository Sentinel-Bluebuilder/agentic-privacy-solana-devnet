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

# Market numbers (Rule 4), from the live node list; 50 tDVPN/GB when fewer than 3 nodes or no list:
#   ask      WANT_DVPN = 2 x p75 price x UNITS (100 tDVPN today: room for 2 market deposits)
#   minimum  MIN_DVPN  = one deposit at the price connect.sh would pick (the cheapest node at or below p75)
NODES=$(sentinel-dvpn node search --service wireguard --live 2>/dev/null) || NODES='[]'
market "$NODES"
PICK=$(cheapest_under "$NODES" "$P75" 2>/dev/null) || PICK=""
PICK_PRICE=${PICK#* }; [ -n "$PICK" ] || PICK_PRICE=$P75
WANT_DVPN=${WANT_DVPN:-$((2 * P75 * UNITS))}
MIN_DVPN=${MIN_DVPN:-$((PICK_PRICE * UNITS))}
echo "market: $NMATCH nodes, p75 $(tdvpn "$P75") tDVPN/GB; ask $(tdvpn "$WANT_DVPN") tDVPN, minimum $(tdvpn "$MIN_DVPN") tDVPN (one deposit at $(tdvpn "$PICK_PRICE") tDVPN/GB x $UNITS GB)" >&2
# "funded" = enough to work (the ask is 0.01 / 0.03 SOL): owner 0.005 SOL, device 0.01 SOL, in lamports
MIN_OWNER_SOL=${MIN_OWNER_SOL:-5000000}
MIN_DEVICE_SOL=${MIN_DEVICE_SOL:-10000000}

OWNER=$(owner_address)
DEVICE=$(device_address)

cat <<EOF
──── send this to whoever funds you ────
Please fund my Sentinel devnet client (Solana devnet):
  owner  $OWNER : $(tdvpn "$WANT_DVPN") tDVPN (mint Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa) + 0.01 SOL
  device $DEVICE : 0.03 SOL
────────────────────────────────────────
Read back with plain JSON-RPC (lamports):
  curl -s $NODE_RPC -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$OWNER"]}'
  curl -s $NODE_RPC -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$DEVICE"]}'
EOF

check() {
  O=$(try none sentinel-dvpn wallet balance --owner "$OWNER" 2>/dev/null)
  D=$(try none sentinel-dvpn wallet balance --owner "$DEVICE" 2>/dev/null)
  OD=$(echo "$O" | jq -r .dvpn_base_units); OL=$(echo "$O" | jq -r .lamports); DL=$(echo "$D" | jq -r .lamports)
  echo "+ sentinel-dvpn wallet balance --owner $OWNER  -> dvpn_base_units=$OD lamports=$OL" >&2
  echo "+ sentinel-dvpn wallet balance --owner $DEVICE -> lamports=$DL" >&2
  [ "$OD" -ge "$MIN_DVPN" ] && [ "$OL" -ge "$MIN_OWNER_SOL" ] && [ "$DL" -ge "$MIN_DEVICE_SOL" ]
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
# The owner alone holds enough tDVPN and SOL for both keys: move the device's share yourself
NEXT="sh direct/fund-request.sh --wait"
if [ "$OD" -ge "$MIN_DVPN" ] && [ "$DL" -lt "$MIN_DEVICE_SOL" ] && [ "$OL" -ge $((MIN_OWNER_SOL + 20000000 + 5000)) ]; then
  NEXT="sh direct/fund-device.sh --sol 0.02 --yes"
fi
printf '{"ok":false,"step":"fund-request","code":"not-funded","money":"none","moneyNote":"Nothing was paid.","error":"owner %s tDVPN base units + %s lamports (minimum %s + %s), device %s lamports (wants %s)","owner":"%s","device":"%s","funded":false,"next":"%s"}\n' \
  "$OD" "$OL" "$MIN_DVPN" "$MIN_OWNER_SOL" "$DL" "$MIN_DEVICE_SOL" "$OWNER" "$DEVICE" "$NEXT"
echo "$E_OPERATOR" > "$FAIL_CODE_FILE"   # the JSON line above is the failure line
exit "$E_OPERATOR"
