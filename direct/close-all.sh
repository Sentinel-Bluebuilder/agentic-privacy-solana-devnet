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
#   3. sweep the owner key: all tDVPN (one Token-2022 transferChecked) and close its token account (its
#      ~0.002 SOL rent goes to --to) in one transaction; then all SOL but the 5000-lamport fee, to --to
#   4. sweep the device key: all SOL but one fee, to --to (signed from a temporary copy, shredded after)
#   5. reads both balances back and checks 0 SOL and 0 tDVPN
# The sends are built and signed here, like fund-device.sh: direct/soltx.py (python3 -I, standard library)
# makes the message, openssl signs it (ed25519), curl sends it to the RPC. No app, no Solana CLI, nothing
# downloaded. --to must already hold a tDVPN token account (no-token-account otherwise, before any send).
# Not swept: the device's user account rent (it stays with the user account).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=close-all
ARGS_VAL="--to"; parse_args "$@"
TO=${ARG_to:-}
need sentinel-dvpn; need jq; need curl; need python3; need openssl
case $TO in
  '') fail "$E_USAGE" usage "--to <address> is required: where the funds go" "sh direct/close-all.sh --help" none ;;
esac
printf '%s' "$TO" | grep -Eq '^[1-9A-HJ-NP-Za-km-z]{32,44}$' \
  || fail "$E_USAGE" usage "--to is not a base58 Solana address: $TO" "sh direct/close-all.sh --help" none
# --to must be a wallet someone can sign for: not a sysvar, not a program, not an off-curve (PDA) address
case $TO in Sysvar*) fail "$E_USAGE" usage "--to $TO is a sysvar, not a wallet" "sh direct/close-all.sh --help" none ;; esac
python3 -I "$HERE/soltx.py" oncurve "$TO" \
  || fail "$E_USAGE" usage "--to $TO is not a wallet key (off the ed25519 curve: a program-derived account nobody can sign for)" "sh direct/close-all.sh --help" none
TO_EXEC=$(sol_rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getAccountInfo\",\"params\":[\"$TO\",{\"encoding\":\"base64\"}]}" | jq -r '.result.value.executable // false')
[ "$TO_EXEC" != true ] || fail "$E_USAGE" usage "--to $TO is a program, not a wallet" "sh direct/close-all.sh --help" none

OWNER_KEY=${OWNER_KEYFILE:-$HOME/.sentinel-dvpn/keys/owner.json}
DEVICE_KEY=/var/lib/sentinel-dvpn/$INSTANCE/keys/$DEVICE_KEY_NAME.json
FEE=5000
MINT=${MINT:-Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa}   # the devnet tDVPN mint (sentinel-dvpn version)

OWNER=$(owner_address)
DEVICE=$(device_address)
[ "$TO" != "$OWNER" ] && [ "$TO" != "$DEVICE" ] || fail "$E_USAGE" usage "--to must be another address, not this box's own key" "sh direct/close-all.sh --help" none

bal() { try none sentinel-dvpn wallet balance --owner "$1" 2>/dev/null; }
sol() { awk -v l="$1" 'BEGIN { printf "%.9f", l / 1000000000 }'; }

# tacct <owner>: "<token account> <program> <amount> <decimals> <lamports>" of its tDVPN token account, or empty
tacct() {
  sol_rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenAccountsByOwner\",\"params\":[\"$1\",{\"mint\":\"$MINT\"},{\"encoding\":\"jsonParsed\",\"commitment\":\"confirmed\"}]}" \
    | jq -r '.result.value[0] // empty | "\(.pubkey) \(.account.owner) \(.account.data.parsed.info.tokenAmount.amount) \(.account.data.parsed.info.tokenAmount.decimals) \(.account.lamports)"'
}

# The tDVPN needs a token account at --to. Checked before anything is signed (refund.sh withdraws into the
# owner's token account, so any owner token account means tDVPN will be sent).
if [ -n "$(tacct "$OWNER")" ] && [ -z "$(tacct "$TO")" ]; then
  fail "$E_OPERATOR" no-token-account "$TO has no tDVPN token account to receive the owner's tDVPN" "sh direct/close-all.sh --help" none \
    "Nothing was paid. Pass a --to that already holds tDVPN (your funder's wallet does)."
fi

