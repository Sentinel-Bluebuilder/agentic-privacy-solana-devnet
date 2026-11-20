# MCP server: Devnet dVPN for an AI agent

A stdio MCP server with no dependencies, in one file: [`server.js`](server.js). It runs the
**installed** `devnet-dvpn` CLI (from the Devnet dVPN package for your OS) and returns the CLI's
JSON and exit code unchanged. Solana devnet only: the tokens have no value.

**Status (2026-11-15, Linux, Node 22):** the unit tests (`node --test mcp/server.test.js`) pass.
A live check (`node mcp/live-check.mjs`, real server, real CLI, real devnet; it spends nothing)
passed against the installed v0.3.0-rc2: `initialize`, `tools/list` (9 tools), `vpn_status`,
`vpn_wallet`, `vpn_nodes` (about 7 s), and on rc2 `vpn_agent_status` / `vpn_up` answer the
"use `vpn_nodes` + `vpn_connect`" fallback. Against a development build that has the `agent`
commands, `vpn_agent_status` answered with `next`, and `vpn_up` on a wallet that had already
been emptied answered `code: "not-funded"` with the amount and address in `action`, as the CLI
does. `vpn_connect` and `vpn_settle` were not called by the check (they spend); the commands
they run are proven on their own.

## 1. Set the machine up with the CLI first

MCP cannot set the machine up: installing the service needs administrator / root once. Do sections
1–4 of [`AGENTS.md`](../AGENTS.md) with the CLI: install **v0.3.0-rc6** by name (macOS: v0.3.0-rc4),
`wallet create --keyfile <path> --yes`, get the address funded (a person sends devnet SOL and
tDVPN), then `daemon init` → `device setup --yes` → `daemon install --yes`. After that,
everything below runs as the normal user over MCP.

## 2. Needs

- **Node.js 20 or newer** to run `server.js`.
- **The CLI.** The server looks for it in this order:
  1. `DEVNET_DVPN_BIN`, if set (a full path);
  2. `devnet-dvpn` on the `PATH` the MCP client gives the server;
  3. macOS only: `/usr/local/bin/devnet-dvpn` (made by `daemon install`), then
     `/Applications/Devnet dVPN.app/Contents/Resources/bin/devnet-dvpn`, then the same under
     `~/Applications`. This covers clients started as GUI apps, which get a short `PATH`.
     Windows only: the installer's default folder,
     `C:\Program Files\Devnet dVPN\bin\devnet-dvpn.cmd`. This covers a client started before the
     install, whose `PATH` is still the old one.

  | OS | where the CLI is |
  |---|---|
  | Linux | `/usr/bin/devnet-dvpn` |
  | Windows | `<install folder>\bin\devnet-dvpn.cmd`, on `PATH` for programs started **after** the install. In the default folder nothing more is needed; in another folder, restart the MCP client once or set `DEVNET_DVPN_BIN` |
  | macOS | `/Applications/Devnet dVPN.app/Contents/Resources/bin/devnet-dvpn`; also `/usr/local/bin/devnet-dvpn` after `daemon install` |

- **A key file**, named by `DVPN_KEYFILE`, as an **absolute** path (the client's working directory
  is unknown). The key travels only through this env variable, never as an argument.
  On macOS, use a key file: without one the CLI uses the login Keychain, which can show an access
  prompt that nobody may be there to answer.

## 3. Config

Get the server: `git clone https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet`
(it is `mcp/server.js` in that folder).

Any MCP client that starts a stdio server. The generic form:

```json
{
  "mcpServers": {
    "agentic-privacy": {
      "command": "node",
      "args": ["/absolute/path/to/mcp/server.js"],
      "env": { "DVPN_KEYFILE": "/absolute/path/to/agent-key.json" }
    }
  }
}
```

On Windows, escape the backslashes in JSON:
`"args": ["C:\\agent\\agentic-privacy-solana-devnet\\mcp\\server.js"]`, `"DVPN_KEYFILE": "C:\\agent\\agent-key.json"`.
Add `"DEVNET_DVPN_BIN"` to `env` only if the CLI is not found (macOS paths need no extra quoting
inside a JSON string, even with the space).

For a command-line client that takes the server as a command, the same thing is
`DVPN_KEYFILE=/absolute/path/to/agent-key.json node /absolute/path/to/mcp/server.js`.

The server speaks MCP protocol versions `2025-06-18`, `2025-03-26` and `2024-11-05`. Its
`initialize` answer carries short instructions for the model (the tool order and the `yes` rule).

## 4. Tools

