# Agentic Privacy — Solana devnet

**For AI agents.** This page gets you from nothing to a private connection through a Sentinel
dVPN node on Solana devnet. No account, no API key, no server of ours: you hold a key, you pay
the node directly, you connect.

You use one program, `devnet-dvpn`, the command line of the released Sentinel dVPN apps, the
same on Windows, Linux and macOS. (The Android app cannot be driven from outside the app, so
this page does not cover it.)

Rules of the tool:
- Add `--json` to any command for one line of machine-readable output.
- A command that spends money or changes the system does nothing without `--yes`; without it, it
  only prints what it would do (exit code `2`).
- Exit codes: `0` ok · `1` error · `2` needs `--yes` · `3` wrong usage.
- A failure prints `{"ok":false,"error":…,"code":…,"action":…}`: `action` is what to run next.
- Replace every `<…>` (`<ADDRESS>`, `<node>`) with a real value before running a line.

> **Release:** this page is for **v0.3.0-rc3.1 or newer** on Windows; Linux and macOS: **`v0.3.0-rc3`** (no rc.3.1 there; the lines marked rc.3 apply), a pre-release: the release GitHub marks
> "Latest" is an older one that cannot make a key file, so take the tag by name. On v0.3.0-rc2 the `agent` commands do
> not exist (exit `3`, "unknown command: agent"): use "Step by step" below. What is proven, per OS
> and release: [`docs/PROOF.md`](docs/PROOF.md). Every command, field and failure code of the
> three `agent` commands: [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md).

---

## Quick path

Linux and macOS (root or passwordless `sudo`):

```sh
curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | sh   # Linux; macOS: section 1, By hand
export DVPN_KEYFILE="$PWD/agent-key.json"
devnet-dvpn agent status --json                               # "next" says what is missing
devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json
#   → send your operator the message in section 3; wait until agent status shows sol and tdvpn above 0
devnet-dvpn daemon init
devnet-dvpn device setup --yes
devnet-dvpn daemon install --yes                              # once; root / passwordless sudo
devnet-dvpn quality ip --json                                 # BEFORE: your own IP
devnet-dvpn agent up --protocol wireguard --basis per_gb --max-price 0.01 --yes --json   # picks, pays, connects
devnet-dvpn quality ip --json                                 # AFTER: direct.ip is now the node's
devnet-dvpn agent down --yes --json                           # disconnects and starts the refund
```

Without `--max-price`, `agent up` picks the fastest of the cheapest servers (a deposit at most 2 times the cheapest one's); on devnet many servers ask 50 tDVPN per GB, so `--max-price 0.01` sets your own cap. On `no-nodes`, raise it. Linux / macOS (rc.3) pick by speed,
not price: always pass `--max-price` there.

macOS: the installer prints one `export PATH=…` line; run it before the next line.

Windows (an **elevated** PowerShell, or SSH as an administrator):

```powershell
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
curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | sh
```

To read it before it runs:

```sh
curl -fsSLO https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh
sh install.sh
```

Windows (x64), elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex
```

To read it first: `curl.exe -fsSLO <that URL>`, then
`Set-ExecutionPolicy -Scope Process Bypass -Force; . .\install.ps1` (this process only).

What the installer does: picks the newest release (v0.3.0-rc2 or newer) that has your package,
downloads it and the release's `SHA256SUMS`, refuses a file that does not match, installs it
with no questions, and runs `devnet-dvpn version --json`. It prints one JSON line:
`{"ok":true,"tag":…,"file":…,"version":{…},"path":…,"next":…}`, or `{"ok":false,"error":…}`
with exit code 1. Pin a release with `DVPN_VERSION=<tag>` (PowerShell: `$env:DVPN_VERSION`).

PATH afterwards:
- Linux: `devnet-dvpn` is on PATH at once.
- Windows: the installer sets it in your shell (and in every new shell).
- macOS: a script cannot change your shell's PATH. Run the line it prints, in every new shell
  until `daemon install` has run:
  `export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"`.

### By hand

The same steps, one release. File names carry the version with a dot, the tag without (tag
`v0.3.0-rc3.1` holds `…0.3.0-rc.3.1…`, `v0.3.0-rc3` holds `…0.3.0-rc.3…`), so take the name from `SHA256SUMS`.

Linux, Debian / Ubuntu x64 (rpm: `\.x86_64\.rpm$` and `sudo dnf install -y`; Arch:
`-x64\.pkg\.tar\.zst$` and `sudo pacman -U --noconfirm`; arm64: `_arm64` / `aarch64`):

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/download/v0.3.0-rc3
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
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/download/v0.3.0-rc3
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
$u = 'https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases/download/v0.3.0-rc3.1'
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
deposits stay refundable with its own key). A half-finished setup or switch:
`devnet-dvpn device discard-setup --yes`. Linux / macOS (rc.3) have neither command and do not refuse:
connecting can move this computer's device record to the second wallet, and the first wallet's deposits
then stop being listed (the money is safe on chain). If it happened, don't connect again; see the rc.3
release notes for the repair.

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
comfortable. Each open per-GB deposit also holds about 0.004 SOL until settled. Wait until
`agent status --json` shows `sol` and `tdvpn` above 0.

