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
need sentinel-dvpn; need jq; need curl
ROUTES=${XDG_CACHE_HOME:-$HOME/.cache}/sentinel-direct/routes-$INSTANCE

SESSION=""; daemon_running && SESSION=$(try none dclient sessions --instance "$INSTANCE" \
  | jq -r '[.sessions[] | select(.status == "active")][0].id // empty')
SPENT=0
if [ -n "$SESSION" ]; then
  OUT=$(try none dclient stop --instance "$INSTANCE" "$SESSION")
  echo "$OUT" >&2
  SPENT=$(echo "$OUT" | jq -r .session.spent)
else
  echo "no active session" >&2
fi

if [ -f "$ROUTES" ]; then
  while read -r ip; do run sudo ip route del "$ip/32" || true; done < "$ROUTES"
  rm -f "$ROUTES"
fi

sleep 2
IP=$(curl -s -4 -m 10 https://api.ipify.org || echo unknown)
if ip -br link | awk -v t="dvpn-$INSTANCE" '$1==t{f=1} END{exit !f}'; then
  fail "$E_OTHER" tunnel-closing "interface dvpn-$INSTANCE is still up after stop" \
    "sudo sentinel-dvpnd service restart --instance $INSTANCE" refund "No new money was spent ($SPENT base units used so far); the unused escrow is still held: sh direct/refund.sh --yes returns it."
fi
summary true disconnect "sh direct/refund.sh (to get unspent escrow back), or sh direct/connect.sh" "\"session\":\"$SESSION\",\"spent\":$SPENT,\"ip\":\"$IP\",\"tunnel\":\"down\""