### Six CLI tools (every release from v0.3.0-rc2 on)

| tool | runs | gives back (`result`) |
|---|---|---|
| `vpn_status` | `devnet-dvpn status --json` | wallet, device, service and session state |
| `vpn_wallet` | `devnet-dvpn wallet show --json` | `owner` (the address to fund), `ownerLamports` (SOL × 10⁹, a number), `ownerTdvpn` (tDVPN × 10⁶, a string), `ready` (true only after `device setup`), … |
| `vpn_nodes {country?, protocol?, sort?}` | `devnet-dvpn nodes list --online [--country CC] [--protocol P] [--sort price] --json` | an array of online nodes |
| `vpn_connect {node, basis?, units?, plan?, yes?}` | `devnet-dvpn connect <node> [--basis per_gb\|per_hour] [--units 1-1000] [--plan S] [--yes] --json` | the session: `id`, `node`, `status` (`active`), `service` (protocol), `channel`, `spent`, `proxyEndpoint` (V2Ray/Xray SOCKS, else empty), `error`, `warning` |
| `vpn_disconnect` | `devnet-dvpn disconnect --json` | `{"ok": true}` |
| `vpn_settle {channel?, yes?}` | `devnet-dvpn settle run [--channel C] [--yes] --json` | `signatures`: the transactions sent; without `yes`, a preview with `pending` (the deposits it would settle) |

`protocol` is one of `wireguard`, `amneziawg`, `openvpn`, `v2ray`, `xray`, `hysteria2`; `country`
is a two-letter code; `sort` is `price`. A typical run: `vpn_wallet` (check funds) → `vpn_nodes
{"protocol": "wireguard", "sort": "price"}` → `vpn_connect {"node": "<address from the list>", "yes": true}` → work
→ `vpn_disconnect` → `vpn_settle {"yes": true}`. A per-GB deposit becomes refundable about two hours after
`vpn_settle` starts the close; run `vpn_settle` once more then (the rest of the refund is a CLI
step: `settle withdraw --yes`).

`vpn_connect` and `vpn_settle` spend or sign, so, like `vpn_up` and `vpn_down`, they pass `--yes` only with `"yes": true`; without it the CLI answers a preview (exit `2`) and nothing is spent.

### Three agent tools (v0.3.0-rc4 and newer)

The output contract is [`docs/AGENT-COMMANDS.md`](../docs/AGENT-COMMANDS.md) (a copy of the
app source's file, kept equal by a test); the fields below follow it.
Amounts are decimal strings in tDVPN or SOL (e.g. `"0.002"`), `baseUnits` is the same amount in
base units, and times (`readyAt`) are Unix seconds.

**`vpn_agent_status`** runs `devnet-dvpn agent status --json`. It is read-only and never needs `yes`.

| field | meaning |
|---|---|
| `address` | wallet address; `null` = no wallet on this computer |
| `sol`, `tdvpn` | balances; `null` when there is no wallet or they could not be read |
| `held` | the wallet's balance held in the program, which `settle withdraw` moves to the wallet; **not** the `refundable` of `vpn_down` (v0.3.0-rc4 named it `refundable`) (on devnet a closed deposit's refund went straight to the wallet, so this stayed `"0"`) |
| `device` | this computer's device key; `null` = not set up |
| `service`, `connected` | booleans: the VPN service answers / a session is live |
| `blocked` | `true` only when no session is live and the internet does not answer (the kill switch holds the block, or the network is down) |
| `session`, `node`, `protocol`, `spent`, `exitIp`, `socks`, `wholeDevice` | only when connected (`exitIp` `null` if the check took over 8 s; `socks` `null` when the protocol gives none, and on Android) |
| `deposits` | only when the wallet has open or closing deposits: `{channel, node, status, refundable, readyAt}` each |
| `code`, `message`, `nodeStopped`, `alsoNext` | only when the node stopped serving: `code` = `server-stopped`, `connected` is false, the deposit is safe; `next` = `agent up --yes` (another node), `alsoNext` = `agent down --yes` (closes the deposit) |
| `next` | the next step: create a wallet, fund it, `agent down --yes` (connected), or `agent up --yes` |

**`vpn_up {protocol?, country?, node?, basis?, units?, plan?, max_price?, yes?}`** runs
`devnet-dvpn agent up […] [--yes] --json`. It picks the best matching online node, pays the
deposit (or uses the plan) and connects.

- `protocol`: `any` or one of the six. `country`: two letters. `node`: one exact node.
  `plan`: a subscription you hold. `units`: 1–1000, default from settings.
