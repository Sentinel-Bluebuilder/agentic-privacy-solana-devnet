#!/bin/sh
# ─── direct/lib.sh: shared helpers for the direct/ scripts (sourced, not run) ───
#
# Every script prints each raw command on stderr as "+ <command>" before it runs it, so you can
# copy any step and run it by hand. The LAST stdout line is always one JSON object:
#   success: {"ok":true,"step":"...","next":"...", ...}
#   failure: {"ok":false,"step":"...","code":"...","money":"...","moneyNote":"...","error":"...","next":"..."}
#   preview: {"ok":false,"needsConfirm":true,"step":"...","what":"...","next":"<same command> --yes"}
#
# Exit codes (the same as Path A's devnet-dvpn):
#   0 ok · 1 failed (default) · 2 needs --yes · 3 usage · 4 needs you or your funder: not-funded,
#   spending-limit, no-wallet · 5 refused for safety · 6 rpc-unavailable AND no deposit can be open
# "code" uses Path A's kebab-case names where one exists (docs/DIRECT.md has the table).
# "money" is exactly one of (Path A's classes):
#   none    nothing was paid (a sent, failed transaction costs only its 5000-lamport fee)
#   open    a deposit (channel escrow) may be open: sentinel-dvpn channel search --owner <owner>
#   unclear not known whether a deposit opened: sentinel-dvpn channel search --owner <owner>
#   refund  no new money spent; unspent escrow is still held: sh direct/refund.sh --yes returns it
# "moneyNote" is one free-text sentence about the same.

INSTANCE=${INSTANCE:-c1}
NODE_RPC=${RPC_URL:-https://api.devnet.solana.com}
DEVICE_KEY_NAME=operator
SOCK=/var/lib/sentinel-dvpn/$INSTANCE/daemon.sock

E_OTHER=1; E_CONFIRM=2; E_USAGE=3; E_OPERATOR=4; E_SAFETY=5; E_NETWORK=6

run() { printf '+ %s\n' "$*" >&2; printf '%s' "$*" > "${LAST_RUN_FILE:-/dev/null}"; "$@"; }

# step <exit> <code> <next> <money> <command...>: a guarded run. On failure the JSON line names
# the code, the failed command, its last stderr lines, and the next command to run.
step() {
  sx=$1; sc=$2; sn=$3; sm=$4; shift 4
  printf '+ %s\n' "$*" >&2
  printf '%s' "$*" > "${LAST_RUN_FILE:-/dev/null}"
  se=$(mktemp)
  "$@" 2>"$se" && { cat "$se" >&2; rm -f "$se"; return 0; }
  st=$?
  cat "$se" >&2
  msg="$* failed (exit $st): $(squash "$(tail -3 "$se")")"
  rm -f "$se"
  fail "$sx" "$sc" "$msg" "$sn" "$sm"
}

jstr() { printf '%s' "$1" | tr '"\n\t' "'  "; }

# summary <ok> <step> <next> [extra json fields without braces]
summary() {
  extra=${4:-}
  [ -n "$extra" ] && extra=",$extra"
  printf '{"ok":%s,"step":"%s","next":"%s"%s}\n' "$1" "$2" "$(jstr "$3")" "$extra"
}

# fd 3 = the real stdout, so a failure inside $(...) still reaches you; a failure in a subshell
# signals the main script, which then exits with the same code. FAIL_CODE_FILE non-empty = the
# last JSON line was already printed (fail, confirm or an explicit failure line).
exec 3>&1
MAIN_PID=$$
FAIL_CODE_FILE=$(mktemp)
LAST_RUN_FILE=$(mktemp)
MONEY_STATE=none          # what is at risk if the script dies here; connect.sh raises it before client start
EXIT_EXTRA=""             # cleanup a script adds (it must not replace the EXIT trap)
trap 'c=$(cat "$FAIL_CODE_FILE" 2>/dev/null); exit "${c:-1}"' USR1
trap 'exit 143' TERM HUP
trap 'exit 130' INT
trap 'on_exit $?' EXIT

# on_exit: the backstop. Any non-zero exit that printed no JSON line (a set -e stop, a kill) still
# ends with one, coded: interrupted (killed: run the same command again) or unknown (a raw stop)
on_exit() {
  rc=$1
  eval "$EXIT_EXTRA"
  if [ "$rc" != 0 ] && [ ! -s "$FAIL_CODE_FILE" ]; then
    last=$(cat "$LAST_RUN_FILE" 2>/dev/null)
    case $MONEY_STATE in none) nx="grep -n -A14 'If something fails' docs/DIRECT.md" ;; *) nx="sh direct/refund.sh" ;; esac
    case $rc in
      130|143) code=interrupted; msg="stopped by a signal (exit $rc) during: ${last:-start}"; nx="$CMD" ;;
      *) code=unknown; msg="stopped (exit $rc) at: ${last:-start}" ;;
    esac
    printf '{"ok":false,"step":"%s","code":"%s","money":"%s","moneyNote":"%s","error":"%s","next":"%s"}\n' \
      "${STEP:-direct}" "$code" "$MONEY_STATE" "$(jstr "$(money_note "$MONEY_STATE")")" "$(jstr "$msg")" "$(jstr "$nx")" >&3
    rc=1
  fi
  rm -f "$FAIL_CODE_FILE" "$LAST_RUN_FILE"
  exit "$rc"
}