# ─── dry run: everything it would do ───
if [ "$YES" != 1 ]; then
  RP=$(sh "$HERE/refund.sh" --revoke 2>/dev/null | tail -1) || true
  OB=$(bal "$OWNER"); DB=$(bal "$DEVICE")
  OD=$(echo "$OB" | jq -r .dvpn_base_units); OL=$(echo "$OB" | jq -r .lamports); DL=$(echo "$DB" | jq -r .lamports)
  RW=$(printf '%s' "$RP" | jq -r '.what // .next // "nothing"')
  # payees: refund.sh's own (money coming back), then the sends to --to
  PAYEES=$(printf '%s' "$RP" | jq -c '.payees // []' 2>/dev/null | sed 's/^\[//; s/\]$//') || PAYEES=""
  fee_tx $(( $(printf '%s' "$RP" | jq -r '.feeLamports // 0' 2>/dev/null || echo 0) / 5000 ))
  TA=$(tacct "$OWNER"); TR=$(echo "$TA" | awk '{print $5}')
  if [ -n "$TA" ]; then
    payee transfer "$TO" "$OD" "$TR" no owner && fee_tx 1   # transferChecked + closeAccount: tDVPN and the token account rent
  fi
  [ "$OL" -gt $((2 * FEE)) ] && payee transfer "$TO" 0 $((OL - 2 * FEE)) no owner && fee_tx 1
  [ "$DL" -gt "$FEE" ] && payee transfer "$TO" 0 $((DL - FEE)) no device && fee_tx 1
  FEE_NOTE="the SOL sends are the balances read now minus their own fee; step 2's rent refunds add to them"
  confirm "1. disconnect any session; 2. refund + revoke: $RW; 3. send owner $(tdvpn "$OD") tDVPN + its token account rent + about $(sol $((OL - 2 * FEE))) SOL (the SOL after step 2 refunds rent, minus fees) to $TO (signed here: python3 + openssl); 4. send device about $(sol $((DL - FEE))) SOL to $TO; 5. read back to 0. If a close is still in its 2 h wait, --yes stops at step 2 (close-wait) before sending anything. Now: owner $OD tDVPN base units + $OL lamports, device $DL lamports" \
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

# ─── 3. owner: all tDVPN (transferChecked) + close its token account (rent to --to), then all SOL ───
SIGS=""
set -- $(tacct "$OWNER")
if [ $# = 5 ]; then
  SRC=$1; TPROG=$2; AMT=$3; DEC=$4
  DST=""
  if [ "$AMT" -gt 0 ]; then
    DST=$(tacct "$TO" | awk '{print $1}')
    [ -n "$DST" ] || fail "$E_OPERATOR" no-token-account "$TO has no tDVPN token account to receive $(tdvpn "$AMT") tDVPN" \
      "sh direct/close-all.sh --help" none \
      "Nothing was sent. The refund and revoke are done; the tDVPN is still on the owner key."
  fi
  sol_send "$OWNER_KEY" "$OWNER" none "transferChecked $AMT base units $SRC -> $DST + closeAccount $SRC (rent to $TO)" \
    token "$SRC" "$MINT" "${DST:-$SRC}" "$AMT" "$DEC" "$TPROG" "$TO"
  SIGS="$SIGS\"owner-tdvpn\":\"$TX_SIG\","; sleep 5
fi
OL=$(bal "$OWNER" | jq -r .lamports)
if [ "$OL" -gt "$FEE" ]; then
  sol_send "$OWNER_KEY" "$OWNER" none "System transfer $((OL - FEE)) lamports $OWNER -> $TO" sol "$TO" $((OL - FEE))
  SIGS="$SIGS\"owner-sol\":\"$TX_SIG\","; sleep 5
fi

# ─── 4. device: all SOL, from a temporary owner-only copy of its key ───
DL=$(bal "$DEVICE" | jq -r .lamports)
if [ "$DL" -gt "$FEE" ]; then
  DK=$(umask 077; mktemp)
  EXIT_EXTRA='[ -f "$DK" ] && shred -u "$DK"'
  step "$E_OTHER" no-device "sudo ls $DEVICE_KEY" none sh -c "sudo cat '$DEVICE_KEY' > '$DK'"
  sol_send "$DK" "$DEVICE" none "System transfer $((DL - FEE)) lamports $DEVICE -> $TO" sol "$TO" $((DL - FEE))
  SIGS="$SIGS\"device-sol\":\"$TX_SIG\","
  shred -u "$DK"; EXIT_EXTRA=""
  sleep 5
fi

# ─── 5. read back ───
OB=$(bal "$OWNER"); DB=$(bal "$DEVICE")
OD=$(echo "$OB" | jq -r .dvpn_base_units); OL=$(echo "$OB" | jq -r .lamports); DL=$(echo "$DB" | jq -r .lamports)
if [ "$OD" != 0 ] || [ "$OL" != 0 ] || [ "$DL" != 0 ]; then
  fail "$E_OTHER" sweep-incomplete "after the sweep: owner $OD tDVPN base units + $OL lamports, device $DL lamports" "sh direct/close-all.sh --to $TO --yes" none \
    "No deposit is open; what is left is still on this box's keys and a rerun sends it."
fi
summary true close-all "sh direct/fund-request.sh" "\"note\":\"done: both keys are empty; the box can be deleted (fund-request.sh reads the balances back)\",${SIGS}\"to\":\"$TO\",\"owner\":\"$OWNER\",\"device\":\"$DEVICE\",\"ownerLamports\":0,\"ownerTdvpn\":0,\"deviceLamports\":0"
