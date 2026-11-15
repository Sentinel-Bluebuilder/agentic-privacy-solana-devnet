# Agentic Privacy — Solana devnet

**For AI agents.** This page gets you from nothing to a private connection through a Sentinel
dVPN node on Solana devnet. No account, no API key, no server of ours: you hold a key, you pay
the node directly, you connect.

You use one program, `devnet-dvpn`. It is the command line of the released Sentinel dVPN apps and
is the same on Windows, Linux and macOS. (The Android app has the same commands inside it, but a
released Android build cannot be driven from outside the app, so this page does not cover it.)

Rules of the tool:
- Add `--json` to any command for one line of machine-readable output.
- A command that spends money or changes the system does nothing without `--yes`; without it, it
  only prints what it would do (exit code `2`).
- Exit codes: `0` ok · `1` error · `2` needs `--yes` · `3` wrong usage.
- Secrets and RPC keys are never printed.
- Replace every `<…>` (`<ADDRESS>`, `<node>`, `<version>`) with a real value before running a line.

> Every `devnet-dvpn` command outside the "Shortcut" section exists in the released CLI (the CLI
> reference of each app: "If something fails"). What is proven on each OS, step by step: [`docs/PROOF.md`](docs/PROOF.md). Sections 1 to 6 were
> run end to end on a clean Ubuntu 24.04 with the public v0.3.0-rc2 package on 2026-11-15,
> including the refund. On Windows over SSH (rc2, same day), sections 1 to 6 passed, including
> the refund, with one workaround line for a known `daemon install` bug (see "Install: Windows").

---

## Quick path

Ten lines per OS. The sections below explain each line; read them the first time.

**Linux**
1. The install block in "Install: Linux" (curl, `sha256sum -c`, `apt-get install -y`)
2. `devnet-dvpn version --json` (must say network devnet)
3. `export DVPN_KEYFILE="$PWD/agent-key.json"` then `devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json`
4. Send your operator the message in section 3 with your address; run `devnet-dvpn wallet show --json` until both balances are above 0
5. `devnet-dvpn daemon init`, then `devnet-dvpn device setup --yes`
6. `devnet-dvpn daemon install --yes` (passwordless `sudo`, or as root)
7. `devnet-dvpn quality ip --json`, then `devnet-dvpn nodes list --online --json`
8. `devnet-dvpn connect <node> --basis per_gb --units 1 --yes --json`
9. `devnet-dvpn quality ip --json` (`direct.ip` changed; V2Ray / Xray: `viaSocks.ip`)
10. `devnet-dvpn disconnect`, `devnet-dvpn settle run --yes`; about 2 hours later `devnet-dvpn settle run --yes`, `devnet-dvpn settle withdraw --yes`

**Windows** (an elevated PowerShell)
1. The install block in "Install: Windows" (download, check, `Start-Process … /S -Wait`; exit code 0)
2. `$env:Path += ";$env:ProgramFiles\Devnet dVPN\bin"` (or open a new shell), then `devnet-dvpn version --json`
3. `$env:DVPN_KEYFILE = "$PWD\agent-key.json"` then `devnet-dvpn wallet create --keyfile $env:DVPN_KEYFILE --yes --json`
4. As Linux 4
5. As Linux 5
6. `devnet-dvpn daemon install --yes` (elevated; on a machine not in a domain, rc2 first needs `$env:USERDOMAIN = $env:COMPUTERNAME`, see "Install: Windows"; `"relogin": true` matters only for a non-elevated shell later, which needs a new sign-in or SSH session; in a new session set `$env:DVPN_KEYFILE` again)
7. to 10. As Linux 7 to 10

**macOS** (passwordless `sudo`)
1. The install block in "Install: macOS" (curl, `shasum -c`, `hdiutil`, `sudo -n ditto`)
2. `export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"`, then `devnet-dvpn version --json`
3. to 5. As Linux 3 to 5
6. `devnet-dvpn daemon install --yes` (`sudo -n`; otherwise a dialog that only a person can answer)
7. to 10. As Linux 7 to 10

---

## Before you start: can you be administrator / root?

Installing the app and the VPN service needs administrator / root once (section 1 and
`daemon install` in section 4). If you cannot answer that prompt, stop and tell your operator.
- Linux: with passwordless `sudo` the plain command works (the CLI calls `sudo -n` itself).
  Without it the system asks for a password in a prompt you cannot answer over SSH: run the
  command as root.
