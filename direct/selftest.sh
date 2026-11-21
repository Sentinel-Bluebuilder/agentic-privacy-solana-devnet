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

STEP=selftest
parse_args "$@"   # an unknown flag is usage (exit 3) before anything runs: this run pays a deposit
case $HOLD in ''|*[!0-9]*) fail "$E_USAGE" usage "HOLD must be whole seconds (got $HOLD)" "env -u HOLD sh direct/selftest.sh" none ;; esac

# stage <name> <command...>: run one script, print its JSON line; on failure pass its code, money
# and next through (step-failed when the script printed no JSON line)
stage() {
  name=$1; shift
  echo "──── $name ────" >&2
  line=$("$@" | tail -1) || true
  echo "$line"
  case $line in *'"ok":true'*) return 0 ;; esac
  ic=$(printf '%s' "$line" | jq -r '.code // empty' 2>/dev/null) || ic=""
  im=$(printf '%s' "$line" | jq -r '.money // empty' 2>/dev/null) || im=""
  inx=$(printf '%s' "$line" | jq -r '.next // empty' 2>/dev/null) || inx=""
  [ "$name" = connect ] && [ -z "$im" ] && im=unclear
  fail "$E_OTHER" "${ic:-step-failed}" "selftest stopped at $name: ${ic:-no JSON line}" "${inx:-sh direct/$name.sh}" "${im:-none}"
}

if [ "${SELFTEST_STAGE:-1}" = 1 ]; then
  stage install sudo sh "$HERE/install.sh"
fi

stage fund-request sh "$HERE/fund-request.sh" --wait
stage connect sh "$HERE/connect.sh" --yes
NODE_IP=$(dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[] | select(.status == "active")][0].node // empty')
t=0
while [ "$t" -lt "$HOLD" ]; do
  sleep 15; t=$((t + 15))
  st=$(dclient sessions --instance "$INSTANCE" | jq -r '[.sessions[] | select(.status == "active")] | length')
  ip=$(public_ip 10)
  echo "hold t=${t}s active=$st exitIp=$ip" >&2
  [ "$st" = 1 ] || fail "$E_OTHER" session-dropped "the session dropped at ${t}s of ${HOLD}s (node $NODE_IP); see 'connection lost' in docs/DIRECT-REFERENCE.md" \
    "sh direct/disconnect.sh && sh direct/refund.sh" refund
done
stage disconnect sh "$HERE/disconnect.sh"
RL=$(stage refund sh "$HERE/refund.sh" --yes) && echo "$RL"   # its next is the exact wait + rerun
summary true selftest "$(printf '%s' "$RL" | jq -r .next)" "\"note\":\"the session held; refund started the close: next waits for it, then refunds\",\"held\":$HOLD"
