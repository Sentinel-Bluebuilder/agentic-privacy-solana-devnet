#!/bin/sh
# ─── direct/connect.sh: connect through a Sentinel node with the upstream CLI only ───
#
#   sh direct/connect.sh                  # PREVIEW: prints what it would sign and spend, exit 2
#   sh direct/connect.sh --yes            # does it (or YES=1)
#   NODE=<node address> sh direct/connect.sh --yes
#
# Steps (each raw command is printed before it runs):
#   1. grant: the daemon's device key may spend for your owner key only through an on-chain grant.
#      If none exists, opens one capped at ALLOWANCE (default 10 deposits at the picked node's price) and approves the
#      same amount as the token delegate. The cap is the most the device can ever lock in channels
#   2. node: NODE, or the cheapest live WireGuard node at or below the price cap: MAX_PRICE (tDVPN/GB),
#      else p75 of the live nodes (50 tDVPN/GB when fewer than 3). Above the cap: price-cap (exit 4)
#   3. route exceptions: the node's own IP (and your SSH client's IP, if any) go via the normal
#      gateway. Without the node route, the daemon's calls to the node's API go into the tunnel,
#      fail, and the session drops after ~50 s ("connection lost") and reconnects in a loop
#   4. client start: reuses your open channel to that node, else opens a new one with
#      ESCROW (default the node price x UNITS, UNITS=1 GB). Always passed: the config default is 1000 tDVPN
#   5. checks the exit IP and prints {"ok","exitIp","next",...}
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=connect
parse_args "$@"
# settings are checked before anything is read or signed (usage, exit 3)
case ${ESCROW:-1} in ''|0*|*[!0-9]*) fail "$E_USAGE" usage "ESCROW must be a whole number of base units above 0 (got ${ESCROW:-})" "env -u ESCROW sh direct/connect.sh" none ;; esac
case ${ALLOWANCE:-1} in ''|0*|*[!0-9]*) fail "$E_USAGE" usage "ALLOWANCE must be a whole number of base units above 0 (got ${ALLOWANCE:-})" "env -u ALLOWANCE sh direct/connect.sh" none ;; esac
case ${UNITS:-1} in ''|0*|*[!0-9]*) fail "$E_USAGE" usage "UNITS must be a whole number of GB above 0 (got ${UNITS:-})" "env -u UNITS sh direct/connect.sh" none ;; esac
[ -z "${NODE:-}" ] || printf '%s' "$NODE" | grep -Eq '^[1-9A-HJ-NP-Za-km-z]{32,44}$' \
  || fail "$E_USAGE" usage "NODE is not a base58 node address: $NODE" "env -u NODE sh direct/connect.sh" none
[ -z "${MAX_PRICE:-}" ] || printf '%s' "$MAX_PRICE" | grep -Eq '^([0-9]+([.][0-9]{1,6})?|[.][0-9]{1,6})$' && [ "$(base_units "${MAX_PRICE:-1}")" -gt 0 ] \
  || fail "$E_USAGE" usage "MAX_PRICE must be tDVPN per GB above 0, up to 6 decimals (got $MAX_PRICE)" "env -u MAX_PRICE sh direct/connect.sh" none
need sentinel-dvpn; need jq; need curl

PERMISSIONS=788529152            # 0x2f000000: the client permissions the daemon's doctor asks for
ANY_TARGET=11111111111111111111111111111111
ROUTES=${XDG_CACHE_HOME:-$HOME/.cache}/sentinel-direct/routes-$INSTANCE
SELF="${NODE:+NODE=$NODE }sh direct/connect.sh"
case ${MAX_PRICE:-1} in ''|*[!0-9.]*) fail "$E_USAGE" usage "MAX_PRICE must be tDVPN per GB, like 50 (got $MAX_PRICE)" "MAX_PRICE=50 sh direct/connect.sh" none ;; esac
case ${UNITS} in ''|0|*[!0-9]*) fail "$E_USAGE" usage "UNITS must be a whole number of GB, like 1 (got $UNITS)" "UNITS=1 sh direct/connect.sh" none ;; esac

