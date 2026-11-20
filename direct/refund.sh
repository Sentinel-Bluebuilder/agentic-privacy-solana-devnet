#!/bin/sh
# ─── direct/refund.sh: get unspent escrow back, step by step; safe to run again ───
#
#   sh direct/refund.sh                  # PREVIEW: lists what is due now, exit 2
#   sh direct/refund.sh --yes            # does it, then tells you when to run it again
#   sh direct/refund.sh --revoke --yes   # also closes the grant and revokes the delegate at the end
#
# The money path (docs/DIRECT.md "Refund"):
#   1. start close  : sentinel-dvpn channel start-close-channel --channel <ch>   (open channels)
#   2. wait         : the program's channel_close_grace_seconds (7200 s = 2 h on devnet), so the
#                     node can still redeem the vouchers you signed
#   3. close        : sentinel-dvpn channel close-channel --channel <ch>; unspent escrow goes to your
#                     user balance; the channel's rent goes back to its rent payer (the device key)
#   4. withdraw     : sentinel-dvpn user withdraw-user-balance; user balance -> your token account
# Sign with the owner key (the default --key.name owner). Do not pass --grant here: the grant is
# for the device key; passing it as the owner fails with ConstraintSeeds (2006).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=refund
parse_args "$@"
REVOKE=0; for a in "$@"; do [ "$a" = --revoke ] && REVOKE=1; done
need sentinel-dvpn; need jq
SELF="sh direct/refund.sh"; [ "$REVOKE" = 1 ] && SELF="$SELF --revoke"

OWNER=$(owner_address)
DEVICE=$(device_address)
GRACE=$(try none sentinel-dvpn program params | jq -r .channel_close_grace_seconds)
NOW=$(date +%s)

ACTIVE=0; daemon_running && ACTIVE=$(try none dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[]? | select(.status == "active")] | length')
[ "$ACTIVE" = 0 ] || fail "$E_OTHER" session-active "a session is active; its channel cannot be closed cleanly" "sh direct/disconnect.sh && $SELF" none

# ─── plan (read-only) ───
CHANNELS=$(try none sentinel-dvpn channel search --owner "$OWNER")
TO_START=$(echo "$CHANNELS" | jq -r '.[] | select(.value.status == 0) | .address')
TO_CLOSE=$(echo "$CHANNELS" | jq -r --argjson now "$NOW" --argjson g "$GRACE" '.[] | select(.value.status == 1 and (.value.close_started_at + $g) <= $now) | .address')
WAITING=$(echo "$CHANNELS" | jq -r --argjson now "$NOW" --argjson g "$GRACE" '[.[] | select(.value.status == 1 and (.value.close_started_at + $g) > $now) | .value.close_started_at + $g] | max // 0')
ESCROW_START=$(echo "$CHANNELS" | jq '[.[] | select(.value.status == 0) | .value.escrow - .value.redeemed] | add // 0')
ESCROW_CLOSE=$(echo "$CHANNELS" | jq --argjson now "$NOW" --argjson g "$GRACE" '[.[] | select(.value.status == 1 and (.value.close_started_at + $g) <= $now) | .value.escrow - .value.redeemed] | add // 0')
BAL=$(try none sentinel-dvpn user search --owner "$OWNER" | jq -r '.[0].value.balance // 0')
GRANT=""
[ "$REVOKE" = 1 ] && GRANT=$(try none sentinel-dvpn grant search --granter "$OWNER" --grantee "$DEVICE" | jq -r '.[0].address // empty')

[ -n "$TO_START" ] && WAIT_UNTIL=$((NOW + GRACE)) || WAIT_UNTIL=0
[ "$WAITING" -gt "$WAIT_UNTIL" ] && WAIT_UNTIL=$WAITING

