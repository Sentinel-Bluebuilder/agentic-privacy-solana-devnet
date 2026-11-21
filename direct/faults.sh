#!/bin/sh
# ─── direct/faults.sh: drive every failure of the direct/ scripts once, check it against DIRECT.md ───
#
#   sh direct/faults.sh            # from the repo root, on an installed box with the daemon running
#
# Each case makes one fault happen, runs one script, and checks its last JSON line:
#   - "code" is the one expected, and it is listed in docs/DIRECT-REFERENCE.md's Path B code table
#   - the exit matches DIRECT.md's exit table (6 only when money is none, else 1)
#   - "money" is one of none/open/unclear/refund, and "moneyNote" is not empty
#   - "next" is not empty, has no <placeholder>, parses as shell, and every command in it exists
#   - the whole line matches its JSON Schema (direct/schema/: failure, preview, or <step>.json)
# Faults come from real conditions where that is safe (no key, bad key mode, not funded, a bogus
# node, a corrupted download, a dummy tunnel interface, the daemon stopped, a bogus RPC URL) and
# otherwise from a PATH shim that returns the upstream error text seen live.
# NO MONEY MOVES: the shim blocks every `sentinel-dvpn client start`, plain or through sudo, and
# answers fund-device's sendTransaction itself. The one live write is the grant-cap check: two
# `grant update-grant` calls (+1 base unit, then back), 2 fees of 5000 lamports.
# IT CHANGES THE BOX: it stops and restarts the daemon (an active session ends), adds and removes a dummy
# dvpn-$INSTANCE interface, and runs install.sh as root (KEYFILE refusals + one same-key reinstall). Run it on
# a test box with no session you need.
# Prints one line per case, then {"ok":…,"step":"faults","pass":N,"fail":M}. Exit 0 all pass, 1 any fail.
set -u
# --help / -h: print this header and exit, before anything runs
for a in "$@"; do case $a in --help|-h) sed -n '2,/^set -/p' "$0" | sed -e '/^set -/d' -e 's/^# \{0,1\}//'
  echo '{"ok":true,"step":"help","next":"sh direct/faults.sh"}'; exit 0 ;; esac; done
cd "$(dirname "$0")/.."
DOC=docs/DIRECT-REFERENCE.md   # the exit and code tables
[ -f "$DOC" ] || { echo "run from the repo root (docs/DIRECT-REFERENCE.md not found)" >&2; exit 3; }
INSTANCE=${INSTANCE:-c1}
SOCK=/var/lib/sentinel-dvpn/$INSTANCE/daemon.sock
FX=$(mktemp -d)
LOG=${LOG:-faults-$(date -u +%Y%m%dT%H%M%SZ).log}
PASS=0; FAILN=0
REAL_DVPN=$(command -v sentinel-dvpn)
# a --to that holds tDVPN, found at run time, for the close-all previews: the owner of the mint's largest token
# account, or else the funder (fee payer of the owner key's first transaction). getTokenLargestAccounts is often 429.
RPCU=${RPC_URL:-https://api.devnet.solana.com}
jr() { curl -s -m 20 "$RPCU" -H 'content-type: application/json' -d "$1"; }
HOLDER=""; i=0
while [ -z "$HOLDER" ] && [ $i -lt 3 ]; do
  HOLDER_TA=$(jr '{"jsonrpc":"2.0","id":1,"method":"getTokenLargestAccounts","params":["Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa"]}' | jq -r '.result.value[0].address // empty')
  [ -z "$HOLDER_TA" ] || HOLDER=$(jr "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getAccountInfo\",\"params\":[\"$HOLDER_TA\",{\"encoding\":\"jsonParsed\"}]}" | jq -r '.result.value.data.parsed.info.owner // empty')
  [ -n "$HOLDER" ] || { i=$((i + 1)); sleep 10; }
done
if [ -z "$HOLDER" ]; then
  FX_OWNER=$("$REAL_DVPN" key show owner | jq -r .public_key)
  FIRST=$(jr "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSignaturesForAddress\",\"params\":[\"$FX_OWNER\",{\"limit\":1000}]}" | jq -r '.result[-1].signature // empty')
  [ -z "$FIRST" ] || HOLDER=$(jr "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTransaction\",\"params\":[\"$FIRST\",{\"encoding\":\"json\",\"maxSupportedTransactionVersion\":0}]}" | jq -r '.result.transaction.message.accountKeys[0] // empty')
fi
[ -n "$HOLDER" ] || { echo "cannot find a tDVPN holder on $RPCU for the close-all cases" >&2; exit 1; }
echo "close-all cases use --to $HOLDER (found at run time)" >&2
# a fresh wallet address with no token account, made at run time (openssl ed25519 key, public half only)
NO_TA=$(openssl genpkey -algorithm ed25519 2>/dev/null | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 \
  | python3 -I -c 'import string, sys
A = "".join(c for c in string.digits + string.ascii_uppercase + string.ascii_lowercase if c not in "0OIl")
b = sys.stdin.buffer.read(); n = int.from_bytes(b, "big"); s = ""
while n: n, r = divmod(n, 58); s = A[r] + s
print("1" * (len(b) - len(b.lstrip(b"\0"))) + s)')
[ -n "$NO_TA" ] || { echo "could not make a fresh address (openssl/python3)" >&2; exit 1; }
OWNER_KEY=$HOME/.sentinel-dvpn/keys/owner.json

[ -w "$SOCK" ] || { echo "the daemon socket $SOCK is not writable by you: start the daemon and log in again" >&2; exit 1; }

# ─── shims ───
mkdir -p "$FX/bin"
cat > "$FX/bin/sentinel-dvpn" <<EOF
#!/bin/sh
case "\$*" in
  *"client start"*)
    if [ -n "\${FX_START_OUT:-}" ]; then printf '%s\n' "\$FX_START_OUT"; exit 0; fi
    printf '%b\n' "\${FX_START_ERR:-error: faults shim: client start blocked}" >&2; exit 1 ;;
esac
if [ -n "\${FX_HANG_MATCH:-}" ]; then
  case "\$*" in *\$FX_HANG_MATCH*) : > "$FX/hanging"; sleep 30; exit 1 ;; esac
