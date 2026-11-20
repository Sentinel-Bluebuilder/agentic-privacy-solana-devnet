#!/bin/sh
# ─── direct/faults.sh: drive every failure of the direct/ scripts once, check it against DIRECT.md ───
#
#   sh direct/faults.sh            # from the repo root, on an installed box with the daemon running
#
# Each case makes one fault happen, runs one script, and checks its last JSON line:
#   - "code" is the one expected, and it is listed in docs/DIRECT.md's Path B code table
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
# Prints one line per case, then {"ok":…,"step":"faults","pass":N,"fail":M}. Exit 0 all pass, 1 any fail.
set -u
cd "$(dirname "$0")/.."
DOC=docs/DIRECT.md
[ -f "$DOC" ] || { echo "run from the repo root (docs/DIRECT.md not found)" >&2; exit 3; }
INSTANCE=${INSTANCE:-c1}
SOCK=/var/lib/sentinel-dvpn/$INSTANCE/daemon.sock
FX=$(mktemp -d)
LOG=${LOG:-faults-$(date -u +%Y%m%dT%H%M%SZ).log}
PASS=0; FAILN=0
REAL_DVPN=$(command -v sentinel-dvpn)
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
  esac
done
exec /usr/bin/curl "$@"
EOF
cat > "$FX/bin/uname" <<'EOF'
#!/bin/sh
[ "${1:-}" = -m ] && [ -n "${FX_ARCH:-}" ] && { echo "$FX_ARCH"; exit 0; }
exec /usr/bin/uname "$@"
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
  if [ "$name" != help ]; then   # --help prints text, every other case ends with a JSON line
    sv=$(python3 -I direct/schema/validate.py "$last" 2>&1) || why="$why schema: $sv;"
  fi
  if [ -z "$why" ]; then PASS=$((PASS + 1)); v=PASS; else FAILN=$((FAILN + 1)); v="FAIL:$why"; fi
  printf '%-22s exit=%s last=%s | %s\n' "$name" "$rc" "$(printf '%s\n' "$out" | tail -1 | cut -c1-120)" "$v" | tee -a "$LOG"
}
# pv <case> <jq test> [VAR=value ...] <command ...>: a preview (exit 2) that passes preview.json and the
# jq test on its payees, feeLamports and rentLamports (S6: every preview names who gets paid)
pv() {
  name=$1; test=$2; shift 2
  out=$(env PATH="$FX/bin:$PATH" "$@" 2>"$FX/$name.err" </dev/null); rc=$?
  last=$(printf '%s\n' "$out" | tail -1); why=""
  [ "$rc" = 2 ] || why="$why exit=$rc(want 2);"
  sv=$(python3 -I direct/schema/validate.py "$last" 2>&1) || why="$why schema: $sv;"
  [ "$(printf '%s' "$last" | jq -r "$test" 2>/dev/null)" = true ] || why="$why payees fail: $test;"
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
fx  needs-root           needs-root   sh direct/install.sh
fx  tool-missing         tool-missing PATH="$FX/nojq" sh direct/disconnect.sh

# ─── keys ───
mkdir -p "$FX/nohome"
fx  no-key               no-wallet    HOME="$FX/nohome" sh direct/fund-request.sh
fx  no-device            no-device    FX_MATCH='sentinel-dvpnd key show' FX_ERR='error: key "operator" not found' sh direct/fund-request.sh
chmod 644 "$OWNER_KEY"
ok_case key-mode-644     0 'readable by other users' MIN_DVPN=1 MIN_OWNER_SOL=1 MIN_DEVICE_SOL=1 sh direct/fund-request.sh
chmod 600 "$OWNER_KEY"

# ─── funding ───
fx  unfunded-dvpn        not-funded   MIN_DVPN=999000000000 sh direct/fund-request.sh
fx  unfunded-sol         not-funded   sh direct/fund-device.sh --sol 1 --yes
fx  device-sol           device-sol   FX_START_ERR='error: Transaction simulation failed: InvalidAccountForFee' sh direct/connect.sh --yes

# ─── daemon ───
fx  daemon-socket        daemon-unavailable FX_MATCH='client sessions' FX_ERR="$ESOCK" sh direct/disconnect.sh
/usr/bin/sudo systemctl stop "sentinel-dvpnd@$INSTANCE.service"
ok_case daemon-down-disc 0 'no active session' sh direct/disconnect.sh
ok_case daemon-down-refd 0 ''         FX_MATCH='search --owner' FX_OUT='[]' sh direct/refund.sh   # no channels, no user balance: the case is the daemon, not the clock
/usr/bin/sudo sentinel-dvpnd service start --instance "$INSTANCE" >/dev/null 2>&1
i=0; while [ $i -lt 30 ] && [ ! -S "$SOCK" ]; do sleep 1; i=$((i + 1)); done

# ─── RPC ───
fx  rpc-429-read         rpc-busy     FX_MATCH='program params' FX_ERR="$E429" sh direct/refund.sh
fx  rpc-429-start        rpc-busy     FX_START_ERR="$E429" sh direct/connect.sh --yes
fx  rpc-refused          rpc-unavailable FX_MATCH='program params' FX_ERR="$EREFUSED" sh direct/refund.sh
fx  rpc-bogus-url        rpc-unavailable RPC_URL=http://127.0.0.1:9 sh direct/fund-device.sh --sol 0.001
fx  rpc-429-send         rpc-busy     FX_CURL_SEND='{"error":{"code":429,"message":"Too Many Requests"}}' sh direct/fund-device.sh --sol 0.001 --yes
fx  send-refused         unknown      FX_CURL_SEND='{"error":{"code":-32002,"message":"Transaction simulation failed"}}' sh direct/fund-device.sh --sol 0.001 --yes
fx  send-unconfirmed     unknown      FX_CURL_SEND='{"result":"FaultsShimSignature1111111111111111111111111"}' FX_CURL_STATUS='{"result":{"value":[null]}}' sh direct/fund-device.sh --sol 0.001 --yes

# ─── nodes ───
BOGUS_NODE="$(printf "%031d" 0 | tr 0 1)2"   # 31 ones + "2": a valid base58 address that is not a node account
fx  node-bogus           node-gone    NODE="$BOGUS_NODE" sh direct/connect.sh
fx  node-offline         node-offline NODE="$NODE_OK" FX_MATCH='node show' FX_OUT='{"value":{"uri":"https://faults.invalid:20000","channel_price_per_gb":2000}}' sh direct/connect.sh
fx  no-nodes             no-nodes     FX_MATCH='node search' FX_OUT='[]' sh direct/connect.sh
fx  price-cap-auto       price-cap    MAX_PRICE=0.001 sh direct/connect.sh
fx  price-cap-node       price-cap    MAX_PRICE=0.001 NODE="$NODE_OK" sh direct/connect.sh
fx  usage-max-price      usage        MAX_PRICE=abc sh direct/connect.sh
fx  close-all-no-to      usage        sh direct/close-all.sh
fx  close-all-bad-to     usage        sh direct/close-all.sh --to nope
ok_case close-all-dry    2 ''           sh direct/close-all.sh --to SysvarC1ock11111111111111111111111111111111
ok_case market-preview   2 'market: ' sh direct/connect.sh
pv  payees-connect   '(.payees | any(.role == "deposit" and .payer == "owner" and .baseUnits > 0 and .comesBack == "unspent-part")) and (.payees | any(.role == "rent" and .payer == "device" and .lamports == 2169160)) and .feeLamports >= 5000 and .rentLamports >= 2169160'     sh direct/connect.sh
pv  payees-fund-dev  '.payees == [.payees[0]] and .payees[0].role == "transfer" and .payees[0].payer == "owner" and .payees[0].lamports == 1000000 and .feeLamports == 5000 and .rentLamports == 0'     sh direct/fund-device.sh --sol 0.001
CH_OPEN="2$(printf "%042d" 0 | tr 0 1)"; CH_DUE="3$(printf "%042d" 0 | tr 0 1)"   # synthetic channels, built at run time
FX_REFUND_CH="[{\"address\":\"$CH_OPEN\",\"value\":{\"status\":0,\"escrow\":2000,\"redeemed\":0,\"close_started_at\":0}},{\"address\":\"$CH_DUE\",\"value\":{\"status\":1,\"escrow\":1000000,\"redeemed\":12,\"close_started_at\":1}}]"
pv  payees-refund    '(.payees | any(.role == "refund" and .payer == "program" and .baseUnits == 999988)) and (.payees | any(.role == "refund" and .lamports == 2169160)) and .feeLamports >= 15000 and .rentLamports == 0'     FX_MATCH='channel search' FX_OUT="$FX_REFUND_CH" sh direct/refund.sh
pv  payees-close-all '(.payees | map(select(.role == "transfer" and .to == "SysvarC1ock11111111111111111111111111111111")) | length) >= 1 and .feeLamports >= 5000'     sh direct/close-all.sh --to SysvarC1ock11111111111111111111111111111111

# ─── sessions + tunnel ───
fx  session-active-conn  session-active FX_MATCH='client sessions' FX_OUT='{"sessions":[{"id":"fx-1","status":"active"}]}' sh direct/connect.sh
fx  session-active-refd  session-active FX_MATCH='client sessions' FX_OUT='{"sessions":[{"id":"fx-1","status":"active"}]}' sh direct/refund.sh
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

printf 'not driven (code-read only): daemon_up start/socket failures (only run when no grant exists), fund-device python/openssl key checks (need a corrupted key), build.sh MISMATCH (a 9-minute build)\n' | tee -a "$LOG"
rm -rf "$FX"
OK=true; [ "$FAILN" = 0 ] || OK=false
printf '{"ok":%s,"step":"faults","pass":%s,"fail":%s,"log":"%s","next":"%s"}\n' "$OK" "$PASS" "$FAILN" "$LOG" \
  "$([ "$FAILN" = 0 ] && echo 'sh direct/selftest.sh' || echo "grep FAIL $LOG")"
[ "$FAILN" = 0 ]
