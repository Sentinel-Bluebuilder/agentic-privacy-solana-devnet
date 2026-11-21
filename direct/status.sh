#!/bin/sh
# ─── direct/status.sh: is a session connected on this box? Look only ───
#
#   sh direct/status.sh           # signs nothing, sends nothing, pays nothing: no --yes, no preview
#
# Reads the daemon's own session list (`sentinel-dvpn client sessions`, a read-only query of the daemon) and,
# when a session is active, this box's public IP. It never stops, starts or changes anything.
# The last stdout line is JSON:
#   {"ok":true,"step":"status","connected":true|false,"session":…|null,"node":…|null,"protocol":…|null,
#    "channel":…|null,"exitIp":…|null,"next":…|null,"onlyIf":…}
# next is null when nothing is connected. When a session is active, next is
# "sh direct/disconnect.sh  # only if this run started the session": a session this run did not start belongs to
# someone else (another agent, a person, a script): leave it, and wait or use another INSTANCE.
# Exit: 0 an answer (connected or not) · 1 the daemon cannot be read (daemon-unavailable) · 3 usage.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=status
parse_args "$@"   # no options: anything else is usage (exit 3)
MONEY_STATE=none  # this script moves no money
[ "${YES:-0}" = 1 ] && fail "$E_USAGE" usage "status.sh only looks: it signs nothing, so it takes no --yes" "sh direct/status.sh" none
need sentinel-dvpn; need jq; need curl

daemon_running || fail "$E_OTHER" daemon-unavailable \
  "the daemon sentinel-dvpnd@$INSTANCE is not running, so its sessions cannot be read" \
  "sudo sentinel-dvpnd service start --instance $INSTANCE" none
SESSIONS=$(try none dclient sessions --instance "$INSTANCE")
S=$(printf '%s' "$SESSIONS" | jq -c '[.sessions[]? | select(.status == "active")][0] // empty' 2>/dev/null) \
  || fail "$E_OTHER" daemon-unavailable "the daemon answered the session list with something that is not JSON" \
       "sudo sentinel-dvpnd service restart --instance $INSTANCE" none

if [ -z "$S" ]; then
  printf '{"ok":true,"step":"status","connected":false,"session":null,"node":null,"protocol":null,"channel":null,"exitIp":null,"next":null,"onlyIf":"nothing is connected on instance %s"}\n' "$INSTANCE"
  exit 0
fi

# A session is active: name it, and the IP traffic leaves from (null when ipify does not give an address).
f() { printf '%s' "$S" | jq -r --arg k "$1" '.[$k] // empty'; }
IP=$(public_ip 10)
jv() { if [ -n "$1" ] && [ "$1" != unknown ]; then printf '"%s"' "$(jstr "$1")"; else printf null; fi; }
NX=$(jstr "$(carry "sh direct/disconnect.sh")")
printf '{"ok":true,"step":"status","connected":true,"session":%s,"node":%s,"protocol":%s,"channel":%s,"exitIp":%s,"next":"%s  # only if this run started the session","onlyIf":"this run started the session; one it did not start belongs to someone else: leave it"}\n' \
  "$(jv "$(f id)")" "$(jv "$(f node)")" "$(jv "$(f service)")" "$(jv "$(f channel)")" "$(jv "$IP")" "$NX"
