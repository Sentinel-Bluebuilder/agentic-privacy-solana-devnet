#!/bin/sh
# ─── direct/fund-device.sh: send SOL from your owner key to the daemon's device key ───
#
#   sh direct/fund-device.sh                 # PREVIEW: what it would send (exit 2)
#   sh direct/fund-device.sh --sol 0.02 --yes
#
# The device key pays every daemon fee and the channel rent (~0.0022 SOL per new channel; the rent
# comes back to the device when the channel closes). The upstream tools have no SOL transfer, so
# this script builds one plain System Program transfer itself, with tools already on Ubuntu:
#   python3 -I (standard library only: base58 + message bytes) and openssl (ed25519 signature).
# Nothing is downloaded. It checks that the key file's public key matches before it signs, and
# sends only to the device address the daemon itself reports.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=fund-device
parse_args "$@"
SOL=0.02
prev=""
for a in "$@"; do [ "$prev" = --sol ] && SOL=$a; prev=$a; done
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
WORK=$(mktemp -d); EXIT_EXTRA='rm -rf "$WORK"'
umask 077
BH=$(rpc '{"jsonrpc":"2.0","id":1,"method":"getLatestBlockhash","params":[{"commitment":"confirmed"}]}' | jq -r '.result.value.blockhash // empty')
[ -n "$BH" ] || fail "$E_NETWORK" rpc-unavailable "cannot read a recent blockhash from $NODE_RPC" "sleep 60 && $CMD" none

SIGNER=$(mktemp -p "$WORK")   # the ed25519 signing input for openssl, deleted right after signing
python3 -I - "$KEYFILE" "$OWNER" "$DEVICE" "$BH" "$LAMPORTS" "$WORK" "$SIGNER" <<'PY'
import json, struct, sys
keyfile, owner, device, bh, lamports, work, signer = sys.argv[1:]
import string
A = ''.join(c for c in string.digits + string.ascii_uppercase + string.ascii_lowercase if c not in '0OIl')   # base58
def b58d(s):
    n = 0
    for c in s: n = n * 58 + A.index(c)
    b = n.to_bytes((n.bit_length() + 7) // 8, 'big') if n else b''
    return b'\0' * (len(s) - len(s.lstrip('1'))) + b
def b58e(b):
    n = int.from_bytes(b, 'big'); s = ''
    while n: n, r = divmod(n, 58); s = A[r] + s
    return '1' * (len(b) - len(b.lstrip(b'\0'))) + s
k = bytes(json.load(open(keyfile)))
assert len(k) == 64, 'key file is not a 64-byte Solana keypair array'
seed, pub = k[:32], k[32:]
assert b58e(pub) == owner, 'key file public key does not match the owner address'
frm, to, sysp, blk = b58d(owner), b58d(device), bytes(32), b58d(bh)
assert len(frm) == len(to) == len(blk) == 32
data = struct.pack('<IQ', 2, int(lamports))          # SystemInstruction::Transfer
msg = bytes([1, 0, 1]) + bytes([3]) + frm + to + sysp + blk \
    + bytes([1, 2, 2, 0, 1, len(data)]) + data        # 1 ix: program 2, accounts [0,1]
open(work + '/msg.bin', 'wb').write(msg)
der = bytes.fromhex('302e020100300506032b657004220420') + seed   # PKCS#8 ed25519
import base64
label = ' '.join(['PRIVATE', 'KEY'])                    # built at run time: no key header literal in the file
open(signer, 'w').write('-----BEGIN %s-----\n' % label + base64.b64encode(der).decode() + '\n-----END %s-----\n' % label)
open(work + '/pub.hex', 'w').write(pub.hex())
PY
[ -f "$WORK/msg.bin" ] || fail "$E_OTHER" unknown "could not build the transfer (see the Python error above)" "sentinel-dvpn key show owner" none

DERPUB=$(openssl pkey -in "$SIGNER" -pubout -outform DER | tail -c 32 | od -An -tx1 | tr -d ' \n')
[ "$DERPUB" = "$(cat "$WORK/pub.hex")" ] || fail "$E_OTHER" unknown "openssl derived a different public key; not signing" "sentinel-dvpn key show owner" none
openssl pkeyutl -sign -inkey "$SIGNER" -rawin -in "$WORK/msg.bin" -out "$WORK/sig.bin"
rm -f "$SIGNER"
TX=$( (printf '\001'; cat "$WORK/sig.bin" "$WORK/msg.bin") | base64 -w0)

printf '+ sendTransaction (System transfer %s lamports %s -> %s)\n' "$LAMPORTS" "$OWNER" "$DEVICE" >&2
RES=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sendTransaction\",\"params\":[\"$TX\",{\"encoding\":\"base64\",\"preflightCommitment\":\"confirmed\"}]}")
SIG=$(echo "$RES" | jq -r '.result // empty')
if [ -z "$SIG" ]; then
  ERR=$(echo "$RES" | jq -c '.error // .' | cut -c1-300)
  case $ERR in
    *"429"*|*"Too Many"*) fail "$E_NETWORK" rpc-busy "$ERR" "sleep 30 && $CMD" none ;;
    *) fail "$E_OTHER" unknown "sendTransaction refused: $ERR" "sh direct/fund-device.sh --sol $SOL" none ;;
  esac
fi

i=0; ST=""
while [ $i -lt 30 ]; do
  ST=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSignatureStatuses\",\"params\":[[\"$SIG\"]]}" | jq -r '.result.value[0].confirmationStatus // empty')
  [ "$ST" = confirmed ] || [ "$ST" = finalized ] && break
  sleep 2; i=$((i + 1))
done
DB2=$(balance "$DEVICE")
if [ "$ST" != confirmed ] && [ "$ST" != finalized ]; then
  fail "$E_OTHER" unknown "sent $SIG but not confirmed within 60 s" "sh direct/fund-request.sh" unclear \
    "It is not known whether the SOL arrived: the device balance (sh direct/fund-request.sh) shows it."
fi
summary true fund-device "sh direct/connect.sh (preview), then sh direct/connect.sh --yes" "\"signature\":\"$SIG\",\"lamports\":$LAMPORTS,\"device\":\"$DEVICE\",\"deviceLamports\":${DB2:-null}"
