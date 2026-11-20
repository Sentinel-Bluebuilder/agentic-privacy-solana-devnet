# Older releases (v0.3.0-rc2, rc4 and rc5)

[`AGENTS.md`](../AGENTS.md) covers **v0.3.0-rc6** only (macOS: v0.3.0-rc4). Take rc6 if you can. This page keeps what
an agent needs on an older release, and the single commands that `agent up` / `agent down` run.

What is proven, per OS and release: [`PROOF.md`](PROOF.md).

## Which release do I have?

```sh
devnet-dvpn version --json
```

- `0.3.0-rc.6`: use [`AGENTS.md`](../AGENTS.md), not this page.
- `0.3.0-rc.5`: read "v0.3.0-rc5" below.
- `0.3.0-rc.4`: the `agent` commands exist; read "v0.3.0-rc4" below.
- `0.3.0-rc.2`: `agent` answers exit `3`, "unknown command: agent". Use "Step by step" below.
- Older than rc2 (the release GitHub marks "Latest" can be one): it cannot make a key file.
  Install rc6 by name (`AGENTS.md`, section 1).

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

`wallet show --json` names the balances differently from `agent status`; the table is in the
appendix of [`AGENTS.md`](../AGENTS.md).

## v0.3.0-rc2 only

- Windows, a machine not joined to a domain: `daemon install` fails with "There is no such global
  user or group: WORKGROUP\…". Run `$env:USERDOMAIN = $env:COMPUTERNAME` in the same shell first
  (`install.ps1` does it for rc2).
- No `agent up` / `agent down` / `agent status`: use "Step by step" above.
- No Windows ARM64 build.
- Windows over SSH: WireGuard was shown on rc2 (connect, disconnect and the refund).

## v0.3.0-rc5

The page applies, with these differences from rc6:

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
`$env:DVPN_VERSION = 'v0.3.0-rc4'`). By hand, replace `v0.3.0-rc6` with the tag in the
download lines of `AGENTS.md`, section 1; the file names then carry `0.3.0-rc.4`.
