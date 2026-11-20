# Path B: connect with Sentinel's own tools, no app

## Get the binaries: two options, the same bytes

You can download the binaries or build them yourself. Both give the same four files with the same SHA-256 hashes:

```text
7040b5740f89fa05c419ba74b9bd692310b494dbc48e49a0a91a69636c18faf1  sentinel-dvpnd-linux-amd64
7131e22a37a945063b8e6758ef4702f081cbfd0b580cbef55ddc9d086dbc7095  sentinel-dvpn-linux-amd64
62fd806b1c59ea9cffa76bf22cb9a09d20af44f0580e02cd98f4163c7f657f8b  sentinel-dvpnd-linux-arm64
01858093aea92693eed2cb2e82bb767349567e20edad5e28d14a3bf5a67755f7  sentinel-dvpn-linux-arm64
```

**Release `direct-v1` (2026-11-20):** these four files, built from upstream `26de5240` unchanged, with the
devnet ids, Go 1.27.3, `CGO_ENABLED=0`, `-trimpath`. A second clean build matched every hash. arm64 is
cross-built and has not been run yet. Devnet only, Linux only.
**When a direct-v2 release is cut:** only when one of these bytes would change (a new upstream commit, Go version
or build flag). A script-only change (`direct/*.sh`) ships in this repo and keeps `direct-v1`. A release is
never re-uploaded: new bytes always get a new tag, plus new lines in `direct/SHA256SUMS` and on this page.

**Which one?** On the quick path you need neither block: `sudo sh direct/install.sh` does Option A
(download + `sha256sum` check). Use Option B when you want to prove the bytes yourself.

<table>
<tr><th>Option A: download</th><th>Option B: build it yourself</th></tr>
<tr><td valign="top">

From the release
[direct-v1](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/tag/direct-v1):

```sh
U=https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/download/direct-v1
for f in SHA256SUMS sentinel-dvpnd-linux-amd64 sentinel-dvpn-linux-amd64; do
  curl -fsSLO "$U/$f"; done
sha256sum --ignore-missing -c SHA256SUMS
gh attestation verify sentinel-dvpnd-linux-amd64 \
  -R Sentinel-Bluebuilder/agentic-privacy-solana-devnet
```

`sudo sh direct/install.sh` does the download and the `sha256sum` check for you, and refuses to
install on a mismatch (exit 5). The attestation comes from the `direct-build` workflow, which rebuilds
the binaries on GitHub's runners and signs them with `actions/attest-build-provenance`. It is bound to
the file's hash, so it verifies these files only once that workflow has produced the same bytes.
Until its first run, `gh attestation verify` reports no attestation. That is expected; the
`sha256sum` line is then the check.

</td><td valign="top">

