# Agent commands: the output contract

What `agent status`, `agent up` and `agent down` print with `--json`, field by field, and every
failure `code` they can return. Source of truth: `src/cli/agent-cmd.ts`, the error line in
`src/cli/index.ts`, `confirm()` in `src/cli/commands.ts`, `CONNECT_CODES` in
`src/core/session/state.ts` and `daemonErrorCopy` in `src/core/daemon/link-copy.ts`.
`tests/unit/agent-commands-doc.test.ts` fails if a code those files can return is missing here.

`<cli>` below is `devnet-dvpn`, or the value of `DVPN_CLI_NAME` when the app's shim sets it.

## The four kinds of answer

Every run prints exactly one JSON line on stdout. A warning (another VPN is on) goes to stderr.

| Exit | Line | Meaning |
|---|---|---|
| 0 | `{"ok":true, …, "next": "…"}` | Done. `next` is the command (or the funding) to do next. |
| 1 | `{"ok":false,"error":"…","code":"…"\|null,"action":"…"\|null}` | Failed. `action` is the command that fixes it, or null. |
| 2 | `{"needsConfirm":true,"what":"…", …}` | Would spend: nothing was signed. Re-run with `--yes`. |
| 3 | (no JSON; one line on stderr) | Wrong usage: bad flag value, unknown flag or unknown subcommand. Nothing ran. |

Amounts are decimal strings in tDVPN or SOL (e.g. `"0.002"`); `baseUnits` is the same amount in
base units, as a string. Times (`readyAt`) are Unix seconds.

## agent status

Reads only. It never signs, never connects, never asks for `--yes`.

| Field | Type | Meaning |
|---|---|---|
| `ok` | `true` | |
| `address` | string \| null | The wallet address; null = no wallet on this computer. |
| `sol` | string \| null | SOL in the wallet; null when there is no wallet or it could not be read. |
| `tdvpn` | string \| null | tDVPN in the wallet. |
| `refundable` | string \| null | The wallet's balance held in the program (`userBalance`), which `settle withdraw` moves to the wallet. **Not** the `refundable` of `agent down` (that one sums the deposits still open). On devnet a closed deposit's refund went straight to the wallet's tDVPN, so this stayed `"0"` (Linux run 2026-11-15). |
| `device` | string \| null | This computer's device key; null = not set up yet. |
| `service` | boolean | The VPN service answers. |
| `connected` | boolean | A session is live. |
| `session` | string | Only when connected: the session id. |
| `node` | string | Only when connected: the server's address. |
| `protocol` | string | Only when connected: the protocol in use. |
| `spent` | string | Only when connected: tDVPN used so far. |
| `exitIp` | string \| null | Only when connected: the address the internet sees; null if the check did not finish within 8 s. |
| `socks` | string \| null | Only when connected: `socks5h://host:port` for apps to use; null on Android or when the protocol gives none. |
| `next` | string | See below. |

`next`, in this order: no wallet → `<cli> wallet create --keyfile <path> --yes, then fund the address it prints`;
connected → `<cli> agent down --yes`; balances unreadable → `<cli> agent status (the balances could not be read; try again in a moment)`;
SOL under 0.02 (wallet not ready) or no tDVPN → `send at least … to <address>, then <cli> agent up --yes`;
device set up but service not answering → the `daemon-missing` action below; otherwise `<cli> agent up --yes`.

## agent up

`agent up [--protocol P] [--country CC] [--node N] [--basis per_gb|per_hour] [--units N] [--plan S] [--max-price N] --yes`

