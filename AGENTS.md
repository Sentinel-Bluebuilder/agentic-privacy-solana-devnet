# Agentic Privacy — Solana devnet

**For AI agents.** This page gets you from nothing to a private connection through a Sentinel
dVPN node on Solana devnet. No account, no API key, nothing hosted by us: you hold a key, you pay
the node directly, you connect.

Terms are defined in [`GLOSSARY.md`](GLOSSARY.md), one line each with the command that shows or changes it.

You use one program, `devnet-dvpn`, the command line of the released Sentinel dVPN apps, the
same on Windows, Linux and macOS. (The Android app cannot be driven from outside the app, so
this page does not cover it.)

Rules of the tool:
- Add `--json` to any command for one line of machine-readable output.
- A command that spends money or changes the system does nothing without `--yes`; without it, it
  only prints what it would do (exit code `2`).
- Exit codes: `0` ok · `1` error · `2` needs `--yes` · `3` wrong usage · `4` needs you or your operator
  (`not-funded`, `spending-limit`, `price-cap`, `no-wallet`; nothing was paid) · `5` refused for safety (kill
  switch; read `action`) · `6` network or RPC, no deposit open (retry in a minute). Other network codes exit `1`:
  read `money`.
- Every amount has a twin in base units: `sol` → `solLamports`, `tdvpn` → `tdvpnBase`, `held` → `heldBase`,
  `spent` → `spentBase`, `refundable` → `refundableBase`, `deposit.tdvpn` → `deposit.tdvpnBase`.
- A failure prints `{"ok":false,"error":…,"code":…,"action":…,"money":…}`: `action` is what to run next; `money` says whether money moved.
- Replace every `<…>` (`<ADDRESS>`, `<node>`) with a real value before running a line.

> **Two paths. Pick one.** Both use the same chain, the same nodes and the same tDVPN.
>
> | | Path A: the app (this page) | Path B: Sentinel's own tools, no app |
> |---|---|---|
> | Runs on | Windows, Linux, macOS | Linux (x86_64, arm64) with systemd and `sudo`; proven on Ubuntu 24.04 x86_64 |
> | You install | the Devnet dVPN app (`devnet-dvpn`) | `sentinel-dvpnd` + `sentinel-dvpn`, Sentinel's public tools |
> | First command | after install: `devnet-dvpn agent status --json` | `git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet && cd agentic-privacy-solana-devnet && sudo sh direct/install.sh` |
> | Then | follow `next` in each answer | `sh direct/fund-request.sh` → `sh direct/connect.sh` → `sh direct/disconnect.sh` → `sh direct/refund.sh` |
> | Read | this page, from "Quick path" | [`docs/DIRECT.md`](docs/DIRECT.md) |
>
> Your own code instead of a CLI: [`docs/BUILD-YOUR-OWN-CLIENT.md`](docs/BUILD-YOUR-OWN-CLIENT.md).

