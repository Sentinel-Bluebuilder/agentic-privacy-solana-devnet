# Path B: connect with Sentinel's own tools, no app

This path uses only Sentinel's public upstream tools, built from
[sentinel-official/sentinel-solana](https://github.com/sentinel-official/sentinel-solana) at commit
[`26de5240`](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0)
with the Solana devnet ids:
- `sentinel-dvpnd`: the daemon. It holds the device key, runs WireGuard and pays fees.
- `sentinel-dvpn`: the CLI. It holds your owner (wallet) key and talks to the chain and the daemon.

Path A (the Devnet dVPN app) uses the same chain, the same nodes and the same tDVPN.

**Proven:** Ubuntu 24.04 x86_64 on Azure, 2026-11-20. Live session through node `E5o54jGD…` (GB):
the exit IP was the node's IP, the session was stopped, and the channel close was started.
**Windows: NOT proven** (Windows 11 x64, Azure, 2026-11-20). Build, daemon, service, grant, session and close start
all work, but traffic does not go through the tunnel (gap W-1; see "Windows").
**Not run yet:** macOS, arm64 (the arm64 binaries build cleanly but have not been run),
and the final `close-channel` + `withdraw-user-balance` (due 2 h after the close start; this page is
updated once they run).

**Needs:** Linux with systemd, `sudo` (WireGuard and routes need root), and git. Go 1.27.3 only if you build.

> **Remote box? Read this first.** The upstream daemon (1) turns the kill switch on by default,
> which locks out SSH, and (2) routes the node's own API into the tunnel, which drops the session
> after ~50 s. `install.sh` and `connect.sh` handle both. If you run the raw commands yourself, see
> step 6 and "Remote box".

## Quick path

```sh
git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet
cd agentic-privacy-solana-devnet
sudo sh direct/install.sh       # tools + owner key + daemon; prints both addresses
sh direct/fund-request.sh       # prints the ONE funding message to send; --wait waits for the money
sh direct/connect.sh            # PREVIEW: says what it would sign and spend (exit 2)
sh direct/connect.sh --yes      # connect; prints {"ok":true,"exitIp":...}
sh direct/disconnect.sh         # stop (signs nothing)
sh direct/refund.sh --yes       # get unspent escrow back (run again after the time it prints)
```

Every script prints each raw command as `+ <command>` on stderr before it runs it, so you can copy
any step and do it by hand. The last stdout line is always one JSON object:

```json
{"ok":true,"step":"connect","next":"sh direct/disconnect.sh","exitIp":"185.241.226.196", ...}
{"ok":false,"needsConfirm":true,"step":"connect","what":"deposit 1000000 base units (1 tDVPN) into a new channel to node E5o5… (2000 base units/GB; device pays ~0.0022 SOL rent, back on close)","next":"sh direct/connect.sh --yes"}
{"ok":false,"step":"connect","code":"device-sol","money":"none","moneyNote":"Nothing was paid.","error":"…InvalidAccountForFee","next":"send SOL to the device address (sh direct/fund-request.sh prints it)"}
```

Read `ok` first, then do what `next` says. Anything that signs (`connect.sh`, `refund.sh`) only
previews unless you pass `--yes` (or `YES=1`). On failure, `code` names the case, `money` says
whether money moved, `moneyNote` says it in one sentence, and `next` is the fix.
`sh direct/selftest.sh` runs the whole page end to end.

`money` is always exactly one of Path A's four classes:

| `money` | Meaning | What to run |
|---|---|---|
| `none` | nothing was paid (a sent, failed transaction costs only its 5000-lamport fee) | the `next` line |
| `open` | a deposit (channel escrow) may be open | `sentinel-dvpn channel search --owner <your-owner-address>`; `sh direct/refund.sh --yes` closes it |
| `unclear` | it is not known whether a deposit opened (the daemon or RPC failed mid-step) | the same read; `sh direct/refund.sh --yes` closes anything it lists |
| `refund` | no new money was spent; unspent escrow is still held | `sh direct/refund.sh --yes` returns it |

| Exit | Meaning | Example `code` |
|---|---|---|
| 0 | ok | |
| 1 | failed (every code not listed below) | `session-active`, `device-sol`, `device-permission`, `node-gone`, `node-stale`, `no-nodes`, `daemon-unavailable`, `tunnel-failed`, `close-wait`, `unknown`, and `rpc-unavailable` when money is not `none` |
| 2 | needs `--yes` (a preview; nothing was signed) | `needsConfirm` |
| 3 | usage (Path A prints no JSON here; Path B does) | `usage`, `needs-root`, `tool-missing` |
| 4 | needs you or your funder; nothing was paid | `not-funded`, `spending-limit`, `no-wallet` |
| 5 | refused for safety | `checksum-mismatch` (Path B only; Path A uses 5 for its kill-switch codes) |
| 6 | network or RPC, and no deposit can be open | `rpc-unavailable` with money `none` |

The exit numbers, the `money` classes and the `code` names are Path A's (`devnet-dvpn`, see
[AGENT-COMMANDS.md](AGENT-COMMANDS.md)). When a Path B failure has a Path A twin it uses the same
name; codes with no Path A twin are Path B only:

