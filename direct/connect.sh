#!/bin/sh
# ─── direct/connect.sh: connect through a Sentinel node with the upstream CLI only ───
#
#   sh direct/connect.sh                  # PREVIEW: prints what it would sign and spend, exit 2
#   sh direct/connect.sh --yes            # does it (or YES=1)
#   NODE=<node address> sh direct/connect.sh --yes
#
# Steps (each raw command is printed before it runs):
#   1. grant: the daemon's device key may spend for your owner key only through an on-chain grant.
#      If none exists, opens one capped at ALLOWANCE (default 5000000 = 5 tDVPN) and approves the
#      same amount as the token delegate. The cap is the most the device can ever lock in channels
#   2. node: NODE, or the cheapest live WireGuard node (node search --service wireguard --live)
#   3. route exceptions: the node's own IP (and your SSH client's IP, if any) go via the normal
#      gateway. Without the node route, the daemon's calls to the node's API go into the tunnel,
#      fail, and the session drops after ~50 s ("connection lost") and reconnects in a loop
#   4. client start: reuses your open channel to that node, else opens a new one with
#      ESCROW (default 1000000 = 1 tDVPN). Always pass an escrow: the config default is 1000 tDVPN
#   5. checks the exit IP and prints {"ok","exitIp","next",...}
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=connect
parse_args "$@"
need sentinel-dvpn; need jq; need curl

ALLOWANCE=${ALLOWANCE:-5000000}
ESCROW=${ESCROW:-1000000}
PERMISSIONS=788529152            # 0x2f000000: the client permissions the daemon's doctor asks for
ANY_TARGET=11111111111111111111111111111111
ROUTES=${XDG_CACHE_HOME:-$HOME/.cache}/sentinel-direct/routes-$INSTANCE
SELF="${NODE:+NODE=$NODE }sh direct/connect.sh"

OWNER=$(owner_address)
DEVICE=$(device_address)

# ─── plan (read-only) ───
ACTIVE=""
if daemon_running; then
  ACTIVE=$(try none dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[] | select(.status == "active")][0].id // empty')
fi
[ -z "$ACTIVE" ] || fail "$E_OTHER" session-active "session $ACTIVE is already active" "sh direct/disconnect.sh" none

GRANT=$(try none sentinel-dvpn grant search --granter "$OWNER" --grantee "$DEVICE" | jq -r '.[0].address // empty')
if [ -n "$GRANT" ]; then
  LEFT=$(try none sentinel-dvpn grant show "$GRANT" | jq -r '.value.allowance')
else
  LEFT=$ALLOWANCE
fi

if [ -z "${NODE:-}" ]; then
  NODE=$(try none sentinel-dvpn node search --service wireguard --live \
    | jq -r 'sort_by(.value.channel_price_per_gb) | .[0].address // empty')
  [ -n "$NODE" ] || fail "$E_OTHER" no-nodes "no live WireGuard node found" "retry in a minute: $SELF" none
fi
NODEJ=$(try none sentinel-dvpn node show "$NODE")
URI=$(echo "$NODEJ" | jq -r .value.uri)
PRICE=$(echo "$NODEJ" | jq -r .value.channel_price_per_gb)
HOST=$(echo "$URI" | sed -e 's#^https://##' -e 's#:[0-9]*$##' -e 's#/.*##')
NODE_IP=$(getent ahostsv4 "$HOST" | awk 'NR==1{print $1}')
[ -n "$NODE_IP" ] || fail "$E_OTHER" node-offline "cannot resolve node host $HOST" "pick another: NODE=<address> $SELF" none

CHANNEL=$(try none sentinel-dvpn channel search --owner "$OWNER" --node "$NODE" \
  | jq -r '[.[] | select(.value.status == 0)][0].address // empty')
if [ -z "$CHANNEL" ] && [ "$LEFT" -lt "$ESCROW" ]; then
  fail "$E_OPERATOR" spending-limit "grant allowance $LEFT < escrow $ESCROW" "the owner raises the cap: sentinel-dvpn grant update-grant --help, then approve-delegate the same" none
fi

WHAT=""
[ -z "$GRANT" ] && WHAT="open grant cap $ALLOWANCE + delegate $ALLOWANCE base units (owner pays ~0.0017 SOL rent, back on close-grant); "
if [ -n "$CHANNEL" ]; then
  WHAT="${WHAT}spend from open channel $CHANNEL to node $NODE ($PRICE base units/GB; no new deposit)"
else
  WHAT="${WHAT}deposit $ESCROW base units ($((ESCROW / 1000000)) tDVPN) into a new channel to node $NODE ($PRICE base units/GB; device pays ~0.0022 SOL rent, back on close)"
fi
confirm "$WHAT" "$SELF"

# ─── 1. grant + delegate ───
if [ -z "$GRANT" ]; then
  try none sentinel-dvpn grant open-grant --grantee "$DEVICE" --target "$ANY_TARGET" \
    --permissions "$PERMISSIONS" --never-expires --allowance "$ALLOWANCE" >/dev/null
  try none \
    sentinel-dvpn wallet approve-delegate --amount-base-units "$ALLOWANCE" >/dev/null
fi

# ─── 2. daemon: starts only once the grant exists ───
daemon_up

# ─── 3. route exceptions ───
GW=$(ip route show default | awk '{print $3; exit}')
DEV=$(ip route show default | awk '{print $5; exit}')
mkdir -p "$(dirname "$ROUTES")"
: > "$ROUTES"
for ip in "$NODE_IP" $(echo "${SSH_CONNECTION:-}" | awk '{print $1}'); do
  run sudo ip route replace "$ip/32" via "$GW" dev "$DEV"
  echo "$ip" >> "$ROUTES"
done
BEFORE_IP=$(curl -s -4 -m 10 https://api.ipify.org || echo unknown)

# ─── 4. start ───
if [ -n "$CHANNEL" ]; then
  OUT=$(try refund dclient start --instance "$INSTANCE" --node "$NODE" --channel "$CHANNEL")
else
  OUT=$(try unclear \
    dclient start --instance "$INSTANCE" --node "$NODE" --new-channel --mode voucher --escrow-base-units "$ESCROW")
fi
echo "$OUT" >&2
SESSION=$(echo "$OUT" | jq -r .session.id)
CHANNEL=$(echo "$OUT" | jq -r .session.channel)

# ─── 5. exit IP ───
sleep 3
EXIT_IP=$(curl -s -4 -m 15 https://api.ipify.org || echo unknown)
if [ "$EXIT_IP" = "$BEFORE_IP" ] || [ "$EXIT_IP" = unknown ]; then
  fail "$E_OTHER" tunnel-failed "exit IP is $EXIT_IP (before: $BEFORE_IP); traffic is not going through the node" \
    "sh direct/disconnect.sh, then try another node" open "A deposit is open in channel $CHANNEL: sh direct/disconnect.sh, then sh direct/refund.sh --yes closes it."
fi
summary true connect "sh direct/disconnect.sh" "\"exitIp\":\"$EXIT_IP\",\"beforeIp\":\"$BEFORE_IP\",\"nodeIp\":\"$NODE_IP\",\"node\":\"$NODE\",\"session\":\"$SESSION\",\"channel\":\"$CHANNEL\""