fi
if [ -n "\${FX_MATCH:-}" ]; then
  case "\$*" in *\$FX_MATCH*)
    if [ -n "\${FX_OUT:-}" ]; then printf '%s\n' "\$FX_OUT"; exit 0; fi
    printf '%b\n' "\$FX_ERR" >&2; exit 1 ;;
  esac
fi
exec $REAL_DVPN "\$@"
EOF
cat > "$FX/bin/sudo" <<'EOF'
#!/bin/sh
case "$*" in *"sentinel-dvpn client start"*) echo "error: faults shim: client start blocked" >&2; exit 1 ;; esac
if [ -n "${FX_MATCH:-}" ]; then
  case "$*" in *$FX_MATCH*) printf '%b\n' "$FX_ERR" >&2; exit 1 ;; esac
fi
exec /usr/bin/sudo "$@"
EOF
cat > "$FX/bin/curl" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case $a in
    *sendTransaction*) [ -n "${FX_CURL_SEND:-}" ] && { printf '%s\n' "$FX_CURL_SEND"; exit 0; }
                       echo '{"error":{"message":"faults shim: send blocked"}}'; exit 0 ;;
    *getSignatureStatuses*) [ -n "${FX_CURL_STATUS:-}" ] && { printf '%s\n' "$FX_CURL_STATUS"; exit 0; } ;;
    *api.ipify.org*) [ -n "${FX_IPIFY:-}" ] && { printf '%s\n' "$FX_IPIFY"; exit 0; } ;;   # an error page, not an IP
  esac
done
exec /usr/bin/curl "$@"
EOF
cat > "$FX/bin/uname" <<'EOF'
#!/bin/sh
[ "${1:-}" = -m ] && [ -n "${FX_ARCH:-}" ] && { echo "$FX_ARCH"; exit 0; }
[ "${1:-}" = -s ] && [ -n "${FX_OS:-}" ] && { echo "$FX_OS"; exit 0; }
exec /usr/bin/uname "$@"
EOF
# python3 shim (W30): FX_TAMPER=1 flips one bit of the transfer amount in the message soltx.py just built, so the
# pre-sign check must catch it (args: -I soltx.py <keyfile> <signer> <blockhash> <work dir> ...)
cat > "$FX/bin/python3" <<'EOF'
#!/bin/sh
/usr/bin/python3 "$@"; rc=$?
if [ -n "${FX_TAMPER:-}" ] && [ "$rc" = 0 ]; then
  case ${2:-}:${3:-} in
    *soltx.py:check|*soltx.py:pubkey|*soltx.py:oncurve) ;;
    *soltx.py:*) [ -f "$6/msg.bin" ] && /usr/bin/python3 -I -c 'import sys; p = sys.argv[1]; b = bytearray(open(p, "rb").read()); b[-8] ^= 1; open(p, "wb").write(b)' "$6/msg.bin" ;;
  esac