| Path B `code` | Path A `code` | When |
|---|---|---|
| `not-funded`, `device-sol`, `spending-limit`, `device-permission`, `session-active`, `node-gone`, `node-stale`, `node-offline`, `no-nodes`, `price-changed`, `deposit-unusable`, `service-down`, `daemon-unavailable`, `rpc-unavailable`, `tunnel-failed`, `tunnel-closing`, `no-wallet`, `unsupported`, `unknown` | the same name | as in Path A |
| `close-wait`, `not-closing`, `nothing-to-withdraw` | (none: Path A's `settle run` does the wait for you) | refund steps run by hand |
| `no-session`, `wrong-account`, `usage`, `needs-root`, `tool-missing`, `checksum-mismatch` | (none) | raw CLI and install cases |

## Two keys, and who pays what

| Key | Where | Created by | Pays |
|---|---|---|---|
| owner (your wallet) | `~/.sentinel-dvpn/keys/owner.json` | `sentinel-dvpn key new owner --unencrypted` (install.sh does it) | the tDVPN escrow, plus the rent for the grant (0.00167 SOL) and fees for the owner-signed steps |
| device ("operator") | `/var/lib/sentinel-dvpn/c1/keys/` (root only) | `sentinel-dvpnd init` | every fee the daemon pays, plus the rent for each channel (0.00217 SOL) and for your user account (0.00124 SOL, once) |

The owner key never enters the daemon. The daemon spends for you only through an on-chain grant,
and only up to the grant's allowance.

**The key files are plain (unencrypted) files: never print them, never commit them.** Back up the owner key:

```sh
cp ~/.sentinel-dvpn/keys/owner.json /some/safe/place/owner.json && chmod 600 /some/safe/place/owner.json
```

Lose the owner key and you lose what it holds. Lose the device key and the rent the device paid is lost.
Any tDVPN left in your user balance can still be withdrawn with the owner key.

## Step by step (what the scripts run)

### 1. Get the tools

Prebuilt (release `direct-v1`, checked against `direct/SHA256SUMS`) or built from source:

```sh
sh direct/build.sh
```

`build.sh` runs:

```sh
git clone https://github.com/sentinel-official/sentinel-solana && git -C sentinel-solana checkout --detach 26de52407c5b722cfecad1772dcbeefd984ef6d0
make -C sentinel-solana/sentinel-dvpnd build SENTINEL_NETWORK=devnet SENTINEL_PROGRAM_ID=J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs SENTINEL_MINT=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa
make -C sentinel-solana/sentinel-dvpn  build SENTINEL_NETWORK=devnet SENTINEL_PROGRAM_ID=J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs SENTINEL_MINT=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa
```

The ids are link-time flags (`-X github.com/sentinel-official/sentinel-go-sdk/v3/version.{Network,ProgramID,Mint}`).
A build without them is a mainnet build with empty ids. With Go 1.27.3 the bytes are reproducible
(`-trimpath`, `CGO_ENABLED=0`). Two separate builds on 2026-11-20 gave identical hashes:

```
7040b5740f89fa05c419ba74b9bd692310b494dbc48e49a0a91a69636c18faf1  sentinel-dvpnd   (= sentinel-dvpnd-linux-amd64)
7131e22a37a945063b8e6758ef4702f081cbfd0b580cbef55ddc9d086dbc7095  sentinel-dvpn    (= sentinel-dvpn-linux-amd64)
62fd806b1c59ea9cffa76bf22cb9a09d20af44f0580e02cd98f4163c7f657f8b  sentinel-dvpnd-linux-arm64 (GOARCH=arm64 make build)
01858093aea92693eed2cb2e82bb767349567e20edad5e28d14a3bf5a67755f7  sentinel-dvpn-linux-arm64
```

Check the build identity (expected output):

```sh
$ sentinel-dvpn version
{"commit":"26de52407c5b722cfecad1772dcbeefd984ef6d0","mint":"Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa","network":"devnet","program_id":"J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs","tag":"26de524"}
```

A read on the public RPC (the default for the build network is `https://api.devnet.solana.com`):

```sh
$ sentinel-dvpn program status
{ "paused_features": [] }
```

### 2. Owner key, daemon, service (`install.sh`)

```sh
sentinel-dvpn key new owner --unencrypted
# {"name":"owner","public_key":"<your-owner-address>","sealed":false}
sudo sentinel-dvpnd init --instance c1 --owner <owner address> --plain-key
# {"dir":"/var/lib/sentinel-dvpn/c1","key_name":"operator","public_key":"<your-device-address>","role":"client","tag":"c1"}
sudo sed -i "s/^kill_switch = .*/kill_switch = 'off'/" /var/lib/sentinel-dvpn/c1/config.toml   # see "Remote box"
sudo sentinel-dvpnd service install --instance c1
sudo usermod -aG sentinel-dvpn $USER                  # CLI access to the daemon socket
```

**After `usermod`, the group applies only to a NEW login:** open a new ssh session, or run
`newgrp sentinel-dvpn`. Until then, `sentinel-dvpn client …` cannot open `daemon.sock` (owned by
`root:sentinel-dvpn`, mode 660); use `sudo sentinel-dvpn client …`. The direct/ scripts do that for you, so they work
straight after `install.sh`.

`public_key` from `init` is the **device address**. If you'd rather not use systemd, run the daemon in the
foreground instead of the service (after step 4): `sudo sentinel-dvpnd run --instance c1`.

`sudo sentinel-dvpnd doctor --instance c1` runs the preflight checks. Before the grant exists it fails on
`grant`, which is expected at this point. **The daemon will not start until the grant exists**: `service start` fails, and the journal shows `error: preflight failed: grant`, with systemd restarting it in a loop. So start it after step 4.

### 3. Funding: one message, both addresses (`fund-request.sh`)

Ask for both at once:
- owner: tDVPN to spend + 0.01 SOL
- device: 0.03 SOL

The device needs about 0.0022 SOL per new channel (rent + fee), so 0.03 SOL covers ~12 channels.
The public tools have no SOL transfer command, so ask your funder for the device SOL directly.
You do not need a Solana CLI.

Read the balances back:

```sh
sentinel-dvpn wallet balance                    # owner: {"dvpn_base_units":20000000,"lamports":150000000,...}
sentinel-dvpn wallet balance --owner <device>   # device: {"lamports":30000000,...}
curl -s https://api.devnet.solana.com -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["<address>"]}'
```

tDVPN has 6 decimals: `1000000` base units = 1 tDVPN. SOL is in lamports: `1000000000` = 1 SOL.

### 4. Grant + delegate: the spending cap (`connect.sh`, first run only)

```sh
sentinel-dvpn grant open-grant --grantee <device> --target 11111111111111111111111111111111 \
  --permissions 788529152 --never-expires --allowance 5000000
sentinel-dvpn wallet approve-delegate --amount-base-units 5000000
```

- `--allowance` is in tDVPN base units. It is the most the device can ever lock into channels for you.
  Each new channel's escrow is charged against it, and it is **not** given back when a channel closes.
  After two 1-tDVPN channels it read 3000000.
- `approve-delegate` lets the program move up to that much from your token account. Set it to the same amount.
- `788529152` (`0x2f000000`) is the client permission set the daemon's `doctor` asks for.
- To see what is left: `sentinel-dvpn grant search --granter <owner> --grantee <device>`.

Now start the daemon (it refuses to start before the grant exists):

```sh
sudo sentinel-dvpnd service start --instance c1
sudo sentinel-dvpnd service status --instance c1      # sentinel-dvpnd@c1: active
```

### 5. Pick a node

```sh
sentinel-dvpn node search --service wireguard --live      # JSON array; sort by .value.channel_price_per_gb
sentinel-dvpn node inspect <node address>                 # verifies signed metadata; "health":{"status":"ok"}
```

Prices are in tDVPN base units. The node we used charged 2000/GB (0.002 tDVPN per GB).

### 6. Route exceptions, then connect

```sh
GW=$(ip route show default | awk '{print $3; exit}')
sudo ip route replace <node IP>/32 via $GW dev eth0          # required, see below
sudo ip route replace <your SSH client IP>/32 via $GW dev eth0  # on a remote box
sentinel-dvpn client start --instance c1 --node <node> --new-channel --mode voucher --escrow-base-units 1000000
```

Expected output (abridged):

```json
{"session":{"id":"63271013-…","node":"E5o54jGD…","status":"active","service":"wireguard",
 "usage":{"rx_bytes":0,"tx_bytes":0,"seconds":0},"spent":0,"channel":"B5Y6pFRo…","error":""}}
```

Then `curl -4 https://api.ipify.org` printed `185.241.226.196`, which is the node's IP; before connecting it
printed the VM's own IP.

- **Always pass `--escrow-base-units`.** The config default (`escrow_base_units`) is 1000000000 = 1000 tDVPN.
  1 tDVPN covered our whole test.
- **The node route is required.** Without it, the daemon's calls to the node's API (`https://<node>:<port>`)
  go into the tunnel and time out. The logs then show `issuing voucher failed` / `closing remote session failed`,
  the session ends after ~50 s with `"error":"connection lost"`, and the daemon reconnects in a loop.
  With the route, the session held 120 s+ with no drops.
- To reuse a channel to the same node, use `--channel <channel address>` instead of `--new-channel …`.
  That opens no new rent and charges no new allowance.

Watch the session: `sentinel-dvpn client status --instance c1 <session id>` (`usage`, `spent`), or
`sentinel-dvpn client watch --instance c1`.

### 7. Disconnect (`disconnect.sh`)

```sh
sentinel-dvpn client stop --instance c1 <session id>
# {"session":{…,"status":"ended","usage":{"rx_bytes":39676,"tx_bytes":18948,"seconds":135},"spent":1,"error":"stopped by user"}}
sudo ip route del <node IP>/32
```

Stopping a session does **not** close the channel. Its unspent escrow stays locked until step 8.

### 8. Refund (`refund.sh`): start close, wait 2 h, close, withdraw

```sh
sentinel-dvpn channel search --owner <owner>                          # status 0 = open, 1 = closing
sentinel-dvpn channel start-close-channel --channel <channel>        # signed by the owner key
# {"events":[{"event":{"channel":"B5Y6pFRo…","close_started_at":1795164263},"type":"ChannelCloseStarted"}],…}
# wait channel_close_grace_seconds (sentinel-dvpn program params: 7200 = 2 h)
sentinel-dvpn channel close-channel --channel <channel>              # unspent escrow -> your user balance
sentinel-dvpn user search --owner <owner>                            # .value.balance
sentinel-dvpn user withdraw-user-balance                             # user balance -> your token account
```

- The 2 h wait lets the node redeem the vouchers you signed. `refund.sh` (preview) lists what is due now; `refund.sh --yes` does it and prints the exact time to run it again.
- Do **not** pass `--grant` when the owner signs. We did, and got `ConstraintSeeds (2006)`; the grant is only for the device key.
- When a channel closes, its rent goes back to its `rent_recipient`, which is the device key that paid it
  (shown in `sentinel-dvpn channel show <channel>`).
- To end the cap completely: `sh direct/refund.sh --revoke --yes` runs `grant close-grant` (grant rent goes back to
  the owner) and `wallet revoke-delegate`.

## Money rules, measured on 2026-11-20

| Item | Amount | Comes back? |
|---|---|---|
| channel escrow | what you pass (1 tDVPN each) | the unspent part, after close + withdraw |
| node charges | what `spent` shows (12 base units for 50 s / 5.5 MB) | no, that is the price |
| grant allowance | charged per new channel escrow | no; raise it with `grant update-grant` |
| grant rent (owner) | 1671320 lamports | yes, on `grant close-grant` |
| user account rent (device) | 1244600 lamports, once | to the device, when the user account closes |
| channel rent (device) | 2169160 lamports per channel | yes, to the device on `close-channel` |
| fees | 5000 lamports per transaction | no |

## Remote box (SSH): kill switch and lock-out

`sentinel-dvpnd init` writes `kill_switch = 'on'`. That installs an nftables output chain with
`policy drop`, which allows only loopback, the tunnel, the node, the RPC and DHCP. It has no rule for
established connections, so on a box you reach over SSH the SSH replies are dropped and you are locked out.

`install.sh` therefore writes `kill_switch = 'off'` and says so. `KILL_SWITCH=on sudo sh direct/install.sh`
keeps it on; only do that on a machine you sit at. `allow_lan = false` and
`dns_servers = ['1.1.1.1','1.0.0.1']` (via `resolvectl`) are the other `[network]` settings in
`/var/lib/sentinel-dvpn/c1/config.toml`. After you edit that file, restart the daemon:
`sudo sentinel-dvpnd service restart --instance c1`.

Even with the kill switch off, the tunnel takes the default route, and the SSH replies leave through it.
`connect.sh` adds a `/32` route for your SSH client's IP (from `$SSH_CONNECTION`) via the normal gateway.
The daemon's routing rule (`lookup main suppress_prefixlength 0`) lets that `/32` win.

**Locked out anyway?** Use the cloud's serial console, or reboot the VM. The tunnel and routes are not
persistent, and the service starts with no session. Then run `sudo sentinel-dvpnd doctor --instance c1`.
It reports a leftover persisted kill switch if there is one.

## If something fails

**Money rule:** a Solana transaction is all-or-nothing. A failed one moves no tDVPN and creates no
account. The payer still loses the 5000-lamport fee if the transaction was sent, not only simulated;
the payer is the device on daemon steps and the owner on owner-signed steps. "simulation failed"
means nothing was sent: no fee.

Raw `sentinel-dvpn` exits with code 1 on every failure, usage errors included, and prints
`error: …` on stderr. The direct/ scripts map each one to the exit codes and `code` names above.

### Daemon and CLI errors (seen live on 2026-11-20)

| Message | Meaning | Money moved | Script `code` / exit | Fix |
|---|---|---|---|---|
| `error: accepts 1 arg(s), received 0` | missing positional argument | none | `usage` / 3 | `key new <name>`, `client stop <id>`, `client status <id>` |
| `error: mode is required with --new-channel` | | none | `usage` / 3 | add `--mode voucher` |
| `open_channel: simulation failed: InvalidAccountForFee` | the device key has 0 SOL | none (simulated) | `device-sol` / 1 | fund the device address (step 3) |
| doctor `grant` … `holds no grant` | no grant yet | none | | step 4 |
| `"error":"connection lost"` after ~50 s, reconnect loop | node API routed into the tunnel | the node is paid only for what you used | (selftest `hold`) / 1 | node route (step 6) |
| `a session is already active` | the daemon allows one session at a time | none | `session-active` / 1 | `sh direct/disconnect.sh` |
| `rpc error: code = NotFound desc = not found: no active session` | the session already ended (see `client sessions`) | none | `no-session` / 1 | nothing to stop |
| `start_close_channel: … ConstraintSeeds (2006)` | `--grant` passed while the owner signs | none (simulated) | `wrong-account` / 1 | drop `--grant` |
| `dial unix /var/lib/sentinel-dvpn/c1/daemon.sock: … no such file` | the daemon is not running | none | `daemon-unavailable` / 1 | `sudo sentinel-dvpnd service start --instance c1` |
| `user show <owner>`: `account owned by another program` | `user show` wants the user account address | none | | `sentinel-dvpn user search --owner <owner>` |

### Program errors (client flow)

Find the number as `Error Number: N` or `custom program error: 0x…` in the output. The source is the
IDL `errors` list at 26de5240; 6033, 6035 and 6049 were produced live on devnet. The table is from
AC-BUILDER; the full version with a "where" column is in [BUILD-YOUR-OWN-CLIENT.md](BUILD-YOUR-OWN-CLIENT.md) §9.

| Message | Meaning | Money moved | Script `code` / exit | Fix |
|---|---|---|---|---|
| `Unauthorized` (6000) | the signer is not the owner and no valid grant was passed, or the grant's granter/grantee does not match | no (fee only) | `device-permission` / 1 | owner-signed steps: no `--grant`; device-signed steps: the grant from step 4 |
| `OperationPaused` (6001) | new channel opens are paused (`paused_mask` bit 32) | no (fee only) | `service-down` / 1 | wait; `sentinel-dvpn program status` |
| `ParamOutOfRange` (6003) | `open-grant`/`update-grant`: grantee is `111…1` or the owner itself, unknown permission bits, or an expiry in the past | no (fee only) | `unknown` / 1 | fix the flags |
| `NodeNotListed` (6015) | the node is delisted | no (fee only) | `node-gone` / 1 | pick another node (`node search --live`) |
| `NodeNotLive` (6016) | the node's listing is older than 24 h | no (fee only) | `node-stale` / 1 | pick another node (`node search --live`) |
| `NodePriceChanged` (6017) | per-hour (stream) channel: the node's price changed since you read it | no (fee only) | `price-changed` / 1 | read the node again and retry |
| `BalanceZero` (6023) | `withdraw-user-balance` with a 0 balance while channels are still open | no (fee only) | `nothing-to-withdraw` / 1 | close the channels first; nothing to withdraw yet |
| `AmountExceedsAllowance` (6024) | the new escrow is bigger than what is left of the grant allowance | no (fee only) | `spending-limit` / 4 | `grant update-grant` (raise the allowance) and `wallet approve-delegate` |
| `ChannelNotOpen` (6032) | the channel is already closing | no (fee only) | `deposit-unusable` / 1 | open a new channel |
| `ChannelNotClosing` (6033) | `close-channel` before `start-close-channel` (live) | no (fee only) | `not-closing` / 1 | run `channel start-close-channel` first |
| `GraceNotElapsed` (6035) | `close-channel` inside the 7200 s wait (live) | no (fee only); the escrow stays locked until the wait ends | `close-wait` / 1 | run it again after `close_started_at + 7200` |
| `ModeNotVoucher` (6037) | `start-close-channel` on a per-hour (stream) channel | no (fee only) | `unknown` / 1 | `channel close-channel` directly; no wait |
| `BatchLengthMismatch` (6040) | `fund-channels`: the number of amounts differs from the number of channels, or both are 0 | no (fee only) | `unknown` / 1 | one amount per channel |
| `BatchNotSorted` (6041) | `fund-channels`: channels not in ascending address-byte order, or a duplicate | no (fee only) | `unknown` / 1 | sort and dedupe the channel list |
| `NodeReopened` (6042) | the node was closed and opened again after your channel opened, so it can no longer redeem it | no | `node-gone` / 1 | close the channel (refund) and open a new one |
| `GrantExpired` (6045) | the grant's `expires_at` has passed | no (fee only) | `device-permission` / 1 | owner: `grant update-grant` with a new expiry, or open a new grant |
| `PermissionNotGranted` (6046) | the grant lacks this action's bit | no (fee only) | `device-permission` / 1 | owner: re-grant with `--permissions 788529152` |
| `GrantTargetMismatch` (6047) | the grant's target is not `111…1`, the node or the channel | no (fee only) | `device-permission` / 1 | grant with `--target 11111111111111111111111111111111` |
| `InvalidVoucherSigner` (6048) | `open_channel`: voucher_signer is not a valid ed25519 key | no (fee only) | `unknown` / 1 | a client bug; the daemon uses its operator key |
| `MissingRentRecipient` (6049) | a rent-recipient argument is `111…1` (live, simulated) | no (fee only) | `unknown` / 1 | pass the signer or the rent payer |
| `InvalidRentRecipient` (6050) | the rent recipient is neither the signer nor the rent payer | no (fee only) | `unknown` / 1 | pass the signer or the rent payer |

Anchor framework errors (standard numbers, not in the dvpn IDL):

| Message | Meaning | Money moved | Fix |
|---|---|---|---|
| `ConstraintSeeds` (2006) | a PDA did not match (seen live: `--grant` as the owner) | no (fee only) | as the owner, drop `--grant` |
| `ConstraintAddress` (2012) | wrong vault, mint or rent-recipient account | no (fee only) | let the CLI derive the accounts |
| `ConstraintTokenMint` / `ConstraintTokenOwner` (2014/2015) | the token account is not the owner's Token-2022 account for the mint | no (fee only) | `sentinel-dvpn wallet create-token-account` |
| `AccountNotInitialized` (3012) | `fund-channels` or `withdraw-user-balance` before any channel created the user account | no (fee only) | open a channel first |
| `InstructionDidNotDeserialize` (102) | the CLI was built for another program version | no (fee only) | build from the pinned commit (step 1) |

Node-side redeem errors (6034, 6036, 6039) protect you and are never shown to the client. The other
numbers in 6000–6050 belong to governance, node, provider and plan instructions.

## Build your own client

Worked examples in Go and TypeScript (read, open channel, close channel): [`build-your-own-client/`](build-your-own-client/).

- Program id `J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs`, mint `Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa` (6 decimals), devnet.
- IDL: [`sentinel-programs/idl/dvpn.json`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/idl/dvpn.json).
- PDA seeds ([`crates/dvpn/core/src/seeds.rs`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/crates/dvpn/core/src/seeds.rs)):
  - config `["config"]`
  - user `["user", owner]`
  - grant `["grant", owner, grantee, target]`
  - channel `["channel", owner, channel_id]`
  - node `["node", node_owner, node_id]`
- Client sequence as run here:
  1. `open_grant` (owner → device)
  2. SPL `approve` of the program delegate
  3. `open_channel` (device signs; creates the user account with `init_if_needed`; the device pays rent)
  4. the session with the node's HTTPS API, paid with signed vouchers
  5. `start_close_channel` (owner)
  6. after `channel_close_grace_seconds`, `close_channel`
  7. `withdraw_user_balance`
- Or drive the daemon: gRPC `sentinel.daemon.v1.ClientService` on the unix socket
  `/var/lib/sentinel-dvpn/<instance>/daemon.sock`. It offers `StartSession`, `StopSession`, `GetSession`,
  `WatchSession`, `ListSessions`, `ListChannels` and `ListTickets`
  ([`daemon.proto`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-go-sdk/daemon/v1/daemon.proto)).

## Windows (Windows 11 x64, 2026-11-20): runs, but the tunnel is not routed (gap W-1)

**Status: not proven.** Every step below works on Windows, from build to close start. But traffic does
not go through the tunnel: during the session, the exit IP was the machine's own IP. The direct/ scripts
are Linux-only. What was proven, on upstream 26de5240: the session went active on `dvpn-c1`, but the exit IP stayed the VM's own, and the daemon installed no route through `dvpn-c1`.

Build (Go 1.27.3; `make` is not needed):

```powershell
$env:CGO_ENABLED=0; $env:GOOS='windows'; $env:GOARCH='amd64'
$v='github.com/sentinel-official/sentinel-go-sdk/v3/version'
go build -trimpath -mod=readonly -ldflags "-s -w -X $v.Commit=26de52407c5b722cfecad1772dcbeefd984ef6d0 -X $v.Tag=26de524 -X $v.Network=devnet -X $v.ProgramID=J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs -X $v.Mint=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa" -o sentinel-dvpnd.exe ./cmd/sentinel-dvpnd
# the same in sentinel-dvpn/ with -o sentinel-dvpn.exe ./cmd/sentinel-dvpn
```

```
93b894c12fea760bb9b0e7e5741c10c30b431461db8cf9bd15bd4f20fa169d1f  sentinel-dvpnd-windows-amd64.exe
e132cf0892e33372efbf360aeaf1dedb0ad5e5e2e21d4e4d492d88ec03e0f3e5  sentinel-dvpn-windows-amd64.exe
```

Run every step in an **administrator** PowerShell:
- **Owner key:** `sentinel-dvpn key new owner --unencrypted` writes `%USERPROFILE%\.sentinel-dvpn\keys\owner.json`.
  It is the same 64-number JSON array as a Solana keypair file, so you can copy an existing keypair file there
  as `owner.json`; `sentinel-dvpn key show owner` confirms the address.
- **Daemon:** `sentinel-dvpnd init --instance c1 --owner <your-owner-address> --plain-key` creates
  `C:\ProgramData\sentinel-dvpn\c1`, with the device key under `keys\`.
- **Kill switch:** in `C:\ProgramData\sentinel-dvpn\c1\config.toml`, set `kill_switch = 'off'`. Keep the quotes;
  without them the daemon fails with `toml: unexpected character U+006F 'o' at start of value`.
- **Service:** `sentinel-dvpnd service install --instance c1` registers the Windows service `sentinel-dvpnd$c1`;
  start it with `sc.exe start 'sentinel-dvpnd$c1'`. Until the grant exists, the service stops by itself with
  `service stopped: preflight failed: grant` in `c1\daemon.log`.
- **CLI access:** the CLI reaches the daemon over the named pipe `\\.\pipe\ProtectedPrefix\Administrators\sentinel-dvpn\c1`,
  which only admins can open. `net localgroup sentinel-dvpn <user> /add` gives a user access.
- **Funding, grant, delegate, node search:** the same as Linux, steps 3–5.
- **Routes:** `route add <node IP> mask 255.255.255.255 <gateway>`, and the same for your RDP/SSH client IP on a
  remote box. Remove each with `route delete <IP>`.
- **Connect:** `sentinel-dvpn client start --instance c1 --node <node> --new-channel --mode voucher --escrow-base-units 1000000`
  makes the session active with interface `dvpn-c1`. With the node route in place, the session ran with no drops.
- **W-1:** during the session, `Invoke-RestMethod https://api.ipify.org` still printed the machine's own IP.
  `daemon.log` has no route line, and `route print -4` shows only the normal default route. Upstream does not
  route the Windows tunnel (seen with `kill_switch = 'off'`; not yet tested with it on).
- **Stop, start close, and the 2 h close + withdraw:** the same as Linux, steps 7–8.

## Upstream gaps (as of `26de5240`)

1. `kill_switch = 'on'` by default, with no established-connection rule: it locks out SSH on remote boxes.
2. The node's API address is not excluded from the tunnel: sessions drop after ~50 s unless you add a route.
3. No SOL transfer and no key import in `sentinel-dvpn`/`sentinel-dvpnd`: the device key must be funded from outside.
4. The default `escrow_base_units` is 1000 tDVPN.
5. Windows: the WireGuard interface comes up, but no route is installed through it, so traffic leaves through the
   normal default route (W-1).