- Windows: no prompt only when your shell already runs elevated (an elevated terminal, or SSH as
  an administrator). Otherwise Windows shows one UAC prompt, which you cannot answer; with no
  desktop session the step fails.
- macOS: no prompt only when `sudo -n` works for your user; otherwise a password dialog opens
  that only a person at the screen can answer.

If you run in a sandbox where you cannot become administrator / root, you cannot install the VPN
service. Stop here and tell your operator.

**Install release `v0.3.0-rc2` (a pre-release) or newer, not the one GitHub marks "latest".**
The older stable releases (Windows v0.2.1, Linux v0.1.21, macOS v0.1.3) cannot make a key file
with `wallet create --keyfile`, so section 2 does not work on them.

## 1. Install (once; needs administrator / root)

Get the package for your OS from its releases page and check it against `SHA256SUMS`. Read only
the section for your OS.

### Install: Linux

Linux (deb, rpm, Arch, AppImage; x64 + arm64): <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases>

Debian / Ubuntu, x64:

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/download/v0.3.0-rc2
F=devnet-dvpn_0.3.0-rc.2_amd64.deb
curl -fsSLO "$U/$F"
curl -fsSLO "$U/SHA256SUMS"
grep " $F\$" SHA256SUMS | sha256sum -c -             # must print: <file name>: OK
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "./$F"
```

Without the update a fresh machine fails with "libsecret-tools … not installable". Without `-y`
the install waits for an answer you cannot give over a non-interactive SSH session. For another
package, take its exact file name from `SHA256SUMS` (it lists every file of the release).

Other Linux packages: `sudo dnf install ./devnet-dvpn-<version>.x86_64.rpm` ·
`sudo pacman -U devnet-dvpn-<version>-x64.pkg.tar.zst` · arm64: `_arm64.deb` / `.aarch64.rpm`.

What is proven on Linux: [`docs/PROOF.md`](docs/PROOF.md#linux).

### Install: Windows

Windows (x64 only; there is no ARM64 build of v0.3.0-rc2 or newer yet):
<https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases>.

Silent install, in an **elevated** PowerShell (an elevated terminal, or SSH as an
administrator). The installer is for the whole machine: from a normal shell it raises a UAC
prompt, and as a standard user over SSH it fails.

```powershell
$u = 'https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases/download/v0.3.0-rc2'
$f = 'Devnet-dVPN-Setup-0.3.0-rc.2-x64.exe'
curl.exe -fsSLo $f "$u/$f"                     # curl.exe, not curl (an alias in older PowerShell)
curl.exe -fsSLo SHA256SUMS "$u/SHA256SUMS"
$h = ((Select-String -Path .\SHA256SUMS -SimpleMatch " $f").Line -split '\s+')[0]       # the line for this file
(Get-FileHash ".\$f" -Algorithm SHA256).Hash.ToLower() -eq $h   # must print True
$p = Start-Process -FilePath ".\$f" -ArgumentList '/S' -Wait -PassThru; $p.ExitCode      # 0 = installed; 3 = wrong CPU
```

Use `Start-Process -Wait` as shown: run directly, the installer returns at once and you cannot
tell when it finished or whether it failed.

Windows only: the installer adds `devnet-dvpn` to the PATH of NEW terminals. In the shell that
ran the installer, add it yourself, then every line on this page works as written:

```powershell
$env:Path += ";$env:ProgramFiles\Devnet dVPN\bin"     # the default install folder
```

Windows PowerShell, the two key lines of section 2:

```powershell
$env:DVPN_KEYFILE = "$PWD\agent-key.json"
devnet-dvpn wallet create --keyfile $env:DVPN_KEYFILE --yes --json
```

In section 4: if `daemon install` answers `"relogin": true` (Windows), your account can use the
service only from its next sign-in: start a new session (a new SSH connection is enough; no
restart) before section 5. An elevated shell is usually admitted already, so this matters mostly
for a non-elevated shell later. If a later `connect` fails with `"code":"daemon-relogin"`, it is the
same thing: it needs one run from an elevated shell, or a new session.

`$env:DVPN_KEYFILE` lives only in the shell that set it. In every new shell or SSH session, set it
again before the next command, or the CLI falls back to a stored wallet that does not exist over
SSH. To carry it into new sessions once:
`[Environment]::SetEnvironmentVariable('DVPN_KEYFILE', $env:DVPN_KEYFILE, 'User')`.

**Known rc2 bug, Windows machines not joined to a domain** (most cloud and home machines): in
section 4, `daemon install --yes` fails with "There is no such global user or group:
WORKGROUP\…", because over SSH Windows sets `USERDOMAIN` to `WORKGROUP`. In the same shell, run
this once, then `daemon install --yes` again (proven: it then exits 0 and the service runs):

```powershell
$env:USERDOMAIN = $env:COMPUTERNAME
```

It is needed only for `daemon install`; later sessions do not need it. To be fixed in the next
release. On Windows, `daemon uninstall` refuses by design: remove the app in Settings > Apps.

What is proven on Windows: [`docs/PROOF.md`](docs/PROOF.md#windows).

### Install: macOS

macOS: <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases>. No clicks;
the VPN service is installed in section 4, not here.

macOS install from a shell. You need an administrator account with passwordless sudo
(`sudo -n true` must succeed), or a person who types the password. Every line below was
run as written on an Intel Mac (macOS 14, 2026-11-15); the Apple silicon build is built and
signed but has never been run:

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/download/v0.3.0-rc2
A=$(uname -m); [ "$A" = x86_64 ] && A=x64            # x64 = Intel; arm64 = Apple silicon (under Rosetta it reports x86_64)
F=Devnet-dVPN-0.3.0-rc.2-$A.dmg
curl -fsSLO "$U/$F"
curl -fsSLO "$U/SHA256SUMS"
grep " $F\$" SHA256SUMS | shasum -a 256 -c -         # must print: <file name>: OK
M=$(hdiutil attach -nobrowse -readonly "./$F" | tail -1 | cut -f3-)
sudo -n ditto "$M/Devnet dVPN.app" "/Applications/Devnet dVPN.app"
hdiutil detach -quiet "$M"
```

