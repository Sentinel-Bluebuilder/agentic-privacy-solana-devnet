# Proof: what has been shown to work, and what has not

This page says, for each OS and each step of [`AGENTS.md`](../AGENTS.md), whether it has been
shown to work in a real run, on which release, and when. It is a summary of the test teams'
evidence. The raw logs are kept by those teams and are not published here.

- **proven**: done end to end in a real run, on real Solana devnet nodes.
- **partly**: proven on an earlier build, or only some of it was run.
- **not proven**: no run yet. The reason is given.

"Earlier build" means a development build from October 2026 with the same command line. The public
release named in `AGENTS.md` is **v0.3.0-rc4** (2026-11-16, app `0.3.0-rc.4`) on Windows, Linux and macOS: one
command line, byte-identical on all three apart from the key store. "rc.3" / "rc.3.1" are the releases before it
(2026-11-16), "rc2" is v0.3.0-rc2 (2026-11-14); most rows below ran on rc2 or rc.3. On rc.4 the release smoke tests
(one paid WireGuard or V2Ray connect and disconnect per OS, run by the app team) passed; the agent-path rows on rc.4
are added as they pass. "rc.1" below is 0.3.0-rc.1 (2026-11-12).

## Agent path on v0.3.0-rc8 (2026-11-20)

The current release is **v0.3.0-rc8** on Windows and Linux (macOS stays on v0.3.0-rc4). The sections after this one
are the earlier record.

- **Published:** Windows `Devnet-dVPN-Setup-0.3.0-rc.8-x64.exe`, Linux `.deb`, `.rpm` and `.AppImage`; each hash is
  in [`docs/PROVENANCE.md`](PROVENANCE.md) and matches the release's `SHA256SUMS`. What changed for an agent:
  [`CHANGELOG.md`](../CHANGELOG.md) "v0.3.0-rc8".
- **Linux, proven:** every shell block of `AGENTS.md` run from the page on v0.3.0-rc8 over `ssh -T` (a planted broken
  block failed, as it must). The edge cases that failed on rc7 now pass: usage errors as JSON, no loop at the price
  cap, one settle line after `agent down`, a key file other users can read named by `agent status`, setup before the
  device key in one command, the clock-skew time-sync line, and a second `agent up` that joins the first (one deposit).
- **Windows, proven:** usage errors as JSON; `wallet send` refusing more than the balance, a program address, or a
  send that leaves too little SOL; `device plan` refusing an allowance above the wallet, and warning on 0; the settle
  line after `agent down`.
- **Windows, not yet:** a clock 10 minutes off is not reported; the key file's permissions are not checked (Linux and
  macOS only); with the kill switch on, the block holds only while the VPN service keeps the session
  ([`docs/SECURITY-MODEL.md`](SECURITY-MODEL.md)); a standard (non-admin) user is told to make a wallet before being
  told it needs an administrator. Each is planned for the next release.
- **Blind tests (on rc7):** three agents that had never seen these pages each did the whole task from `llms.txt`:
  two on the app, each recovering from a planted fault, and one with Sentinel's own tools and no app. All three
  passed 5 of 5. They used one model and Linux only.
- **Path B (`direct/*.sh`):** the scripted fault suite passes (104 of 104) and so do all 54 edge cases, including
  `--help` output, the input checks and a refusal to sign with an owner key file other users can read.

## Agent path on v0.3.0-rc4

**Linux** (2026-11-19 18:45Z–19:14Z, Azure Ubuntu 24.04 x64, `devnet-dvpn 0.3.0-rc.4` installed by the `AGENTS.md`
Linux lines, one paid pass):
- `agent up --node` on all six protocols (WireGuard, OpenVPN, V2Ray, Xray, Hysteria2, AmneziaWG): connected, the
  exit address differs from the computer's own, and the loaded wallet paid each time.
- Network faults (six rows): each ended cleanly, with no new chain transactions from the faults themselves.
  Interruptions: all seven rows proven. I2 (running the recovery step the app prints) passed on its re-run the same
  evening, after a test-script fix.
