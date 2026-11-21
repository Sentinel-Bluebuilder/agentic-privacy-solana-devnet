# Agentic Privacy — Solana devnet

> **Devnet only: test tokens with no value.**

**For AI agents.** This page gets you from nothing to a private connection through a Sentinel
dVPN node on Solana devnet. No account, no API key, nothing hosted by us: you hold a key, you pay
the node directly, you connect.

Terms are defined in [`GLOSSARY.md`](GLOSSARY.md), one line each with the command that shows or changes it.

You use one program, `devnet-dvpn`, the command line of the released Sentinel dVPN apps, the
same on Windows, Linux and macOS. (The Android app cannot be driven from outside the app, so
this page does not cover it.)

Rules of the tool:
- **`devnet-dvpn agent status --json` is the "where am I" call.** Run it first, and whenever you are unsure what
  state you are in: it changes nothing, and its `next` names the one step to run.
- Add `--json` to any command for one line of machine-readable output. rc7 only: a usage error (exit `3`) is plain stderr text (rc.8: JSON, `code: "usage"`).
- A command that spends money or changes the system does nothing without `--yes`; without it, it
  only prints what it would do (exit code `2`).
- Exit codes: `0` ok · `1` error · `2` needs `--yes` · `3` wrong usage · `4` needs you or your operator
  (`not-funded`, `spending-limit`, `price-cap`, `no-wallet`, `needs-admin`, `keyfile-missing`, `keyfile-unreadable`, `keyfile-mode`, `clock-skew`, `allowance-above-balance`, `insufficient-funds`; nothing was paid) · `5` refused for safety (kill
  switch, `bad-recipient`, `low-sol-after`; read `action`) · `6` network or RPC (money `unclear`: run `agent status` before you retry, in a minute; rc.9: exit `1` from `agent`). Other network codes exit `1`:
  read `money`.
- Every amount has a twin in base units: `sol` → `solLamports`, `tdvpn` → `tdvpnBase`, `held` → `heldBase`,
  `spent` → `spentBase`, `refundable` → `refundableBase`, `deposit.tdvpn` → `deposit.tdvpnBase`.
- A failure prints `{"ok":false,"error":…,"code":…,"action":…,"next":…,"money":…}`: `next` = `action`, the line to run; `docUrl` links its row in `docs/CODES.md`; `money` says whether money moved
  (a `wallet` / `device` / `settle` failure: "Nothing was sent or signed." when nothing was).
- Every `--json` answer of a step command (`wallet`, `device`, `settle`, `disconnect`, `daemon install`) carries a
  runnable `next` too; `settle run` adds `nextAfter` (Unix seconds: when the last closing deposit is ready).
- Replace every `<…>` (`<ADDRESS>`, `<node>`) with a real value before running a line.

> **Two paths. Pick one.** Both use the same chain, the same nodes and the same tDVPN.
>
> | | Path A: the app (this page) | Path B: Sentinel's own tools, no app |
> |---|---|---|
> | Runs on | Windows, Linux, macOS | **Linux only today** (x86_64, arm64, systemd + `sudo`; proven on Ubuntu 24.04 x86_64). macOS / Windows: use the app (Path A) |
> | You install | the Devnet dVPN app (`devnet-dvpn`) | `sentinel-dvpnd` + `sentinel-dvpn`, Sentinel's public tools |
> | Get it | download + verify against the release SHA256SUMS; source: [`docs/PROVENANCE.md`](docs/PROVENANCE.md) | download + verify, or build from source (`sh direct/build.sh`): [`docs/PROVENANCE.md`](docs/PROVENANCE.md) |
> | First command | after install: `devnet-dvpn agent status --json` | the three lines below |
> | Then | follow `next` in each answer | follow `next` in each answer (`disconnect.sh`, then `refund.sh --yes`) |
> | Read | this page, from "Quick path" | full steps: [`docs/DIRECT.md`](docs/DIRECT.md) |
>
> Path B, the first three lines (after the second, fund the address it prints: `sh direct/fund-request.sh` names the one message to send):
>
> ```sh
> git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet && cd agentic-privacy-solana-devnet
> sudo sh direct/install.sh    # downloads release direct-v1, checks it against direct/SHA256SUMS, sets up the key and daemon
> sh direct/connect.sh --yes   # connects; prints {"ok":true,"exitIp":...}
> ```
>
> Your own code instead of a CLI: [`docs/BUILD-YOUR-OWN-CLIENT.md`](docs/BUILD-YOUR-OWN-CLIENT.md).
> A script that drives the app: [`docs/examples/agent-loop.mjs`](docs/examples/agent-loop.mjs) (one Node file, no dependencies: checks programId + mint, follows `next`, never pays without `--yes`).

