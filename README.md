# Agentic Privacy — Solana devnet

Private internet for AI agents, with no account, no API key and no company server in the middle.
An agent holds its own key, pays a Sentinel dVPN node directly on Solana devnet and connects
through it. It chooses the protocol (WireGuard, AmneziaWG, OpenVPN, V2Ray, Xray, Hysteria2),
the country, and how it pays (per GB, per hour or a plan), with split tunnelling and a kill
switch when it needs them. Everything runs through `devnet-dvpn`, the command line inside the
released Sentinel dVPN apps.

**Start here:** an AI agent → [`AGENTS.md`](AGENTS.md) · the person helping an agent (funding,
one admin prompt) → [`docs/OPERATOR.md`](docs/OPERATOR.md) · an MCP client →
[`mcp/README.md`](mcp/README.md).

> **Cost:** nothing real. Devnet only: SOL and tDVPN come free from two public faucets and have
> no value. Do not use a wallet that holds real funds.
>
> **Proven** on earlier releases (v0.3.0-rc2, v0.3.0-rc4): the whole flow on Linux, refund
> included; on Windows over SSH, install through connect, disconnect and the refund; the macOS
> install lines on an Intel Mac. What is proven on which release, per OS and step:
> [`docs/PROOF.md`](docs/PROOF.md).

## Agents: read [`AGENTS.md`](AGENTS.md)

That one page takes an agent from nothing to a working connection: install, make a key, get
funded (the one step a person does), connect, prove the tunnel, disconnect and get the unused
deposit back. Every `devnet-dvpn` command on it exists in the release it names.

## Get the app

Use release **v0.3.0-rc6** (GitHub "Latest" on Windows and Linux), by name; on macOS v0.3.0-rc4 until rc6
is published there. On macOS the release GitHub marks "Latest" is older and cannot create the key file the agent flow uses.
On an older release: [`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md).

| OS | Releases |
|---|---|
| Linux (deb, rpm, Arch, AppImage; x64 + arm64) | <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases> |
| Windows (x64) | <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases> |
| macOS (Intel + Apple silicon) | <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases> |
| Android | <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-android/releases> |

Each release has a `SHA256SUMS` file: check the download against it before installing.

## MCP

For agents that use the Model Context Protocol, [`mcp/server.js`](mcp/server.js) is a stdio MCP server
with no dependencies. Each of its tools runs one `devnet-dvpn … --json` command. Set the machine up
with the CLI first (sections 1 to 4 of `AGENTS.md`). Get it with
`git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet`. Config, tools and the consent rule:
[`mcp/README.md`](mcp/README.md).

## Proof

- [`docs/PROOF.md`](docs/PROOF.md): per OS and per step of the agent flow, what is proven, on
  which release and when, and what is not.
- A fresh-machine test run on Linux (Ubuntu 24.04, public v0.3.0-rc2 package, 2026-11-15): install,
  key, connect over WireGuard (exit IP changed, then back), disconnect and the refund (after its
  two-hour close) all passed. A fresh AI agent given only `AGENTS.md` and a funded key then went
  from install to a proven tunnel and back on the same OS in 6.5 minutes.
- Windows over SSH (Windows 11 x64, v0.3.0-rc2, 2026-11-15): install, key, connect over
  WireGuard (exit IP changed, then back), disconnect and the refund passed, with the one
  workaround line rc2 needed ([`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md)). Details: [`docs/PROOF.md`](docs/PROOF.md#windows).
- Test method and results for every Sentinel dVPN client:
  <https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-testing-tools>.

## Not covered yet

- **Android:** the app has the same commands inside it, but a released Android build cannot be
  driven from outside the app, so an agent cannot use it this way.
- **Apple silicon:** the macOS steps are proven on the Intel build; the Apple silicon build has
  not been run.
- **Windows on ARM:** there is no ARM64 build.
- **MCP:** unit tests pass and a live check against real devnet nodes passed on Linux; a paid
  connection through the MCP server has not been run.
- **No sandbox installs:** installing the VPN service needs administrator or root once.

## License

**Sentinel dVPN License**, the same license as the Sentinel protocol repository
[sentinel-official/sentinel-solana](https://github.com/sentinel-official/sentinel-solana) and the
four Sentinel dVPN app repositories: see [`LICENSE`](LICENSE).

Built on [Sentinel](https://sentinel.co) and the public
[sentinel-official/sentinel-solana](https://github.com/sentinel-official/sentinel-solana) protocol.
