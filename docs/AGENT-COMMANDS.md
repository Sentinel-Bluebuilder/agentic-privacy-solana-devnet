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
| `blocked` | `true` | Only when no session is live and the internet does not answer (the kill switch still holds the block, or the network is down). |
| `session` | string | Only when connected: the session id. |
| `node` | string | Only when connected: the server's address. |
| `protocol` | string | Only when connected: the protocol in use. |
| `spent` | string | Only when connected: tDVPN used so far. |
| `exitIp` | string \| null | Only when connected: the address the internet sees; null if the check did not finish within 8 s. |
| `socks` | string \| null | Only when connected: `socks5h://host:port` for apps to use; null on Android or when the protocol gives none. |
| `wholeDevice` | boolean | Only when connected: true when the whole computer goes through the node (WireGuard, AmneziaWG, OpenVPN, Hysteria2 always; V2Ray and Xray when the service runs them whole-device, the default on a fresh Windows or macOS install; on Linux they cover only apps that use `socks`; Android always). |
| `next` | string | See below. |

`next`, in this order: `blocked` → `<cli> agent up --yes to reconnect through a server (protection stays), or <cli> daemon restore-network to go direct (protection off until the next connect)` (with no wallet: `<cli> daemon restore-network (the internet is blocked), then` the no-wallet step);
no wallet → `<cli> wallet create --keyfile <path> --yes, then fund the address it prints`;
connected → `<cli> agent down --yes`; balances unreadable → `<cli> agent status (the balances could not be read; try again in a moment)`;
SOL under 0.02 (wallet not ready) or no tDVPN → `send at least … to <address>, then <cli> agent up --yes`;
device set up but service not answering → the `daemon-missing` action below; otherwise `<cli> agent up --yes`.

## agent up

`agent up [--protocol P] [--country CC] [--node N] [--basis per_gb|per_hour] [--units N] [--plan S] [--max-price N] --yes`

