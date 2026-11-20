#!/bin/sh
# ─── direct/selftest.sh: run docs/DIRECT.md's steps end to end on a FRESH Linux box ───
#
#   sh direct/selftest.sh 2>&1 | tee selftest.log
#
# install -> fund-request --wait (send the printed message to your funder) -> connect -> hold
# HOLD seconds (default 120, exit IP checked every 15 s) -> disconnect -> refund (starts the close;
# run "sh direct/refund.sh" again after the time it prints). Stops at the first failing step.
# Every step's JSON line is printed; the last line is {"ok","step":"selftest","next",...}.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
HOLD=${HOLD:-120}

step() { # step <name> <command...>
  name=$1; shift
  echo "──── $name ────" >&2
  if ! line=$("$@" | tail -1); then
    echo "$line"
    summary false selftest "fix step $name, then rerun sh direct/selftest.sh" "\"failed\":\"$name\""
    exit 1
  fi
  echo "$line"
  case $line in *'"ok":true'*) ;; *) summary false selftest "fix step $name" "\"failed\":\"$name\""; exit 1 ;; esac
}

if [ "${SELFTEST_STAGE:-1}" = 1 ]; then
  step install sudo sh "$HERE/install.sh"
fi

step fund-request sh "$HERE/fund-request.sh" --wait
step connect sh "$HERE/connect.sh" --yes
NODE_IP=$(dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[] | select(.status == "active")][0].node // empty')
t=0
while [ "$t" -lt "$HOLD" ]; do
  sleep 15; t=$((t + 15))
  st=$(dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[] | select(.status == "active")] | length')
  ip=$(curl -s -4 -m 10 https://api.ipify.org || echo unknown)
  echo "hold t=${t}s active=$st exitIp=$ip" >&2
  [ "$st" = 1 ] || { summary false selftest "session dropped at ${t}s: read docs/DIRECT.md 'connection lost'" "\"failed\":\"hold\",\"node\":\"$NODE_IP\""; exit 1; }
done
step disconnect sh "$HERE/disconnect.sh"
step refund sh "$HERE/refund.sh" --yes
summary true selftest "after the time refund printed: sh direct/refund.sh" "\"held\":$HOLD"