fi
exit $rc
EOF
chmod +x "$FX/bin/"*
mkdir -p "$FX/nojq"
for f in /usr/bin/* /usr/local/bin/* /bin/*; do
  b=$(basename "$f"); [ "$b" = jq ] || [ -e "$FX/nojq/$b" ] || ln -s "$f" "$FX/nojq/$b"
done

# ─── DIRECT.md lookups ───
doc_exit() { # doc_exit <code> <money>: the exit the exit table gives
  for n in 3 4 5 6; do
    if grep -E "^\| $n \|" "$DOC" | grep -q "\`$1\`"; then
      if [ "$n" = 6 ] && [ "$2" != none ]; then echo 1; else echo "$n"; fi
      return
    fi
  done
  echo 1
}
doc_code() { # the code is listed in the Path B code table
  awk '/^\| Path B `code` \|/{t=1; next} t && /^$/{exit} t' "$DOC" | grep -q "\`$1\`"
}
runnable() { # runnable <next>
  n=$1
  [ -n "$n" ] || return 1
  case $n in *'<'*|*'>'*) return 1 ;; esac
  sh -n -c "$n" 2>/dev/null || return 1
  printf '%s\n' "$n" | sed -e 's/&&/\n/g' -e 's/;/\n/g' | {
    ok=0
    while read -r seg; do
      # shellcheck disable=SC2086
      set -- $seg
      while [ $# -gt 0 ]; do
        case $1 in
          env) shift; while [ "${1:-}" = -u ]; do shift 2; done ;;
          *=*) shift ;;
          *) break ;;
        esac
      done
      [ $# -gt 0 ] || continue
      case $1 in
        sh) [ -f "${2:-}" ] || ok=1 ;;
        sudo) shift; while case ${1:-} in *=*) true ;; *) false ;; esac; do shift; done
              [ "${1:-}" = sh ] && { [ -f "${2:-}" ] || ok=1; } || command -v "${1:-x}" >/dev/null 2>&1 || ok=1 ;;
        *) command -v "$1" >/dev/null 2>&1 || ok=1 ;;
      esac
    done
    exit $ok
  }
}

# ─── checker ───
# check <case> <want code> <rc> <last json line>
check() {
  name=$1; want=$2; rc=$3; j=$4
  code=$(printf '%s' "$j" | jq -r '.code // empty' 2>/dev/null)
  money=$(printf '%s' "$j" | jq -r '.money // empty' 2>/dev/null)
  note=$(printf '%s' "$j" | jq -r '.moneyNote // empty' 2>/dev/null)
  next=$(printf '%s' "$j" | jq -r '.next // empty' 2>/dev/null)
  why=""
  [ "$code" = "$want" ] || why="$why code=$code(want $want);"
  doc_code "$code" || why="$why code not in DIRECT.md table;"
  dx=$(doc_exit "$code" "$money")
  [ "$rc" = "$dx" ] || why="$why exit=$rc(DIRECT.md says $dx);"
  case $money in none|open|unclear|refund) ;; *) why="$why money=$money;" ;; esac
  [ -n "$note" ] || why="$why no moneyNote;"
  runnable "$next" || why="$why next not runnable: $next;"
  sv=$(python3 -I direct/schema/validate.py "$j" 2>&1) || why="$why schema: $sv;"
  if [ -z "$why" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL:$why"; fi
  printf '%-22s code=%-20s exit=%s money=%-7s next=%s | %s\n' "$name" "$code" "$rc" "$money" "$next" "$v" | tee -a "$LOG"
}
# fx <case> <want code> [VAR=value ...] <command ...>: run with the shims, check the last JSON line
fx() {
  name=$1; want=$2; shift 2
  out=$(env PATH="$FX/bin:$PATH" "$@" 2>"$FX/$name.err" </dev/null); rc=$?
  check "$name" "$want" "$rc" "$(printf '%s\n' "$out" | tail -1)"
}
# ok_case <case> <want exit> <stderr must contain> [VAR=value ...] <command ...>: a case that must not fail
ok_case() {
  name=$1; wx=$2; grepfor=$3; shift 3
  out=$(env PATH="$FX/bin:$PATH" "$@" 2>"$FX/$name.err" </dev/null); rc=$?
  why=""
  [ "$rc" = "$wx" ] || why="$why exit=$rc(want $wx);"
  [ -z "$grepfor" ] || grep -q "$grepfor" "$FX/$name.err" || why="$why stderr lacks '$grepfor';"
  last=$(printf '%s\n' "$out" | tail -1)
  sv=$(python3 -I direct/schema/validate.py "$last" 2>&1) || why="$why schema: $sv;"   # --help too: text, then a help JSON line
  case $name in help*) [ "$(printf '%s' "$last" | jq -r .step 2>/dev/null)" = help ] || why="$why last line is not the help JSON;" ;; esac
  if [ -z "$why" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL:$why"; fi
  printf '%-22s exit=%s last=%s | %s\n' "$name" "$rc" "$(printf '%s\n' "$out" | tail -1 | cut -c1-120)" "$v" | tee -a "$LOG"
}
# sj <case> <jq test> [VAR=value ...] <command ...>: a look-only answer (exit 0) that passes its schema and the jq test
sj() {
  name=$1; test=$2; shift 2
  out=$(env PATH="$FX/bin:$PATH" "$@" 2>"$FX/$name.err" </dev/null); rc=$?
  last=$(printf '%s\n' "$out" | tail -1); why=""
  [ "$rc" = 0 ] || why="$why exit=$rc(want 0);"
  sv=$(python3 -I direct/schema/validate.py "$last" 2>&1) || why="$why schema: $sv;"
  printf '%s' "$last" | jq -e "$test" >/dev/null 2>&1 || why="$why jq test failed: $test;"
  if [ -z "$why" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL:$why"; fi
  printf '%-22s exit=%s last=%s | %s\n' "$name" "$rc" "$(printf '%s' "$last" | cut -c1-120)" "$v" | tee -a "$LOG"
}
# pv <case> <jq test> [VAR=value ...] <command ...>: a preview (exit 2) that passes preview.json and the
# jq test on its payees, feeLamports and rentLamports (S6: every preview names who gets paid)
pv() {
  name=$1; test=$2; shift 2
  out=$(env PATH="$FX/bin:$PATH" "$@" 2>"$FX/$name.err" </dev/null); rc=$?
  last=$(printf '%s\n' "$out" | tail -1); why=""
  [ "$rc" = 2 ] || why="$why exit=$rc(want 2);"
  sv=$(python3 -I direct/schema/validate.py "$last" 2>&1) || why="$why schema: $sv;"
  [ "$(printf '%s' "$last" | jq -r --arg h "$HOLDER" "$test" 2>/dev/null)" = true ] || why="$why payees fail: $test;"
  if [ -z "$why" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL:$why"; fi
  printf '%-22s exit=%s payees=%s fee=%s rent=%s | %s\n' "$name" "$rc" \
    "$(printf '%s' "$last" | jq -c '[.payees[]? | [.role, .payer, .baseUnits, .lamports]]' 2>/dev/null | cut -c1-120)" \
    "$(printf '%s' "$last" | jq -r '.feeLamports // "-"' 2>/dev/null)" "$(printf '%s' "$last" | jq -r '.rentLamports // "-"' 2>/dev/null)" "$v" | tee -a "$LOG"
}
# cl <case> <want code> <money in> <error text>: classify alone (every program-error row)
cl() {
  name=$1; want=$2; m=$3; e=$4
  out=$(sh -c 'e=$1; m=$2; set --; . direct/lib.sh; STEP=classify; classify "$e" "$m"' direct/connect.sh "$e" "$m" 2>/dev/null); rc=$?
  check "$name" "$want" "$rc" "$(printf '%s\n' "$out" | tail -1)"
}

E429='error: searching accounts: (*jsonrpc.RPCError)(0x30)({\n Code: (int) 429,\n Message: (string) (len=31) "Connection rate limits exceeded",\n Data: (interface {}) <nil>\n})'
EREFUSED='error: fetching config: rpc call getAccountInfo() on http://127.0.0.1:9: Post "http://127.0.0.1:9": dial tcp 127.0.0.1:9: connect: connection refused'
ESOCK='error: calling daemon: dial unix /var/lib/sentinel-dvpn/c1/daemon.sock: connect: no such file or directory'
NODE_OK=$($REAL_DVPN node search --service wireguard --live 2>/dev/null | jq -r 'sort_by(.value.channel_price_per_gb) | .[0].address // empty')

echo "faults.sh $(date -u +%FT%TZ) on $(hostname -s); node $NODE_OK" | tee "$LOG"

# ─── usage ───
fx  usage-sol            usage        sh direct/fund-device.sh --sol abc
fx  usage-cli            usage        FX_MATCH='program params' FX_ERR='error: unknown flag: --bogus' sh direct/refund.sh
ok_case help             0 ''         sh direct/refund.sh --help
ok_case help-faults      0 ''         sh direct/faults.sh --help   # prints help; must not run the suite
ok_case help-build       0 ''         sh direct/build.sh --help    # prints help; must not build
ok_case help-install     0 ''         sh direct/install.sh --help  # as a user: help, not needs-root
ok_case help-connect     0 ''         sh direct/connect.sh --help
ok_case help-close-all   0 ''         sh direct/close-all.sh --help
fx  usage-instance       usage        INSTANCE='c1;x' sh direct/connect.sh
fx  unsupported-os       unsupported-os FX_OS=Darwin sh direct/connect.sh    # Path B is Linux only: the app's next
fx  build-unsupported-os unsupported-os FX_OS=Darwin sh direct/build.sh      # refused before anything is cloned or built
ok_case help-on-darwin   0 ''         FX_OS=Darwin sh direct/install.sh --help   # help still works on another OS
# parse: every script parses under bash -n and bash --posix -n (a uname shim cannot catch a parse error), and has
# no `$(case` (bash 3.2, macOS /bin/sh, cannot parse a bare `pattern)` inside $( ); bash 5 here accepts it)
why=""
for f in direct/*.sh install.sh; do
  bash -n "$f" 2>/dev/null || why="$why $f:bash-n;"
  bash --posix -n "$f" 2>/dev/null || why="$why $f:posix-n;"
  bad=$(grep -nE '^[^#]*[$][(]case .* in ' "$f" | cut -d: -f1 | tr '\n' ' ')   # code lines only, not comments
  [ -z "$bad" ] || why="$why $f:\$(case at line $bad;"
done
if [ -z "$why" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL:$why"; fi
printf '%-22s %s | %s\n' parse-all "bash -n + bash --posix -n + no \$(case, $(ls direct/*.sh install.sh | wc -l) files" "$v" | tee -a "$LOG"
# INSTANCE you set is kept in next (an instance with no device key: no-device, next = install with INSTANCE=)
out=$(env PATH="$FX/bin:$PATH" INSTANCE=fxzz sh direct/fund-request.sh 2>"$FX/instance-carry.err" </dev/null); rc=$?
check instance-carry     no-device "$rc" "$(printf '%s\n' "$out" | tail -1)"
case $(printf '%s\n' "$out" | tail -1 | jq -r .next 2>/dev/null) in
  *INSTANCE=fxzz*) ;;
  *) FAILN=$((FAILN + 1)); echo "instance-carry-next    next drops INSTANCE=fxzz: $(printf '%s\n' "$out" | tail -1 | cut -c1-160) | FAIL" | tee -a "$LOG" ;;
esac
fx  needs-root           needs-root   sh direct/install.sh
fx  tool-missing         tool-missing PATH="$FX/nojq" sh direct/disconnect.sh

# ─── keys ───
mkdir -p "$FX/nohome"
fx  no-key               no-wallet    HOME="$FX/nohome" sh direct/fund-request.sh
fx  no-device            no-device    FX_MATCH='sentinel-dvpnd key show' FX_ERR='error: key "operator" not found' sh direct/fund-request.sh
nk=$(env PATH="$FX/bin:$PATH" HOME="$FX/nohome" sh direct/connect.sh 2>/dev/null </dev/null | tail -1 | jq -r .next 2>/dev/null)
case $nk in   # no-wallet: next imports the key file you have (install.sh KEYFILE=), it does not make a new key
  *KEYFILE=*install.sh*) PASS=$((PASS + 1)); echo "no-key-next            next=$nk | PASS" | tee -a "$LOG" ;;
  *) FAILN=$((FAILN + 1)); echo "no-key-next            next is not a KEYFILE= install: $nk | FAIL" | tee -a "$LOG" ;;
esac
fx  keyfile-missing     keyfile-missing OWNER_KEYFILE="$FX/none.json" sh direct/fund-request.sh
fx  keyfile-missing-kf   keyfile-missing KEYFILE="$FX/none.json" sh direct/connect.sh
chmod 644 "$OWNER_KEY"
ok_case key-mode-644     0 'readable by other users' MIN_DVPN=1 MIN_OWNER_SOL=1 MIN_DEVICE_SOL=1 sh direct/fund-request.sh
pv  key-644-warnings '(.warnings | length) == 1 and (.warnings[0] | contains("chmod 600"))'     sh direct/connect.sh
fx  insecure-key         insecure-key sh direct/connect.sh --yes
fx  insecure-key-fund    insecure-key sh direct/fund-device.sh --sol 0.001 --yes
chmod 600 "$OWNER_KEY"

# ─── funding ───
fx  unfunded-dvpn        not-funded   MIN_DVPN=999000000000 sh direct/fund-request.sh
fx  fundreq-search-429   rpc-busy     FX_MATCH='node search' FX_ERR="$E429" sh direct/fund-request.sh   # a failed read is never not-funded
fx  fundreq-balance-down rpc-unavailable FX_MATCH='wallet balance' FX_ERR='error: dial tcp: connection refused' sh direct/fund-request.sh
fx  unfunded-sol         not-funded   sh direct/fund-device.sh --sol 1 --yes
fx  device-sol           device-sol   FX_START_ERR='error: Transaction simulation failed: InvalidAccountForFee' sh direct/connect.sh --yes

# ─── daemon ───
fx  daemon-socket        daemon-unavailable FX_MATCH='client sessions' FX_ERR="$ESOCK" sh direct/disconnect.sh
fx  status-socket        daemon-unavailable FX_MATCH='client sessions' FX_ERR="$ESOCK" sh direct/status.sh   # look-only: a coded line, never "not connected"
/usr/bin/sudo systemctl stop "sentinel-dvpnd@$INSTANCE.service"
fx  status-daemon-down   daemon-unavailable sh direct/status.sh   # the daemon is stopped: it cannot say "not connected"
ok_case daemon-down-disc 0 'no active session' sh direct/disconnect.sh
ok_case daemon-down-refd 0 ''         FX_MATCH='search --owner' FX_OUT='[]' sh direct/refund.sh   # no channels, no user balance: the case is the daemon, not the clock
/usr/bin/sudo sentinel-dvpnd service start --instance "$INSTANCE" >/dev/null 2>&1
i=0; while [ $i -lt 30 ] && [ ! -S "$SOCK" ]; do sleep 1; i=$((i + 1)); done

# ─── RPC ───
fx  rpc-429-read         rpc-busy     FX_MATCH='program params' FX_ERR="$E429" sh direct/refund.sh
fx  rpc-429-start        rpc-busy     FX_START_ERR="$E429" sh direct/connect.sh --yes
# W77: the daemon's "escrow below node minimum" → its own code, money none, and no node route left behind
fx  escrow-below-min     escrow-below-minimum FX_START_ERR='error: opening channel: channel escrow below node minimum' sh direct/connect.sh --yes
RT=${XDG_CACHE_HOME:-$HOME/.cache}/sentinel-direct/routes-$INSTANCE
if [ ! -f "$RT" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL: $RT still lists $(tr '\n' ' ' < "$RT")"; fi
printf '%-22s %s | %s\n' escrow-min-routes "routes file after the failed start: $([ -f "$RT" ] && echo present || echo removed)" "$v" | tee -a "$LOG"
fx  rpc-refused          rpc-unavailable FX_MATCH='program params' FX_ERR="$EREFUSED" sh direct/refund.sh
fx  rpc-bogus-url        rpc-unavailable RPC_URL=http://127.0.0.1:9 sh direct/fund-device.sh --sol 0.001
fx  rpc-429-send         rpc-busy     FX_CURL_SEND='{"error":{"code":429,"message":"Too Many Requests"}}' sh direct/fund-device.sh --sol 0.001 --yes
fx  send-refused         unknown      FX_CURL_SEND='{"error":{"code":-32002,"message":"Transaction simulation failed"}}' sh direct/fund-device.sh --sol 0.001 --yes
fx  tx-mismatch          tx-mismatch FX_TAMPER=1 sh direct/fund-device.sh --sol 0.001 --yes   # W30: caught before signing
# W30 offline: soltx.py check passes the message it built and refuses one amount or recipient off (sol and token)
(umask 077; python3 -I -c 'import json, os; print(json.dumps(list(os.urandom(64))))' > "$FX/w30.json"); mkdir -p "$FX/w30"
W30S=$(python3 -I direct/soltx.py pubkey "$FX/w30.json"); BH=11111111111111111111111111111111
T22=TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb; MNT=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa
w30() { # w30 <case> <kind> <build args> -- <check args>: the build must pass its own check and fail the other
  name=$1; kind=$2; shift 2; ba=""; while [ "$1" != -- ]; do ba="$ba $1"; shift; done; shift
  # shellcheck disable=SC2086
  python3 -I direct/soltx.py "$FX/w30.json" "$W30S" "$BH" "$FX/w30" "$FX/w30/signer.tmp" "$kind" $ba >/dev/null 2>&1; rm -f "$FX/w30/signer.tmp"
  # shellcheck disable=SC2086
  ok=$(python3 -I direct/soltx.py check "$FX/w30/msg.bin" "$W30S" "$kind" $ba >/dev/null 2>&1 && echo pass || echo fail)
  bad=$(python3 -I direct/soltx.py check "$FX/w30/msg.bin" "$W30S" "$kind" "$@" 2>&1); brc=$?
  if [ "$ok" = pass ] && [ "$brc" = 1 ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL: own=$ok other-rc=$brc"; fi
  printf '%-22s %s | %s\n' "$name" "$(printf '%s' "$bad" | cut -c1-110)" "$v" | tee -a "$LOG"
}
w30 w30-sol-amount   sol "$HOLDER" 1000000 -- "$HOLDER" 1000001
w30 w30-sol-to       sol "$HOLDER" 1000000 -- "$NO_TA" 1000000
w30 w30-token-amount token "$NO_TA" "$MNT" "$HOLDER" 5000 6 "$T22" "$HOLDER" -- "$NO_TA" "$MNT" "$HOLDER" 5001 6 "$T22" "$HOLDER"
w30 w30-token-rent   token "$NO_TA" "$MNT" "$HOLDER" 5000 6 "$T22" "$HOLDER" -- "$NO_TA" "$MNT" "$HOLDER" 5000 6 "$T22" "$NO_TA"
shred -u "$FX/w30.json"
fx  send-unconfirmed     unknown     FX_CURL_SEND='{"result":"FaultsShimSignature1111111111111111111111111"}' FX_CURL_STATUS='{"result":{"value":[null]}}' sh direct/fund-device.sh --sol 0.001 --yes

# ─── nodes ───
BOGUS_NODE="$(printf "%031d" 0 | tr 0 1)2"   # 31 ones + "2": a valid base58 address that is not a node account
fx  node-bogus           node-gone    NODE="$BOGUS_NODE" sh direct/connect.sh
fx  node-offline         node-offline NODE="$NODE_OK" FX_MATCH='node show' FX_OUT='{"value":{"uri":"https://faults.invalid:20000","channel_price_per_gb":2000}}' sh direct/connect.sh
fx  no-nodes             no-nodes     FX_MATCH='node search' FX_OUT='[]' sh direct/connect.sh
fx  price-cap-auto       price-cap    MAX_PRICE=0.001 sh direct/connect.sh
fx  price-cap-node       price-cap    MAX_PRICE=0.001 NODE="$NODE_OK" sh direct/connect.sh
fx  usage-max-price      usage        MAX_PRICE=abc sh direct/connect.sh
fx  usage-unknown-flag   usage        sh direct/connect.sh --bogus
fx  usage-stray-arg      usage        sh direct/refund.sh yes
fx  usage-bare-sol       usage        sh direct/fund-device.sh --sol
fx  usage-selftest-flag  usage        sh direct/selftest.sh --bogus        # audit S3: refused before the paid run
fx  usage-selftest-hold  usage        HOLD=abc sh direct/selftest.sh       # audit S1: HOLD=abc no longer skips the hold
fx  usage-sol-empty      usage        sh direct/fund-device.sh --sol=
ok_case sol-equals-form  2 ''         sh direct/fund-device.sh --sol=0.001
fx  usage-escrow         usage        ESCROW=abc sh direct/connect.sh
fx  usage-escrow-zero    usage        ESCROW=0 sh direct/connect.sh
fx  escrow-too-small     escrow-too-small ESCROW=1 NODE="$NODE_OK" sh direct/connect.sh   # below the node's first 100 MB block, before anything signs
fx  usage-node           usage        NODE=not-a-node sh direct/connect.sh
fx  usage-units          usage        UNITS=1.5 sh direct/connect.sh
fx  close-all-no-to      usage        sh direct/close-all.sh
fx  close-all-bad-to     usage        sh direct/close-all.sh --to nope
ok_case close-all-dry    2 ''           sh direct/close-all.sh --to "$HOLDER"
fx  close-all-no-ta      no-token-account sh direct/close-all.sh --to "$NO_TA"
fx  close-all-sysvar     usage        sh direct/close-all.sh --to SysvarC1ock11111111111111111111111111111111
fx  close-all-program    usage        sh direct/close-all.sh --to J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs
PDA=$("$REAL_DVPN" channel search --owner "$("$REAL_DVPN" key show owner | jq -r .public_key)" | jq -r '.[0].address // empty')
[ -z "$PDA" ] || fx close-all-pda usage sh direct/close-all.sh --to "$PDA"   # a channel account: off the curve
ok_case market-preview   2 'market: ' sh direct/connect.sh
pv  payees-connect   '(.payees | any(.role == "deposit" and .payer == "owner" and .baseUnits > 0 and .comesBack == "unspent-part")) and (.payees | any(.role == "rent" and .payer == "device" and .lamports == 2169160)) and .feeLamports >= 5000 and .rentLamports >= 2169160'     sh direct/connect.sh
pv  grant-cap-default '(.payees | map(select(.role == "deposit"))[0].baseUnits) as $e | (.what | contains("open grant cap \($e * 10) + delegate \($e * 10) base units")) and (.payees | any(.role == "rent" and .lamports == 1671320))' \
    FX_MATCH='grant search' FX_OUT='[]' sh direct/connect.sh
pv  payees-fund-dev  '.payees == [.payees[0]] and .payees[0].role == "transfer" and .payees[0].payer == "owner" and .payees[0].lamports == 1000000 and .feeLamports == 5000 and .rentLamports == 0'     sh direct/fund-device.sh --sol 0.001
CH_OPEN="2$(printf "%042d" 0 | tr 0 1)"; CH_DUE="3$(printf "%042d" 0 | tr 0 1)"   # synthetic channels, built at run time
FX_REFUND_CH="[{\"address\":\"$CH_OPEN\",\"value\":{\"status\":0,\"escrow\":2000,\"redeemed\":0,\"close_started_at\":0}},{\"address\":\"$CH_DUE\",\"value\":{\"status\":1,\"escrow\":1000000,\"redeemed\":12,\"close_started_at\":1}}]"
pv  payees-refund    '(.payees | any(.role == "refund" and .payer == "program" and .baseUnits == 999988)) and (.payees | any(.role == "refund" and .lamports == 2169160)) and .feeLamports >= 15000 and .rentLamports == 0'     FX_MATCH='channel search' FX_OUT="$FX_REFUND_CH" sh direct/refund.sh
pv  payees-close-all '(.payees | map(select(.role == "transfer" and .to == $h)) | length) >= 1 and .feeLamports >= 5000'     sh direct/close-all.sh --to "$HOLDER"

# ─── sessions + tunnel ───
ok_case already-connected 0 '' FX_MATCH='client sessions' FX_OUT="{\"sessions\":[{\"id\":\"fx-1\",\"status\":\"active\",\"node\":\"$NO_TA\",\"channel\":\"$NO_TA\"}]}" sh direct/connect.sh   # connect while connected: ok, alreadyConnected
fx  session-active-refd  session-active FX_MATCH='client sessions' FX_OUT='{"sessions":[{"id":"fx-1","status":"active"}]}' sh direct/refund.sh
# K13 class: session-active never tells an agent to end a session it may not own; it says look first (status.sh)
nx=$(printf '%s\n' "$out" | tail -1 | jq -r '.next // empty' 2>/dev/null)
if [ "$nx" = "sh direct/status.sh" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL: next=$nx"; fi
printf '%-22s next=%s | %s\n' session-active-look "$nx" "$v" | tee -a "$LOG"
# status.sh: look only (signs nothing). Not connected, only an ended session, connected (named, next = conditional disconnect)
sj  status-none      '.connected == false and .next == null and .session == null and .exitIp == null' FX_MATCH='client sessions' FX_OUT='{"sessions":[]}' sh direct/status.sh
sj  status-ended     '.connected == false and .next == null' FX_MATCH='client sessions' FX_OUT='{"sessions":[{"id":"fx-0","status":"ended","node":"N0"}]}' sh direct/status.sh
sj  status-connected '.connected == true and .session == "fx-1" and .node == "FaultsNode1" and .protocol == "wireguard" and .channel == "FaultsChan1" and .exitIp == "203.0.113.9" and (.next | startswith("sh direct/disconnect.sh  # only if this run started"))' \
    FX_MATCH='client sessions' FX_IPIFY=203.0.113.9 FX_OUT='{"sessions":[{"id":"fx-0","status":"ended"},{"id":"fx-1","status":"active","node":"FaultsNode1","service":"wireguard","channel":"FaultsChan1"}]}' sh direct/status.sh
sj  status-ip-page   '.connected == true and .exitIp == null' FX_MATCH='client sessions' FX_IPIFY='<html>"rate limited"</html>' FX_OUT='{"sessions":[{"id":"fx-1","status":"active","node":"N1","service":"v2ray","channel":"C1"}]}' sh direct/status.sh
ok_case help-status      0 ''         sh direct/status.sh --help
fx  usage-status-flag    usage        sh direct/status.sh --yes   # look only: even --yes is refused (there is nothing to confirm)
fx  tunnel-failed        tunnel-failed FX_START_OUT='{"session":{"id":"fx-s","channel":"FaultsShimChannel"}}' sh direct/connect.sh --yes
ok_case tunnel-cleanup   0 ''         sh direct/disconnect.sh

# ─── kill and rerun: a connect killed mid-step still ends with a coded JSON line; a rerun is clean ───
env PATH="$FX/bin:$PATH" FX_START_ERR="$E429" sh direct/connect.sh --yes >"$FX/kill.out" 2>"$FX/kill.err" </dev/null &
kp=$!
i=0; while [ $i -lt 60 ] && ! grep -q 'RPC busy (429) on client start' "$FX/kill.err" 2>/dev/null; do sleep 1; i=$((i + 1)); done
kill -TERM "$kp"; wait "$kp"; rc=$?
check kill-mid-connect   interrupted "$rc" "$(tail -1 "$FX/kill.out")"
ok_case rerun-after-kill 2 'market: '   sh direct/connect.sh
ok_case rerun-disconnect 0 ''           sh direct/disconnect.sh
# audit B26: ipify answering a page (rate limit) must give ip "unknown" and valid JSON, never the page in the line
ok_case ipify-page       0 ''           env FX_IPIFY='<html><b>"rate limited"</b></html>' sh direct/disconnect.sh
fx  usage-disconnect-flag usage       sh direct/disconnect.sh --bogus      # audit B26: no longer ignored
# audit B27: build.sh failures are one JSON line. PATH=/usr/bin:/bin never holds a go.dev Go 1.27.3, so this
# stops at the tool check (no clone, no build) on every box
fx  usage-build-flag     usage        sh direct/build.sh --bogus
fx  build-tool-missing   tool-missing env PATH=/usr/bin:/bin sh direct/build.sh
# Past the tool check with shims of git / make / go in $FX/bb (nothing is cloned or compiled, no network):
#   build-git-failed   git clone fails                         → build-failed, exit 1, one JSON line (B27)
#   build-quote-src    the same with a " in SRC                → still one valid JSON line (bfail escapes)
#   build-mismatch     a "build" whose bytes cannot match      → checksum-mismatch, exit 5 (32ecbab)
mkdir -p "$FX/bb" "$FX/bsrc/.git"
printf '#!/bin/sh\necho "faults shim: git $*" >&2\ncase "$*" in *clone*) exit 128 ;; *rev-parse*) echo 26de52407c5b722cfecad1772dcbeefd984ef6d0 ;; esac\nexit 0\n' > "$FX/bb/git"
printf '#!/bin/sh\n[ "$1" = -C ] || exit 2\nmkdir -p "$2/bin" && printf planted > "$2/bin/$(basename "$2")"\n' > "$FX/bb/make"
printf '#!/bin/sh\necho go1.27.3\n' > "$FX/bb/go"
chmod +x "$FX/bb/git" "$FX/bb/make" "$FX/bb/go"
fx  build-git-failed     build-failed      env PATH="$FX/bb:/usr/bin:/bin" SRC="$FX/nosrc" DIST="$FX/bdist" ARCHES=amd64 sh direct/build.sh
fx  build-quote-src      build-failed      env PATH="$FX/bb:/usr/bin:/bin" SRC="$FX/no\"src\\x" DIST="$FX/bdist" ARCHES=amd64 sh direct/build.sh
fx  build-mismatch       checksum-mismatch env PATH="$FX/bb:/usr/bin:/bin" SRC="$FX/bsrc" DIST="$FX/bdist" ARCHES=amd64 sh direct/build.sh
# kill refund.sh while it signs (start-close-channel hangs), then the rerun finishes the job (S8)
env PATH="$FX/bin:$PATH" FX_MATCH='channel search' FX_OUT="$FX_REFUND_CH" FX_HANG_MATCH='start-close-channel' \
  sh direct/refund.sh --yes > "$FX/killr.out" 2> "$FX/killr.err" < /dev/null &
kp=$!
rm -f "$FX/hanging"; i=0; while [ $i -lt 60 ] && [ ! -f "$FX/hanging" ]; do sleep 1; i=$((i + 1)); done
kill -TERM "$kp"; wait "$kp"; rc=$?
check kill-mid-refund    interrupted "$rc" "$(tail -1 "$FX/killr.out")"
[ "$(tail -1 "$FX/killr.out" | jq -r '.money + " " + .next' 2>/dev/null)" = "refund sh direct/refund.sh --yes" ] \
  || { FAILN=$((FAILN + 1)); echo "kill-mid-refund-next   money/next not 'refund sh direct/refund.sh --yes': $(tail -1 "$FX/killr.out" | cut -c1-160) | FAIL" | tee -a "$LOG"; }
ok_case rerun-after-refund-kill 0 '' FX_MATCH='search --owner' FX_OUT='[]' sh direct/refund.sh --yes   # nothing left due: done
/usr/bin/sudo ip link add "dvpn-$INSTANCE" type dummy
fx  tunnel-closing       tunnel-closing sh direct/disconnect.sh
/usr/bin/sudo ip link del "dvpn-$INSTANCE"

# ─── install ───
mkdir -p "$FX/rel"
cp direct/SHA256SUMS "$FX/rel/SHA256SUMS"
for t in sentinel-dvpnd sentinel-dvpn; do echo corrupted > "$FX/rel/$t-linux-amd64"; done
out=$(/usr/bin/sudo env RELEASE_URL="file://$FX/rel" sh direct/install.sh 2>"$FX/checksum.err" </dev/null); rc=$?
check checksum-mismatch checksum-mismatch "$rc" "$(printf '%s\n' "$out" | tail -1)"
out=$(/usr/bin/sudo env PATH="$FX/bin:$PATH" FX_ARCH=riscv64 sh direct/install.sh 2>"$FX/arch.err" </dev/null); rc=$?
check unsupported-cpu unsupported "$rc" "$(printf '%s\n' "$out" | tail -1)"
# KEYFILE= (an owner key file you already have): every refusal comes before anything is installed
(umask 077; cp "$OWNER_KEY" "$FX/k-same.json"; cp "$OWNER_KEY" "$FX/k-644.json"; echo '[1,2]' > "$FX/k-bad.json"
 python3 -I -c 'import json, os; print(json.dumps(list(os.urandom(64))))' > "$FX/k-other.json")
chmod 644 "$FX/k-644.json"
kf() { # kf <case> <want code> <env...>: install.sh as root via sudo (SUDO_USER = you)
  name=$1; want=$2; shift 2
  out=$(/usr/bin/sudo env "$@" sh direct/install.sh 2>"$FX/$name.err" </dev/null); rc=$?
  check "$name" "$want" "$rc" "$(printf '%s\n' "$out" | tail -1)"
}
kf  keyfile-mode-644     key-unsafe    KEYFILE="$FX/k-644.json"
kf  keyfile-not-a-key    usage         KEYFILE="$FX/k-bad.json"
kf  keyfile-install-none keyfile-missing KEYFILE="$FX/k-none.json"
kf  keyfile-owner-differs wrong-account KEYFILE="$FX/k-same.json" OWNER="$NO_TA"
kf  keyfile-other-key    wrong-account KEYFILE="$FX/k-other.json"
ok_case keyfile-same     0 'already holds' /usr/bin/sudo env KEYFILE="$FX/k-same.json" sh direct/install.sh
shred -u "$FX"/k-*.json
i=0; while [ $i -lt 30 ] && [ ! -S "$SOCK" ]; do sleep 1; i=$((i + 1)); done

# ─── classify: every program / daemon error row ───
cl  cl-spending-limit    spending-limit     none    'Error Code: AmountExceedsAllowance. Error Number: 6024'
cl  cl-device-permission device-permission  none    'Error Code: PermissionNotGranted. Error Number: 6046'
cl  cl-service-down      service-down       none    'Error Code: OperationPaused. Error Number: 6001'
cl  cl-node-gone         node-gone          none    'Error Code: NodeNotListed. Error Number: 6015'
cl  cl-node-stale        node-stale         none    'Error Code: NodeNotLive. Error Number: 6016'
cl  cl-price-changed     price-changed      none    'Error Code: NodePriceChanged. Error Number: 6017'
cl  cl-close-wait        close-wait         none    'Error Code: GraceNotElapsed. Error Number: 6035'
cl  cl-not-closing       not-closing        none    'Error Code: ChannelNotClosing. Error Number: 6033'
cl  cl-deposit-unusable  deposit-unusable   none    'Error Code: ChannelNotOpen. Error Number: 6032'
cl  cl-nothing-withdraw  nothing-to-withdraw none   'Error Code: BalanceZero. Error Number: 6023'
cl  cl-insufficient      not-funded         none    'Transfer: insufficient lamports 100, need 2169160'
cl  cl-session-active    session-active     none    'calling daemon: a session is already active'
cl  cl-no-session        no-session         none    'calling daemon: no active session'
cl  cl-wrong-account     wrong-account      none    'Error Code: ConstraintSeeds. Error Number: 2006'
cl  cl-daemon-unclear    daemon-unavailable unclear "$ESOCK"
cl  cl-429-unclear       rpc-busy           unclear 'Code: (int) 429, Message: Connection rate limits exceeded'
cl  cl-timeout-none      rpc-unavailable    none    'context deadline exceeded'
cl  cl-timeout-unclear   rpc-unavailable    unclear 'context deadline exceeded'
cl  cl-unknown-none      unknown            none    'something nobody has seen'
cl  cl-unknown-unclear   unknown            unclear 'something nobody has seen'

# ─── live: is update-grant --allowance absolute? (the spending-limit next relies on it) ───
OWNER=$($REAL_DVPN key show owner | jq -r .public_key)
DEVICE=$(/usr/bin/sudo sentinel-dvpnd key show operator --instance "$INSTANCE" | jq -r .public_key)
G=$($REAL_DVPN grant search --granter "$OWNER" --grantee "$DEVICE" | jq -r '.[0].address // empty')
if [ -n "$G" ]; then
  J1=$($REAL_DVPN grant show "$G" | jq -cS .value); A=$(echo "$J1" | jq -r .allowance)
  $REAL_DVPN grant update-grant --grant "$G" --allowance $((A + 1)) >"$FX/ug1.out" 2>&1; sleep 8
  B=$($REAL_DVPN grant show "$G" | jq -r .value.allowance)
  $REAL_DVPN grant update-grant --grant "$G" --allowance "$A" >"$FX/ug2.out" 2>&1; sleep 8
  J3=$($REAL_DVPN grant show "$G" | jq -cS .value); C=$(echo "$J3" | jq -r .allowance)
  if [ "$B" = $((A + 1)) ] && [ "$J3" = "$J1" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL: not absolute, or other grant fields changed: before $J1 after $J3"; fi
  printf '%-22s allowance %s -> update %s gives %s -> update %s gives %s | %s\n' update-grant-absolute "$A" $((A + 1)) "$B" "$A" "$C" "$v" | tee -a "$LOG"
else
  echo "update-grant-absolute  skipped: no grant" | tee -a "$LOG"
fi

printf 'not driven (code-read only): daemon_up start/socket failures (only run when no grant exists), fund-device python/openssl key checks (need a corrupted key), a real build.sh MATCH / MISMATCH (a 9-minute build: build-mismatch drives the MISMATCH line with shims)\n' | tee -a "$LOG"
rm -rf "$FX"
OK=true; [ "$FAILN" = 0 ] || OK=false
printf '{"ok":%s,"step":"faults","pass":%s,"fail":%s,"log":"%s","next":"%s"}\n' "$OK" "$PASS" "$FAILN" "$LOG" \
  "$([ "$FAILN" = 0 ] && echo 'sh direct/selftest.sh' || echo "grep FAIL $LOG")" | tee -a "$LOG"   # the log carries its own result (tools/check-faults-fresh.mjs)
[ "$FAILN" = 0 ]