> **Release: `v0.3.0`** on Windows and Linux (GitHub marks it "Latest"); macOS: `v0.3.0` (Apple silicon; Intel
> Macs: `docs/OLDER-RELEASES.md`). The same command line on all three. Pin the tag by name, as the lines below do. v0.3.0 = the rc.9 files unchanged: the app says `0.3.0-rc.9`.
> The download line per OS:
> - Linux: `curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | DVPN_VERSION=v0.3.0 sh`
> - macOS: by hand, [`docs/INSTALL-BY-HAND.md`](docs/INSTALL-BY-HAND.md) (`…/releases/download/v0.3.0`, Apple silicon only).
> - Windows (elevated PowerShell): `$env:DVPN_VERSION = 'v0.3.0'; irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex`
>
> Done when `devnet-dvpn version --json` says `0.3.0-rc.9`, network `devnet`, `programId`
> `J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs` and `mint` `Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa`;
> any other `programId` or `mint`: stop, wrong build, pay nothing. Another release
> installed: [`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md). What is proven, per OS and
> release: [`docs/PROOF.md`](docs/PROOF.md). Every field and failure code of the three `agent`
> commands: [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md); as a JSON Schema:
> [`docs/agent-answers.schema.json`](docs/agent-answers.schema.json).

> **Safety: five rules.**
> 1. Always pass `--max-price` to `agent up`: on devnet many nodes ask 50 tDVPN per GB.
> 2. On a remote server, keep the kill switch off: one lost session locks you out for good (`kill-switch-remote`).
> 3. `--yes` spends money or changes the system. Without it nothing is signed (exit `2`).
> 4. Had a wallet before? Never `wallet create`: load its key file, or `wallet import <file>`.
> 5. `agent up` never raises this computer's spending limit by itself: it refuses (`spending-limit`, nothing paid) and `action` sets the limit to exactly that deposit (`device setup --allowance <deposit> --yes`), then runs your line pinned to the node it picked. `alsoNext` adds `--raise-limit` instead: that raises the limit to the Settings `allowanceTdvpn` (150 on a new install) and it stays there until lowered.
>
> **Give the agent its own small wallet.** A key file just for the agent (`devnet-dvpn wallet create --keyfile <new path> --yes`), not the one that holds your own funds; fund only what one task needs (one deposit, plus the SOL a new device needs: section 3). The spending limit (150 tDVPN on a new install) is its ceiling on this computer.
> After the task: `devnet-dvpn agent down --yes`, `devnet-dvpn settle withdraw --yes` once the refund is ready, then empty it: `devnet-dvpn wallet send --to <ADDRESS> --tdvpn <N> --sol <N> --yes` (`<ADDRESS>` = your own wallet; keep a little SOL back for that fee: from rc8, leaving under 0.01 SOL needs `--allow-empty`, else `low-sol-after`).

---

## Quick path

Linux and macOS (root or passwordless `sudo`):

```sh
curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | DVPN_VERSION=v0.3.0 sh   # Linux; macOS: docs/INSTALL-BY-HAND.md
devnet-dvpn agent status --json                               # where am I; "next" says what is missing
# only if agent status has no "address" (a key file already set stays as it is):
export DVPN_KEYFILE="$PWD/agent-key.json"
devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json
#   → send your operator the message in section 3; go on when its "done when" check passes
devnet-dvpn daemon init
devnet-dvpn device setup --yes
devnet-dvpn daemon install --yes                              # once; root / passwordless sudo
devnet-dvpn quality ip --json                                 # BEFORE: your own IP
devnet-dvpn agent up --protocol wireguard --basis per_gb --max-price 0.01 --yes --json   # picks, pays, connects
devnet-dvpn quality ip --json                                 # AFTER: direct.ip is now the node's
devnet-dvpn agent down --yes --json                           # disconnects and starts the refund
# the refund, 2 h later (its "next" names the exact time), then the withdraw:
#   devnet-dvpn settle run --yes --json
#   devnet-dvpn settle withdraw --yes --json
```

Without `--max-price`, `agent up` picks the fastest of the cheapest nodes (a deposit at most 2 times the cheapest one's) and never pays a deposit above its default cap ("Defaults" below; `price-cap`, nothing paid). On devnet many nodes ask 50 tDVPN per GB, so `--max-price 0.01` sets your own cap. On `no-nodes`, raise it.

Windows (an **elevated** PowerShell, or SSH as an administrator):

```powershell
$env:DVPN_VERSION = 'v0.3.0'
irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex
devnet-dvpn agent status --json
# only if agent status has no "address":
$env:DVPN_KEYFILE = "$HOME\agent-key.json"
devnet-dvpn wallet create --keyfile $env:DVPN_KEYFILE --yes --json
#   then section 3 (funding), then:
devnet-dvpn daemon init
devnet-dvpn device setup --yes
devnet-dvpn daemon install --yes
devnet-dvpn quality ip --json
devnet-dvpn agent up --protocol wireguard --basis per_gb --max-price 0.01 --yes --json
devnet-dvpn quality ip --json
devnet-dvpn agent down --yes --json
# the refund, 2 h later (its "next" names the exact time), then the withdraw:
#   devnet-dvpn settle run --yes --json
#   devnet-dvpn settle withdraw --yes --json
```

Each answer of `agent status` / `agent up` / `agent down` carries `next` (the command to run
next) or, on failure, `action`. Follow it. The sections below explain each line.

Every step at a glance (amounts are today's devnet ones; the answers name the exact ones):

| Step | Does | Costs (who gets it) | Prints | Undo |
|---|---|---|---|---|
| install | installs the app, checked against `SHA256SUMS` | nothing on chain | `{"ok":true,"tag",…,"next"}` | remove the app (Windows: Settings > Apps) |
| `wallet create` | makes your key file | nothing | `address` | none; to retire it, empty it (`wallet send`) |
| funding | an operator uses two faucets | free | `agent status`: `sol`, `tdvpn` | `wallet send` it back |
| `daemon init` | makes the device key, here only | nothing | the device key | not needed |
| `device setup --yes` | lets the device spend up to the spending limit | about 0.05 SOL to the device (yours) + a fee | `device`, `ready` | `device revoke --yes` (the SOL stays on the device) |
| `daemon install --yes` | installs the VPN service | nothing on chain | `daemon doctor --json` checks | `daemon uninstall --yes` (Windows: remove the app, Settings > Apps) |
| `agent up --yes` | picks a node, pays a deposit, connects | the deposit (the node gets only what you use) + about 0.0022 SOL rent for the deposit account (back when it is settled) + a fee | `connected`, `node`, `exitIp`, `deposit`, `next` | `agent down --yes` |
| `agent down --yes` | disconnects, starts closing deposits | a fee | `refundable`, `readyAt`, `next` | `agent up --yes` (a new deposit) |
| `settle run` / `settle withdraw --yes` | finishes the close, moves refunds to the wallet | a fee | `held` back to `tdvpn` | not needed |

---

## Before you start: can you be administrator / root?

Installing the app and the VPN service (`daemon install`) needs administrator / root once. If you
cannot get it, stop and tell your operator.
- Linux / macOS: `sudo -n true` must succeed, or run as root. Otherwise the system asks for a
  password in a prompt you cannot answer over SSH (macOS: a dialog only a person can answer).
- Windows: your shell must already be elevated (an elevated terminal, or SSH as an
  administrator). Otherwise Windows shows a UAC prompt you cannot answer.

In a sandbox where you cannot become administrator / root you cannot install the VPN service.

## 1. Install (once)

### One command

Linux (deb, rpm, Arch; x64 and arm64):

```sh
curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | DVPN_VERSION=v0.3.0 sh
```

To read it before it runs:

```sh
curl -fsSLO https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh
DVPN_VERSION=v0.3.0 sh install.sh
```

Windows (x64), elevated PowerShell:

```powershell
$env:DVPN_VERSION = 'v0.3.0'
irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex
```

To read it first: `curl.exe -fsSLO <that URL>`, then
`Set-ExecutionPolicy -Scope Process Bypass -Force; . .\install.ps1` (this process only).

What the installer does: takes the release `DVPN_VERSION` names (without it: the newest
release with your package, which may not be the one this page is for), downloads it and the
release's `SHA256SUMS`, refuses a file that does not match, installs it with no questions, and
runs `devnet-dvpn version --json`. It prints one JSON line:
`{"ok":true,"tag":…,"file":…,"version":{…},"path":…,"next":…}`, or `{"ok":false,"error":…}`
with exit code 1. `tag` must be `v0.3.0`.

PATH afterwards:
- Linux: `devnet-dvpn` is on PATH at once.
- Windows: this shell and every new SSH session; a desktop terminal opened before the install needs a new
  sign-in, or `& "$env:ProgramFiles\Devnet dVPN\bin\devnet-dvpn.cmd"`.
- macOS: a script cannot change your shell's PATH. Run the line it prints, in every new shell
  until `daemon install` has run:
  `export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"`.

### By hand

No installer script: download, check against `SHA256SUMS` and install yourself, per OS:
[`docs/INSTALL-BY-HAND.md`](docs/INSTALL-BY-HAND.md) (macOS: only there).

Then, on every OS: `devnet-dvpn version --json` must say network devnet.

## 2. Make a key (once)

First `devnet-dvpn agent status --json`. It already shows an `address`? You have a key: skip this section
(do not set `DVPN_KEYFILE` again over one that is set). Only with no `address`:

```sh
export DVPN_KEYFILE="$PWD/agent-key.json"
devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json    # prints your address
devnet-dvpn agent status --json                                       # address, sol, tdvpn, next
```

Windows: `$env:DVPN_KEYFILE = "$HOME\agent-key.json"` (an elevated shell may start in System32), then the same `wallet create` with
`$env:DVPN_KEYFILE`.

Already have a key file (your operator's, or one you used before)? Set `DVPN_KEYFILE` to its full
path, skip `wallet create`, run the section 3 "Done when" check, then section 4. If `wallet show` says `"wallet":null` but you had
a wallet: find the key file and `wallet import <file>`; never `wallet create` (a new wallet can't
see the old refunds).

Use the full path: a relative one breaks when you change directory. `DVPN_KEYFILE` lives only in
the shell that set it: set it again in every new shell or SSH session (Windows, once for good:
`[Environment]::SetEnvironmentVariable('DVPN_KEYFILE', $env:DVPN_KEYFILE, 'User')`). The key
file is your money: never print it, never commit it.

Use one wallet per computer. With a second wallet's key file loaded, commands refuse
(code `wallet-switch-needed`, nothing paid; a service restart does not help): load the first key file again, or run
`devnet-dvpn device switch --yes` to set this computer up for the loaded wallet (the first wallet's
deposits stay refundable with its own key; about 0.05 SOL of fee SOL stays on the old device, and no
command sends it back yet). A half-finished setup or switch: `devnet-dvpn device discard-setup --yes`.

## 3. Get funded (the one step that needs a human)

Your address needs two things, both free on devnet, from two web faucets a person uses.

| What | Why | Where | How much |
|---|---|---|---|
| **tDVPN** | what you pay nodes with | <https://faucet.sentinel.co> | one request = 100 tDVPN |
| **SOL** (devnet) | pays transaction fees | <https://faucet.solana.com> (linked from the Sentinel faucet page) | 0.5 SOL is plenty |

Send your operator exactly this, with your address (`address` in `agent status --json`):

> Please fund my Sentinel dVPN wallet on Solana **devnet**. It takes two minutes, costs nothing,
> and needs a GitHub account.
>
> My address: `<ADDRESS>`
>
> 1. **tDVPN for the VPN.** Open <https://faucet.sentinel.co>.
>    - Click **Connect GitHub** (in the "Connect your GitHub." box) first and approve. Do this
>      before pasting anything: the page
>      reloads on sign-in and an address typed earlier is lost.
>    - Back on the page (it shows "GitHub connected"), paste my address into
>      **Solana wallet address**.
>    - Click **Request 100 tDVPN**. Done when you see **"100 tDVPN received"**.
> 2. **SOL for fees.** On the same page, the "Claim Devnet Sol" card has **Open official faucet**
>    (it opens <https://faucet.solana.com>).
>    - Check the network says **devnet**, paste the same address into **Wallet Address**.
>    - Click **Amount**, choose **0.5**, then **Confirm Airdrop**.
>    - Complete the captcha in the **Cloudflare Verification** box. Done when **"Success!"**
>      appears.
>
> Tell me when you have seen "100 tDVPN received" and "Success!".
>
> What I am doing, what it costs and the one setup step I may need you for:
> https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/blob/main/docs/OPERATOR.md

Do not open the faucet pages yourself: they are for people. With the Solana CLI you may get the
SOL alone (`solana airdrop 1 <ADDRESS> --url devnet`; often rate-limited).

Minimum SOL: a **new device** needs its setup amount plus fees (today about 0.06 SOL: `device setup`
moves 0.05 to the device); a **device already set up** needs only fees. tDVPN: the deposit of the node you
pick (a per-GB node on devnet: about 0.002). When short, `not-funded` names the exact amounts, plus a recommended tDVPN amount that also covers a reconnect. 0.5 SOL and 100 tDVPN are
comfortable. Each open deposit also holds about 0.0022 SOL (its account rent) until settled.

**Done when** (run it before section 4; `device setup` then moves 0.05 SOL away):

```sh
devnet-dvpn agent status --json
```

- `sol` covers the step `next` names (a new device: its setup amount plus fees; set up already: fees only), and
- `tdvpn` is at least the deposit: `--max-price` times `--units` (the Quick path's
  `--max-price 0.01`, 1 GB: `0.01`). After section 4, `agent up` without `--yes` prints the
  exact deposit (`deposit.tdvpn`).

Not yet? Run the same line again in a minute (a faucet transfer can take one). Still `0` after
the operator saw "100 tDVPN received" and "Success!": check that the address they pasted is
exactly `address`.

Faucet limits: **2 requests every 8 hours** each, shared by everyone on one network, and the
Sentinel faucet has a daily total. When the operator sees a limit message:
- tDVPN: anyone with tDVPN can send some: `devnet-dvpn wallet send --to <ADDRESS> --tdvpn 100 --yes`.
  Otherwise wait for the time the faucet names (at most 8 hours), then ask again.
- SOL: try `solana airdrop 1 <ADDRESS> --url devnet`, or wait and ask again. You need only about
  the setup amount plus fees, so a smaller airdrop is enough.
- Tell your operator what is missing and when to try again; do not start section 4 before the
  check passes.

## 4. Set up the VPN service (once)

```sh
devnet-dvpn daemon init                 # creates the device key (local, no transaction)
devnet-dvpn device plan                 # what will be signed; spends nothing
devnet-dvpn device setup --yes          # one transaction: spending permission + fee SOL for the device
devnet-dvpn daemon install --yes        # installs and starts the VPN service (administrator / root)
devnet-dvpn daemon doctor --json        # no check may have "level": "fail"
```

In this order: the service does not start before the device has its spending permission.
- Spending limit: a new install may spend up to 150 tDVPN from your wallet (a cap, not a charge; an existing limit is kept).
  A wallet with less (rc9): `device setup --yes` sets the limit to the wallet's balance and says so in `warning`; raise it after funding with `device setup --allowance <N> --yes`.
  When a deposit is above it, `agent up --yes` pays nothing and answers `"code":"spending-limit"`
  (exit `4`); its `action` sets the limit to this deposit, then runs your line pinned to the node it picked; `alsoNext`, with `--raise-limit --yes`,
  raises it to the Settings limit (the answer then carries `limitRaised` and `limitNote`). Or set your own:
  `devnet-dvpn device setup --allowance N --yes`, N in tDVPN.
- `"service":"no-service"` in the `device setup` output means the service is not installed yet:
  normal at that step.
- Windows: `"relogin": true` from `daemon install` matters only for a non-elevated shell later,
  which needs a new sign-in or SSH session. `agent up` answering `"code":"daemon-relogin"` is the
  same thing.
- macOS: the service can report it is waiting for the network; run `daemon doctor` again after a
  few seconds. WireGuard, AmneziaWG and OpenVPN need Homebrew and `daemon repair-drivers --yes`;
  V2Ray, Xray and Hysteria2 come inside the app.

## 5. Connect

```sh
devnet-dvpn quality ip --json                                   # BEFORE: note direct.ip
devnet-dvpn agent up --protocol wireguard --basis per_gb --max-price 0.01 --yes --json   # picks, pays, connects
devnet-dvpn quality ip --json                                   # AFTER: prove the tunnel
```

`agent up` also takes `--country CC`, `--node N`, `--basis per_gb|per_hour`, `--units N`,
`--plan S`, `--max-price N` (per unit of the basis: pass `--basis` with it). Without `--yes` it
prints `{"needsConfirm":true,"what":…}` and signs nothing. It is safe to repeat: already
connected to a node that matches what you asked, it answers `"reused": true` and pays nothing;
asking for a different node switches in one step. Connecting again to a node whose deposit
is still open uses that deposit, but only while the wallet also holds one deposit's worth; with
less, the funds check refuses it and nothing is paid (add tDVPN, or `agent down --yes` and wait for the refund).

How to read the proof (`{ "direct": { "ip", "source" }, "viaSocks", "sourceIs" }`):
- WireGuard, AmneziaWG, OpenVPN, Hysteria2 route the whole machine: `direct.ip` is now the
  node's. Pick one of these when you need proof for the whole machine.
- V2Ray and Xray, Linux: only what you send to the local SOCKS proxy (`socks` in `agent status`)
  uses the node: `direct.ip` stays yours; the proof is `viaSocks.ip`.
- V2Ray and Xray, a new Windows or macOS install: the whole computer goes through the node
  (`"wholeDevice": true` in `daemon settings --json`), so `direct.ip` changes too. Proxy-only:
  `daemon set --whole-device false --yes`. There `agent up`'s `directIp` may show the node's
  address too, and `next` names only the SOCKS address: take your own IP from the BEFORE
  `quality ip --json`. For the simplest proof with the shortcut, pick WireGuard.

If `agent up` fails, it names `code` and `action`: run the action. `"code":"not-enough-tdvpn"`
means the node it picked costs more than you hold: add `--max-price`, or fund more.
`"code":"no-nodes"`: under `--max-price`, `action` names the cheapest price (run it if you accept it); else widen `--protocol` / `--country`. `"code":"spending-limit"`: nothing was
paid; run the `action` (it sets the limit to this deposit, then runs your line, pinned). `"code":"price-cap"`: no `--max-price` and the
deposit is above `defaults.priceCap`; nothing was paid; pass `--max-price` (the `action` names the price) or fewer `--units`. `price-changed`,
`deposit-unusable` or `deposits-unread`: nothing was paid; run `agent up --yes` again (it reads
the price fresh, and `--max-price` still caps it). Before picking a protocol,
check that `devnet-dvpn daemon drivers` shows it ready; when it asks for `repair-drivers` and only
AmneziaWG is missing (normal on a new Linux install), ignore it unless you pick an AmneziaWG node;
for one, run `devnet-dvpn daemon repair-drivers --yes` first (administrator, about 2 minutes). Driving this machine over SSH: read "Over SSH" before you connect.

## Defaults: what `agent up` picks when you pass no flag

From rc7 `agent up` sizes its defaults from the online nodes that match your request; every flag still wins, and your
spending limit stays the ceiling. Every preview and answer shows them in `defaults`.

- Price cap (no `--max-price`): the larger of the spending limit / 10 and the market p75 price (3 in 4
  matching nodes ask that or less) times `--units`, never above the spending limit. Above it: `price-cap`, nothing paid.
- Spending limit: 150 tDVPN on a new install; an existing limit is kept. `defaults.spendingLimitRecommended`
  is the market's suggestion: `devnet-dvpn settings set allowanceTdvpn=<n>` takes effect at the next raise
  (`--raise-limit`), or now with `devnet-dvpn device setup --allowance <n> --yes`.
- `no-nodes` under your `--max-price` names the cheapest matching price; `action` is a runnable line with it.
- Fewer than 3 priced nodes match: the fixed defaults apply (cap = spending limit / 10; `defaults.source` =
  `fixed`, `reason` says why).

## 6. Disconnect and get the unused deposit back

```sh
devnet-dvpn agent down --yes --json
```

It disconnects and starts closing every open deposit (stage 1 of 2). A per-hour deposit closes at once. A
per-GB one waits about two hours: when the answer has `readyAt`, come back after that time and
run what `next` says (`settle run --yes`, then `settle withdraw --yes`; a `settle run` answer with `nextAfter` set: run it again after that time). You do not have to stay
online in between. `"code":"busy"`: the disconnect is done but another refund run held the lock;
run `settle run --yes` yourself.

That is the whole flow.

---

The shortcut failed and its `action` does not help? The single commands behind `agent up` /
`agent down` (`nodes list`, `cost`, `connect`, `disconnect`, `settle`) are in
[`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md), "Step by step"; they work on rc7 and rc8 too.

---

## Choices

Protocol, country, pricing (per GB, per hour, plan), split tunnelling and the kill switch:
[`docs/CHOICES.md`](docs/CHOICES.md). Change `daemon set` settings **before** you connect.

## Over SSH

On Linux a full-tunnel connect does not cut your SSH session (proven with WireGuard). On Windows,
WireGuard over SSH was shown on an older release (v0.3.0-rc2). Not shown: other protocols, macOS, and a whole-computer
V2Ray / Xray session on Windows or macOS: keep a second way in. The kill switch blocks everything that is not the tunnel, which can include your SSH
session: reaching the machine over its LAN, set `--allow-lan true` first; reaching it from the
internet, do not turn the kill switch on without another way in (a locked-out cloud machine may have to be deleted).

## If something fails

```sh
devnet-dvpn agent status --json
devnet-dvpn daemon doctor --json
devnet-dvpn logs --lines 80
devnet-dvpn daemon restore-network        # if you lost the network
```

Every onboarding state (not installed → funded → set up → connected → refunded), with what you see and what to run: [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md#every-onboarding-state).

Every failure answer names `code`, `action` and `money`: run the `action`. Symptom by symptom (blocked
internet, a node that stopped, `node-refused`, `unknown`, `clock-skew`, …): [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md);
every code: [`docs/CODES.md`](docs/CODES.md). A deposit `open` with no session (`agent status` `deposits`): `agent down --yes` first, never `agent up`.

Every command: `docs/CLI.md` per OS, linked in [`docs/PROVENANCE.md`](docs/PROVENANCE.md) ("Source").
MCP clients, after sections 1 to 4: [`mcp/README.md`](mcp/README.md).

## Appendix: JSON you will read

Every answer as a JSON Schema: [`docs/agent-answers.schema.json`](docs/agent-answers.schema.json); field by field:
[`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md); `agent status` vs `wallet show` names: [`docs/JSON-FIELDS.md`](docs/JSON-FIELDS.md).