- A node that misbehaves (our own WireGuard node, run on rc.4's node software). When it stopped mid-session,
  `agent status` said within about 13 s that the server had stopped, that traffic was NOT going through it and that
  the deposit is safe, and named both ways out. When it refused the connection after the deposit, `agent up` said
  so, named the open deposit, and the next `agent up` used another node. Overbilling is checked in the code (the
  client refuses a node's count above its own); no live run, because the node software has no switch to overbill.
- Key file missing: refused as `keyfile-missing`, "Nothing was paid.", next is to restore the file (never to make
  a new wallet). Clock 10 minutes ahead: refused as clock skew before any deposit.
- A second wallet's key file on a computer set up for another wallet: refused before any write, through both
  `connect` and `agent up` (the device record and staged settings are byte-identical before and after).
- `device switch` both ways: the preview names the SOL it moves; afterwards `settle list` still shows all 15
  deposits made under the old device.
- Kill switch with a live session (2026-11-20 ~01:00Z):
  with the kill switch on, `agent up` connected. When the node dropped for 60 s the block held: 28 of 28 address
  checks found no way out and none showed the computer's own address. `daemon restore-network` lifted the block
  within 30 s. With the kill switch off, a service restart stayed direct. One gap: during the block, `agent status`
  said `blocked: true` but its next step was only `agent up --yes`, not `daemon restore-network` (plain `status`
  names it). Fixed in code, not yet released.
- Closing: `agent down` ended the session and started closing every deposit. Every refund from the pass is back
  (final close 2026-11-19 23:47Z, `userOpenChannels` 0, surplus returned).

**Windows** (2026-11-19 19:21Z–19:36Z, Azure Windows 11 Pro x64):
- Upgrade rc.3 → rc.4 with the silent installer, the download checked against `SHA256SUMS`.
- `device setup` on a computer whose device had been revoked: rc.4 granted the same device again, and the
  service was running afterwards.
- A second wallet's key file on a computer set up for another wallet: refused before any write, through
  `connect`, `agent up` and `device switch` (the device record and staged settings are byte-identical).
- Clock 10 minutes ahead: refused as clock skew before any deposit, via both `connect` and `agent up`.
  Key file missing: `agent status`, `up` and `down` all name the missing file and never offer a new wallet.
- `agent up --max-price`: it picked a node within the cap and paid it.
- `device switch` both ways (re-run 2026-11-19 ~21:40Z): the preview names the SOL it moves and says old deposits
  stay refundable; afterwards, the old wallet's deposit is still listed under the new wallet's record and is
  never started by the other wallet's refund run.
- Closing: every deposit from the window was refunded and every test wallet and device ended at 0
  (final close 2026-11-20 ~02:00Z, `userOpenChannels` 0 on every key, read back on chain).

Every test wallet from the rc.4 rounds (Linux, Windows, misbehaving node, fresh AI agents) ended with every
deposit closed and its money returned (last close 2026-11-20 03:12Z). One thing to know: when a wallet's last
deposit closes, the account rent (about 0.0034 SOL) goes back to the device that opened the account, even if that
device was already emptied. Only that device's key file can send it on, and the app does not say so.

Known on rc.4, to be fixed in a later release (fixes already in the app's code with tests, not yet released):
- `agent up` with the wrong wallet loaded asks for funds before it says the wallet is wrong (`connect` gets this
  right). Nothing is paid, but an agent that follows that advice funds the wrong wallet first. (Both OSes.)
- Switching back to a wallet makes a new device each time instead of reusing the old one, so about 0.05 SOL of fee
  SOL is left on each old device. It can be sent back with that device's key file, but the app does not say where
  that file is. (Both OSes.)
- A deposit made under a replaced device is closed only after that device is revoked
  (`device revoke --device D`, then `settle run --device D`). On rc.4 `agent down` answers ok without saying that
  deposit is still open. Fixed in code.
- `agent up` raises a spending limit below the deposit to the Settings limit (50 tDVPN) without saying so. A
  fresh AI agent with a 0.001 tDVPN limit never knew it had been raised. Fixed in code: the preview and the answer
  now name the raise.
- With the VPN service stopped, `agent status`'s next step names only a deposit wait, not the service fix. Fixed in
  code.

**Fresh AI agents (blind round 3, rc.4, 2026-11-19):** three new sessions, each given only `AGENTS.md`, one ssh
line and the task, on a machine left with one problem.
- Linux, VPN service stopped (Sonnet): **passed**. It saw `service: false`, ran the page's `daemon install --yes`,
  connected, proved the node's exit address, disconnected and started the refund, in 1.5 minutes.
- Linux, spending limit below the deposit (Opus): **failed**. It connected and proved the exit, but rc.4 raised the
  limit to 50 tDVPN silently, so the agent never learned its limit had been overridden (see above).
- Windows over SSH, kill switch blocking (Opus): **failed**. It found the block and lifted it with
  `daemon restore-network`, as the page says. It could not then connect, because our own test setup blocked the
  cheap nodes and the wallet held less than the 50 tDVPN the other nodes asked. That was the test's fault, not the
  app's.

**macOS:** not run on rc.4. The only macOS test machine is a cloud snapshot that is out of reach at the moment.

## Linux

A fresh-machine test run on **v0.3.0-rc2**, 2026-11-15: a clean Ubuntu 24.04 cloud machine, the public
`.deb`, driven over SSH by following `AGENTS.md`.

| step | status | how |
|---|---|---|
| 1. Install the `.deb`, `version`, `status` | **proven** on rc2 (fresh-machine run) | A fresh image first needs `sudo apt-get update`, or the install fails on a missing dependency. The page now says so |
| 1. rpm (Fedora, Rocky), Arch, arm64, AppImage | partly | proven on earlier builds; not run on rc2 (same CLI, different package) |
| 2. `wallet create --keyfile`, then `DVPN_KEYFILE` everywhere | **proven** on rc2 (fresh-machine run) | the key's address was printed; no secret appeared in any output |
| 3. Funding | not a product step | the operator sent 0.15 SOL and 20 tDVPN, which was enough |
| 4. `daemon init` → `device setup` → `daemon install` → `daemon doctor` | **proven** on rc2 (fresh-machine run) | with passwordless `sudo` no prompt appears; doctor showed no failure |
| 5. `nodes list`, `cost`, `connect` (WireGuard, per GB), `quality ip` | **proven** on rc2 (fresh-machine run) | the public IP changed to the node's while connected and came back after |
| 5. The other five protocols | partly | proven on earlier builds, all six (traffic exits at the node, nothing left after) |
| 5. SSH over a full tunnel | **proven** on rc2 (fresh-machine run, WireGuard) | the SSH session that drove the run survived the connect |
| 6. `disconnect`, `settle run` | **proven** on rc2 (fresh-machine run) | IP back to direct; the deposit moved to "closing" |
| 6. Final refund (`settle run` after 2 h, `settle withdraw`) | **proven** on rc2 (fresh-machine run) | after the two-hour close, `settle run --yes` and `settle withdraw --yes` both exited 0: the refund finished |
| A fresh AI agent with only this page (`AGENTS.md`), over SSH, with a funded key file given to it | **proven** on rc2 (2026-11-15) | clean Ubuntu 24.04: install → connect over WireGuard → exit IP checked by an outside service → disconnect → refund started, in 6.5 minutes, nothing failed. Its feedback is folded into the page |
| Shortcut: `agent status`, `agent up`, `agent down` | **proven** with a development build (not in rc2) | run live on Linux 2026-11-15, a development build of the `agent` commands on the released rc2 runtime: status, preview, connect with exit IP = node, reuse without paying, disconnect, status after. The first run's one failure (the `agent down` preview counted 0 deposits while connected) was fixed and the re-run passed |
| Per hour with the `agent` commands (`agent up --basis per_hour`, `agent down --yes`) | **proven** (2026-11-15) | a development build of the `agent` commands on the released rc2 runtime: exit IP = node, the `agent down` preview counted the live per-hour deposit, `agent down --yes` closed it at once and the unused part came back to the wallet |
| V2Ray on rc2: proxy only | **seen** on rc2 (2026-11-16) | Linux has no whole-computer setting: `direct.ip` stayed the machine's own and `viaSocks.ip` was the node's |
| Kill switch with no session (rc2 runtime, 2026-11-15) | observed | setting `persist` did not block the internet; `restore-network`, `set on` (the same setting as `persist`), a service restart and `set off` all left it direct. As designed: with no session, no mode blocks (read from the daemon's source, not checked against rc2's exact build). The blocked case (a session that dropped under the kill switch) was not run on Linux |
| 5. WireGuard, OpenVPN, V2Ray | **proven** on rc2 (2026-11-16) | own IP before; the node's IP after; back to direct after `disconnect`; session and deposit on chain for each |
| Failure paths: no `--yes`, bad flags, too-dear node, missing key file | **proven** on rc2 | exit 2 / 3 / 1 (`preflight`) / 1 (`no-wallet`) as documented; nothing spent |
| Split tunnel (exclude one address) + SOCKS only | **proven** on rc2 | excluded address went direct, everything else via the node; SOCKS carried only what was sent to it |
| 5. AmneziaWG, Xray, Hysteria2 | **proven** on rc2 (2026-11-15) | AmneziaWG was missing on the new install: `daemon repair-drivers --yes` added it (about 1.5 minutes). After `device setup --allowance N --yes` raised the limit: AmneziaWG and Hysteria2 gave the node's IP; Xray gave a local SOCKS proxy whose exit was the node, while plain traffic stayed direct; back to direct after each `disconnect`. With these, all six protocols on Linux rc2 |
| Deposit above the spending limit | **known gap** on rc2 | as on Windows: `connect` refuses before paying (`preflight`), nothing signed. A limit exactly equal to the deposit is accepted and used up by it; the next deposit is refused again, with no next step |
| Per hour, plans, split tunnelling, kill switch, drivers | partly | proven on earlier builds; kill switch across a reboot proven on rc2 |

The install line on the Linux release page was corrected on 2026-11-15 to start with
`sudo apt-get update`, matching `AGENTS.md`.

Known limits: killing the OpenVPN or Hysteria2 process lifts the kill switch; "allow LAN" does not
cover IPv6. Neither is in the main agent path.

## Windows

| step | status | how |
|---|---|---|
| 1. Silent install `Setup.exe /S` | **proven** on rc2 (2026-11-15) | a fresh install of rc2 after a full uninstall on a used Windows 11 Pro x64 machine (not a fresh OS image), over SSH as a local administrator: exit code 0 in 19 s. Earlier builds: clean Windows Server 2022 and Windows 11, x64 and ARM64 |
| 1. The download, checksum and install lines in `AGENTS.md`, exactly as written | **proven** on rc2 (2026-11-15) | the hash check printed True; `Start-Process … -Wait` returned exit code 0 |
| 1. `devnet-dvpn` on PATH | **proven** on rc2 (2026-11-15) | not on PATH in the shell that ran the installer (as the page says), on PATH in every new SSH session. The page's `$env:Path += …` line for the installing shell: parse-checked, not run |
| 2. `wallet create --keyfile` over SSH | **proven** on rc2 (2026-11-15) | |
| 4. `daemon init` → `device setup` | **proven** on rc2 (2026-11-15) | over SSH as an administrator, no prompt |
| 4. `daemon install` | **partly**: rc2 bug, with a proven workaround | on a machine not joined to a domain it fails: "There is no such global user or group: WORKGROUP\…". Over SSH, Windows sets `USERDOMAIN` to `WORKGROUP` there. With `$env:USERDOMAIN = $env:COMPUTERNAME` first, in the same shell, it exits 0 (`"relogin": false`) and the service runs. Reported; the fix is not released |
| 4. As a standard (non-admin) user | limit | install and `daemon install` each need one UAC prompt, which an agent cannot answer |
| 5. `connect` (WireGuard, per GB), `quality ip` | **proven** on rc2 (2026-11-15) | in a new SSH session after the install: the public IP changed to the node's while connected and came back after `disconnect`. A node asking 50 tDVPN per GB was refused for a wallet holding 20 ("Not enough tDVPN"): check `cost` first |
| 5. V2Ray on a new rc2 install: whole computer | **seen** on rc2 (2026-11-16) | `"wholeDevice": true` by default: `direct.ip` was the node's during the session and the machine's own again after `disconnect` |
| 5. All six protocols, per GB and per hour; exit IP = node | proven (earlier builds) | x64 and ARM64. v0.3.0-rc2 has no ARM64 build, so on rc2 Windows is x64 only |
| 5. Plan: `plans subscribe` | proven (earlier builds) | connecting on a plan ticket has not been run on Windows (proven on Linux; it is a chain-side path) |
| Split tunnelling (apps and addresses), kill switch (on, persist, service killed, reboot), allow LAN | proven (earlier builds) | kill switch across a reboot also proven on rc2-era code |
| 6. `disconnect`, `settle run` | **proven** on rc2 (2026-11-15) | the deposit moved to closing |
| 6. Final refund (`settle run` after 2 h, `settle withdraw`) | **proven** on rc2 (2026-11-15) | after the two-hour close, `settle run --yes` closed the deposit and the unused deposit came back to the wallet in full; `settle withdraw --yes` then had nothing left to move ("Nothing to withdraw" is a normal answer). Run from another machine holding the wallet's key file, with `settle run --device <device> --yes`: closing a deposit is signed by the wallet owner, so it worked after the device's permission had been removed, with no new device setup |
| 5. SSH over a full tunnel | **proven** on rc2 (2026-11-15, WireGuard) | the SSH session survived the connect; other protocols not run |
| 5. All six protocols | **proven** on rc2 (2026-11-15) | WireGuard, AmneziaWG, OpenVPN, V2Ray, Xray, Hysteria2: the node's IP during each session, the machine's own after, the SSH session stayed up, each deposit settled |
| Kill switch with a live session | **proven** on rc2 (2026-11-15) | tunnel cut on purpose: no sample showed the machine's own IP until `daemon restore-network`; direct within seconds of it; stayed direct after `--kill-switch off` and a service restart |
| Kill switch after the session dropped | **seen** on rc2 | `status` said not connected while the block was still on; `quality ip` showed no address (the page says so since update 6) |
| Split tunnel + SOCKS only | **proven** on rc2 | excluded address direct, everything else via the node; with whole computer off, SOCKS = node, plain traffic = own IP; proxy off after `disconnect` |
| Failure paths: no `--yes`, bad basis, no node, too-dear node, no wallet, unfunded | **proven** on rc2 | documented codes; nothing spent |
| A connect with the service stopped | **seen** on rc2 | not a refusal: the CLI starts the service and connects |
| Deposit above the spending limit | **known gap** on rc2 | `connect` refuses before paying (`preflight`, "spending approval is lower than this deposit"); it does not raise the limit itself. `device setup --allowance N --yes` raised it (one transaction, plus a small SOL top-up for the device); a refund does not give the approval back |
| Shortcut: `agent` commands | not run | no Windows result yet |

Known limit on rc2: updating from 0.2.1 by running the installer from PowerShell 7 can leave the
service stopped. This is fixed after rc2. A fresh install is not affected.

## macOS

All macOS runs are on the **Intel (x64)** build.

| step | status | how |
|---|---|---|
| 1. No-click install from the `.dmg` (`hdiutil` + `ditto`) | proven (0.3.0-rc.1, 2026-11-12) | the CLI runs from inside the app until `daemon install` puts it on PATH |
| 1. The download-and-checksum lines, the install lines and the `export PATH=…` line in `AGENTS.md`, exactly as written | proven (v0.3.0-rc2, 2026-11-15) | Intel Mac, macOS 14: `curl` of the `.dmg` and `SHA256SUMS`, `shasum` printed OK, `hdiutil` + `ditto`, then the PATH line in both `sh` and `zsh` |
| 1. `version` on a fresh machine | proven (rc.1; rc2 2026-11-15) | rc2 reports `"app":"0.3.0-rc.2"`, `"network":"devnet"` |
| 1. `status` on a fresh machine | proven (rc.1) | |
| 2. `wallet create --keyfile`, `wallet show`, `DVPN_KEYFILE` everywhere | proven (rc.1 and rc2; rc2 lines as written 2026-11-15) | a key-file wallet never touches the Keychain |
| 3. Funding by `wallet send` | proven (rc.1) | |
| 4. `daemon init` → `device setup` → `daemon install` with no prompt | proven (rc.1) | needs passwordless `sudo`; otherwise macOS shows a password dialog that only a person at the screen can answer |
| 4. `daemon doctor` | partly | no failures, but as a normal user some rows say "warn" by design |
| 5. `connect` per GB, exit IP = node | proven (rc.1, and rc2 as an upgrade, 2026-11-14) | WireGuard |
| 5. All six protocols per GB | proven (earlier build) | |
| 5. V2Ray on a new rc2 install: whole computer | **seen** on rc2 (2026-11-16) | `"wholeDevice": true` by default: `direct.ip` and `viaSocks.ip` both the node's; no system proxy. `daemon set --whole-device false --yes` gives the proxy-only mode |
| 5. V2Ray / Xray SOCKS proxy (whole computer off) | proven (earlier build) | only traffic sent to the proxy exits at the node |
| 5. `quality ip` showing the SOCKS exit IP | partly | in the shared code; no macOS log of that line |
| 6. `disconnect`, `settle run`, `settle list`, `settle withdraw` | proven (rc.1 and earlier) | nothing left behind after disconnect |
| 5. WireGuard, OpenVPN | **proven** on rc2 (2026-11-15) | the node's IP during the session, own IP after |
| 5. AmneziaWG, Xray, Hysteria2 | **proven** on rc2 (2026-11-15) | after `device setup --allowance N --yes` raised the limit (one transaction, plus a small SOL top-up for the device): the node's IP during each session, own IP after; Xray also gave a local SOCKS proxy, and with whole computer on, plain traffic used the node too |
| Split tunnel (exclude one address) | **proven** on rc2, with a gap | passed. First try failed: after a `daemon set` run with `sudo`, the user's own `daemon set` hits "permission denied" on its settings file, with no code or next step |
| Deposit above the spending limit | **known gap** on rc2 | as on Windows: `connect` refuses before paying (`preflight`), nothing signed, limit and SOL unchanged |
| Deposits of this computer's device | **known gap** on rc2 | `settle list --device <this computer's device>` refuses ("leave out --device"), so that check works only after a revoke |
| Per hour, plans, split by address and by app, whole device, kill switch on and persist (across reboots on rc2), allow LAN | proven (earlier builds; persist on rc2) | |

Not proven: the **Apple silicon** build (built and signed, never run). Steps 3 to 6 on rc2 from
this page's exact lines (proven on rc.1 and as an rc2 upgrade). After an update, opening the app
(not the CLI) asks for the Keychain password once.

## Android

An agent cannot use the released Android app this way. Its command line runs inside the app. Only
test (debug) builds expose it outside the app, and a release build never accepts a key file.
Every command was proven on phones and emulators through a test build in October 2026: connect on
all six protocols, kill switch, split tunnelling and refunds. Upgrading the public 0.1.4 to rc2
keeps the wallet and settings. That shows the commands work, not that an agent can reach them.

## Checks on the page itself

- **Command names:** every `devnet-dvpn` command and flag on `AGENTS.md` is checked by a script
  against the CLI's own command reference. It passes (2026-11-15).
- **PowerShell lines:** parsed, not run: 0 errors in Windows PowerShell 5.1 and PowerShell 7.
- **Shell (sh) lines:** the Linux and macOS install blocks were run as written (Ubuntu 24.04 and
  an Intel Mac, 2026-11-15); a `bash -n` pass over every other block is scheduled. Parsing is not
  running: a line can parse and still fail on a real machine.

## Not covered anywhere yet

- A fresh AI agent with only `AGENTS.md` connecting on Windows or macOS (on Windows one got out of a blocking kill
  switch but did not connect, see "Fresh AI agents"; on Linux one did, see above).
- The kill-switch recovery after a session that had already dropped (`quality ip` shows no
  address → `daemon restore-network`, then `daemon set --kill-switch off --yes`): proven on
  Windows and on Linux rc.4; not run on macOS.
- The `agent up / down / status` commands on v0.3.0-rc4 on macOS (Linux and Windows: see "Agent path on v0.3.0-rc4").
- Fixed in v0.3.0-rc4 on all three OSes, not yet re-run on it (rows flip once they have): a plain `connect` above
  the spending limit now raises it like `agent up`; `agent up` picks among the cheapest nodes, not the fastest;
  an empty `--plan` is refused; a node that stopped serving is reported (`server-stopped`) and skipped for 10 minutes.
- Unchanged in v0.3.0-rc4: reconnecting to a node whose deposit is still open needs one more deposit's worth in
  the wallet, or the funds check refuses it (nothing is paid).
- Known gaps on rc2: a plain `connect` above the spending
  limit refuses and does not raise it (`agent up` does); after a `sudo daemon set` on macOS, the
  user's own `daemon set` can hit "permission denied"; `settle list --device` refuses this
  computer's own device; on Linux, macOS and Android rc2, turning off automatic device permission does
  not stick, and neither does a revoke's write (fixed in rc.3).
- Known gaps in v0.3.0-rc3.1 and v0.3.0-rc4, to be fixed in a later release: a device replaced by `device switch` keeps about
  0.05 SOL of fee SOL; it can't be sent back until the next build. A failure in the middle of a `device switch`
  is covered by unit tests only, not by a live run. Repeated device setups can leave a token approval larger than
  the limit you set, and lowering the limit doesn't reduce it yet.
- The MCP server making a paid connection: its unit tests pass and a live check against real devnet nodes passed on Linux (2026-11-15, read-only tools and previews only).
