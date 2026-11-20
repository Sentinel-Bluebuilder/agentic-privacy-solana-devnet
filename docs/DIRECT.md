# Path B: connect with Sentinel's own tools, no app

**Path B: Linux only today (macOS/Windows: use the app).** The scripts need Linux with systemd and `ip`; on a Mac or a
Windows PC, use Path A, the app ([AGENTS.md](../AGENTS.md)). On an Apple silicon Mac (2026-11-20): the public upstream
builds for darwin-arm64 at the pinned commit, and `sentinel-dvpnd` gets as far as `preflight failed: grant`; a client
session is not possible with `direct/` as shipped. There, `sh direct/build.sh` refuses (`unsupported-os`), and
`VERIFY_ONLY=1 sh direct/build.sh` checks the Linux files' SHA-256.

Read this page once, top to bottom. Every code, exit, money class, error message and raw command is in
[DIRECT-REFERENCE.md](DIRECT-REFERENCE.md); a script's `next` points there when you need it.

## Already have a funded key file?

The standard Solana key file (a 64-number JSON array, the same file Path A uses):

```sh
git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet && cd agentic-privacy-solana-devnet
chmod 600 ~/owner.json                          # it is a plain secret key: install.sh refuses other modes
sudo KEYFILE=~/owner.json sh direct/install.sh  # tools + daemon, your key as the owner; prints owner + device
sh direct/fund-request.sh                       # checks both balances; "next" names what is missing
sh direct/fund-device.sh --yes                  # only if "next" names it: 0.02 SOL owner -> device
sh direct/connect.sh                            # PREVIEW (exit 2): payees, fee, rent; then the same with --yes
sh direct/disconnect.sh && sh direct/refund.sh --yes    # stop; refund starts the 2 h close
sh direct/close-all.sh --to <your-funder-address> --yes # after the wait: everything back, both keys at 0
```

No key file yet? Start at "Quick path" below: `install.sh` makes one.

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
all work, but traffic does not go through the tunnel (gap W-1; see "Windows" in [DIRECT-REFERENCE.md](DIRECT-REFERENCE.md)).
**Not run yet:** a client session on macOS (no `ip`/systemd), and the linux-arm64 binaries (they build, and their
SHA-256 matches, but they have not been run). The darwin-arm64 build ran `init` and `doctor` on macOS up to the grant check.

**Per release.** CI (`.github/workflows/checks.yml`) runs on every push: script syntax, every last line against
`direct/schema` (hand-made and 23 captured live lines), and the example programs. The live checks cannot run in
CI (they need a VM, root and a devnet wallet), so `sh direct/faults.sh` and the paid `sh direct/selftest.sh` are
re-run on Azure Ubuntu 24.04 whenever the pinned upstream commit, the Go version or the release tag (`direct-v1` today)
changes, and after any change to `direct/*.sh`. Each run's log is kept and dated, and it is enforced: where the logs are kept, CI fails on any change to `direct/*.sh` or `direct/SHA256SUMS` until a newer passing `faults.sh` log is committed. Runs for `direct-v1` on
2026-11-20: `faults.sh` at 11:28Z (52 pass, 0 fail), 11:40Z (56/0), 12:07Z (59/0), 12:43Z (62/0) and 13:14Z
(66/0, the current set); `selftest.sh` passed on a fresh box twice (channel close started 11:02Z and 11:49Z).

**Needs:** Linux with systemd, `sudo` (WireGuard and routes need root), and git. `install.sh` adds
`wireguard-tools`, `jq` and `curl`. `fund-device.sh` also uses `python3` and `openssl`, which stock Ubuntu has.
Go 1.27.3 only if you build.

> **Remote box? Read this first.** The upstream daemon (1) turns the kill switch on by default,
> which locks out SSH, and (2) routes the node's own API into the tunnel, which drops the session
> after ~50 s. `install.sh` and `connect.sh` handle both. If you run the raw commands yourself, see
> step 6 in [DIRECT-REFERENCE.md](DIRECT-REFERENCE.md) and "Remote box" below.

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
- **`<address>`** for `close-all.sh` is the wallet that gets everything back, usually your funder's. It must already hold tDVPN: without a tDVPN token account there, `close-all.sh` stops with `no-token-account` (exit 4) before it signs anything.

