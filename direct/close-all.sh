#!/bin/sh
# ─── direct/close-all.sh: end a box in one command: refund, revoke, sweep both keys, read back to 0 ───
#
#   sh direct/close-all.sh --to <address>          # DRY: what it would do, every amount (exit 2)
#   sh direct/close-all.sh --to <address> --yes    # does it
#
# Steps (each prints its raw commands):
#   1. sh direct/disconnect.sh                  stop any session
#   2. sh direct/refund.sh --revoke --yes       close what is due, withdraw, then close the grant and
#                                               revoke the delegate. If a close is still in its 2 h wait,
#                                               it stops with close-wait and the time to run it again
#   3. sweep the owner key: all tDVPN, then all SOL but one 5000-lamport fee, to --to
#   4. sweep the device key: all SOL but one fee, to --to (from a temporary copy, shredded after)
#   5. reads both balances back and checks 0 SOL and 0 tDVPN
# The sends use Path A's CLI (`devnet-dvpn wallet send`; the upstream tools have no token transfer).
# If it is missing, --yes installs the Linux .deb from the app release after checking its SHA-256.
# Not swept: the owner's token account rent (~0.002 SOL stays in the account; no tool closes it) and
# the device's user account rent (it stays with the user account).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=close-all
parse_args "$@"
TO=""; prev=""
for a in "$@"; do [ "$prev" = --to ] && TO=$a; prev=$a; done
need sentinel-dvpn; need jq; need curl
case $TO in
  '') fail "$E_USAGE" usage "--to <address> is required: where the funds go" "sh direct/close-all.sh --help" none ;;
esac
printf '%s' "$TO" | grep -Eq '^[1-9A-HJ-NP-Za-km-z]{32,44}$' \
  || fail "$E_USAGE" usage "--to is not a base58 Solana address: $TO" "sh direct/close-all.sh --help" none

PATHA_URL=${PATHA_URL:-https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/download/v0.3.0-rc5}
PATHA_DEB=devnet-dvpn_0.3.0-rc.5_amd64.deb
OWNER_KEY=${OWNER_KEYFILE:-$HOME/.sentinel-dvpn/keys/owner.json}
DEVICE_KEY=/var/lib/sentinel-dvpn/$INSTANCE/keys/$DEVICE_KEY_NAME.json
FEE=5000

OWNER=$(owner_address)
DEVICE=$(device_address)
[ "$TO" != "$OWNER" ] && [ "$TO" != "$DEVICE" ] || fail "$E_USAGE" usage "--to must be another address, not this box's own key" "sh direct/close-all.sh --help" none

bal() { try none sentinel-dvpn wallet balance --owner "$1" 2>/dev/null; }
sol() { awk -v l="$1" 'BEGIN { printf "%.9f", l / 1000000000 }'; }

# ─── dry run: everything it would do ───
if [ "$YES" != 1 ]; then
  RP=$(sh "$HERE/refund.sh" --revoke 2>/dev/null | tail -1) || true
  OB=$(bal "$OWNER"); DB=$(bal "$DEVICE")
  OD=$(echo "$OB" | jq -r .dvpn_base_units); OL=$(echo "$OB" | jq -r .lamports); DL=$(echo "$DB" | jq -r .lamports)
  RW=$(printf '%s' "$RP" | jq -r '.what // .next // "nothing"')
  # payees: refund.sh's own (money coming back), then the three sends to --to
  PAYEES=$(printf '%s' "$RP" | jq -c '.payees // []' 2>/dev/null | sed 's/^\[//; s/\]$//') || PAYEES=""
  fee_tx $(( $(printf '%s' "$RP" | jq -r '.feeLamports // 0' 2>/dev/null || echo 0) / 5000 ))
  [ "$OD" -gt 0 ] && payee transfer "$TO" "$OD" 0 no owner && fee_tx 1
  [ "$OL" -gt $((2 * FEE)) ] && payee transfer "$TO" 0 $((OL - 2 * FEE)) no owner && fee_tx 1
  [ "$DL" -gt "$FEE" ] && payee transfer "$TO" 0 $((DL - FEE)) no device && fee_tx 1
  FEE_NOTE="the SOL sends are the balances read now minus their own fee; step 2's rent refunds add to them"
  confirm "1. disconnect any session; 2. refund + revoke: $RW; 3. send owner $(tdvpn "$OD") tDVPN + about $(sol $((OL - 2 * FEE))) SOL (the SOL after step 2 refunds rent, minus fees) to $TO; 4. send device about $(sol $((DL - FEE))) SOL to $TO; 5. read back to 0. Now: owner $OD tDVPN base units + $OL lamports, device $DL lamports" \
    "sh direct/close-all.sh --to $TO"
fi

