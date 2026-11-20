#!/bin/sh
# ─── direct/fund-device.sh: send SOL from your owner key to the daemon's device key ───
#
#   sh direct/fund-device.sh                 # PREVIEW: what it would send (exit 2)
#   sh direct/fund-device.sh --sol 0.02 --yes
#
# The device key pays every daemon fee and the channel rent (~0.0022 SOL per new channel; the rent
# comes back to the device when the channel closes). The upstream tools have no SOL transfer, so
# this script builds one plain System Program transfer itself (direct/soltx.py + sol_send in lib.sh, the
# same signer close-all.sh uses), with tools already on Ubuntu:
#   python3 -I (standard library only: base58 + message bytes) and openssl (ed25519 signature).
# Nothing is downloaded. It checks that the key file's public key matches before it signs, and
# sends only to the device address the daemon itself reports.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=fund-device
ARGS_VAL="--sol"; parse_args "$@"
SOL=${ARG_sol:-0.02}

need sentinel-dvpn; need jq; need curl; need python3; need openssl

KEYFILE=${OWNER_KEYFILE:-$HOME/.sentinel-dvpn/keys/owner.json}
[ -r "$KEYFILE" ] || fail "$E_OPERATOR" no-wallet "owner key file $KEYFILE not found" "sudo sh direct/install.sh" none
OWNER=$(owner_address)
DEVICE=$(device_address)
LAMPORTS=$(python3 -I -c 'import sys,decimal; v=decimal.Decimal(sys.argv[1]); assert 0 < v <= 1; print(int(v*1000000000))' "$SOL" 2>/dev/null) \
  || fail "$E_USAGE" usage "--sol must be a number above 0 and at most 1 (got $SOL)" "sh direct/fund-device.sh --sol 0.02" none

rpc() { curl -s -m 20 "$NODE_RPC" -H 'content-type: application/json' -d "$1"; }
balance() { rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getBalance\",\"params\":[\"$1\",{\"commitment\":\"confirmed\"}]}" | jq -r '.result.value // empty'; }

OB=$(balance "$OWNER"); DB=$(balance "$DEVICE")
[ -n "$OB" ] || fail "$E_NETWORK" rpc-unavailable "cannot read the owner balance from $NODE_RPC" "sleep 60 && $CMD" none
echo "owner $OWNER: $OB lamports; device $DEVICE: ${DB:-?} lamports" >&2
NEED=$((LAMPORTS + 5000))
[ "$OB" -ge "$NEED" ] || fail "$E_OPERATOR" not-funded "the owner has $OB lamports, needs $NEED ($LAMPORTS + 5000 fee)" "sh direct/fund-request.sh" none

payee transfer "$DEVICE" 0 "$LAMPORTS" yours owner
fee_tx 1   # one System Program transfer, signed by the owner
FEE_NOTE="the device is your own key; it spends this SOL on fees and rent"
confirm "send $LAMPORTS lamports ($SOL SOL) from owner $OWNER to device $DEVICE (fee 5000 lamports)" "sh direct/fund-device.sh --sol $SOL"

# ─── build, sign, send ───
sol_send "$KEYFILE" "$OWNER" unclear "System transfer $LAMPORTS lamports $OWNER -> $DEVICE" sol "$DEVICE" "$LAMPORTS"
SIG=$TX_SIG
DB2=$(balance "$DEVICE")
summary true fund-device "sh direct/connect.sh" "\"then\":\"sh direct/connect.sh --yes\",\"signature\":\"$SIG\",\"lamports\":$LAMPORTS,\"device\":\"$DEVICE\",\"deviceLamports\":${DB2:-null}"