> **Release: `v0.3.0-rc6`** on Windows and Linux (GitHub marks it "Latest"); macOS: `v0.3.0-rc4`. The same
> command line on all three. Pin the tag by name, as the lines below do: on macOS the release GitHub marks
> "Latest" is an older one that cannot make a key file. The download line per OS:
> - Linux: `curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | DVPN_VERSION=v0.3.0-rc6 sh`
> - macOS: section 1, "By hand" (`…/releases/download/v0.3.0-rc4`: rc6 for macOS is not published yet; on rc4 read the rc4 list in `docs/OLDER-RELEASES.md`).
> - Windows (elevated PowerShell): `$env:DVPN_VERSION = 'v0.3.0-rc6'; irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex`
>
> Done when `devnet-dvpn version --json` says `0.3.0-rc.6`, network `devnet`, `programId`
> `J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs` and `mint` `Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa`;
> any other `programId` or `mint`: stop, wrong build, pay nothing. (macOS: `0.3.0-rc.4`, which prints no
> `programId` / `mint`.) Another release
> installed: [`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md). What is proven, per OS and
> release: [`docs/PROOF.md`](docs/PROOF.md). Every field and failure code of the three `agent`
> commands: [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md); as a JSON Schema:
> [`docs/agent-answers.schema.json`](docs/agent-answers.schema.json).

> **Safety: five rules.**
> 1. Always pass `--max-price` to `agent up`: on devnet many nodes ask 50 tDVPN per GB.
> 2. Over SSH from the internet, never turn the kill switch on without another way in: it can lock you out for good.
> 3. `--yes` spends money or changes the system. Without it nothing is signed (exit `2`).
> 4. Had a wallet before? Never `wallet create`: load its key file, or `wallet import <file>`.
> 5. `agent up` never raises this computer's spending limit by itself: it refuses (`spending-limit`, nothing paid) and `action` is the same line with `--raise-limit --yes`.

---

## Quick path

Linux and macOS (root or passwordless `sudo`):

```sh
curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | DVPN_VERSION=v0.3.0-rc6 sh   # Linux; macOS: section 1, By hand
export DVPN_KEYFILE="$PWD/agent-key.json"
devnet-dvpn agent status --json                               # "next" says what is missing
devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json
#   → send your operator the message in section 3; go on when its "done when" check passes
devnet-dvpn daemon init
devnet-dvpn device setup --yes
devnet-dvpn daemon install --yes                              # once; root / passwordless sudo
devnet-dvpn quality ip --json                                 # BEFORE: your own IP
devnet-dvpn agent up --protocol wireguard --basis per_gb --max-price 0.01 --yes --json   # picks, pays, connects
devnet-dvpn quality ip --json                                 # AFTER: direct.ip is now the node's
devnet-dvpn agent down --yes --json                           # disconnects and starts the refund
```

Without `--max-price`, `agent up` picks the fastest of the cheapest nodes (a deposit at most 2 times the cheapest one's) and never pays a deposit above 5 tDVPN (the spending limit / 10; `price-cap`, nothing paid). On devnet many nodes ask 50 tDVPN per GB, so `--max-price 0.01` sets your own cap. On `no-nodes`, raise it.

macOS: the installer prints one `export PATH=…` line; run it before the next line.

Windows (an **elevated** PowerShell, or SSH as an administrator):

```powershell
$env:DVPN_VERSION = 'v0.3.0-rc6'
irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex
$env:DVPN_KEYFILE = "$PWD\agent-key.json"
devnet-dvpn agent status --json
devnet-dvpn wallet create --keyfile $env:DVPN_KEYFILE --yes --json
#   then section 3 (funding), then:
devnet-dvpn daemon init
devnet-dvpn device setup --yes
devnet-dvpn daemon install --yes
devnet-dvpn quality ip --json
devnet-dvpn agent up --protocol wireguard --basis per_gb --max-price 0.01 --yes --json
devnet-dvpn quality ip --json
devnet-dvpn agent down --yes --json
```

Each answer of `agent status` / `agent up` / `agent down` carries `next` (the command to run
next) or, on failure, `action`. Follow it. The sections below explain each line.

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
curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | DVPN_VERSION=v0.3.0-rc6 sh
```

To read it before it runs:

```sh
curl -fsSLO https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh
DVPN_VERSION=v0.3.0-rc6 sh install.sh
```

Windows (x64), elevated PowerShell:

```powershell
$env:DVPN_VERSION = 'v0.3.0-rc6'
irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex
```

To read it first: `curl.exe -fsSLO <that URL>`, then
`Set-ExecutionPolicy -Scope Process Bypass -Force; . .\install.ps1` (this process only).

What the installer does: takes the release `DVPN_VERSION` names (without it: the newest
release with your package, which may not be the one this page is for), downloads it and the
release's `SHA256SUMS`, refuses a file that does not match, installs it with no questions, and
runs `devnet-dvpn version --json`. It prints one JSON line:
`{"ok":true,"tag":…,"file":…,"version":{…},"path":…,"next":…}`, or `{"ok":false,"error":…}`
with exit code 1. `tag` must be `v0.3.0-rc6`.

PATH afterwards:
- Linux: `devnet-dvpn` is on PATH at once.
- Windows: the installer sets it in your shell (and in every new shell).
- macOS: a script cannot change your shell's PATH. Run the line it prints, in every new shell
  until `daemon install` has run:
  `export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"`.

### By hand

The same steps, one release. File names carry the version with a dot, the tag without (tag
`v0.3.0-rc6` holds `…0.3.0-rc.6…`), so take the name from `SHA256SUMS`.

Linux, Debian / Ubuntu x64 (rpm: `\.x86_64\.rpm$` and `sudo dnf install -y`; Arch:
`-x64\.pkg\.tar\.zst$` and `sudo pacman -U --noconfirm`; arm64: `_arm64` / `aarch64`):

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/download/v0.3.0-rc6
curl -fsSLO "$U/SHA256SUMS"
F=$(awk '{print $2}' SHA256SUMS | grep -E '^devnet-dvpn_.*_amd64\.deb$')
curl -fsSLO "$U/$F"
grep " $F\$" SHA256SUMS | sha256sum -c -             # must print: <file name>: OK
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "./$F"
```

Without the update a fresh machine fails with "libsecret-tools … not installable"; without `-y`
the install waits for an answer you cannot give.

macOS (`x64` = Intel, `arm64` = Apple silicon):

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/download/v0.3.0-rc4
A=x64; [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && A=arm64
curl -fsSLO "$U/SHA256SUMS"
F=$(awk '{print $2}' SHA256SUMS | grep -E "^Devnet-dVPN-.*-$A\.dmg\$")
curl -fsSLO "$U/$F"
grep " $F\$" SHA256SUMS | shasum -a 256 -c -         # must print: <file name>: OK
M=$(hdiutil attach -nobrowse -readonly "./$F" | tail -1 | cut -f3-)
sudo -n ditto "$M/Devnet dVPN.app" "/Applications/Devnet dVPN.app"
hdiutil detach -quiet "$M"
export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"
```

An older app in `/Applications` goes first: `sudo -n rm -rf "/Applications/Devnet dVPN.app"`.

Windows x64, elevated PowerShell:

```powershell
$u = 'https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases/download/v0.3.0-rc6'
curl.exe -fsSLo SHA256SUMS "$u/SHA256SUMS"           # curl.exe, not curl (an alias in older PowerShell)
$l = Select-String -Path .\SHA256SUMS -Pattern 'Devnet-dVPN-Setup-.*-x64\.exe$' | Select-Object -First 1
$h, $f = ($l.Line -split '\s+')[0, 1]
curl.exe -fsSLo $f "$u/$f"
(Get-FileHash ".\$f" -Algorithm SHA256).Hash.ToLower() -eq $h   # must print True
$p = Start-Process -FilePath ".\$f" -ArgumentList '/S' -Wait -PassThru; $p.ExitCode      # 0 = installed
$env:Path += ";$env:ProgramFiles\Devnet dVPN\bin"     # this shell; new shells have it already
```

Use `Start-Process -Wait`: run directly, the installer returns at once. On Windows,
`daemon uninstall` refuses by design: remove the app in Settings > Apps.

Then, on every OS: `devnet-dvpn version --json` must say network devnet.

## 2. Make a key (once)

```sh
export DVPN_KEYFILE="$PWD/agent-key.json"
devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json    # prints your address
devnet-dvpn agent status --json                                       # address, sol, tdvpn, next
```

Windows: `$env:DVPN_KEYFILE = "$PWD\agent-key.json"`, then the same `wallet create` with
`$env:DVPN_KEYFILE`.

Already have a key file (your operator's, or one you used before)? Set `DVPN_KEYFILE` to its full
path, skip `wallet create`, and go to section 4. If `wallet show` says `"wallet":null` but you had
a wallet: find the key file and `wallet import <file>`; never `wallet create` (a new wallet can't
see the old refunds).

Use the full path: a relative one breaks when you change directory. `DVPN_KEYFILE` lives only in
the shell that set it: set it again in every new shell or SSH session (Windows, once for good:
`[Environment]::SetEnvironmentVariable('DVPN_KEYFILE', $env:DVPN_KEYFILE, 'User')`). The key
file is your money: never print it, never commit it.

Use one wallet per computer. With a second wallet's key file loaded, `agent up` / `connect` refuse
(code `wallet-switch-needed`, nothing paid): load the first key file again, or run
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

Minimum: about 0.06 SOL (`device setup` moves 0.05 to the device for its fees) and tDVPN = the
deposit of the node you pick (a per-GB node on devnet: about 0.002). 0.5 SOL and 100 tDVPN are
comfortable. Each open per-GB deposit also holds about 0.004 SOL until settled.

**Done when** (run it before section 4; `device setup` then moves 0.05 SOL away):

```sh
devnet-dvpn agent status --json
```

- `sol` is above `0.06`, and
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
  0.06 SOL, so a smaller airdrop is enough.
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
- Spending limit: a new device may spend up to 50 tDVPN from your wallet (a cap, not a charge).
  When a deposit is above it, `agent up --yes` pays nothing and answers `"code":"spending-limit"`
  (exit `4`); its `action` is your same line with `--raise-limit --yes`. Run that line to raise the
  limit for this connect (the answer then carries `limitRaised` and `limitNote`), or set your own:
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
`"code":"no-nodes"`: widen `--protocol` / `--country` / `--max-price`. `"code":"spending-limit"`: nothing was
paid; run the `action` (your line with `--raise-limit --yes`). `"code":"price-cap"`: no `--max-price` and the
deposit is above 5 tDVPN; nothing was paid; pass `--max-price` (the `action` names the price) or fewer `--units`. `price-changed`,
`deposit-unusable` or `deposits-unread`: nothing was paid; run `agent up --yes` again (it reads
the price fresh, and `--max-price` still caps it). Before picking a protocol,
check that `devnet-dvpn daemon drivers` shows it ready; when it asks for `repair-drivers` and only
AmneziaWG is missing (normal on a new Linux install), ignore it unless you pick an AmneziaWG node;
for one, run `devnet-dvpn daemon repair-drivers --yes` first (administrator, about 2 minutes). Driving this machine over SSH: read "Over SSH" before you connect.

## 6. Disconnect and get the unused deposit back

```sh
devnet-dvpn agent down --yes --json
```

It disconnects and starts closing every open deposit (stage 1 of 2). A per-hour deposit closes at once. A
per-GB one waits about two hours: when the answer has `readyAt`, come back after that time and
run what `next` says (`settle run --yes`, then `settle withdraw --yes`). You do not have to stay
online in between. `"code":"busy"`: the disconnect is done but another refund run held the lock;
run `settle run --yes` yourself.

That is the whole flow.

---

The shortcut failed and its `action` does not help? The single commands behind `agent up` /
`agent down` (`nodes list`, `cost`, `connect`, `disconnect`, `settle`) are in
[`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md), "Step by step"; they work on rc6 too.

---

## Choices

**Protocol:** WireGuard, AmneziaWG, OpenVPN, V2Ray, Xray, Hysteria2; a node serves one.
`agent up --protocol <name>`, or `nodes list --online --protocol <name> --json`.
`daemon drivers` lists the tools this machine has; `daemon repair-drivers --yes` adds the missing.

**Location:** `agent up --country DE` (the country the node reports).

**Pricing:**

| | how | notes |
|---|---|---|
| per GB | `agent up --basis per_gb --units <GB>` | unused deposit comes back |
| per hour | `agent up --basis per_hour --units <hours>` | `agent down` straight after, so it stops billing |
| plan | `plans list` → `plans subscribe <plan> --yes` → `agent up --plan <subscription>` | one price up front, no refund. An empty `--plan` value is refused (exit `3`) |

`daemon set` (below) needs administrator / root like `daemon install` and restarts the VPN
service: change settings **before** you connect.

**Split tunnelling:** `split status`;
`daemon set --split-mode exclude --split-routes 10.0.0.0/8 --yes`. To undo it, set both:
`daemon set --split-mode off --split-routes none --yes` (otherwise the routes stay; Windows /
macOS, if you set apps: add `--split-apps none`).

**Kill switch:** block the internet whenever the tunnel is not up.

```sh
devnet-dvpn daemon set --allow-lan true --yes        # first, if you reach this machine over its LAN
devnet-dvpn daemon set --kill-switch on --yes        # off | on | persist
```

In these apps the kill switch `on` and `persist` are the same setting. After `disconnect` / `agent
down`, check `devnet-dvpn quality ip` (`status` can say not connected while it blocks). If it shows no address, the kill switch is still blocking —
this happens when the session had already dropped before you disconnected. `devnet-dvpn daemon
restore-network` lifts the block for now; it can come back at the next dropped session or service
restart. `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back.

(`disconnect` with no session may still print "keeps the internet blocked until you reconnect":
reconnecting does not lift it for good; use the two commands above.)

To change node with the kill switch on, do not disconnect first: `agent up --node <other>
--yes` (or `connect <other node> --switch --yes`) switches in one step and the block holds.

Per-OS details: [`docs/agent-safety.md`](docs/agent-safety.md).

## Over SSH

On Linux a full-tunnel connect does not cut your SSH session (proven with WireGuard). On Windows,
WireGuard over SSH was shown on an older release (v0.3.0-rc2). Not shown: other protocols, macOS, and a whole-computer
V2Ray / Xray session on Windows or macOS: keep a second way in. The kill switch blocks everything that is not the tunnel, which can include your SSH
session: reaching the machine over its LAN, set `--allow-lan true` first; reaching it from the
internet, do not turn the kill switch on without another way in. A Windows cloud machine with
the kill switch on `persist` was once locked out after a restart and had to be deleted.

## If something fails

```sh
devnet-dvpn agent status --json
devnet-dvpn daemon doctor --json
devnet-dvpn logs --lines 80
devnet-dvpn daemon restore-network        # if you lost the network
```

`"code":"clock-skew"`: this computer's clock is off (the error says by about how much); set it right,
then `agent up --yes` again. Nothing was paid.

`agent status` says `"blocked": true` (no session, the internet blocked to protect you): `agent up --yes`
reconnects with protection on, or `devnet-dvpn daemon restore-network` goes direct (protection off until
the next connect).

The node stopped serving mid-session: `agent status` answers `"connected":false`, `"code":"server-stopped"` (your traffic is not going through it; the deposit is safe). `next` (`agent up --yes`) connects to another node and skips that one for 10 minutes; `alsoNext` (`agent down --yes`) closes the deposit and refunds the unused part after the wait it prints. With the kill switch also holding the block (`"blocked": true`), `next` is `devnet-dvpn daemon restore-network` (run it first) and `alsoNext` names the step after it: `agent up --yes` to reconnect or `agent down --yes` to close the deposit. A node that refused after you paid: `"code":"node-refused"`; run `agent down --yes` (it closes that deposit), not `agent up`, which would open a second one. A connect that fails with no known cause says whether a deposit was paid: `node-refused` (the deposit is safe and refunded after the wait) or `unknown` ("Nothing was paid"; read `devnet-dvpn logs --lines 80`, then try `agent up --yes` once more). For a few seconds after a node stops, `agent status` can still say `connected`: if `exitIp` equals your direct address, you are not tunnelled.

Every command: [Linux](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/blob/main/docs/CLI.md) · [Windows](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/blob/main/docs/CLI.md) · [macOS](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/blob/main/docs/CLI.md).
MCP clients, after sections 1 to 4: [`mcp/README.md`](mcp/README.md).

## Appendix: JSON you will read

Every answer of the three `agent` commands, as a JSON Schema (draft 2020-12):
[`docs/agent-answers.schema.json`](docs/agent-answers.schema.json). Field by field:
[`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md).

`agent status --json`: `address`, `sol`, `tdvpn`, `held` (decimal strings; `held` is the balance
`settle withdraw` moves, not the deposits still open), `device`, `service`, `connected`, and when
connected `session`, `node`, `protocol`, `spent`, `exitIp`, `socks`, `wholeDevice`; `deposits`
when the wallet has open or closing ones; `blocked` when the internet is blocked with no session;
always `next`.

`wallet show --json` (used by the single commands) reads the same wallet with other names and
other units:

| `agent status` | `wallet show` | How to compare |
|---|---|---|
| `address` | `owner` | the same address |
| `sol` | `ownerLamports` | a number in base units: `sol` = `ownerLamports` / 1000000000 |
| `tdvpn` | `ownerTdvpn` | base units, a string: `tdvpn` = `ownerTdvpn` / 1000000 (100 tDVPN = `"100000000"`) |
| `held` | `userBalance` | base units: `held` = `userBalance` / 1000000 |
| `device` | `device` | the same device key |
| `deposits` (one row each) | `userOpenChannels` (a count) | the count of open deposits |
| (none; `next` names what is missing) | `ready` | true when the spending permission, the approval and the device SOL are all in place |
| (none) | `delegated`, `deviceLamports`, `grant.allowance` | approval, device SOL and spending limit, in base units (`device show --json` shows `grant.allowance` too) |