- `basis` defaults to the **saved setting**, not always `per_gb`. `max_price` is tDVPN per unit
  of the basis, so the server refuses `max_price` without `basis`.
- On its own it reads the session, nodes, wallet and plans, and creates the device key if
  there is none (local, no transaction). The deposit, the spending limit, the connect and a
  switch need `yes: true`.

| answer | fields |
|---|---|
| connected (exit 0) | `session`, `node`, `protocol` (the one really used), `country`, `exitIp`, `directIp`, `socks` (`socks5h://host:port` or `null`), `wholeDevice`, `channel`, `deposit`, `next` (always `agent down --yes`), `note` (what the session means, in one sentence); `blockedBefore: true` when the kill switch held the internet before it; `replaced` / `replacedNote` when the live session was not tunnelled and it switched; `skipped` / `skippedNote` when it left out a node that recently stopped or refused |
| `deposit` | `{basis, units, tdvpn, baseUnits}` (`tdvpn` = the most it can hold; the unused part is refunded); `{plan, tdvpn: "0"}` with a plan; `null` when `reused` |
| already connected to a match | the same, with `reused: true`; nothing paid, no `yes` needed. A match: `node` is the live node, or, with no `node`, `protocol` and `country` (each only if given) equal the live ones. `basis`, `units`, `plan` and `max_price` are not compared while a session is live |
| connected elsewhere | it switches: leaves the live node and connects to the new one (with the kill switch on, the block stays up in between); never picks the live server |
| preview (exit 2, no `yes`) | `needsConfirm: true`, `what` (the sentence it would do), `node`, `deposit`, `switchFrom` (`null` = not connected) |

**`vpn_down {yes?}`** runs `devnet-dvpn agent down [--yes] --json`. With `yes: true` it
disconnects (with the kill switch on, the block usually lifts at the disconnect; check as described below), then one
`settle run`: per-hour deposits close at once (they bill until closed), per-GB deposits start
their two-hour close.