From the public source
[sentinel-official/sentinel-solana@26de52407c5b722cfecad1772dcbeefd984ef6d0](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0)
with [Go 1.27.3](https://go.dev/dl/):

```sh
sh direct/build.sh
# MATCH    sentinel-dvpnd-linux-amd64
# ... one line per file, then
# {"ok":true,"step":"build","result":"MATCH",...}
```

`build.sh` clones that exact commit and builds both tools for amd64 and arm64 with the devnet ids.
It compares each hash with the lines above (`direct/SHA256SUMS`), and exits 5 on a mismatch.
`sudo BUILD=1 sh direct/install.sh` builds and installs that way.

</td></tr>
</table>

This path uses only Sentinel's public upstream tools, built from
[sentinel-official/sentinel-solana](https://github.com/sentinel-official/sentinel-solana) at commit
[`26de5240`](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0)
with the Solana devnet ids:
- `sentinel-dvpnd`: the daemon. It holds the device key, runs WireGuard and pays fees.
- `sentinel-dvpn`: the CLI. It holds your owner (wallet) key and talks to the chain and the daemon.

Path A (the Devnet dVPN app) uses the same chain, the same nodes and the same tDVPN.

**Proven:** Ubuntu 24.04 x86_64 on Azure, 2026-11-20. Live session through node `E5o54jGD…` (GB):
the exit IP was the node's IP, the session was stopped, the channel close was started, and 2 h later
`close-channel` + `withdraw-user-balance` returned the full escrow (20 of 20 tDVPN back). Then
`grant close-grant` + `wallet revoke-delegate` ran. `sh direct/selftest.sh` passed on a second, fresh
box, including a live public-RPC 429 that the retry absorbed. The same owner key file also opened in
Path A's `devnet-dvpn` (rc.5) with the same address and balances.
**Windows: NOT proven** (Windows 11 x64, Azure, 2026-11-20). Build, daemon, service, grant, session and close start
all work, but traffic does not go through the tunnel (gap W-1; see "Windows").
**Not run yet:** macOS, arm64 (the arm64 binaries build cleanly but have not been run).

**Per release.** CI (`.github/workflows/checks.yml`) runs on every push: script syntax, every last line against
`direct/schema` (hand-made and 17 captured live lines), and the example programs. The live checks cannot run in
CI (they need a VM, root and a devnet wallet), so `sh direct/faults.sh` and the paid `sh direct/selftest.sh` are
re-run on Azure Ubuntu 24.04 whenever the pinned upstream commit, the Go version or the release tag (`direct-v1` today)
changes, and after any change to `direct/*.sh`. Each run's log is kept and dated. Runs for `direct-v1` on
2026-11-20: `faults.sh` at 11:28Z (52 pass, 0 fail), 11:40Z (56/0), 12:07Z (59/0), 12:43Z (62/0) and 13:14Z
(66/0, the current set); `selftest.sh` passed on a fresh box twice (channel close started 11:02Z and 11:49Z).

**Needs:** Linux with systemd, `sudo` (WireGuard and routes need root), and git. `install.sh` adds
`wireguard-tools`, `jq` and `curl`. `fund-device.sh` also uses `python3` and `openssl`, which stock Ubuntu has.
Go 1.27.3 only if you build.

> **Remote box? Read this first.** The upstream daemon (1) turns the kill switch on by default,
> which locks out SSH, and (2) routes the node's own API into the tunnel, which drops the session
> after ~50 s. `install.sh` and `connect.sh` handle both. If you run the raw commands yourself, see
> step 6 and "Remote box".

## Quick path

```sh
git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet
cd agentic-privacy-solana-devnet
sudo sh direct/install.sh       # tools + owner key + daemon; prints both addresses
sh direct/fund-request.sh       # prints the ONE funding message for your funder; --wait waits for the money
sh direct/fund-device.sh --yes  # only when fund-request's "next" names it: sends 0.02 SOL owner -> device
sh direct/connect.sh            # PREVIEW: says what it would sign and spend (exit 2)
sh direct/connect.sh --yes      # connect; prints {"ok":true,"exitIp":...}
sh direct/disconnect.sh         # stop (signs nothing)
sh direct/refund.sh --yes       # get unspent escrow back (run again after the time it prints)
sh direct/close-all.sh --to <address> --yes   # done with the box: refund, revoke, send both keys' funds to <address>
```

- **Your funder** is whoever gives you devnet tDVPN; the token has no public faucet. Devnet SOL is
  also free from `https://faucet.solana.com`.
- **`<address>`** for `close-all.sh` is the wallet that gets everything back, usually your funder's.

| Script | Signs or pays? | Safe to run again? (exact rerun behaviour) |
|---|---|---|
| `sudo sh direct/install.sh` | no | **Yes.** It keeps an existing owner key and daemon instance (`config.toml`), downloads and re-checks the binaries, sets the kill switch again, and restarts the service only if it is already running. |
| `sh direct/fund-request.sh` | no | **Yes.** It only reads balances. `--wait` polls every 30 s for up to 30 min. |
| `sh direct/fund-device.sh --yes` | yes: one SOL transfer | **No, each `--yes` sends again.** Run the preview (no `--yes`) first: it shows both balances. If it was killed after `sendTransaction`, read the device balance (`sh direct/fund-request.sh`) before you rerun. |
| `sh direct/connect.sh --yes` | yes: grant (first run), deposit | **Yes.** The grant opens only if there is none. A channel to the same node that is still open is reused (no new deposit). With a session active it refuses (`session-active`). If it is killed after `client start`, a channel may be open (`money` = `unclear`): the rerun reuses that channel. |
| `sh direct/disconnect.sh` | no | **Yes.** With no session it prints `no active session` and still removes the route exceptions. |
| `sh direct/refund.sh --yes` | yes: close, withdraw | **Yes.** Each run does only what is due now (start close, close after 2 h, withdraw) and prints when to run it again. A killed run is finished by the next run. |
| `sh direct/close-all.sh --to <address> --yes` | yes: close, withdraw, revoke, sends | **Yes.** Without `--yes` it is a dry run that lists every step and amount. While a close is still in its 2 h wait it stops (`close-wait`) before sending anything, and `next` is the same command after the wait. A rerun after a partial sweep sends what is left (`sweep-incomplete`). |
| `sh direct/selftest.sh` | yes: one deposit per run | **Yes, but each run opens a new deposit** (refund starts its close), plus about 0.0022 SOL channel rent from the device, which comes back on close. |
| `sh direct/build.sh` | no | **Yes.** It reuses `./sentinel-solana` and rebuilds into `./dist-build`. |
| `sh direct/faults.sh` | two 5000-lamport fees | **Yes.** It blocks every deposit. Its only writes are the two `grant update-grant` calls (+1, then back). |

A killed or `set -e`-stopped script still ends with a JSON line: `interrupted` (killed: `next` is the same
command) or `unknown` (a raw stop, naming the last command), with `money` set by how far it got.
The last line of every script matches a JSON Schema in [`direct/schema/`](../direct/schema/):
`failure.json`, `preview.json`, or `<step>.json` on success. `python3 -I direct/schema/validate.py '<line>'` checks
one line, and `faults.sh` checks every case.

Every script prints each raw command as `+ <command>` on stderr before it runs it, so you can copy
any step and do it by hand. The last stdout line is always one JSON object:

```json
{"ok":true,"step":"connect","next":"sh direct/disconnect.sh","exitIp":"185.241.226.196", ...}
{"ok":false,"needsConfirm":true,"step":"connect","what":"deposit 2000 base units (0.002 tDVPN = 1 GB) into a new channel to node E5o5… (0.002 tDVPN/GB; device pays ~0.0022 SOL rent, back on close)","next":"sh direct/connect.sh --yes"}
{"ok":false,"step":"connect","code":"device-sol","money":"none","moneyNote":"Nothing was paid.","error":"…InvalidAccountForFee","next":"sh direct/fund-device.sh --sol 0.02 --yes && sh direct/connect.sh --yes"}
```

Read `ok` first, then do what `next` says: it is always one command you can run as printed. Anything
that signs or sends (`connect.sh`, `refund.sh`, `fund-device.sh`, `close-all.sh`) only previews unless
you pass `--yes` (or `YES=1`). On failure, `code` names the case, `money` says whether money moved,
`moneyNote` says it in one sentence, and `next` is the fix. Every script takes `--help`.
A preview also says who gets paid, the fee and the rent:

| Preview field | Meaning |
|---|---|
| `payees` | one entry per payment this step makes or returns, with the fields below |
| `role` | deposit (escrow to a node), transfer (a send), rent (a new account) or refund (money coming back to you) |
| `to` | who gets it: a node, device or wallet address, or the kind of account the rent opens |
| `payer` | owner, device, or program (the program pays out a refund) |
| `baseUnits`, `tdvpn` | the tDVPN amount, in base units and in tDVPN |
| `lamports` | the SOL amount, in lamports |
| `comesBack` | yes, no, unspent-part (escrow: what the node does not redeem) or yours (a send between your own keys) |
| `feeLamports` | the network fees this step pays |
| `feeSource` | how the fee was counted: fixed, 5000 lamports per signature, one signature per transaction |
| `rentLamports` | the rent this step pays for new accounts (it comes back when they close, except the user account) |
| `rentSource` | where the rent amounts come from: measured on devnet on 2026-11-20 |
`sh direct/selftest.sh` runs the whole page end to end on a funded box (it opens one deposit).

**No terminal needed.** No script prompts or reads a TTY; `--yes` is the only confirmation. On 2026-11-20 at
13:21Z, over `ssh -T` (stdin and stdout not a tty, stdin from `/dev/null`), `fund-request.sh`, `disconnect.sh`
and the previews of `connect.sh`, `fund-device.sh`, `refund.sh` and `close-all.sh` each ended with a JSON line
that passed its schema. `faults.sh` (66 cases) ran the same way. The paid `selftest.sh` itself has not yet been run over `ssh -T`:
it opens a deposit with a 2 h close.

Every script at a glance (amounts measured on devnet on 2026-11-20, see "Money rules"; the preview `what`
names the exact ones):

| Script | Does | Costs (who gets it) | Prints (`next`) | Undo |
|---|---|---|---|---|
| `sudo sh direct/install.sh` | installs the two tools (checked against `SHA256SUMS`), makes the owner key, registers the daemon service (it starts in `connect.sh`, once the grant exists) | nothing on chain | `owner`, `device` (`next`: fund) | `sudo systemctl disable --now` the `sentinel-dvpnd` socket and service (instance `c1`); keep the owner key |
| `sh direct/fund-request.sh` | prints the one funding message; `--wait` waits | nothing | `funded` (`next`: `connect.sh`) | not needed |
| `sh direct/fund-device.sh --yes` | sends `--sol` SOL (default 0.02) from the owner to the device | that SOL to the device (yours) + a 5000-lamport fee | `signature`, `deviceLamports` | not needed (the device spends it on fees and rent) |
| `sh direct/connect.sh --yes` | first run: grant + delegate (the spending cap); then opens a channel and connects | the deposit (escrow; the node gets only what it redeems) + rent: grant 0.00167 SOL (owner), channel 0.00217 SOL and user account 0.00124 SOL once (device) + fees | `exitIp`, `node`, `channel` (`next`: `disconnect.sh`) | `disconnect.sh`, then `refund.sh --yes` |
| `sh direct/disconnect.sh` | ends the session | nothing (signs nothing) | `spent`, `tunnel` (`next`: `refund.sh`) | `connect.sh --yes` |
| `sh direct/refund.sh --yes` | starts closing, after 2 h closes, withdraws | fees; the unspent escrow and the channel rent come back | `closeAfter`, then `userBalance` (`next`: wait, then run it again) | not needed; `--revoke` also closes the grant (its rent comes back) |
| `sh direct/close-all.sh --to <address> --yes` | disconnect, refund + revoke, then sends all tDVPN and SOL from both keys to `<address>` (with Path A's `devnet-dvpn`, installed from its release if missing) | fees; the owner's token account rent (~0.002 SOL) stays | the three send signatures, all balances 0 | not needed |

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
| 4 | needs you or your funder; nothing was paid | `not-funded`, `spending-limit`, `price-cap`, `no-wallet` |
| 5 | refused for safety | `checksum-mismatch` (Path B only; Path A uses 5 for its kill-switch codes) |
| 6 | network or RPC, and no deposit can be open | `rpc-busy`, `rpc-unavailable` with money `none`, `download-failed` |

Each exit class is tested by `sh direct/faults.sh`. The run on Azure Ubuntu 24.04 on 2026-11-20 at 13:14Z gave
66 pass, 0 fail. Lines from that run for exits 4, 5 and 6 (case, code, exit, money):

```text
no-key                 code=no-wallet            exit=4 money=none    | PASS
unfunded-dvpn          code=not-funded           exit=4 money=none    | PASS
price-cap-auto         code=price-cap            exit=4 money=none    | PASS
cl-spending-limit      code=spending-limit       exit=4 money=none    | PASS
checksum-mismatch      code=checksum-mismatch    exit=5 money=none    | PASS
rpc-429-read           code=rpc-busy             exit=6 money=none    | PASS
rpc-refused            code=rpc-unavailable      exit=6 money=none    | PASS
rpc-429-start          code=rpc-busy             exit=1 money=unclear | PASS   (same code; a deposit may be open, so exit 1)
```

The exit numbers, the `money` classes and the `code` names are Path A's (`devnet-dvpn`, see
[AGENT-COMMANDS.md](AGENT-COMMANDS.md)). When a Path B failure has a Path A twin it uses the same
name; codes with no Path A twin are Path B only:

| Path B `code` | Path A `code` | When |
|---|---|---|
| `not-funded`, `device-sol`, `spending-limit`, `price-cap`, `device-permission`, `session-active`, `node-gone`, `node-stale`, `node-offline`, `no-nodes`, `price-changed`, `deposit-unusable`, `service-down`, `daemon-unavailable`, `rpc-busy`, `rpc-unavailable`, `tunnel-failed`, `tunnel-closing`, `no-wallet`, `unsupported`, `unknown` | the same name | as in Path A |
| `close-wait`, `not-closing`, `nothing-to-withdraw` | (none: Path A's `settle run` does the wait for you) | refund steps run by hand |
| `no-session`, `wrong-account`, `usage`, `needs-root`, `tool-missing`, `checksum-mismatch`, `no-device`, `install-failed`, `download-failed`, `build-failed`, `route-failed`, `session-dropped`, `step-failed`, `interrupted`, `sweep-incomplete` | (none) | raw CLI and install cases (`no-device`: the daemon instance has no device key; run `sudo sh direct/install.sh`) |

## Two keys, and who pays what

| Key | Where | Created by | Pays |
|---|---|---|---|
| owner (your wallet) | `~/.sentinel-dvpn/keys/owner.json` | `sentinel-dvpn key new owner --unencrypted` (install.sh does it) | the tDVPN escrow, plus the rent for the grant (0.00167 SOL) and fees for the owner-signed steps |
| device ("operator") | `/var/lib/sentinel-dvpn/c1/keys/` (root only) | `sentinel-dvpnd init` | every fee the daemon pays, plus the rent for each channel (0.00217 SOL) and for your user account (0.00124 SOL, once) |

The owner key never enters the daemon. The daemon spends for you only through an on-chain grant,
and only up to the grant's allowance.

| Key | Where it lives | What it can sign |
|---|---|---|
| **Owner key** (your wallet) | `~/.sentinel-dvpn/keys/owner.json`, a plain file only your user can read (mode 600) | Everything the wallet can do: open, change and close the grant (`grant open-grant`, `grant update-grant`, `grant close-grant`), approve and revoke the token delegate, start closing and close channels, withdraw your user balance, and send SOL (`fund-device.sh`, `close-all.sh`). Anyone with this file holds your funds. |
| **Device key** ("operator") | `/var/lib/sentinel-dvpn/c1/keys/`, root only; used by `sentinel-dvpnd` | Only what the grant allows (permissions `788529152`, the client set): open and fund channels to nodes and sign vouchers for the node to redeem. It moves your tDVPN only up to the grant's allowance, and it pays its own fees and rent from its SOL. It cannot withdraw, send your tDVPN elsewhere or change the grant. |
| **The grant** (an on-chain account, not a key) | the program account `grant search --granter <owner> --grantee <device>` shows | It signs nothing. It is the cap: the allowance is a running total of escrow the device may lock (closes do not give it back). The owner removes it with `sh direct/refund.sh --revoke --yes` (`grant close-grant` + `wallet revoke-delegate`). |

**The same key file works on both paths (a 64-number JSON array).** It is the standard Solana keypair
file. Path A reads it with `DVPN_KEYFILE=~/.sentinel-dvpn/keys/owner.json devnet-dvpn wallet show --json`,
and that showed the same address and balances as `sentinel-dvpn wallet balance`. To move between
the paths you copy the file; no conversion is needed.

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
# for each ARCH in amd64 arm64 and each TOOL in sentinel-dvpnd sentinel-dvpn:
env GOOS=linux GOARCH=$ARCH make -C sentinel-solana/$TOOL build SENTINEL_NETWORK=devnet SENTINEL_PROGRAM_ID=J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs SENTINEL_MINT=Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa
cp sentinel-solana/$TOOL/bin/$TOOL dist-build/$TOOL-linux-$ARCH
# then sha256sum dist-build/* and compare each line with direct/SHA256SUMS
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
- owner: tDVPN to spend (the ask is 2 × the market p75 price × `UNITS`: 100 tDVPN today; see "Market defaults" in step 5) + 0.01 SOL
- device: 0.03 SOL

The device needs about 0.0022 SOL per new channel (rent + fee), so 0.03 SOL covers ~12 channels.
The public Sentinel tools have no SOL transfer command. If your funder sent everything to the owner,
move the device's share yourself:

```sh
sh direct/fund-device.sh --sol 0.02          # preview: what it would send (exit 2)
sh direct/fund-device.sh --sol 0.02 --yes    # {"ok":true,"signature":"…","lamports":20000000,"deviceLamports":…}
```

`fund-device.sh` builds one System Program transfer from the owner key to the device address the
daemon reports. It uses only tools already on Ubuntu: `python3 -I` (standard library) to encode it and
`openssl` to sign it (ed25519). It first checks that the key file's public key matches the owner
address. Nothing is downloaded, and no Solana CLI is needed.

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
  --permissions 788529152 --never-expires --allowance 150000000
sentinel-dvpn wallet approve-delegate --amount-base-units 150000000
```

- `--allowance` is in tDVPN base units. It is the most the device can ever lock into channels for you.
  Each new channel's escrow is charged against it, and it is **not** given back when a channel closes.
  After two 1-tDVPN channels a 5-tDVPN cap read 3000000. connect.sh opens it at 3 × the price cap (150 tDVPN today).
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

`channel_price_per_gb` is in tDVPN base units per GB. The node we used charged 2000 (0.002 tDVPN per GB).
`connect.sh` does this pick for you, with the rules below.

**Market defaults (no fixed amounts).** Every amount comes from the live node list
(`sentinel-dvpn node search --service wireguard --live`, price field `channel_price_per_gb`):

| Number | Rule | Today (2026-11-20, 7 live WireGuard nodes) | Override |
|---|---|---|---|
| price cap | p75 of the live prices, after dropping prices above 10 × p50; 50 tDVPN/GB if fewer than 3 nodes; never below `ALLOWANCE` / 10 | 50 tDVPN/GB | `MAX_PRICE=<tDVPN per GB>` |
| node | the cheapest node at or below the cap | `E5o54jGD…`, 0.002 tDVPN/GB | `NODE=<address>` |
| escrow (one deposit) | the node's price × `UNITS` (GB, default 1) | 0.002 tDVPN | `ESCROW=<base units>`, `UNITS=<GB>` |
| grant cap | 3 × the price cap × `UNITS` (a running total: closes do not give it back) | 150 tDVPN | `ALLOWANCE=<base units>` |
| tDVPN ask (fund-request) | 2 × p75 × `UNITS` | 100 tDVPN | `WANT_DVPN=<base units>` |
| tDVPN minimum ("funded") | one deposit at the price the node pick would use | 0.002 tDVPN | `MIN_DVPN=<base units>` |
| SOL | ask owner 0.01, device 0.03; funded at owner 0.005, device 0.01 | | `MIN_OWNER_SOL`, `MIN_DEVICE_SOL` |

When the cheapest node is above the cap, `connect.sh` refuses with `price-cap` (exit 4, money `none`)
and names the number, for example: `cheapest matching node above the cap: 60 tDVPN/GB (cap 50); set MAX_PRICE=60`,
with `next` `MAX_PRICE=60 sh direct/connect.sh`.

### 6. Route exceptions, then connect

```sh
GW=$(ip route show default | awk '{print $3; exit}')     # your gateway
DEV=$(ip route show default | awk '{print $5; exit}')    # your interface (eth0 on our VM)
sudo ip route replace <node IP>/32 via $GW dev $DEV          # required, see below
sudo ip route replace <your SSH client IP>/32 via $GW dev $DEV  # on a remote box
sentinel-dvpn client start --instance c1 --node <node> --new-channel --mode voucher --escrow-base-units <node price x GB>
```

Expected output (abridged):

```json
{"session":{"id":"63271013-…","node":"E5o54jGD…","status":"active","service":"wireguard",
 "usage":{"rx_bytes":0,"tx_bytes":0,"seconds":0},"spent":0,"channel":"B5Y6pFRo…","error":""}}
```

Then `curl -4 https://api.ipify.org` printed `185.241.226.196`, which is the node's IP; before connecting it
printed the VM's own IP.

- **Always pass `--escrow-base-units`.** The config default (`escrow_base_units`) is 1000000000 = 1000 tDVPN.
  connect.sh passes the node's price × `UNITS` (1 GB by default); 1 tDVPN covered our whole test.
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
| channel escrow | what you pass (connect.sh: the node price × `UNITS`) | the unspent part, after close + withdraw |
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
| your SSH session freezes, then `Connection timed out` / `Broken pipe`, and new `ssh` attempts hang | the kill switch is on (`kill_switch = 'on'`, the upstream default) and its drop-policy chain has no rule for established connections, so your own SSH replies are dropped. Or the tunnel took the default route with no `/32` for your SSH client | none (the session still runs and is paid only for what it uses) | none: the script cannot reach you | from the cloud serial console: `sudo sentinel-dvpnd service stop --instance c1` (stopping the daemon removes its tunnel and chain), or reboot the VM (neither persists). Then `sudo sh direct/install.sh` (sets `kill_switch = 'off'`) and `sh direct/connect.sh` (adds the SSH `/32`). See "Remote box" |
| `a session is already active` | the daemon allows one session at a time | none | `session-active` / 1 | `sh direct/disconnect.sh` |
| `rpc error: code = NotFound desc = not found: no active session` | the session already ended (see `client sessions`) | none | `no-session` / 1 | nothing to stop |
| `start_close_channel: … ConstraintSeeds (2006)` | `--grant` passed while the owner signs | none (simulated) | `wrong-account` / 1 | drop `--grant` |
| `dial unix /var/lib/sentinel-dvpn/c1/daemon.sock: … no such file` | the daemon is not running | none | `daemon-unavailable` / 1 | `sudo sentinel-dvpnd service start --instance c1` |
| `429 Too Many Requests` (public RPC) | `api.devnet.solana.com` rate-limits bursts | none on reads; on `client start` a channel may have opened | `rpc-busy` / 6 (1 if money is not `none`) | the scripts retry once after 30 s: a read retries as is; `client start` first checks `channel search` and reuses a channel the first try opened. Otherwise wait 30 s and run the same line again, or set `RPC_URL` and `--rpc.url` to your own endpoint |
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
3. No SOL transfer and no key import in `sentinel-dvpn`/`sentinel-dvpnd`: the device key must be funded from outside (`direct/fund-device.sh` does it with python3 + openssl).
4. The default `escrow_base_units` is 1000 tDVPN.
5. Windows: the WireGuard interface comes up, but no route is installed through it, so traffic leaves through the
   normal default route (W-1).