| Script | Signs or pays? | Safe to run again? (exact rerun behaviour) |
|---|---|---|
| `sudo sh direct/install.sh` | no | **Yes.** It keeps an existing owner key and daemon instance (`config.toml`), downloads and re-checks the binaries, sets the kill switch again, and restarts the service only if it is already running. |
| `sh direct/fund-request.sh` | no | **Yes.** It only reads balances. `--wait` polls every 30 s for up to 30 min. |
| `sh direct/fund-device.sh --yes` | yes: one SOL transfer | **No, each `--yes` sends again.** Run the preview (no `--yes`) first: it shows both balances. If it was killed after `sendTransaction`, read the device balance (`sh direct/fund-request.sh`) before you rerun. |
| `sh direct/connect.sh --yes` | yes: grant (first run), deposit | **Yes.** The grant opens only if there is none. A channel to the same node that is still open is reused (no new deposit). With a session already active it signs nothing and answers ok with `alreadyConnected: true`. If it is killed after `client start`, a channel may be open (`money` = `unclear`): the rerun reuses that channel. |
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

The full output contract (what each script costs and prints, the four `money` classes, every exit and
`code`, and the preview fields) is in [DIRECT-REFERENCE.md](DIRECT-REFERENCE.md#output-contract).

`sh direct/selftest.sh` runs the whole page end to end on a funded box (it opens one deposit).

**No terminal needed.** No script prompts or reads a TTY; `--yes` is the only confirmation. On 2026-11-20 at
13:21Z, over `ssh -T` (stdin and stdout not a tty, stdin from `/dev/null`), `fund-request.sh`, `disconnect.sh`
and the previews of `connect.sh`, `fund-device.sh`, `refund.sh` and `close-all.sh` each ended with a JSON line
that passed its schema. `faults.sh` (66 cases) ran the same way. The paid `selftest.sh` itself has not yet been run over `ssh -T`:
it opens a deposit with a 2 h close.

## Two keys, and who pays what

| Key | Where | Created by | Pays |
|---|---|---|---|
| owner (your wallet) | `~/.sentinel-dvpn/keys/owner.json` | `sentinel-dvpn key new owner --unencrypted` (install.sh does it) | the tDVPN escrow, plus the rent for the grant (0.00167 SOL) and fees for the owner-signed steps |
| device ("operator") | `/var/lib/sentinel-dvpn/c1/keys/` (root only) | `sentinel-dvpnd init` | every fee the daemon pays, plus the rent for each channel (0.00217 SOL) and for your user account (0.00124 SOL, once) |

The owner key never enters the daemon. The daemon spends for you only through an on-chain grant,
and only up to the grant's allowance.

| Key | Where it lives | What it can sign |
|---|---|---|
| **Owner key** (your wallet) | `~/.sentinel-dvpn/keys/owner.json`, a plain file only your user can read (mode 600) | Everything the wallet can do: open, change and close the grant (`grant open-grant`, `grant update-grant`, `grant close-grant`), approve and revoke the token delegate, start closing and close channels, withdraw your user balance, and send SOL and tDVPN (`fund-device.sh`, `close-all.sh`). Anyone with this file holds your funds. |
| **Device key** ("operator") | `/var/lib/sentinel-dvpn/c1/keys/`, root only; used by `sentinel-dvpnd` | Only what the grant allows (permissions `788529152`, the client set): open and fund channels to nodes and sign vouchers for the node to redeem. It moves your tDVPN only up to the grant's allowance, and it pays its own fees and rent from its SOL. It cannot withdraw, send your tDVPN elsewhere or change the grant. |
| **The grant** (an on-chain account, not a key) | the program account `grant search --granter <owner> --grantee <device>` shows | It signs nothing. It is the cap: the allowance is a running total of escrow the device may lock (closes do not give it back). The owner removes it with `sh direct/refund.sh --revoke --yes` (`grant close-grant` + `wallet revoke-delegate`). |

**The same key file works on both paths (a 64-number JSON array).** It is the standard Solana keypair
file. Path A reads it with `DVPN_KEYFILE=~/.sentinel-dvpn/keys/owner.json devnet-dvpn wallet show --json`,
and that showed the same address and balances as `sentinel-dvpn wallet balance`. To move between
the paths you copy the file; no conversion is needed. `sudo KEYFILE=<path> sh direct/install.sh` does that copy for you.

**The key files are plain (unencrypted) files: never print them, never commit them.** Back up the owner key:

```sh
cp ~/.sentinel-dvpn/keys/owner.json /some/safe/place/owner.json && chmod 600 /some/safe/place/owner.json
```

Lose the owner key and you lose what it holds. Lose the device key and the rent the device paid is lost.
Any tDVPN left in your user balance can still be withdrawn with the owner key.

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


## Reference

[DIRECT-REFERENCE.md](DIRECT-REFERENCE.md): the output contract, every raw command step by step, the
money rules, every error message with its code and fix, building your own client, Windows, and the
upstream gaps.