money_note() { # money_note <class>
  case $1 in
    none) echo "Nothing was paid." ;;
    open) echo "A deposit may be open: sentinel-dvpn channel search --owner <owner> lists it; sh direct/refund.sh --yes closes it." ;;
    unclear) echo "It is not known whether a deposit was opened: sentinel-dvpn channel search --owner <owner> lists it." ;;
    refund) echo "No new money was spent; the unused part of a deposit is still held: sh direct/refund.sh --yes returns it." ;;
  esac
}

# fail <exit> <code> <message> <next> [money class: none|open|unclear|refund] [moneyNote]
fail() {
  cls=${5:-none}
  note=${6:-$(money_note "$cls")}
  echo "error: $3" >&2
  printf '{"ok":false,"step":"%s","code":"%s","money":"%s","moneyNote":"%s","error":"%s","next":"%s"}\n' \
    "${STEP:-direct}" "$2" "$cls" "$(jstr "$note")" "$(jstr "$3")" "$(jstr "$4")" >&3
  echo "$1" > "$FAIL_CODE_FILE"
  kill -USR1 "$MAIN_PID" 2>/dev/null || true
  exit "$1"
}

need() { command -v "$1" >/dev/null 2>&1 || fail "$E_USAGE" tool-missing "$1 not found on PATH" "sudo sh direct/install.sh"; }

# ─── how this script was run, so a "next" can repeat it exactly ───
CMD_BASE="sh direct/$(basename "$0")"
CMD="${NODE:+NODE=$NODE }$CMD_BASE"
for a in "$@"; do case $a in *[!A-Za-z0-9._=/-]*) CMD="$CMD '$a'" ;; *) CMD="$CMD $a" ;; esac; done

# --help / -h on any script: print its header comment and exit 0
for a in "$@"; do
  case $a in --help|-h) sed -n '2,/^set -eu/p' "$0" | sed -e '/^set -eu/d' -e 's/^# \{0,1\}//'; exit 0 ;; esac
done

# ─── confirm gate: anything that signs previews first ───
YES=${YES:-0}
parse_args() { for a in "$@"; do case $a in --yes|-y) YES=1 ;; esac; done; }

# ─── who gets paid: every preview lists it (S6) ───
# payee <role> <to> <tDVPN base units> <lamports> <comes back: yes|no|unspent-part> <payer: owner|device|program>
#   role: deposit, transfer, rent, refund (money coming back to you)
# fee_tx <n>: n more transactions this step sends; each has one signature = 5000 lamports
RENT_GRANT=1671320; RENT_CHANNEL=2169160; RENT_USER=1244600   # measured on devnet 2026-11-20
PROGRAM_ID=${PROGRAM_ID:-J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs}   # the devnet build id (sentinel-dvpn version)
PAYEES=""; FEE_TX=0; RENT=0
payee() {
  [ -n "$PAYEES" ] && PAYEES="$PAYEES,"
  PAYEES="$PAYEES{\"role\":\"$1\",\"to\":\"$2\",\"payer\":\"$6\",\"baseUnits\":$3,\"tdvpn\":\"$(tdvpn "$3")\",\"lamports\":$4,\"comesBack\":\"$5\"}"
  case $1 in rent) RENT=$((RENT + $4)) ;; esac
}
fee_tx() { FEE_TX=$((FEE_TX + $1)); }