OWNER=$(owner_address)
DEVICE=$(device_address)

# ─── plan (read-only) ───
ACTIVE=""; SJ=""
if daemon_running; then
  SJ=$(try none dclient sessions --instance "$INSTANCE" | jq -c '[.sessions[] | select(.status == "active")][0] // empty')
  ACTIVE=$(printf '%s' "$SJ" | jq -r '.id // empty')
fi
if [ -n "$ACTIVE" ]; then   # already connected: nothing to do, nothing signed (ok, not a failure)
  EXIT_IP=$(curl -s -4 -m 10 https://api.ipify.org || echo "")
  summary true connect "sh direct/disconnect.sh" "\"alreadyConnected\":true,\"note\":\"session $ACTIVE was already active; nothing was signed\",\"exitIp\":\"$EXIT_IP\",\"beforeIp\":\"\",\"nodeIp\":\"\",\"node\":\"$(printf '%s' "$SJ" | jq -r '.node // empty')\",\"session\":\"$ACTIVE\",\"channel\":\"$(printf '%s' "$SJ" | jq -r '.channel // empty')\""
  exit 0
fi

# market: price cap = MAX_PRICE, else p75 of the live WireGuard nodes (50 tDVPN/GB when < 3 match),
# never below ALLOWANCE / 10 per unit; escrow = node price x UNITS; grant cap = 10 escrows
NODES=$(try none sentinel-dvpn node search --service wireguard --live)
market "$NODES"
if [ -n "${MAX_PRICE:-}" ]; then PRICE_CAP=$(base_units "$MAX_PRICE"); else PRICE_CAP=$P75; fi
if [ -n "${ALLOWANCE:-}" ] && [ -z "${MAX_PRICE:-}" ] && [ "$PRICE_CAP" -lt $((ALLOWANCE / 10 / UNITS)) ]; then
  PRICE_CAP=$((ALLOWANCE / 10 / UNITS))
fi
# ALLOWANCE (the grant cap) is set after the node pick: 10 deposits at that node's price
echo "market: $NMATCH nodes, p50 $(tdvpn "$P50") / p75 $(tdvpn "$P75") tDVPN/GB; cap $(tdvpn "$PRICE_CAP") tDVPN/GB x $UNITS GB" >&2

GRANT=$(try none sentinel-dvpn grant search --granter "$OWNER" --grantee "$DEVICE" | jq -r '.[0].address // empty')
if [ -n "$GRANT" ]; then
  LEFT=$(try none sentinel-dvpn grant show "$GRANT" | jq -r '.value.allowance')
else
  LEFT=""   # no grant yet: the new cap, set after the node pick
fi

if [ -z "${NODE:-}" ]; then
  [ "$(printf '%s' "$NODES" | jq 'length')" -gt 0 ] || fail "$E_OTHER" no-nodes "no live WireGuard node found" "sleep 60 && $CMD" none
  PICK=$(cheapest_under "$NODES" "$PRICE_CAP")
  if [ -z "$PICK" ]; then
    LOW=$(printf '%s' "$NODES" | jq '[.[].value.channel_price_per_gb] | min')
    fail "$E_OPERATOR" price-cap "cheapest matching node above the cap: $(tdvpn "$LOW") tDVPN/GB (cap $(tdvpn "$PRICE_CAP")); set MAX_PRICE=$(tdvpn "$LOW")" \
      "MAX_PRICE=$(tdvpn "$LOW") sh direct/connect.sh" none
  fi
  NODE=${PICK%% *}
fi
NODEJ=$(try none sentinel-dvpn node show "$NODE")
URI=$(echo "$NODEJ" | jq -r .value.uri)
PRICE=$(echo "$NODEJ" | jq -r .value.channel_price_per_gb)
if [ "$PRICE" -gt "$PRICE_CAP" ]; then
  fail "$E_OPERATOR" price-cap "node $NODE costs $(tdvpn "$PRICE") tDVPN/GB, above the cap $(tdvpn "$PRICE_CAP"); set MAX_PRICE=$(tdvpn "$PRICE")" \
    "MAX_PRICE=$(tdvpn "$PRICE") NODE=$NODE sh direct/connect.sh" none
fi
# escrow-too-small: the node takes its first block (100 MB = a tenth of the GB price) at connect, and the daemon
# refuses an escrow under half of it ("channel escrow below node minimum"). Checked here, before anything is signed.
MIN_ESCROW=$(( (PRICE + 9) / 10 ))
if [ -n "${ESCROW:-}" ] && [ "$ESCROW" -lt "$MIN_ESCROW" ]; then
  fail "$E_USAGE" escrow-too-small "ESCROW=$ESCROW base units is below this node's first 100 MB block, $MIN_ESCROW base units ($(tdvpn "$MIN_ESCROW") tDVPN at $(tdvpn "$PRICE") tDVPN/GB); nothing was signed" \
    "ESCROW=$MIN_ESCROW NODE=$NODE sh direct/connect.sh" none
fi
ESCROW=${ESCROW:-$((PRICE * UNITS))}
ALLOWANCE=${ALLOWANCE:-$((10 * ESCROW))}   # default grant cap: 10 deposits at this price (a running total)
[ -n "$LEFT" ] || LEFT=$ALLOWANCE
echo "grant cap $(tdvpn "$ALLOWANCE") tDVPN ($([ -n "$GRANT" ] && echo "grant $GRANT has $(tdvpn "$LEFT") left" || echo "new grant: 10 deposits of $(tdvpn "$ESCROW") tDVPN; ALLOWANCE=<base units> sets another"))" >&2
HOST=$(echo "$URI" | sed -e 's#^https://##' -e 's#:[0-9]*$##' -e 's#/.*##')
NODE_IP=$(getent ahostsv4 "$HOST" | awk 'NR==1{print $1}')
[ -n "$NODE_IP" ] || fail "$E_OTHER" node-offline "cannot resolve node host $HOST" "env -u NODE sh direct/connect.sh" none

CHANNEL=$(try none sentinel-dvpn channel search --owner "$OWNER" --node "$NODE" \
  | jq -r '[.[] | select(.value.status == 0)][0].address // empty')
if [ -z "$CHANNEL" ] && [ "$LEFT" -lt "$ESCROW" ]; then
  fail "$E_OPERATOR" spending-limit "grant allowance $LEFT < escrow $ESCROW" "$(raise_cap_cmd)" none
fi

WHAT=""
if [ -z "$GRANT" ]; then
  WHAT="open grant cap $ALLOWANCE + delegate $ALLOWANCE base units ($(tdvpn "$ALLOWANCE") tDVPN = 10 deposits at this price, a running total that closes do not give back; ALLOWANCE=<base units> sets another) (owner pays ~0.0017 SOL rent, back on close-grant); "
  payee rent "new grant account (program $PROGRAM_ID)" 0 "$RENT_GRANT" yes owner
  fee_tx 2   # grant open-grant + wallet approve-delegate, both signed by the owner
fi
if [ -n "$CHANNEL" ]; then
  WHAT="${WHAT}spend from open channel $CHANNEL to node $NODE ($PRICE base units/GB; no new deposit)"
  FEE_NOTE="reusing channel $CHANNEL sends no new transaction; the node redeems your signed vouchers itself"
else
  WHAT="${WHAT}deposit $ESCROW base units ($(tdvpn "$ESCROW") tDVPN = $UNITS GB) into a new channel to node $NODE ($(tdvpn "$PRICE") tDVPN/GB; device pays ~0.0022 SOL rent, back on close)"
  payee deposit "$NODE" "$ESCROW" 0 unspent-part owner
  payee rent "new channel account (program $PROGRAM_ID)" 0 "$RENT_CHANNEL" yes device
  if [ "$(try none sentinel-dvpn user search --owner "$OWNER" | jq 'length')" = 0 ]; then
    payee rent "new user account (program $PROGRAM_ID)" 0 "$RENT_USER" no device
  fi
  fee_tx 1   # the daemon's channel open, signed and paid by the device
  FEE_NOTE="the node is paid only what it redeems from the escrow; the rest comes back through refund.sh"
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
GW=$(ip route show default 2>/dev/null | awk '{print $3; exit}') || GW=""
DEV=$(ip route show default 2>/dev/null | awk '{print $5; exit}') || DEV=""
[ -n "$GW" ] && [ -n "$DEV" ] || fail "$E_OTHER" route-failed "no default route (gateway '$GW', device '$DEV'): the node route cannot be added" "ip route show default" none
step "$E_OTHER" route-failed "mkdir -p $(dirname "$ROUTES")" none mkdir -p "$(dirname "$ROUTES")"
: > "$ROUTES"
for ip in "$NODE_IP" $(echo "${SSH_CONNECTION:-}" | awk '{print $1}'); do
  step "$E_OTHER" route-failed "sudo ip route replace $ip/32 via $GW dev $DEV && $CMD" none sudo ip route replace "$ip/32" via "$GW" dev "$DEV"
  echo "$ip" >> "$ROUTES"
done
BEFORE_IP=$(curl -s -4 -m 10 https://api.ipify.org || echo unknown)
# from here a deposit may open: a stop without a JSON line reports money as unclear
if [ -n "$CHANNEL" ]; then MONEY_STATE=refund; else MONEY_STATE=unclear; fi

# ─── 4. start ───
if [ -n "$CHANNEL" ]; then
  OUT=$(try refund dclient start --instance "$INSTANCE" --node "$NODE" --channel "$CHANNEL")
else
  # One retry on a public-RPC 429, and only after checking whether the first try opened a channel:
  # if it did, the retry reuses it (no second deposit).
  TRY_ERR_FILE=$(mktemp)
  if ! OUT=$(TRY_ERR_FILE=$TRY_ERR_FILE try_raw dclient start --instance "$INSTANCE" --node "$NODE" --new-channel --mode voucher --escrow-base-units "$ESCROW"); then
    ERR1=$(cat "$TRY_ERR_FILE"); rm -f "$TRY_ERR_FILE"
    is_rpc_busy "$ERR1" || classify "$(squash "$ERR1")" unclear
    echo "RPC busy (429) on client start: checking for a channel, then retrying once in 30 s" >&2
    sleep 30
    OPENED=$(try none sentinel-dvpn channel search --owner "$OWNER" --node "$NODE" \
      | jq -r '[.[] | select(.value.status == 0)][0].address // empty')
    if [ -n "$OPENED" ]; then
      echo "the first try opened channel $OPENED; reusing it" >&2
      OUT=$(try refund dclient start --instance "$INSTANCE" --node "$NODE" --channel "$OPENED")
    else
      OUT=$(try unclear dclient start --instance "$INSTANCE" --node "$NODE" --new-channel --mode voucher --escrow-base-units "$ESCROW")
    fi
  fi
  rm -f "$TRY_ERR_FILE"
fi
echo "$OUT" >&2
SESSION=$(echo "$OUT" | jq -r .session.id)
CHANNEL=$(echo "$OUT" | jq -r .session.channel)
MONEY_STATE=open          # the session runs on a funded channel

# ─── 5. exit IP ───
sleep 3
EXIT_IP=$(curl -s -4 -m 15 https://api.ipify.org || echo unknown)
if [ "$EXIT_IP" = "$BEFORE_IP" ] || [ "$EXIT_IP" = unknown ]; then
  fail "$E_OTHER" tunnel-failed "exit IP is $EXIT_IP (before: $BEFORE_IP); traffic is not going through the node" \
    "sh direct/disconnect.sh && sh direct/refund.sh" open "A deposit is open in channel $CHANNEL: sh direct/disconnect.sh, then sh direct/refund.sh --yes closes it."
fi
summary true connect "sh direct/disconnect.sh" "\"exitIp\":\"$EXIT_IP\",\"beforeIp\":\"$BEFORE_IP\",\"nodeIp\":\"$NODE_IP\",\"node\":\"$NODE\",\"session\":\"$SESSION\",\"channel\":\"$CHANNEL\""
