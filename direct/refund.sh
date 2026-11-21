#!/bin/sh
# ─── direct/refund.sh: get unspent escrow back, step by step; safe to run again ───
#
#   sh direct/refund.sh                  # PREVIEW: lists what is due now, exit 2
#   sh direct/refund.sh --yes            # does it, then tells you when to run it again
#   sh direct/refund.sh --revoke --yes   # also closes the grant and revokes the delegate at the end
#
# The money path (docs/DIRECT-REFERENCE.md, step 8 "Refund"):
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
ARGS_BOOL="--revoke"; parse_args "$@"
REVOKE=${ARG_revoke:-0}
need sentinel-dvpn; need jq
SELF="sh direct/refund.sh"; [ "$REVOKE" = 1 ] && SELF="$SELF --revoke"

OWNER=$(owner_address)
DEVICE=$(device_address)
GRACE=$(try none sentinel-dvpn program params | jq -r .channel_close_grace_seconds)
NOW=$(chain_now)   # the chain's clock decides when a close is due, not this box's

ACTIVE=0; daemon_running && ACTIVE=$(try none dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[]? | select(.status == "active")] | length')
[ "$ACTIVE" = 0 ] || fail "$E_OTHER" session-active "a session is active; its channel cannot be closed cleanly. It may be another run's: look before you end it" "sh direct/status.sh" none

# ─── plan (read-only) ───
CHANNELS=$(try none sentinel-dvpn channel search --owner "$OWNER")
TO_START=$(echo "$CHANNELS" | jq -r '.[] | select(.value.status == 0) | .address')
TO_CLOSE=$(echo "$CHANNELS" | jq -r --argjson now "$NOW" --argjson g "$GRACE" '.[] | select(.value.status == 1 and (.value.close_started_at + $g) <= $now) | .address')
WAITING=$(echo "$CHANNELS" | jq -r --argjson now "$NOW" --argjson g "$GRACE" '[.[] | select(.value.status == 1 and (.value.close_started_at + $g) > $now) | .value.close_started_at + $g] | min // 0')   # the EARLIEST still waiting
ESCROW_START=$(echo "$CHANNELS" | jq '[.[] | select(.value.status == 0) | .value.escrow - .value.redeemed] | add // 0')
ESCROW_CLOSE=$(echo "$CHANNELS" | jq --argjson now "$NOW" --argjson g "$GRACE" '[.[] | select(.value.status == 1 and (.value.close_started_at + $g) <= $now) | .value.escrow - .value.redeemed] | add // 0')
BAL=$(try none sentinel-dvpn user search --owner "$OWNER" | jq -r '.[0].value.balance // 0')
GRANT=""
[ "$REVOKE" = 1 ] && GRANT=$(try none sentinel-dvpn grant search --granter "$OWNER" --grantee "$DEVICE" | jq -r '.[0].address // empty')

[ -n "$TO_START" ] && WAIT_UNTIL=$((NOW + GRACE)) || WAIT_UNTIL=0
{ [ "$WAITING" -gt 0 ] && { [ "$WAIT_UNTIL" = 0 ] || [ "$WAITING" -lt "$WAIT_UNTIL" ]; }; } && WAIT_UNTIL=$WAITING   # the earliest due

# wait_line: the success line while a close is still in its wait: next sleeps until the EARLIEST due (chain
# clock + 5 s), then reruns with --yes; channels[] lists every closing channel and when it is due
wait_line() {
  WHEN=$(date -u -d "@$WAIT_UNTIL" +%Y-%m-%dT%H:%M:%SZ)
  CH=$(echo "$CHANNELS" | jq -c --argjson now "$NOW" --argjson g "$GRACE" \
    '[.[] | select(.value.status <= 1) | {channel: .address, closeAfter: (((if .value.status == 1 then .value.close_started_at else $now end) + $g) | todate)}]')
  N=$((WAIT_UNTIL - $(chain_now) + 5)); [ "$N" -gt 5 ] || N=5
  summary true refund "sleep $N && $SELF --yes" "\"closeAfter\":\"$WHEN\",\"channels\":$CH,\"userBalance\":$BAL"
}

WHAT=""
for ch in $TO_START; do WHAT="${WHAT}start close $ch; "; done
for ch in $TO_CLOSE; do WHAT="${WHAT}close $ch; "; done
[ -n "$TO_START" ] && WHAT="${WHAT}(up to $ESCROW_START base units come back after the 2 h wait) "
[ -n "$TO_CLOSE" ] && WHAT="${WHAT}(up to $ESCROW_CLOSE base units move to your user balance, minus what the node redeems) "
{ [ "$BAL" -gt 0 ] || [ -n "$TO_CLOSE" ]; } && WHAT="${WHAT}withdraw user balance to your wallet; "
[ "$REVOKE" = 1 ] && [ "$WAIT_UNTIL" = 0 ] && WHAT="${WHAT}close grant ${GRANT:-none} (rent back to owner) + revoke delegate; "

if [ -z "$WHAT" ]; then
  if [ "$WAIT_UNTIL" -gt 0 ]; then
    wait_line
  else
    summary true refund "sh direct/connect.sh" "\"note\":\"done: nothing left locked\",\"userBalance\":$BAL"
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
if [ -n "$TO_START" ]; then
  # The chain stamps close_started_at at the start tx's block time, after NOW was read: NOW + GRACE printed a
  # closeAfter up to a few seconds EARLY (pathb-edge rf_yes, 00:42:21 vs the chain's 00:42:22). Read the real ones.
  NOW=$(chain_now)
  CHANNELS=$(try refund sentinel-dvpn channel search --owner "$OWNER")
  WAIT_UNTIL=$(echo "$CHANNELS" | jq -r --argjson now "$NOW" --argjson g "$GRACE" '[.[] | select(.value.status <= 1) | (if .value.status == 1 then .value.close_started_at else $now end) + $g | select(. > $now)] | min // 0')
fi
BAL=$(try none sentinel-dvpn user search --owner "$OWNER" | jq -r '.[0].value.balance // 0')
if [ "$BAL" -gt 0 ]; then
  try refund sentinel-dvpn user withdraw-user-balance >&2
  BAL=0
fi

if [ "$WAIT_UNTIL" -gt 0 ]; then
  wait_line
  exit 0
fi

if [ "$REVOKE" = 1 ]; then
  [ -n "$GRANT" ] && try none sentinel-dvpn grant close-grant --grant "$GRANT" >&2
  try none sentinel-dvpn wallet revoke-delegate >&2
fi

W=$(try none sentinel-dvpn wallet balance)
summary true refund "sh direct/connect.sh" "\"note\":\"done: nothing left locked\",\"dvpn_base_units\":$(echo "$W" | jq .dvpn_base_units),\"lamports\":$(echo "$W" | jq .lamports)"