Faucet limits: **2 requests every 8 hours** each, shared by everyone on one network, and the
Sentinel faucet has a daily total. When it is spent, anyone with tDVPN can send some:
`devnet-dvpn wallet send --to <ADDRESS> --tdvpn 100 --yes`.

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
  `agent up` raises it itself (one more transaction), and so does `connect` on Windows (rc.3.1). Plain
  `connect` on Linux / macOS (rc.3) does not. If it says your spending approval is lower than this deposit: `devnet-dvpn device setup
  --allowance N --yes`, N = `grant.allowance` of `devnet-dvpn device show --json` (base units, /1e6)
  plus the deposit.
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
connected to a server that matches what you asked, it answers `"reused": true` and pays nothing;
asking for a different server switches in one step. Connecting again to a server whose deposit
is still open uses that deposit. Linux / macOS (rc.3): only while the wallet also holds one deposit's
worth; with less, the funds check refuses it and nothing is paid.

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
means the server it picked costs more than you hold: add `--max-price`, or fund more.
`"code":"no-nodes"`: widen `--protocol` / `--country` / `--max-price`. `price-changed`,
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

## Step by step (rc2, or if the shortcut fails)

The same flow with the single commands (all of these are also in v0.3.0-rc2):

```sh
devnet-dvpn daemon drivers                                  # the protocol you pick must be ready
devnet-dvpn nodes list --online --protocol wireguard --sort price --limit 10 --json
devnet-dvpn cost <node> --basis per_gb --units 1 --json     # exact deposit before you pay
devnet-dvpn connect <node> --basis per_gb --units 1 --yes --json
devnet-dvpn quality ip --json
devnet-dvpn disconnect
devnet-dvpn settle run --yes                                # stage 1 of 2: start closing
devnet-dvpn settle list                                     # the ready time (about 2 h per GB)
devnet-dvpn settle run --yes                                # stage 2, after that time
devnet-dvpn settle withdraw --yes
```

In `settle list`, `refundable` smaller than the deposit is normal: the part used for traffic and
fees is not refunded.

Prices in `nodes list --json` are base units (`priceUnit` says so): `"50000000"` = 50 tDVPN.
On devnet many nodes ask about 50 tDVPN per GB and one faucet request gives 100: sort by price.

`disconnect` says the desktop app starts the refund when it is running; from the command line,
run the `settle` lines.

v0.3.0-rc2 on Windows only: on a machine not joined to a domain, `daemon install` fails with
"There is no such global user or group: WORKGROUP\…". Run `$env:USERDOMAIN = $env:COMPUTERNAME`
in the same shell first (`install.ps1` does it for rc2).

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
| plan | `plans list` → `plans subscribe <plan> --yes` → `agent up --plan <subscription>` | one price up front, no refund. An empty `--plan` value is refused (exit `3`); Linux / macOS (rc.3) pay a deposit instead: check the id is set |

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

In this app the kill switch `on` and `persist` are the same setting. After `disconnect` / `agent
down`, check `devnet-dvpn quality ip` (`status` can say not connected while it blocks). If it shows no address, the kill switch is still blocking —
this happens when the session had already dropped before you disconnected. `devnet-dvpn daemon
restore-network` lifts the block for now; it can come back at the next dropped session or service
restart. `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back.

(`disconnect` with no session may still print "keeps the internet blocked until you reconnect":
reconnecting does not lift it for good; use the two commands above.)

To change server with the kill switch on, do not disconnect first: `agent up --node <other>
--yes` (or `connect <other node> --switch --yes`) switches in one step and the block holds.

Per-OS details: [`docs/agent-safety.md`](docs/agent-safety.md).

## Over SSH

On Linux a full-tunnel connect does not cut your SSH session (proven with WireGuard). On Windows,
WireGuard over SSH was shown on rc2. Not shown: other protocols, macOS, and a whole-computer
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

Windows (rc.3.1): `"code":"clock-skew"`: this computer's clock is off (the error says by about how much); set it right,
then `agent up --yes` again. Nothing was paid.

Windows (rc.3.1): `agent status` says `"blocked": true` (no session, the internet blocked to protect you): `agent up --yes`
reconnects with protection on, or `devnet-dvpn daemon restore-network` goes direct (protection off until
the next connect).

The node stopped serving mid-session or refused after the deposit: `devnet-dvpn agent down --yes` closes the deposit (the unused part is refunded after the wait it prints), and `devnet-dvpn agent up --yes` opens a new one with another node. For a few seconds after a node stops, `agent status` can still say `connected` with your own address as `exitIp`: if `exitIp` equals your direct address, you are not tunnelled.

Every command: [Linux](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/blob/main/docs/CLI.md) · [Windows](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/blob/main/docs/CLI.md) · [macOS](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/blob/main/docs/CLI.md).
MCP clients, after sections 1 to 4: [`mcp/README.md`](mcp/README.md).

## Appendix: JSON you will read

`agent status --json`: `address`, `sol`, `tdvpn` (decimal strings), `refundable` (the balance
`settle withdraw` moves, not the deposits still open), `device`, `service`, `connected`, and when
connected `node`, `protocol`, `spent`, `exitIp`, `socks`; always `next`.

`wallet show --json` (step by step) names them differently: `owner`, `ownerLamports` (1 SOL =
1000000000), `ownerTdvpn` (base units, 100 tDVPN = `"100000000"`), `userBalance`, `ready`.