WHAT=""
for ch in $TO_START; do WHAT="${WHAT}start close $ch; "; done
for ch in $TO_CLOSE; do WHAT="${WHAT}close $ch; "; done
[ -n "$TO_START" ] && WHAT="${WHAT}(up to $ESCROW_START base units come back after the 2 h wait) "
[ -n "$TO_CLOSE" ] && WHAT="${WHAT}(up to $ESCROW_CLOSE base units move to your user balance, minus what the node redeems) "
{ [ "$BAL" -gt 0 ] || [ -n "$TO_CLOSE" ]; } && WHAT="${WHAT}withdraw user balance to your wallet; "
[ "$REVOKE" = 1 ] && [ "$WAIT_UNTIL" = 0 ] && WHAT="${WHAT}close grant ${GRANT:-none} (rent back to owner) + revoke delegate; "

if [ -z "$WHAT" ]; then
  if [ "$WAIT_UNTIL" -gt 0 ]; then
    WHEN=$(date -u -d "@$WAIT_UNTIL" +%Y-%m-%dT%H:%M:%SZ)
    summary true refund "wait until $WHEN, then $SELF" "\"closeAfter\":\"$WHEN\",\"userBalance\":$BAL"
  else
    summary true refund "done: nothing left locked" "\"userBalance\":$BAL"
  fi
  exit 0
fi
# who gets what back, and the fees (S6)
NS=$(printf '%s\n' $TO_START | grep -c . || true); NC=$(printf '%s\n' $TO_CLOSE | grep -c . || true)
fee_tx "$NS"; fee_tx "$NC"   # one start-close-channel / close-channel each, signed by the owner
[ "$NC" -gt 0 ] && payee refund "$OWNER" "$ESCROW_CLOSE" 0 unspent-part program \
  && payee refund "$DEVICE" 0 $((NC * RENT_CHANNEL)) yes program
{ [ "$BAL" -gt 0 ] || [ "$NC" -gt 0 ]; } && fee_tx 1   # withdraw-user-balance
[ "$BAL" -gt 0 ] && payee refund "$OWNER" "$BAL" 0 yes program
if [ "$REVOKE" = 1 ] && [ "$WAIT_UNTIL" = 0 ]; then
  fee_tx 2   # grant close-grant + wallet revoke-delegate
  [ -n "$GRANT" ] && payee refund "$OWNER" 0 "$RENT_GRANT" yes program
fi
[ "$NS" -gt 0 ] && FEE_NOTE="starting a close returns nothing yet: up to $ESCROW_START base units come back on the run after the 2 h wait"
confirm "$WHAT" "$SELF"
MONEY_STATE=refund        # a stop from here leaves deposits closing or in the user balance: run refund.sh again

# ─── do it ───
for ch in $TO_START; do try refund sentinel-dvpn channel start-close-channel --channel "$ch" >&2; done
for ch in $TO_CLOSE; do try refund sentinel-dvpn channel close-channel --channel "$ch" >&2; done
BAL=$(try none sentinel-dvpn user search --owner "$OWNER" | jq -r '.[0].value.balance // 0')
if [ "$BAL" -gt 0 ]; then
  try refund sentinel-dvpn user withdraw-user-balance >&2
  BAL=0
fi

if [ "$WAIT_UNTIL" -gt 0 ]; then
  WHEN=$(date -u -d "@$WAIT_UNTIL" +%Y-%m-%dT%H:%M:%SZ)
  summary true refund "wait until $WHEN, then $SELF --yes" "\"closeAfter\":\"$WHEN\",\"userBalance\":$BAL"
  exit 0
fi

if [ "$REVOKE" = 1 ]; then
  [ -n "$GRANT" ] && try none sentinel-dvpn grant close-grant --grant "$GRANT" >&2
  try none sentinel-dvpn wallet revoke-delegate >&2
fi

W=$(try none sentinel-dvpn wallet balance)
summary true refund "done: nothing left locked" "\"dvpn_base_units\":$(echo "$W" | jq .dvpn_base_units),\"lamports\":$(echo "$W" | jq .lamports)"