In this app the kill switch `on` and `persist` are the same setting. After `disconnect` / `agent
down`, check `devnet-dvpn quality ip`. If it shows no address, the kill switch is still blocking —
this happens when the session had already dropped before you disconnected. `devnet-dvpn daemon
restore-network` lifts the block for now; it can come back at the next dropped session or service
restart. `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back. (These are CLI
commands; the MCP server has no tool for them.)

| answer | fields |
|---|---|
| done (exit 0) | `disconnected` (disconnect's own answer or `null`), `spent` (`null` = no session), `refundable` (the sum over `pending`, a lower bound; **not** the wallet balance of `vpn_agent_status`), `readyAt`, `signatures`, `pending` (deposits left: `{channel, node, mode, status, readyAt, refundable, …}`), `next` |
| `next` | after `readyAt`: `settle run --yes`, then `settle withdraw --yes`; or `settle list`; or `agent up --yes` to connect again |
| preview (exit 2, no `yes`) | `needsConfirm: true`, `what`, `session`, `perHour`, `perGb` (deposits it would close / start closing, the live session's own deposit included) |

These two ask for consent explicitly, because `vpn_up` picks the node and the deposit for you:
`yes` must be the boolean `true` (the string `"true"` is refused). Without it the CLI exits `2`
and shows what it would do; the tool returns that as a **preview** (`structuredContent.preview:
true`, `isError: false`). Call again with `"yes": true` to do it.

On macOS, until `daemon install` has run, a `next` may start with the quoted app path instead of
`devnet-dvpn`.

A `next` or `action` that runs `… agent up`, `… agent down` or `… agent status` maps to `vpn_up`,
`vpn_down` or `vpn_agent_status` (`--yes` in it = `yes: true`). Any other command in it
(`daemon install`, `device setup`, `settle run`, …) is a CLI step: see "Not covered".

**On a release without the `agent` commands** (v0.3.0-rc2 or older: [`docs/OLDER-RELEASES.md`](../docs/OLDER-RELEASES.md)), the three tools return `isError: true` with
`structuredContent.error = "no agent command in this CLI"` and a `fix` that says to use
`vpn_nodes` + `vpn_connect`. Nothing is run.

## 5. Results and errors

Every result has `structuredContent = { exitCode, command, result }`:

- `command`: the exact CLI line that ran (no key in it).
- `result`: the CLI's JSON (`null` if it printed none). The text content is the same JSON line.
- `exitCode`: `0` ok, `1` error, `2` needs `--yes`, `3` usage. Non-zero sets `isError`, except
  the exit-2 preview of `vpn_up` / `vpn_down`.
- A CLI error is `{"ok": false, "error": "…", "code": "…", "action": "…"}`: `action` is the next
  thing to do. On a non-zero exit the CLI's stderr is added as a second text item.

### Failure codes of the agent tools

On a failure (exit 1) `result` is `{"ok": false, "error", "code", "action"}`. Do what `action`
says; when it is `null`, read `error`. "→ status" means the action is `agent status`: read
`error`, and pick another server or filter if the code names the server.

| code | where | action / meaning |
|---|---|---|
| `no-wallet` | up | `wallet create --keyfile <path> --yes`, then have the address funded |
| `no-wallet` | down | `vpn_disconnect` to leave the VPN now; then `wallet import <file>` (the wallet that paid) and `vpn_down {"yes": true}` to close the deposits: with no wallet the CLI cannot read or close them; nothing ran |
| `no-device` | up | `daemon doctor`: the device key could not be made |
| `no-subscription` | up with `plan` | `plans list`, then `plans subscribe <plan> --yes`, or drop `plan` |
| `no-nodes` | up | `nodes list --online --json`, then widen protocol / country / max_price (check basis); nothing paid |
| `not-funded` | up | send the SOL / tDVPN it names to the address, then `agent up --yes`; nothing paid |
| `connect-failed` | up | → status (connect failed with no code) |
| `settle-failed` | down | `settle list`: the disconnect is done; the deposits are listed there |
| `busy` | down | `settle run --yes` (`vpn_settle {"yes": true}`): the disconnect is done, but another refund run held the lock, so nothing was closed; a per-hour deposit bills until it is |
| the disconnect's own code (e.g. `daemon-unavailable`), else `stop-failed` | down | `daemon doctor`, then `vpn_down {"yes": true}` again: the disconnect failed, so no deposit was closed, and a per-hour deposit keeps billing while the session is up |
| `daemon-missing` | up | `daemon install --yes` once (administrator / root; Windows: from an elevated shell or an administrator SSH login), then `agent up --yes` |
| `daemon-relogin` | up | Windows: the service does not accept this account yet: `daemon install --yes` once from an elevated shell, or a new sign-in; elsewhere as `daemon-missing` |
| `protocol-missing` | up | another protocol this computer has, or `daemon repair-drivers --yes`; the deposit comes back with `agent down --yes` |
| `device-permission` | up | `device setup --yes`, then `agent up --yes` |
| `daemon-unavailable`, `daemon-restarting` | up | `daemon doctor` |
| `test-running` | up | `test stop`, then `agent up --yes` |
| `rpc-busy` | up | `agent up --yes` again in a minute |
| `price-changed`, `deposit-unusable`, `deposits-unread` | up | `agent up --yes` again: nothing was paid, and it reads the price fresh (`max_price` still caps it). The server's price rose above the deposit shown / your open deposit with it started closing / your open deposits could not be read |
| `not-confirmed`, `plan-limit`, `busy`, `unsupported`, `network-mismatch` | up | → status: refused before anything started |
| `session-active`, `node-gone`, `node-stale`, `node-offline`, `protocol-blocked`, `driver-missing`, `basis-unavailable`, `not-enough-tdvpn`, `spending-limit`, `device-sol`, `preflight`, `kill-switch-held`, `switch-reconnecting`, `switch-offline` | up | → status: the check before paying failed; nothing paid |
| `price-cap` | up | rc6: no `max_price` and the deposit is above the default cap (the spending limit / 10: 5 tDVPN by default); nothing was paid. Call `vpn_up` again with `max_price` (the `action` names the node's price) or fewer `units` |
| `cancelled` | up | → status: stopped |
| `waiting-for-network`, `ticket-other-owner`, `approval-revoked`, `service-stopped-connecting`, `node-identity`, `node-ledger`, `node-price`, `node-error`, `kill-switch-failed`, `tunnel-failed`, `tunnel-dead`, `tunnel-mtu`, `tunnel-closing`, `port-in-use`, `dns-apply`, `deposit-pending`, `rpc-network`, `rpc-timeout`, `rpc-quota`, `timeout`, `chain-encoding` | up | → status: failed after the start; a deposit already paid stays open until `agent down --yes` |
| `credit_exhausted`, `peer_limit_reached`, `lease_insufficient`, `subscription_invalid`, `ticket_request_stale`, `provider_unreachable`, `ticket_invalid`, `unauthorized`, `cannot cover the prepay`, `voucher_exceeds_escrow`, `channel_node_reopened`, `terms_rejected`, `rate_limited`, `voucher_signature_invalid`, `mode_not_voucher`, `mode_not_stream` | up | → status: the server refused; pick another with `node` or other filters |
| `stop-failed`, `dns-revert-failed`, `tunnel-left` | up | → status: leaving the old session failed |
| `unknown` | up | → status |
| `service-down` | any | the VPN service is not running: the start hint, or `null` |
| `service-not-ready` | any | `null`: try again in a moment |
| `approval-revoked` | any | `device setup --yes` (also above) |
| `not-enough-tdvpn` | any | `null`: fund the wallet or use fewer `units` (also above) |
| `session-active` | any | `disconnect` (also above) |
| `rpc-unavailable` | any | every RPC endpoint failed: check the network, or set another RPC |
| `keyfile-missing` | up | restore the key file named in the error from your backup (it is the only key to this wallet), then `agent up --yes`; never `wallet create` (a new wallet cannot see the old refunds) |
| `wallet-switch-needed` | up, down, status | load the key file of the wallet named in the error, or `device switch --yes` (sets this computer up for the loaded wallet; the other wallet's deposits stay refundable). Nothing was paid |
| `clock-skew` | up | set this computer's clock to the right time (the error says by about how much), then `agent up --yes` |

Usage errors (exit 3) print nothing on stdout, only one line on stderr: a bad flag value, an
unknown flag or subcommand. The tool's schema check stops nearly all of them before the CLI runs.

The server's own errors have `exitCode: null`, `isError: true`, `error` and `fix`: CLI not found
(the fix names the download for each OS), or bad input (the schema is checked before anything
runs; nothing passes through a shell).

Time limits: `vpn_connect` and `vpn_up` 300 s, `vpn_settle` and `vpn_down` 180 s, `vpn_nodes`
120 s, the rest 60 s. On a timeout the CLI is stopped and the result says so: call `vpn_status`
before retrying, because a connect may have finished anyway. A timed-out `vpn_connect` or `vpn_up` can leave a deposit already paid: `vpn_agent_status` (or `vpn_status`) shows it, and `vpn_disconnect` then `vpn_settle {"yes": true}` (or `vpn_down {"yes": true}`) gets it back.

On Windows the server runs the two programs inside the installer's `bin\devnet-dvpn.cmd` shim
directly, so no argument ever reaches `cmd.exe`.

**macOS:** if the service has not granted this account access yet, a call can run one
administrator step. Without passwordless `sudo`, that is a password dialog on the screen, and the
call waits for it until the time limit. A call that seems to hang may be waiting for that dialog.

**Windows:** if the service has not accepted this account yet, a call can run one administrator
step. From a client that is not elevated, that is a UAC prompt on the screen, and the call waits
for it until the time limit. With no desktop (a client run as a service, or over SSH as a
non-administrator) it fails with `code: "daemon-relogin"`: run `devnet-dvpn daemon install --yes`
once from an elevated shell, then retry.

## 6. Not covered by this server

First-run setup (`wallet create`, `daemon init`, `device setup`, `daemon install`), split
tunnelling and the kill switch (`daemon set …`), and `settle withdraw` are CLI-only: they need an
administrator step or are rare. Run them with the CLI, as `AGENTS.md` describes.

## 7. Checking it

- Unit tests, from the repo root: `node --test mcp/server.test.js` (Node 20+; a bare `mcp/`
  argument fails on Node 22). No CLI or network needed.
- Live check, spends nothing: `DVPN_KEYFILE=<key> node mcp/live-check.mjs --out <dir>` starts the
  server, speaks real JSON-RPC to it, and calls only the read-only tools plus `vpn_up` without
  `yes`. It needs `devnet-dvpn` findable as in section 2. `--bundle <devnet-dvpn.cjs>` adds a pass
  against a CLI built from source (the `out/cli/devnet-dvpn.cjs` of a build; the copy inside an
  installed app is packed in `app.asar` and plain Node cannot read it).
- Live check with one paid session (v0.3.0-rc4 or newer, after sections 1 to 4 of `AGENTS.md`):
  `DVPN_KEYFILE=<key> node mcp/live-check.mjs --out <dir> --paid --yes` adds `vpn_up`
  (`yes: true`, WireGuard, per GB, 1 unit), `vpn_agent_status` (connected), `vpn_down`
  (`yes: true`) and `vpn_agent_status` (not connected). It spends one deposit (about 0.002 tDVPN
  per GB on devnet; the unused part comes back after the two-hour close). Without both `--paid`
  and `--yes` it spends nothing. `--protocol <name>` and `--basis per_hour` change the session.
