# Older releases (v0.3.0-rc2, rc4, rc5 and rc6)

[`AGENTS.md`](../AGENTS.md) covers **v0.3.0-rc8** (macOS: Apple silicon; Intel Macs: "Intel Mac" below). Take rc8 if you can. This page keeps what
an agent needs on an older release, and the single commands that `agent up` / `agent down` run.

What is proven, per OS and release: [`PROOF.md`](PROOF.md).

## Which release do I have?

```sh
devnet-dvpn version --json
```

- `0.3.0-rc.8` or `0.3.0-rc.7`: use [`AGENTS.md`](../AGENTS.md), not this page (what rc8 added: [`CHANGELOG.md`](../CHANGELOG.md)).
- macOS on an Intel Mac: "Intel Mac: v0.3.0-rc4" below.
- `0.3.0-rc.6`: read "v0.3.0-rc6" below.
- `0.3.0-rc.5`: read "v0.3.0-rc5" below.
- `0.3.0-rc.4`: the `agent` commands exist; read "v0.3.0-rc4" below. It is the newest Intel Mac build.
- `0.3.0-rc.2`: `agent` answers exit `3`, "unknown command: agent". Use "Step by step" below.
- Older than rc2 (the release GitHub marks "Latest" can be one): it cannot make a key file.
  Install rc8 by name (`AGENTS.md`, section 1).

## Step by step (rc2, or on any release if the shortcut fails)

The same flow with the single commands. All of them are in v0.3.0-rc2 and in every newer release.

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

`wallet show --json` names the balances differently from `agent status`; the table is in
[`JSON-FIELDS.md`](JSON-FIELDS.md).

## v0.3.0-rc2 only

- Windows, a machine not joined to a domain: `daemon install` fails with "There is no such global
  user or group: WORKGROUP\…". Run `$env:USERDOMAIN = $env:COMPUTERNAME` in the same shell first
  (`install.ps1` does it for rc2).
- No `agent up` / `agent down` / `agent status`: use "Step by step" above.
- No Windows ARM64 build.
- Windows over SSH: WireGuard was shown on rc2 (connect, disconnect and the refund).

## v0.3.0-rc6

The page applies, with these differences from rc7:

- Fixed defaults: without `--max-price` the cap is the spending limit / 10 (5 tDVPN), and a new install's
  spending limit is 50 tDVPN. No `defaults` block in the `agent up` answers. Pass `--max-price`.
- `no-nodes` under `--max-price` says only "widen the filters": `devnet-dvpn nodes list --online --json` shows the prices.
- The `spending-limit` action is an `agent up … --raise-limit --yes` line that can drop your `--protocol` /
  `--max-price` (E-88): read it before you run it.
- A failure has `action` but no `next` or `docUrl`; `keyfile-missing` exits `1`; RPC failures name no RPC fix.
- `not-funded` names the shortfall only (no recommended amount). `agent down` has no `deposited`.
- The step commands (`wallet`, `device`, `settle`, …) print no `next`; `settle run` has no `nextAfter`.

To install it: `DVPN_VERSION=v0.3.0-rc6` (PowerShell: `$env:DVPN_VERSION = 'v0.3.0-rc6'`).

## v0.3.0-rc5

The page applies, with the rc6 differences above and these from rc6:

- Every failure exits `1`: there are no exit codes `4`, `5`, `6`. Read `code` and `money`.
- `agent up --yes` raises this computer's spending limit itself, up to the Settings limit, when a deposit is
  above it, and says so: `limitRaised` (`from`, `to`) and `limitNote` (the command that lowers it). The
  preview without `--yes` names the raise first. There is no `--raise-limit`.
- No default price cap: without `--max-price`, `agent up` can pay any deposit among the cheapest nodes. Always
  pass `--max-price`.
- A connect that fails with no known cause can say only "Something went wrong. Retry." and its `action` can
  name an earlier deposit with that node (E-71). Run `devnet-dvpn agent down --yes`;
  `devnet-dvpn agent status --json` lists every open deposit in `deposits`.
- `version --json` prints no `programId` / `mint`.
- No base-unit twins (`tdvpnBase`, `heldBase`, …): amounts are decimal strings only, except `deposit.baseUnits`.

To install it: `DVPN_VERSION=v0.3.0-rc5` (PowerShell: `$env:DVPN_VERSION = 'v0.3.0-rc5'`).

## Intel Mac: v0.3.0-rc4

v0.3.0-rc8 for macOS is built for Apple silicon only; the newest Intel (`x64`) build is v0.3.0-rc4 (2026-11-16). On an
Intel Mac install it by hand, then follow "v0.3.0-rc4" below (it prints no `programId` / `mint`: check network
`devnet` only). An older app in `/Applications` goes first: `sudo -n rm -rf "/Applications/Devnet dVPN.app"`.

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/download/v0.3.0-rc4
curl -fsSLO "$U/SHA256SUMS"
F=$(awk '{print $2}' SHA256SUMS | grep -E '^Devnet-dVPN-.*-x64\.dmg$')
curl -fsSLO "$U/$F"
grep " $F\$" SHA256SUMS | shasum -a 256 -c -         # must print: <file name>: OK
M=$(hdiutil attach -nobrowse -readonly "./$F" | tail -1 | cut -f3-)
sudo -n ditto "$M/Devnet dVPN.app" "/Applications/Devnet dVPN.app"
hdiutil detach -quiet "$M"
export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"
```

## v0.3.0-rc4

The `agent` commands exist, with these differences from rc5:

- `agent status` names the held balance `refundable`, not `held` (the same number as
  `userBalance` in `wallet show`; it is not the `refundable` of `agent down`).
- `agent up` can raise this computer's spending limit without saying so (E-73). Check
  `devnet-dvpn device show --json` (`grant.allowance`, base units) after a connect.
- With the VPN service down and a deposit open, `agent status` names only the deposit wait as
  `next` (E-75). Run `devnet-dvpn daemon doctor --json` first and fix the service.
- `agent down` says `ok` and refunds nothing for a deposit another device of this wallet opened
  (E-72). Check `devnet-dvpn settle list`.
- With the node stopped and the kill switch holding the block, `next` says only `agent up --yes`
  (E-82). Run `devnet-dvpn daemon restore-network` first.

To pin an older release with the installer: `DVPN_VERSION=v0.3.0-rc4` (PowerShell:
`$env:DVPN_VERSION = 'v0.3.0-rc4'`). By hand, replace `v0.3.0-rc7` with the tag in the
download lines of [`INSTALL-BY-HAND.md`](INSTALL-BY-HAND.md); the file names then carry `0.3.0-rc.4`.
