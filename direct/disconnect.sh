#!/bin/sh
# ─── direct/disconnect.sh: stop the active session and remove the route exceptions ───
#
#   sh direct/disconnect.sh       # signs nothing on chain, so no --yes needed
#
# Stopping a session does NOT close its channel: the unspent escrow stays locked in the channel
# until refund.sh (start close, wait 2 h, close, withdraw). You can reconnect to the same node
# and keep spending from it with connect.sh.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=disconnect
parse_args "$@"   # an unknown flag is usage (exit 3), as on every other script
MONEY_STATE=refund        # stopping keeps the channel deposit: refund.sh returns it
need sentinel-dvpn; need jq; need curl
ROUTES=${XDG_CACHE_HOME:-$HOME/.cache}/sentinel-direct/routes-$INSTANCE

SESSION=""; daemon_running && SESSION=$(try none dclient sessions --instance "$INSTANCE" \
  | jq -r '[.sessions[] | select(.status == "active")][0].id // empty')
SPENT=0
if [ -n "$SESSION" ]; then
  OUT=$(try none dclient stop --instance "$INSTANCE" "$SESSION")
  echo "$OUT" >&2
  SPENT=$(echo "$OUT" | jq -r '.session.spent // 0')   # an integer even when the reply has none (schema: spent integer)
else
  echo "no active session" >&2
fi

if [ -f "$ROUTES" ]; then
  while read -r ip; do run sudo ip route del "$ip/32" || true; done < "$ROUTES"
  rm -f "$ROUTES"
fi

sleep 2
IP=$(public_ip 10)
if ip -br link | awk -v t="dvpn-$INSTANCE" '$1==t{f=1} END{exit !f}'; then
  fail "$E_OTHER" tunnel-closing "interface dvpn-$INSTANCE is still up after stop" \
    "sudo sentinel-dvpnd service restart --instance $INSTANCE" refund "No new money was spent ($SPENT base units used so far); the unused escrow is still held: sh direct/refund.sh --yes returns it."
fi
summary true disconnect "sh direct/refund.sh" "\"alternatives\":[\"sh direct/connect.sh\"],\"note\":\"refund.sh gets the unspent escrow back; connect.sh starts a new session\",\"session\":\"$SESSION\",\"spent\":$SPENT,\"ip\":\"$IP\",\"tunnel\":\"down\""