# confirm <what> <command line to repeat>: the preview line (exit 2) with what, payees, fee and rent
confirm() {
  [ "$YES" = 1 ] && return 0
  printf '{"ok":false,"needsConfirm":true,"step":"%s","what":"%s","payees":[%s],"feeLamports":%s,"feeSource":"%s","rentLamports":%s,"rentSource":"%s","next":"%s --yes"}\n' \
    "${STEP:-direct}" "$(jstr "$1")" "$PAYEES" "$((FEE_TX * 5000))" \
    "fixed: 5000 lamports per signature, $FEE_TX transaction(s) with one signature each${FEE_NOTE:+; $FEE_NOTE}" \
    "$RENT" "measured on devnet 2026-11-20: grant $RENT_GRANT, channel $RENT_CHANNEL, user account $RENT_USER lamports" \
    "$(jstr "$2")" >&3
  echo "$E_CONFIRM" > "$FAIL_CODE_FILE"
  exit "$E_CONFIRM"
}

# ─── upstream error -> code / exit / money / next ───
# classify <error text> <money class if the outcome is not known: none|open|unclear|refund>
# A program error or a failed simulation is all-or-nothing: no tDVPN moved, so money = none.
# A daemon / network / unknown error after the command may have reached the chain keeps $m.
classify() {
  t=$1; m=${2:-none}
  # money not known: refund.sh's preview lists every channel that holds a deposit and what it would do
  CHECK="sh direct/refund.sh"
  case $t in
    *InvalidAccountForFee*)
      fail "$E_OTHER" device-sol "$t" "sh direct/fund-device.sh --sol 0.02 --yes && $CMD" none ;;
    *"insufficient lamports"*|*"insufficient funds"*)
      fail "$E_OPERATOR" not-funded "$t" "sh direct/fund-request.sh" none ;;
    *6024*|*AmountExceedsAllowance*)
      fail "$E_OPERATOR" spending-limit "$t" "$(raise_cap_cmd)" none ;;
    *6045*|*GrantExpired*|*6046*|*PermissionNotGranted*|*6047*|*GrantTargetMismatch*|*6000*|*Unauthorized*)
      fail "$E_OTHER" device-permission "$t" "sh direct/refund.sh --revoke --yes && sh direct/connect.sh --yes" none ;;
    *6001*|*OperationPaused*)
      fail "$E_OTHER" service-down "$t" "sentinel-dvpn program status" none ;;
    *6015*|*NodeNotListed*|*6042*|*NodeReopened*)
      fail "$E_OTHER" node-gone "$t" "env -u NODE sh direct/connect.sh" none ;;
    *6016*|*NodeNotLive*)
      fail "$E_OTHER" node-stale "$t" "env -u NODE sh direct/connect.sh" none ;;
    *6017*|*NodePriceChanged*)
      fail "$E_OTHER" price-changed "$t" "$CMD" none ;;
    *6035*|*GraceNotElapsed*)
      fail "$E_OTHER" close-wait "$t" "sh direct/refund.sh" refund ;;
    *6033*|*ChannelNotClosing*)
      fail "$E_OTHER" not-closing "$t" "sh direct/refund.sh --yes" refund ;;
    *6032*|*ChannelNotOpen*)
      fail "$E_OTHER" deposit-unusable "$t" "sh direct/connect.sh --yes" refund ;;
    *6023*|*BalanceZero*)
      fail "$E_OTHER" nothing-to-withdraw "$t" "sh direct/refund.sh" refund ;;
    *"a session is already active"*)
      fail "$E_OTHER" session-active "$t" "sh direct/disconnect.sh && $CMD" none ;;
    *"no active session"*)
      fail "$E_OTHER" no-session "$t" "sentinel-dvpn client sessions --instance $INSTANCE" none ;;
    *"accepts "*" arg"*|*"unknown flag"*|*"unknown command"*|*"is required"*|*"required flag"*)
      fail "$E_USAGE" usage "$t" "$CMD_BASE --help" none ;;
    *ConstraintSeeds*|*2006*|*ConstraintAddress*|*2012*)
      fail "$E_OTHER" wrong-account "$t" "grep -n -A1 wrong-account docs/DIRECT.md" none ;;
    *daemon.sock*|*"code = Unavailable"*)
      if [ "$m" = none ]; then
        fail "$E_OTHER" daemon-unavailable "$t" "sudo sentinel-dvpnd service start --instance $INSTANCE && $CMD" none
      fi
      fail "$E_OTHER" daemon-unavailable "$t" "$CHECK" "$m" ;;
    *429*|*"Too Many Requests"*|*"too many requests"*|*"rate limit"*)
      if [ "$m" = none ]; then
        fail "$E_NETWORK" rpc-busy "$t" "sleep 30 && $CMD" none
      fi
      fail "$E_OTHER" rpc-busy "$t" "$CHECK" "$m" ;;
    *timeout*|*"deadline exceeded"*|*DeadlineExceeded*|*"no such host"*|*"dial tcp"*|*"connection refused"*|*EOF*)
      if [ "$m" = none ]; then
        fail "$E_NETWORK" rpc-unavailable "$t" "sleep 60 && $CMD" none
      fi
      fail "$E_OTHER" rpc-unavailable "$t" "$CHECK" "$m" ;;
    *"fetching node"*|*"node not found"*)
      fail "$E_OTHER" node-gone "$t" "env -u NODE sh direct/connect.sh" none ;;
    *)
      if [ "$m" = none ]; then
        fail "$E_OTHER" unknown "$t" "grep -n -A14 'If something fails' docs/DIRECT.md" none
      fi
      fail "$E_OTHER" unknown "$t" "$CHECK" "$m" ;;
  esac
}