Flags: `--protocol` = `any` or one of the protocols in `src/shared/protocols.ts`; `--country` = two letters;
`--basis` defaults to the saved setting (not always per_gb); `--units` 1–1000 GB or hours, default from settings;
`--max-price` = tDVPN per unit of the basis; `--plan` = a subscription address you hold (no deposit, the plan's live servers only);
`--node` = one exact server (it must still be online and match the other filters).
Without `--node` it picks the lowest latency among the matching servers that answer. With no `--max-price`, only
among the cheapest of them (a deposit at most 2 times the cheapest one's), so a fast server at 50 tDVPN/GB is
never taken while one at 0.002 answers; `--max-price` sets your own cap instead. A flag given with no value
(`--plan` alone, `--plan=`) is a usage error: nothing runs.

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
| `directIp` | string \| null | This computer's own address, never the node's. With only `socks` routed it is measured outside the tunnel; in whole-device mode a direct check exits by the node too, so it is the address read before the connect, or null if none was read. |
| `socks` | string \| null | `socks5h://host:port`; null on Android or when the protocol gives none. |
| `wholeDevice` | boolean | True when the whole computer goes through the node (WireGuard, AmneziaWG, OpenVPN, Hysteria2 always; V2Ray and Xray when the service runs them whole-device, the default on a fresh Windows or macOS install; on Linux they cover only apps that use `socks`; Android always). |
| `channel` | string \| null | The deposit account. |
| `deposit` | object \| null | `{basis, units, tdvpn, baseUnits}` for a per-server deposit (`tdvpn` = most it can hold; the unused part is refunded); `{plan, tdvpn: "0"}` with `--plan`; null when `reused`. |
| `reused` | `true` | Only when an existing session was kept. |
| `blockedBefore` | `true` | Only when the internet was blocked before this connect (no session, kill switch holding the block); the new session lifts it while it is up. A block connect cannot lift is refused with code `kill-switch-held`. |
| `next` | string | Always `<cli> agent down --yes` (one plain command a runner can run; E-38). |
| `note` | string | What the session means. Whole device: `the whole computer goes through the node; when done: <cli> agent down --yes`, with ` (<socks> works too)` after "node" when there is a `socks`. Only `socks`: `send traffic through <socks> (e.g. curl --proxy <socks> https://api.ipify.org); only apps that use it go through the node; when done: <cli> agent down --yes`. |
| `replaced` / `replacedNote` | object / string | Only when the live session was not tunnelled (its exit address is this computer's own, E-35): `replaced` = `{ node, code: "server-stopped" }`, `replacedNote` = `The server stopped serving; your traffic is NOT going through it. Switched to <node>; <old node> is skipped next time.` |

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
| `no-wallet` | up | `<cli> wallet create --keyfile <path> --yes, then fund the address it prints`; when this computer has a device record: `<cli> wallet import <the key file of <owner>, the wallet that set up this computer's device>, then <cli> agent up --yes` | Create a wallet in a 0600 key file, ask its owner to fund it. With a device record, import that wallet instead: a new one would not hold its funds. |
| `no-wallet` | down | `<cli> disconnect to leave the VPN now; <cli> wallet import <file> (the wallet that paid), then <cli> agent down --yes to close the deposits` | This computer's CLI has no wallet, so it cannot read or close deposits. Nothing ran. `disconnect` needs no wallet: run it to leave the VPN at once, then import the wallet that paid and run `agent down --yes`. |
| `keyfile-missing` | up, down, status | `restore <path> from your backup, then run the command again` | The key file that --keyfile or DVPN_KEYFILE names is gone. This is not "no wallet": a new wallet would not hold the funds, which stay with the lost key. Nothing ran. |
| `wallet-switch-needed` | up, down, status | `load the key file of the wallet named in "error", or <cli> device switch --yes (sets this computer up for the loaded wallet; the other wallet's deposits stay refundable)` | This computer is set up for another wallet, so the loaded key cannot pay here. Nothing was paid. |
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
| `protocol-missing` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <a ready one> --yes; or <cli> daemon repair-drivers --yes`. The deposit is refunded by `agent down --yes`. |
| `device-permission` | `<cli> device setup --yes, then <cli> agent up --yes` (as `no-device` from connect) |
| `daemon-unavailable` | `<cli> daemon doctor` |
| `daemon-restarting` | `<cli> agent up --yes again in a few seconds (the VPN service is restarting); if it keeps failing, <cli> daemon doctor` |
| `preflight` with action "Open diagnostics", "Open settings" or a "Repair drivers" sentence | `<cli> daemon doctor`, `<cli> daemon settings` or `<cli> daemon repair-drivers --yes`, each followed by `, then <cli> agent up --yes` |
| `test-running` | `<cli> test stop, then <cli> agent up --yes` (a server test holds the VPN service) |
| `rpc-busy` | `<cli> agent up --yes again in a minute (the network was busy)` |
| `spending-limit`, and `preflight` saying "Your spending approval is lower than this deposit" or "This device's spending limit is lower than this deposit" | `<cli> device setup --allowance <N> --yes (N = grant.allowance from "devnet-dvpn device show --json" divided by 1000000, plus the deposit, in tDVPN), then <cli> agent up --yes`. The approval only grows when N is above the current allowance. |
| `price-changed`, `deposit-unusable`, `deposits-unread` | `<cli> agent up --yes again (nothing was paid; it reads the price fresh)`. Nothing was paid in each case. `price-changed`: the server's price rose above the deposit `agent up` showed. `deposit-unusable`: your open deposit with this server started closing, so it cannot be used, and a new one is never paid without being shown. `deposits-unread`: your open deposits could not be read, so no second deposit was opened beside one you may have. `--max-price` still caps the next try. |
| `not-confirmed` | `<cli> agent up --yes (add --yes: nothing is paid without it)` |
| `busy` | `<cli> agent up --yes again in a few seconds (another connect was running)` |
| `keyfile-missing` | `restore the key file named in "error" from your backup (it is the only key to this wallet), then <cli> agent up --yes` |
| `plan-limit` | `<cli> agent up --plan <subscription> --node <a server you already use> --yes` |
| `network-mismatch` | `<cli> daemon install --yes (administrator once: it installs the service for this network), then <cli> agent up --yes` |
| `session-active` | `<cli> agent down --yes, then <cli> agent up --yes` |
| `node-gone`, `node-stale`, `node-offline`, `node-identity`, `node-ledger`, `peer_limit_reached`, `terms_rejected`; `preflight` with action "Pick another server" | `<cli> nodes list --online --json, then <cli> agent up --node <another server> --yes` |
| `protocol-blocked`, `tunnel-failed`, `tunnel-dead`, `tunnel-mtu`, `port-in-use` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <another ready one> --yes` |
| `driver-missing` | `<cli> daemon repair-drivers --yes, then <cli> agent up --yes` |
| `basis-unavailable` | `<cli> agent up --basis <the other one: per_gb or per_hour> --yes` |
| `not-enough-tdvpn` | `send tDVPN to the wallet address (<cli> agent status shows it), then <cli> agent up --yes` |
| `device-sol`, `ticket-other-owner`, `approval-revoked` | `<cli> device setup --yes, then <cli> agent up --yes` |
| `unauthorized` | `<cli> device show --json: if the grant is there and not revoked, set this computer's clock to the right time (a wrong clock makes the server refuse), then <cli> agent up --yes; otherwise <cli> device setup --yes, then <cli> agent up --yes` (E-22: clock skew answered this after a deposit opened) |
| `clock-skew` | `set this computer's clock to the right time (it is off by about N minutes), then <cli> agent up --yes`: refused before any deposit (nothing was paid); N is read from `error` ("about N min ahead of / behind the network's time") |
| `kill-switch-held` | `<cli> daemon restore-network, then <cli> agent up --yes` |
| `switch-reconnecting` | `<cli> agent status until "connected" is true, or <cli> agent down --yes first` |
| `switch-offline`, `timeout`, `ticket_request_stale`, `ticket_invalid`, `channel_node_reopened` | `<cli> agent up --yes again in a moment` |
| `cancelled` | `<cli> agent up --yes again (it was stopped before it finished)` |
| `waiting-for-network` | `<cli> agent up --yes again in a minute (this computer has no network yet)` |
| `service-stopped-connecting` | `<cli> quality ip; if it shows no address, <cli> daemon restore-network; then <cli> agent up --yes` |
| `node-price`, `credit_exhausted`, `lease_insufficient`, `voucher_exceeds_escrow`, `voucher_signature_invalid` | `<cli> agent down --yes, then <cli> agent up --yes (a new deposit)` |
| `node-error`, `rate_limited` | `<cli> agent up --yes again in a minute` |
| `provider_unreachable` | `<cli> agent up --yes again in a minute (the plan provider did not answer)` |
| `kill-switch-failed` | `<cli> agent up --yes again, or <cli> daemon set --kill-switch off --yes` |
| `tunnel-closing` | `<cli> agent up --yes again in a few seconds` |
| `dns-apply` | `<cli> daemon set --dns-mode none --yes (the VPN's DNS off), then <cli> agent up --yes` |
| `deposit-pending` | `<cli> agent up --yes again in a few minutes (it never pays twice)` |
| `rpc-network`, `rpc-quota` | `<cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` |
| `rpc-timeout` | `<cli> agent up --yes again in a minute; if it keeps failing, <cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` |
| `chain-encoding`, `mode_not_voucher` | `<cli> agent up --basis per_hour --yes` (pay per hour instead) |
| `mode_not_stream` | `<cli> agent up --basis per_gb --yes` |
| `subscription_invalid` | `<cli> plans subscriptions, then <cli> agent up --plan <an active one> --yes, or <cli> agent up --yes without --plan` |
| `cannot cover the prepay` | `<cli> agent up --units <more> --yes (a deposit large enough for the server's minimum)` |
| `preflight` (any other action) | `read "error": it names what to change (nothing was paid), then <cli> agent up --yes` |
| `stop-failed` | `<cli> daemon doctor, then <cli> agent up --yes` |
| `dns-revert-failed`, `tunnel-left` | `<cli> daemon restore-network` |
| `unknown`, `connect-failed`, `unsupported` | `<cli> agent status`: nothing more specific is known; read `error` |

Elevation: on Windows `agent up` can itself need one elevated step (the service pipe granting this
account); a non-elevated agent then gets `daemon-relogin`. On Linux/macOS the service install needs root once.

Every code connect() can answer (`CONNECT_CODES`) has a command above; a code before paying means nothing
was paid. Only `unknown`, `connect-failed` and `unsupported` answer `agent status`.
**An open deposit comes first (E-22):** when the start failed after the check before paying and a deposit is open
with that server, `action` is `a deposit of X tDVPN is open with this server (<channel>): <cli> agent up --node <node> --yes
picks another node (this server is skipped), or <cli> agent down --yes closes it and refunds the unused part at once (per hour: it bills until closed)` (per GB:
`2 h after it starts the close`; a closing deposit: `after <ISO readyAt>`), whatever the code. A failure that follows the deposit with code `unknown` or `connect-failed` answers `node-refused` (E-37; the server refused after it was paid, and is skipped next time). `agent status` then lists every open or closing deposit in `deposits` (`channel`, `node`, `status`, `refundable`, `readyAt`), with `next` = `<cli> agent down --yes` (closing: `<cli> agent down --yes after <ISO readyAt>`), never `agent up`, which would open a second deposit.

**The server stopped serving (E-35 / E-36):** when the exit address of the live session is this computer's own, or the daemon ended the session with "the connection to this server stopped working" in the last 30 min, `agent status` answers `connected: false`, `code: "server-stopped"`, `message` = `The server stopped serving; your traffic is NOT going through it. Your deposit is safe: <cli> agent down --yes closes it and the unused <X> tDVPN is refunded (<when>).`, `serverStopped` = `{ node, session, reason }`, `next` = `<cli> agent up --yes` (the dead server is skipped for 10 min), `alsoNext` = `<cli> agent down --yes`. `agent up` never reuses such a session (see `replaced`). Not for a plan connect or a code from the check before paying.
`tests/unit/agent-no-dead-end.test.ts` fails when a new code has no command here, or a next step names an app
screen or button. In text mode `cliMessage` also rewrites "press Restore network" (either case) in `error`; the
JSON `error` keeps the app sentence, so read `action` for what to run.

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