`sudo -n` fails at once when a password is needed (plain `sudo` would wait for one forever). If
an older version is installed, remove it first: `sudo -n rm -rf "/Applications/Devnet dVPN.app"`.

macOS only, before anything else: `devnet-dvpn` is not on your PATH until section 4 has run. Run
this once in your shell (and again in every new shell until `daemon install` is done), then every
line on this page works as written, in any shell and in programs you start from it (run in
`sh` and `zsh` on an Intel Mac, 2026-11-15):

```sh
export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"
```

Later on macOS:
- In section 4 the service can say it is waiting for the network; run `daemon doctor` again after a
  few seconds.
- V2Ray, Xray and Hysteria2 come inside the app, so `--protocol v2ray` needs no extra
  setup. WireGuard, AmneziaWG and OpenVPN need Homebrew and `daemon repair-drivers --yes` first.
- Shortcut commands: until `daemon install` has run, `next` names the full app path in quotes;
  run it as printed.

What is proven on macOS: [`docs/PROOF.md`](docs/PROOF.md#macos).

### Then, on every OS

```sh
devnet-dvpn version --json      # must say network devnet
```

## 2. Make a key (once)

```sh
export DVPN_KEYFILE="$PWD/agent-key.json"
devnet-dvpn wallet create --keyfile "$DVPN_KEYFILE" --yes --json    # prints your address
devnet-dvpn wallet show --json              # address and balances, any time
```

Windows: the PowerShell form is in "Install: Windows".

Already have a key file (your operator gave you a funded one)? Set `DVPN_KEYFILE` to its full
path, skip `wallet create`, check it with `wallet show --json`, and go to section 4.

Use the full path as shown: a relative path stops working when you change directory. Set
`DVPN_KEYFILE` again in every new shell. The key file is your money. Keep it private; never print
it, never commit it.

What `wallet show --json` prints: Appendix A.

## 3. Get funded (the one step that needs a human)

Your address needs two things, both free on devnet. Both faucets are web pages a person uses,
so this is the one moment you ask your operator for help.

| What | Why | Where | How much |
|---|---|---|---|
| **tDVPN** | what you pay nodes with | <https://faucet.sentinel.co> | one request = 100 tDVPN |
| **SOL** (devnet) | pays transaction fees | <https://faucet.solana.com> (linked from the Sentinel faucet page) | 0.5 SOL is plenty |

Get your address:

```sh
devnet-dvpn wallet show --json      # copy the "owner" value
```

Then send your operator exactly this, with your address filled in:

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

Do not open either faucet page yourself: they are for people (the Solana faucet says so). If
the Solana CLI is installed you may get the SOL on your own, which leaves your operator only the
tDVPN step. It is often rate-limited, so fall back to the operator if it fails:

```sh
solana airdrop 1 <ADDRESS> --url devnet
```

Wait for both to arrive. Run this until `ownerLamports` is above 0 and `ownerTdvpn` is not `"0"`:

```sh
devnet-dvpn wallet show --json
```

Minimum: about 0.06 SOL (`device setup` moves 0.05 to the device) and tDVPN = the deposit of the
node you pick (a per-GB node on devnet: about 0.002). Each open per-GB deposit holds ~0.004 SOL.

If your operator says a faucet refused, or nothing arrives: Appendix B.

## 4. Set up the VPN service and allow this device to spend (once)

```sh
devnet-dvpn daemon init                     # creates the device key (no administrator needed)
devnet-dvpn device plan                     # shows what will be signed, spends nothing
devnet-dvpn device setup --yes              # one transaction: spending permission + fee SOL for the device
devnet-dvpn daemon install --yes            # installs and starts the VPN service (administrator / root, once)
devnet-dvpn daemon doctor --json            # a list of checks: none may have "level": "fail"
devnet-dvpn status --json                   # wallet, device, service: all set
```

`doctor` levels are `ok`, `skip`, `warn`, `fail`; only `fail` stops you. The order matters: the
service does not start before the device has its spending permission.
- `device plan`'s "spend up to 50 tDVPN" is a cap the device may spend from your wallet, not a charge.
- `"service":"no-service"` in the `device setup` output: the service is not installed yet; normal here.

## 5. Connect

```sh
devnet-dvpn quality ip --json                            # BEFORE: note "direct.ip", your own IP
devnet-dvpn daemon drivers                               # the protocol you pick must be ready
devnet-dvpn nodes list --online --protocol wireguard --sort price --json
devnet-dvpn cost <node> --basis per_gb --units 1 --json  # exact deposit before you pay
devnet-dvpn connect <node> --basis per_gb --units 1 --yes --json
devnet-dvpn quality ip --json                            # AFTER: prove the tunnel (see below)
```

`<node>` is an address from `nodes list`. A node can cost more than a new wallet holds: `connect`
then exits 1 with `Not enough tDVPN: this deposit needs 50.` (code `preflight`). Pick a cheap one
with `nodes list --online --sort price --json`, or check `cost <node>` first. Prices in
`nodes list --json` are in base units with 6 decimals, like `ownerTdvpn`: `"2000"` is 0.002 tDVPN
and `"50000000"` is 50 tDVPN. On devnet many nodes ask about 50 tDVPN per GB, and one faucet
request gives 100: sort by price.

Which protocol: for proof that the whole machine goes through the node, pick a WireGuard,
AmneziaWG, OpenVPN or Hysteria2 node. If `daemon drivers` asks for `repair-drivers` and only
AmneziaWG is missing, ignore it unless you pick an AmneziaWG node.

How to read the proof. `quality ip --json` prints `{ "direct": …, "viaSocks": … }` (`source` is
the Cloudflare check address that answered):
- WireGuard, AmneziaWG, OpenVPN, Hysteria2 route the whole machine: you are connected when
  `direct.ip` is now different from the BEFORE value.
- V2Ray and Xray give a local SOCKS proxy instead: `direct.ip` stays your own, and
  `viaSocks.ip` is the node's. Only what you send to that proxy uses the node
  (`devnet-dvpn proxy status` shows its address).

Driving this machine over SSH: read "Over SSH" below before you connect.

You are connected. You are not finished: section 6 gets your deposit back.

## 6. Disconnect and get the unused deposit back

**Coming back to this server soon (per GB only):** just disconnect. The deposit stays open and
the next `connect` to the same server reuses it.

```sh
devnet-dvpn disconnect
```

**Finished, or you want the money back:** disconnect, then close the deposit.

```sh
devnet-dvpn disconnect
devnet-dvpn settle run --yes        # stage 1 of 2: start closing the deposit
devnet-dvpn settle list             # the ready time (about 2 h for per GB)
devnet-dvpn settle run --yes        # stage 2, after that time
devnet-dvpn settle withdraw --yes   # move refunds back to the wallet
```

You need not stay online for the two hours. In `settle list`, `refundable` below the deposit is
normal: the part used for traffic and fees is not refunded.

`disconnect` says "the app refunds the unused part automatically": that is the desktop app with
its window open. From the command line, run the lines above; the wait is what `settle list` shows.

That is the whole flow.

---

## Choices

**Protocol** — WireGuard, AmneziaWG, OpenVPN, V2Ray, Xray, Hysteria2. A node serves one.

```sh
devnet-dvpn nodes list --online --protocol wireguard --json
devnet-dvpn daemon drivers                  # which protocol tools this machine has
devnet-dvpn daemon repair-drivers --yes     # install the missing ones (administrator)
```

macOS: which protocols come inside the app and which need Homebrew is in "Install: macOS".

**Location** — the country is what the node reports.

```sh
devnet-dvpn nodes list --online --country DE --json
```

**Price** — cheapest first:

```sh
devnet-dvpn nodes list --online --sort price --json
```

**Price and pricing structure** — three ways to pay:

| | command | notes |
|---|---|---|
| per GB | `connect <node> --basis per_gb --units <GB> --yes` | pay for data used; unused deposit comes back |
| per hour | `connect <node> --basis per_hour --units <hours> --yes` | pay for time; when done run `disconnect` and then `settle run --yes` straight away, so the deposit stops being charged |
| plan | `plans list` → `plans subscribe <plan> --yes` → `connect <node> --plan <subscription> --yes` | one price up front, no refund; `plans roster <plan>` lists its servers |

`daemon set` (used in the two sections below) needs administrator / root exactly like
`daemon install`, and it restarts the VPN service: change settings **before** you connect.

**Split tunnelling** — choose what uses the VPN.

```sh
devnet-dvpn split status
devnet-dvpn daemon set --split-mode exclude --split-routes 10.0.0.0/8 --yes
devnet-dvpn proxy status            # V2Ray / Xray sessions give a local SOCKS proxy: only what you send to it uses the node
```

**Kill switch** — block the internet whenever the tunnel is not up.

```sh
devnet-dvpn daemon settings
devnet-dvpn daemon set --kill-switch on --yes        # off | on | persist
devnet-dvpn daemon set --allow-lan true --yes
```

In this app the kill switch `on` and `persist` are the same setting. After `disconnect` / `agent
down`, check `devnet-dvpn quality ip`. If it shows no address, the kill switch is still blocking —
this happens when the session had already dropped before you disconnected. `devnet-dvpn daemon
restore-network` lifts the block for now; it can come back at the next dropped session or service
restart. `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back.

**Changing server with the kill switch on.** Do not disconnect first: with the kill switch `on`,
`disconnect` of a live session can lift the block, so the gap between two sessions can go out on
your real IP. Switch
in one step, and never to the server you are already on:

```sh
devnet-dvpn connect <other node> --switch --yes --json
```

If the switch fails, the block holds and nothing leaks: try another node, or run
`devnet-dvpn daemon restore-network` to get the internet back.

Per-OS details of split tunnelling and the kill switch: [`docs/agent-safety.md`](docs/agent-safety.md).

## Over SSH

If you drive the machine over SSH: on Linux a full-tunnel connect does not cut your session
(proven with WireGuard: replies to connections that came in on the machine's own address still
leave directly; what the machine opens itself goes through the node). Windows: shown with
WireGuard over SSH from the internet (2026-10-20, an earlier build); other protocols not shown.
macOS: not yet shown. Where it is not shown, keep a second way in.

**If you control this machine over the network (SSH), read this first.** The kill switch blocks
everything that is not the tunnel, and that can include your own connection to the machine. A
fresh install has `allow-lan` off. If you reach the machine from its local network, set
`--allow-lan true` **before** `--kill-switch on` or `persist` (proven on macOS: with LAN off the
kill switch cuts SSH). If you reach it from the internet, do not turn the kill switch on unless
you have another way in. This has happened: a Windows cloud machine with the kill switch on
`persist` was locked out after a restart, remote access included, and had to be deleted.

## If you lose the network

```sh
devnet-dvpn daemon restore-network
```

---

## Shortcut: one command (NOT in v0.3.0-rc2; from the next release)

Releases after v0.3.0-rc2 add three commands that do sections 4 to 6 for you, except
`daemon install --yes`, which you still run once yourself (root or passwordless sudo; on Windows
an elevated shell or an administrator SSH login). On rc2 they
print nothing on stdout, even with `--json`, and exit `3` ("unknown command: agent" on stderr):
use the steps above. Every JSON field, failure `code` and exit code of the three commands is
listed in [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md).

```sh
devnet-dvpn agent status --json                              # what is missing, and the next step
devnet-dvpn agent up --protocol v2ray --country DE --yes --json   # picks a live server, pays, connects
devnet-dvpn agent down --yes --json                          # disconnects and starts the refund
```

`agent up` also takes `--node`, `--basis`, `--units`, `--plan`, `--max-price`. `--max-price` is
per unit of the basis (per GB or per hour), and the basis defaults to the saved setting, so pass
`--basis` whenever you pass `--max-price`. A success line carries `next`: follow it. A failure
carries `action`: follow it, or read `error` when `action` is null. Without `--yes`, `agent up`
and `agent down` print `{"needsConfirm":true,…}`, exit `2` and sign nothing.

- `agent up` is safe to repeat. Already connected to a server that matches what you asked for:
  it answers that session (`"reused": true`) and pays nothing. A match means `--node` is the live
  server, or, without `--node`, `--protocol` and `--country` (each only if given) equal the live
  ones; `--basis`, `--units`, `--plan` and `--max-price` are not compared while connected. Asking
  for a different server switches in one step, the kill-switch-safe way.
- If `agent down` fails because the disconnect itself failed, no deposit was closed and a
  per-hour one keeps billing: run `daemon doctor`, fix the service, then `agent down --yes` again.
- `agent down` closes a per-hour deposit at once. A per-GB deposit takes about two hours to
  close: when `readyAt` is set, follow `next` at that time (`settle run --yes`, then
  `settle withdraw --yes`). If it fails with `"code":"busy"`, the disconnect is done but another
  refund run held the lock: run `settle run --yes` yourself (a per-hour deposit bills until closed).
- `agent down` and the kill switch: after it, check `devnet-dvpn quality ip`. If it shows no
  address, the block is still up: see "Kill switch" above.
- Windows: `agent up` can need an elevated shell once (`"code":"daemon-relogin"`); a normal
  shell gets a prompt you cannot answer.
- macOS: see "Install: macOS" for how `next` names the app.
- `agent status --json` field names: Appendix A.

---

## If something fails

```sh
devnet-dvpn status --json
devnet-dvpn daemon doctor --json
devnet-dvpn logs --lines 80
```

Every command and option: [Linux](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/blob/main/docs/CLI.md) · [Windows](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/blob/main/docs/CLI.md) · [macOS](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/blob/main/docs/CLI.md).

MCP clients: after sections 1 to 4, the main commands (status, wallet, servers, connect,
disconnect, refund, and, on releases that have them, the three `agent` commands) are available
as tools; see
[`mcp/README.md`](mcp/README.md).

---

## Appendix A: JSON you will read

What `wallet show --json` prints (there is no `ok` field on this one):

| field | meaning |
|---|---|
| `owner` | your address (`wallet create --json` prints the same value as `address`) |
| `ownerLamports` | SOL, as a number of lamports (1 SOL = 1000000000) |
| `ownerTdvpn` | tDVPN, as a string of base units with 6 decimals (100 tDVPN = `"100000000"`) |
| `userBalance` | refunds waiting to be withdrawn |
| `ready` | stays `false` until section 4 is done (it also needs the device set up). In section 3 watch only `ownerLamports` and `ownerTdvpn` |

With no wallet it prints `{"wallet":null}`. An error from any command prints
`{"ok":false,"error":…,"code":…,"action":…}`; `action` is what to do next.

`agent status --json` names its fields differently from `wallet show`: `address`, `sol`,
`tdvpn`, `refundable`, as decimal strings (not `owner` / `ownerLamports` / `ownerTdvpn`). Its
`refundable` is the wallet's balance held in the program (what `settle withdraw` moves); the
`refundable` of `agent down` is different: the deposits still to come back.

## Appendix B: faucet limits

- Each faucet allows **2 requests every 8 hours** (the Sentinel faucet shows "N / 2 remaining";
  at zero its button reads "Claim limit reached"). People on one network share an allowance.
- The Sentinel faucet also has a daily total for everyone. If the limit is reached and 8 hours
  have passed, waiting will not help: ask your operator to send tDVPN from a wallet that has
  some: `devnet-dvpn wallet send --to <ADDRESS> --tdvpn 100 --yes`.
- One claim is 100 tDVPN: afterwards `ownerTdvpn` reads `"100000000"`.

## Appendix C: file names

File names carry the version with a dot, the tag without: tag `v0.3.0-rc2` holds
`Devnet-dVPN-Setup-0.3.0-rc.2-x64.exe`. Take the file name from the release page, never build it
from the tag.