# raise_cap_cmd: the exact owner commands that raise the grant cap to ALLOWANCE (default 5 tDVPN more)
raise_cap_cmd() {
  g=${GRANT:-}
  new=$(( ${LEFT:-0} + ${ALLOWANCE:-5000000} ))
  if [ -n "$g" ]; then
    echo "sentinel-dvpn grant update-grant --grant $g --allowance $new && sentinel-dvpn wallet approve-delegate --amount-base-units $new && $CMD"
  else
    echo "sh direct/refund.sh --revoke --yes && sh direct/connect.sh --yes"
  fi
}

is_rpc_busy() { case $1 in *429*|*"Too Many Requests"*|*"too many requests"*|*"rate limit"*) return 0 ;; esac; return 1; }

# squash <error text>: the whole error on one line, so a multi-line RPC error keeps its "Code: 429"
squash() { printf '%s' "$1" | sed 's/^error: //' | tr '\n\t' '  ' | tr -s ' ' | cut -c1-600; }

# try <money class if it fails in an unknown way> <command...>: run, keep stdout, classify stderr.
# A 429 (public RPC rate limit) on a call that cannot have paid anything (money none) is retried
# once after 30 s. Calls that may pay (client start) are retried by connect.sh, which checks first.
try() {
  m=$1; shift
  n=0
  while :; do
    printf '+ %s\n' "$*" >&2; printf "%s" "$*" > "${LAST_RUN_FILE:-/dev/null}"
    errf=$(mktemp)
    if out=$("$@" 2>"$errf"); then cat "$errf" >&2; rm -f "$errf"; printf '%s\n' "$out"; return 0; fi
    err=$(cat "$errf"); rm -f "$errf"; echo "$err" >&2
    if [ "$m" = none ] && [ "$n" = 0 ] && is_rpc_busy "$err"; then
      n=1; echo "RPC busy (429): retrying once in 30 s" >&2; sleep 30; continue
    fi
    classify "$(squash "$err")" "$m"
  done
}

# try_raw <command...>: run once; on failure keep stderr in TRY_ERR and return 1 (no classify)
try_raw() {
  printf '+ %s\n' "$*" >&2; printf "%s" "$*" > "${LAST_RUN_FILE:-/dev/null}"
  errf=$(mktemp)
  if out=$("$@" 2>"$errf"); then cat "$errf" >&2; rm -f "$errf"; printf '%s\n' "$out"; return 0; fi
  TRY_ERR=$(cat "$errf"); rm -f "$errf"; echo "$TRY_ERR" >&2
  printf '%s' "$TRY_ERR" > "${TRY_ERR_FILE:-/dev/null}"
  return 1
}

# ─── daemon socket: works before you log in again after install (falls back to sudo) ───
dclient() {
  if [ -w "$SOCK" ]; then sentinel-dvpn client "$@"; else sudo sentinel-dvpn client "$@"; fi
}

