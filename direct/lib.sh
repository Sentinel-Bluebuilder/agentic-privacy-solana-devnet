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

run() { printf '+ %s\n' "$*" >&2; "$@"; }

jstr() { printf '%s' "$1" | tr '"\n\t' "'  "; }

# summary <ok> <step> <next> [extra json fields without braces]
summary() {
  extra=${4:-}
  [ -n "$extra" ] && extra=",$extra"
  printf '{"ok":%s,"step":"%s","next":"%s"%s}\n' "$1" "$2" "$(jstr "$3")" "$extra"
}

# fd 3 = the real stdout, so a failure inside $(...) still reaches you; a failure in a subshell
# signals the main script, which then exits with the same code
exec 3>&1
MAIN_PID=$$
FAIL_CODE_FILE=$(mktemp)
trap 'c=$(cat "$FAIL_CODE_FILE" 2>/dev/null); rm -f "$FAIL_CODE_FILE"; exit "${c:-1}"' USR1
trap 'rm -f "$FAIL_CODE_FILE"' EXIT

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

# ─── confirm gate: anything that signs previews first ───
YES=${YES:-0}
parse_args() { for a in "$@"; do case $a in --yes|-y) YES=1 ;; esac; done; }

# confirm <what> <command line to repeat>
confirm() {
  [ "$YES" = 1 ] && return 0
  printf '{"ok":false,"needsConfirm":true,"step":"%s","what":"%s","next":"%s --yes"}\n' \
    "${STEP:-direct}" "$(jstr "$1")" "$(jstr "$2")" >&3
  exit "$E_CONFIRM"
}

# ─── upstream error -> code / exit / money / next ───
# classify <error text> <money class if the outcome is not known: none|open|unclear|refund>
# A program error or a failed simulation is all-or-nothing: no tDVPN moved, so money = none.
# A daemon / network / unknown error after the command may have reached the chain keeps $m.
classify() {
  t=$1; m=${2:-none}
  LIST="sentinel-dvpn channel search --owner \$(sentinel-dvpn key show owner | jq -r .public_key)"
  case $t in
    *InvalidAccountForFee*)
      fail "$E_OTHER" device-sol "$t" "send SOL to the device address (sh direct/fund-request.sh prints it)" none ;;
    *"insufficient lamports"*|*"insufficient funds"*)
      fail "$E_OPERATOR" not-funded "$t" "sh direct/fund-request.sh" none ;;
    *6024*|*AmountExceedsAllowance*)
      fail "$E_OPERATOR" spending-limit "$t" "the owner raises the cap: sentinel-dvpn grant update-grant --help, then approve-delegate the same" none ;;
    *6045*|*GrantExpired*|*6046*|*PermissionNotGranted*|*6047*|*GrantTargetMismatch*|*6000*|*Unauthorized*)
      fail "$E_OTHER" device-permission "$t" "close and reopen the grant: sentinel-dvpn grant close-grant --grant <grant>, then sh direct/connect.sh --yes" none ;;
    *6001*|*OperationPaused*)
      fail "$E_OTHER" service-down "$t" "channel opens are paused on chain; retry later (sentinel-dvpn program status)" none ;;
    *6015*|*NodeNotListed*|*6042*|*NodeReopened*)
      fail "$E_OTHER" node-gone "$t" "pick another node: sh direct/connect.sh (without NODE=)" none ;;
    *6016*|*NodeNotLive*)
      fail "$E_OTHER" node-stale "$t" "pick another node: sh direct/connect.sh (without NODE=)" none ;;
    *6017*|*NodePriceChanged*)
      fail "$E_OTHER" price-changed "$t" "read the node again and retry: sh direct/connect.sh" none ;;
    *6035*|*GraceNotElapsed*)
      fail "$E_OTHER" close-wait "$t" "wait 7200 s after the close start, then sh direct/refund.sh --yes" refund ;;
    *6033*|*ChannelNotClosing*)
      fail "$E_OTHER" not-closing "$t" "sh direct/refund.sh --yes starts the close first" refund ;;
    *6032*|*ChannelNotOpen*)
      fail "$E_OTHER" deposit-unusable "$t" "the channel is closing; sh direct/connect.sh --yes opens a new one" refund ;;
    *6023*|*BalanceZero*)
      fail "$E_OTHER" nothing-to-withdraw "$t" "close channels first: sh direct/refund.sh --yes" refund ;;
    *"a session is already active"*)
      fail "$E_OTHER" session-active "$t" "sh direct/disconnect.sh" none ;;
    *"no active session"*)
      fail "$E_OTHER" no-session "$t" "nothing to stop: sentinel-dvpn client sessions --instance $INSTANCE" none ;;
    *"accepts "*" arg"*|*"unknown flag"*|*"unknown command"*|*"is required"*|*"required flag"*)
      fail "$E_USAGE" usage "$t" "read the command's --help" none ;;
    *ConstraintSeeds*|*2006*|*ConstraintAddress*|*2012*)
      fail "$E_OTHER" wrong-account "$t" "a PDA or account did not match: as the owner, do not pass --grant" none ;;
    *daemon.sock*|*"connection refused"*|*"code = Unavailable"*)
      if [ "$m" = none ]; then
        fail "$E_OTHER" daemon-unavailable "$t" "sudo sentinel-dvpnd service start --instance $INSTANCE" none
      fi
      fail "$E_OTHER" daemon-unavailable "$t" "check for a funded channel: $LIST; sh direct/refund.sh --yes closes it" "$m" ;;
    *429*|*"Too Many Requests"*|*timeout*|*"deadline exceeded"*|*DeadlineExceeded*|*"no such host"*|*"dial tcp"*|*EOF*)
      if [ "$m" = none ]; then
        fail "$E_NETWORK" rpc-unavailable "$t" "retry in a minute; check the RPC: sentinel-dvpn program status" none
      fi
      fail "$E_OTHER" rpc-unavailable "$t" "check for a funded channel: $LIST; sh direct/refund.sh --yes closes it" "$m" ;;
    *)
      if [ "$m" = none ]; then
        fail "$E_OTHER" unknown "$t" "read docs/DIRECT.md 'If something fails'" none
      fi
      fail "$E_OTHER" unknown "$t" "check for a funded channel: $LIST; then read docs/DIRECT.md 'If something fails'" "$m" ;;
  esac
}

# try <money class if it fails in an unknown way> <command...>: run, keep stdout, classify stderr
try() {
  m=$1; shift
  printf '+ %s\n' "$*" >&2
  errf=$(mktemp)
  if out=$("$@" 2>"$errf"); then cat "$errf" >&2; rm -f "$errf"; printf '%s\n' "$out"; return 0; fi
  err=$(cat "$errf"); rm -f "$errf"; echo "$err" >&2
  classify "$(printf '%s' "$err" | sed 's/^error: //' | tail -3 | tr '\n' ' ')" "$m"
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

owner_address() { sentinel-dvpn key show owner | jq -r .public_key; }
device_address() { sudo sentinel-dvpnd key show "$DEVICE_KEY_NAME" --instance "$INSTANCE" | jq -r .public_key; }