Flags: `--protocol` = `any` or one of the protocols in `src/shared/protocols.ts`; `--country` = two letters;
`--basis` defaults to the saved setting (not always per_gb); `--units` 1–1000 GB or hours, default from settings;
`--max-price` = tDVPN per unit of the basis; `--plan` = a subscription address you hold (no deposit, the plan's live servers only);
`--node` = one exact server (it must still be online and match the other filters).

**On its own (no `--yes` needed):** reads the live session, the server list (probing them), wallet and
subscriptions; creates the device key if this computer has none (`daemon init`: local, no transaction).
**Never without `--yes`:** the deposit, the spending approval, the connect, a switch. Without `--yes` it
answers exit 2:

| Field (exit 2) | Type | Meaning |
|---|---|---|
| `needsConfirm` | `true` | |
| `what` | string | The sentence it would do, e.g. `Connect to <node> (DE, wireguard): deposit up to 0.002 tDVPN (1 GB), unused part refunded.` A switch starts `Switch from <node>.` |
| `node` | string | The server it picked. |
| `deposit` | object | As below. |
| `switchFrom` | string \| null | The live server it would leave; null = not connected. |

A live session is reused when `--node` is the live server, or, with no `--node`, `--protocol` (if given) is the
live protocol and `--country` (if given) is the live server's country. Nothing else is compared: `--basis`,
`--units`, `--max-price` and `--plan` are ignored while a session is live. A reused session is answered at once, exit 0, `reused: true`, nothing paid, no `--yes` needed. One that does not match is
switched: connect()'s switch path leaves it and connects to the new server; with the kill switch on, the
block stays up between the two. The live server is never picked for the switch.

| Field (exit 0) | Type | Meaning |
|---|---|---|
| `ok`, `connected` | `true` | |
| `session` | string | Session id. |
| `node` | string | Server address. |
| `protocol` | string | The protocol really used (on a server that offers several, the service picks). |
| `country` | string \| null | Two-letter country of the server. |
| `exitIp` | string \| null | Address the internet sees; null if the check did not finish within 8 s. |
| `directIp` | string \| null | This computer's own address (for the check that traffic moved). |
| `socks` | string \| null | `socks5h://host:port`; null on Android or when the protocol gives none. |
| `channel` | string \| null | The deposit account. |
| `deposit` | object \| null | `{basis, units, tdvpn, baseUnits}` for a per-server deposit (`tdvpn` = most it can hold; the unused part is refunded); `{plan, tdvpn: "0"}` with `--plan`; null when `reused`. |
| `reused` | `true` | Only when an existing session was kept. |
| `next` | string | With `socks`: `send traffic through <socks> (e.g. curl --proxy <socks> https://api.ipify.org); when done: <cli> agent down --yes`. Without: `this computer's traffic now goes through the node; when done: <cli> agent down --yes`. |

## agent down

`agent down --yes`. **On its own:** reads the live session and the open deposits. **Never without
`--yes`:** the disconnect or any transaction. Without `--yes`, exit 2:

| Field (exit 2) | Type | Meaning |
|---|---|---|
| `needsConfirm` | `true` | |
| `what` | string | e.g. `Disconnect from <node>, then close 1 per-hour deposit(s) (they bill until closed) and start closing 0 per-GB deposit(s); refunds go to your wallet.` |
| `session` | string \| null | The live session. |
| `perHour`, `perGb` | number | Deposits it would close / start closing: the open and ready ones, plus the live session's own deposit (it reads `in-use` until the disconnect). |

**Kill switch.** In this app the kill switch `on` and `persist` are the same setting. After
`disconnect` / `agent down`, check `devnet-dvpn quality ip`. If it shows no address, the kill switch
is still blocking — this happens when the session had already dropped before you disconnected.
`devnet-dvpn daemon restore-network` lifts the block for now; it can come back at the next dropped
session or service restart. `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back.

With `--yes` it runs `disconnect` (which also puts back a system proxy left with no session), then one `settle run`: a per-hour deposit is closed at once (it bills until closed); a per-GB one
starts its 2-hour close. Exit 0:

| Field | Type | Meaning |
|---|---|---|
| `ok` | `true` | |
| `disconnected` | object \| null | `disconnect`'s own answer (e.g. `{ok, session, killSwitchReleased}`); null if it printed none. |
| `spent` | string \| null | tDVPN the session used; null = there was no session. |
| `refundable` | string | The sum of `refundable` over `pending`: tDVPN still to come back from the deposits left. **Not** the wallet balance of `agent status`. A lower bound: on the Linux run of 2026-11-15 a deposit listed 0.001883 and 0.001999 came back. |
| `readyAt` | number \| null | Latest time a closing deposit can be finished. |
| `signatures` | string[] | Transactions this run signed. |
| `pending` | object[] | Deposits left: `{channel, node, mode, status ('open'\|'closing'\|'ready'\|'in-use'), readyAt, refundable, …}`. |
| `next` | string | With `readyAt`: `<cli> settle run --yes after <ISO time> (a closing deposit waits 2 h), then <cli> settle withdraw --yes`; deposits left: `<cli> settle list`; none: `<cli> agent up --yes to connect again`. |

## Failure codes (exit 1)

`action` is copied verbatim into the JSON line. Do what it says; when it is null, read `error`.

### Raised by agent-cmd itself

| Code | From | `action` | What the agent does |
|---|---|---|---|
| `no-wallet` | up | `<cli> wallet create --keyfile <path> --yes, then fund the address it prints` | Create a wallet in a 0600 key file, ask its owner to fund it. |
| `no-wallet` | down | `<cli> disconnect to leave the VPN now; <cli> wallet import <file> (the wallet that paid), then <cli> agent down --yes to close the deposits` | This computer's CLI has no wallet, so it cannot read or close deposits. Nothing ran. `disconnect` needs no wallet: run it to leave the VPN at once, then import the wallet that paid and run `agent down --yes`. |
| `no-device` | up | `<cli> daemon doctor` (device key could not be made) | Run it; report what it says. |
| `no-subscription` | up `--plan` | `<cli> plans list, then <cli> plans subscribe <plan> --yes` | Subscribe, or drop `--plan`. |
| `no-nodes` | up | `<cli> nodes list --online --json, then widen --protocol / --country / --max-price` | Widen the filters (check `--basis`). No transaction ran. |
| `not-funded` | up | `send at least <n> SOL and/or <n> tDVPN to <address>, then <cli> agent up --yes` | Ask the owner to fund the address. Nothing was paid. |
| `connect-failed` | up | `<cli> agent status` | connect() failed with no code: read `error`. |
| `settle-failed` | down | `<cli> settle list` | The disconnect is done; the deposits are listed there. |
| `busy` | down | `<cli> settle run --yes` | The disconnect is done, but another refund run in the same process held the lock, so nothing was closed: run it (a per-hour deposit bills until closed). |
| disconnect's code (e.g. `daemon-unavailable`, `service-down`, `rpc-unavailable`), else `stop-failed` | down | `<cli> daemon doctor, then <cli> agent down --yes again` | The disconnect failed, so no deposit was closed (the message starts `Could not disconnect, so no deposit was closed`, then the service's plain sentence; this line is never rewritten by the rule below). A live session's deposit cannot be closed while the session is up, so a per-hour one keeps billing: fix the service, then run `agent down --yes` again. |

### From connect() (agent up), `action` = `nextFor(code)`

| Code | `action` |
|---|---|
| `daemon-missing` | Linux/macOS: `<cli> daemon install --yes (administrator/root once: passwordless sudo, or a person types the password), then <cli> agent up --yes`. Windows: `<cli> daemon install --yes from an elevated shell or an administrator SSH login (a normal shell shows a UAC prompt an agent cannot answer), then <cli> agent up --yes`. |
| `daemon-relogin` | Linux/macOS: as `daemon-missing`. Windows: `<cli> daemon install --yes once from an elevated shell or an administrator SSH login (the VPN service does not accept this account yet; …), then <cli> agent up --yes`. |
| `protocol-missing` | `<cli> agent up --protocol v2ray --yes (a protocol this computer has), or <cli> daemon repair-drivers --yes`. The deposit is refunded by `agent down --yes`. |
| `device-permission` | `<cli> device setup --yes, then <cli> agent up --yes` (as `no-device` from connect) |
| `daemon-unavailable`, `daemon-restarting` | `<cli> daemon doctor` |
| `test-running` | `<cli> test stop, then <cli> agent up --yes` (a server test holds the VPN service) |
| `rpc-busy` | `<cli> agent up --yes again in a minute (the network was busy)` |
| `price-changed`, `deposit-unusable`, `deposits-unread` | `<cli> agent up --yes again (nothing was paid; it reads the price fresh)`. Nothing was paid in each case. `price-changed`: the server's price rose above the deposit `agent up` showed. `deposit-unusable`: your open deposit with this server started closing, so it cannot be used, and a new one is never paid without being shown. `deposits-unread`: your open deposits could not be read, so no second deposit was opened beside one you may have. `--max-price` still caps the next try. |
| every other code | `<cli> agent status` |

Elevation: on Windows `agent up` can itself need one elevated step (the service pipe granting this
account); a non-elevated agent then gets `daemon-relogin`. On Linux/macOS the service install needs root once.

The other codes connect() can answer (`CONNECT_CODES`), all with action `<cli> agent status`. For each,
read `error`; a code before paying means nothing was paid:

- refused before anything starts: `not-confirmed`, `plan-limit`, `busy`, `unsupported`, `network-mismatch`
- the check before paying (nothing paid): `session-active`, `node-gone`, `node-stale`, `node-offline`, `protocol-blocked`, `driver-missing`, `basis-unavailable`, `not-enough-tdvpn`, `spending-limit`, `device-sol`, `preflight`, `kill-switch-held`, `switch-reconnecting`, `switch-offline`
- stopped: `cancelled`
- after the start was asked of the service: `waiting-for-network`, `ticket-other-owner`, `approval-revoked`, `service-stopped-connecting`, `node-identity`, `node-ledger`, `node-price`, `node-error`, `kill-switch-failed`, `tunnel-failed`, `tunnel-dead`, `tunnel-mtu`, `tunnel-closing`, `port-in-use`, `dns-apply`, `deposit-pending`, `rpc-network`, `rpc-timeout`, `rpc-quota`, `timeout`, `chain-encoding`
- the server's own refusal: `credit_exhausted`, `peer_limit_reached`, `lease_insufficient`, `subscription_invalid`, `ticket_request_stale`, `provider_unreachable`, `ticket_invalid`, `unauthorized`, `cannot cover the prepay`, `voucher_exceeds_escrow`, `channel_node_reopened`, `terms_rejected`, `rate_limited`, `voucher_signature_invalid`, `mode_not_voucher`, `mode_not_stream`. Pick another server with `--node` or other filters.
- leaving: `stop-failed`, `dns-revert-failed`, `tunnel-left`
- `unknown`

A failed connect after a deposit was paid leaves that deposit open: `agent down --yes` closes it (closing an open
deposit is unit-tested; that connect() leaves it open after such a failure is not tested here).

### Replaced on the way out (any of the three)

`index.ts` rewrites an error whose raw text is a VPN-service or RPC failure. Then `code` and `action`
come from the shared copy, not the table above:

| Code | `action` |
|---|---|
| `service-down` | the service start hint, or null |
| `service-not-ready` | null: try again in a moment |
| `approval-revoked` | `devnet-dvpn device setup --yes` |
| `not-enough-tdvpn` | null: fund the wallet or use fewer `--units` |
| `session-active` | `devnet-dvpn disconnect` |
| `rpc-unavailable` | the RPC hint (every RPC endpoint failed: check the network, or set another RPC) |

### Usage (exit 3) and confirm (exit 2)

Exit 3, nothing ran: `--basis must be per_gb or per_hour`, `--units must be a whole number from 1 to 1000`,
`--protocol must be any, …`, `--country must be a two-letter country code, e.g. DE`, `--max-price: …`,
an unknown flag, `unknown: agent <x> (up | down | status)`. Exit 2: `up` or `down` without `--yes` (above).