# ─── daemon lifecycle: the daemon refuses to start until the grant exists ("preflight failed: grant") ───
daemon_running() { [ -S "$SOCK" ] && systemctl is-active --quiet "sentinel-dvpnd@$INSTANCE.service"; }

# daemon_up: start the service (after the grant) and wait up to 30 s for its socket
daemon_up() {
  daemon_running && return 0
  run sudo systemctl reset-failed "sentinel-dvpnd@$INSTANCE.service" 2>/dev/null || true
  run sudo sentinel-dvpnd service start --instance "$INSTANCE" >&2 \
    || fail "$E_OTHER" daemon-unavailable "the daemon did not start: sudo journalctl -u sentinel-dvpnd@$INSTANCE -n 20" \
         "sudo sentinel-dvpnd doctor --instance $INSTANCE" none
  i=0; while [ $i -lt 30 ]; do daemon_running && return 0; sleep 1; i=$((i + 1)); done
  fail "$E_OTHER" daemon-unavailable "the daemon started but its socket $SOCK did not appear" "sudo sentinel-dvpnd doctor --instance $INSTANCE" none
}


# ─── market numbers (Rule 4): read from the live node list, never fixed ───
FALLBACK_PRICE=50000000   # 50 tDVPN/GB: the cap when fewer than 3 nodes match or the list is empty
UNITS=${UNITS:-1}         # GB bought by one deposit
# market <node list json>: sets P50 and P75 of channel_price_per_gb (base units; prices above
# 10 x p50 dropped as outliers) and NMATCH, the nodes left. Fewer than 3: P75 = FALLBACK_PRICE
market() {
  set -- $(printf '%s' "$1" | jq -r '[.[].value.channel_price_per_gb | numbers] | sort
    | (if length == 0 then 0 else .[((length - 1) / 2 | floor)] end) as $p50
    | (map(select(. <= 10 * $p50))) as $k | ($k | length) as $n
    | "\($p50) \(if $n == 0 then 0 else $k[((($n * 0.75) | ceil) - 1)] end) \($n)"' 2>/dev/null || echo "0 0 0")
  P50=${1:-0}; P75=${2:-0}; NMATCH=${3:-0}
  [ "$NMATCH" -ge 3 ] || P75=$FALLBACK_PRICE
}
# cheapest_under <node list json> <cap>: the cheapest node priced at or below the cap, and its price
cheapest_under() {
  printf '%s' "$1" | jq -r --argjson cap "$2" '[.[] | select(.value.channel_price_per_gb <= $cap)]
    | sort_by(.value.channel_price_per_gb) | .[0] | if . == null then "" else "\(.address) \(.value.channel_price_per_gb)" end'
}
tdvpn() { awk -v b="$1" 'BEGIN { s = sprintf("%.6f", b / 1000000); sub(/0+$/, "", s); sub(/\.$/, "", s); print s }'; }
base_units() { awk -v t="$1" 'BEGIN { printf "%d", t * 1000000 + 0.5 }'; }
# owner_address: the owner key's address; no key -> no-wallet (exit 4). A key file readable by other
# users is used, with a warning: it is a plain secret file (chmod 600 fixes it)
owner_address() {
  kf=${OWNER_KEYFILE:-$HOME/.sentinel-dvpn/keys/owner.json}
  if [ -f "$kf" ]; then
    case $(stat -c %a "$kf" 2>/dev/null) in
      600|400) ;;
      *) echo "warning: $kf is readable by other users (mode $(stat -c %a "$kf")); fix: chmod 600 $kf" >&2 ;;
    esac
  fi
  a=$(sentinel-dvpn key show owner 2>/dev/null | jq -r '.public_key // empty') || a=""
  [ -n "$a" ] || fail "$E_OPERATOR" no-wallet "no owner key ($kf): sentinel-dvpn key show owner failed" "sudo sh direct/install.sh" none
  echo "$a"
}
# device_address: the daemon's device key; missing -> no-device (install did not finish)
device_address() {
  a=$(sudo sentinel-dvpnd key show "$DEVICE_KEY_NAME" --instance "$INSTANCE" 2>/dev/null | jq -r '.public_key // empty') || a=""
  [ -n "$a" ] || fail "$E_OTHER" no-device "no device key in instance $INSTANCE (sentinel-dvpnd key show $DEVICE_KEY_NAME failed)" "sudo sh direct/install.sh" none
  echo "$a"
}