# ─── 1 + 2: session, refund, revoke ───
D1=$(sh "$HERE/disconnect.sh" | tail -1) || true
case $D1 in *'"ok":true'*) ;; *) echo "$D1"; fail "$E_OTHER" "$(printf '%s' "$D1" | jq -r '.code // "step-failed"')" "disconnect did not finish" "$(printf '%s' "$D1" | jq -r '.next // "sh direct/disconnect.sh"')" refund ;; esac
R1=$(sh "$HERE/refund.sh" --revoke --yes | tail -1) || true
echo "$R1" >&2
case $R1 in *'"ok":true'*) ;; *) fail "$E_OTHER" "$(printf '%s' "$R1" | jq -r '.code // "step-failed"')" "refund did not finish" "$(printf '%s' "$R1" | jq -r '.next // "sh direct/refund.sh"')" refund ;; esac
AFTER=$(printf '%s' "$R1" | jq -r '.closeAfter // empty')
if [ -n "$AFTER" ]; then
  WAIT=$(( $(date -u -d "$AFTER" +%s) - $(date -u +%s) + 30 )); [ "$WAIT" -gt 0 ] || WAIT=30
  fail "$E_OTHER" close-wait "a channel close is still in its wait until $AFTER; nothing was swept yet" "sleep $WAIT && sh direct/close-all.sh --to $TO --yes" refund
fi
MONEY_STATE=none

# ─── Path A CLI for the sends ───
if ! command -v devnet-dvpn >/dev/null 2>&1; then
  T=$(mktemp -d)
  step "$E_NETWORK" download-failed "sleep 60 && $CMD" none curl -fsSL -o "$T/SHA256SUMS" "$PATHA_URL/SHA256SUMS"
  step "$E_NETWORK" download-failed "sleep 60 && $CMD" none curl -fsSL -o "$T/$PATHA_DEB" "$PATHA_URL/$PATHA_DEB"
  (cd "$T" && sha256sum --ignore-missing -c SHA256SUMS >&2) \
    || fail "$E_SAFETY" checksum-mismatch "SHA-256 mismatch on $PATHA_DEB; not installed" "sh direct/close-all.sh --to $TO" none
  step "$E_OTHER" install-failed "sudo apt-get install -y $T/$PATHA_DEB" none \
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$T/$PATHA_DEB"
  rm -rf "$T"
fi

# send <keyfile> <--tdvpn|--sol> <amount>: one Path A send; prints the signature
send() {
  out=$(export DVPN_KEYFILE="$1"; try none devnet-dvpn wallet send --to "$TO" "$2" "$3" --yes --json)
  printf '%s' "$out" | jq -r '.signature // empty'
}

# ─── 3. owner: tDVPN, then SOL ───
SIGS=""
OD=$(bal "$OWNER" | jq -r .dvpn_base_units)
if [ "$OD" -gt 0 ]; then
  s=$(send "$OWNER_KEY" --tdvpn "$(tdvpn "$OD")"); SIGS="$SIGS\"owner-tdvpn\":\"$s\","; sleep 8
fi
OL=$(bal "$OWNER" | jq -r .lamports)
if [ "$OL" -gt "$FEE" ]; then
  s=$(send "$OWNER_KEY" --sol "$(sol $((OL - FEE)))"); SIGS="$SIGS\"owner-sol\":\"$s\","; sleep 8
fi

# ─── 4. device: SOL, from a temporary owner-only copy of its key ───
DL=$(bal "$DEVICE" | jq -r .lamports)
if [ "$DL" -gt "$FEE" ]; then
  umask 077
  DK=$(mktemp)
  EXIT_EXTRA='[ -f "$DK" ] && shred -u "$DK"'
  step "$E_OTHER" no-device "sudo ls $DEVICE_KEY" none sh -c "sudo cat '$DEVICE_KEY' > '$DK'"
  s=$(send "$DK" --sol "$(sol $((DL - FEE)))"); SIGS="$SIGS\"device-sol\":\"$s\","
  shred -u "$DK"; EXIT_EXTRA=""
  sleep 8
fi

# ─── 5. read back ───
OB=$(bal "$OWNER"); DB=$(bal "$DEVICE")
OD=$(echo "$OB" | jq -r .dvpn_base_units); OL=$(echo "$OB" | jq -r .lamports); DL=$(echo "$DB" | jq -r .lamports)
if [ "$OD" != 0 ] || [ "$OL" != 0 ] || [ "$DL" != 0 ]; then
  fail "$E_OTHER" sweep-incomplete "after the sweep: owner $OD tDVPN base units + $OL lamports, device $DL lamports" "sh direct/close-all.sh --to $TO --yes" none \
    "No deposit is open; what is left is still on this box's keys and a rerun sends it."
fi
summary true close-all "done: both keys are empty; the box can be deleted" "${SIGS}\"to\":\"$TO\",\"owner\":\"$OWNER\",\"device\":\"$DEVICE\",\"ownerLamports\":0,\"ownerTdvpn\":0,\"deviceLamports\":0"
