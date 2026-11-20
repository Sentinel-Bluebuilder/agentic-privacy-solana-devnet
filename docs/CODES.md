# Failure codes: what each one means, whether money moved, what to run

Every `code` an agent can get from `devnet-dvpn agent status | up | down`, and from the follow-up
commands those answers tell it to run (`settle`, `device`, `wallet`). One row per code, four answers each:

- **Meaning**: what happened, in plain words.
- **Money moved?**: the `money` field of the `{ok:false}` line, by class. `none` = nothing was paid.
  `open` = a deposit may be open. `unclear` = the code does not say. `refund` = no new spend, but a refund
  is still held. Only `agent`, `connect`, `switch` and `test` failures carry `money`. On other commands
  this column says `no field` and then gives the true state.
- **Next**: the `action` the line carries (`<cli>` = `devnet-dvpn`, or `DVPN_CLI_NAME`). Run it as printed.
- **alsoNext**: the other way out. Only `agent status` prints an `alsoNext` field. On a failure line this
  column is this page's fallback for when **Next** does not work.

Source of truth: the `devnet-dvpn` app at 0.3.0-rc.5 (`afa55c19`), traced from `src/cli/agent-cmd.ts`.
`tools/check-glossary.mjs --src <devnet-dvpn checkout>` fails when a code those paths can return has no
row here, or when a row's money class differs from `src/cli/money-note.ts`.

**An open deposit wins over the code (E-22).** After a failed `agent up` past the check before paying,
if a deposit is open with that node, `action` is always
`a deposit of X tDVPN is open with this node (<channel>): <cli> agent up --yes picks another node (this node is skipped), or <cli> agent down --yes closes it and refunds the unused part …`,
whatever the code. The rows below give `action` for when no deposit is open.

## agent up: refused by agent-cmd itself

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `no-wallet` | No wallet in this CLI: no key file named, none in the vault. | `none` | `<cli> wallet create --keyfile <path> --yes, then fund the address it prints`. When this computer has a device record: `<cli> wallet import <the key file of <owner>, the wallet that set up this computer's device>, then <cli> agent up --yes (a new wallet would not hold its funds)` | `<cli> agent status` (shows `address: null`) |
| `keyfile-missing` | The key file that `--keyfile` or `DVPN_KEYFILE` names is gone. Not "no wallet": the funds stay with the lost key. | `none` | `restore the key file named in "error" from your backup (it is the only key to this wallet), then <cli> agent up --yes` | none: never `wallet create` (a new wallet holds none of the funds) |
| `no-device` | `daemon init` could not create this computer's device key. | `none` | `<cli> daemon doctor` | `<cli> device setup --yes, then <cli> agent up --yes` |
| `no-subscription` | `--plan` names a subscription this wallet does not hold, or one that is not active. | `none` | `<cli> plans list, then <cli> plans subscribe <plan> --yes` | `<cli> agent up --yes` without `--plan` (pays a deposit) |
| `no-nodes` | No online node matches `--protocol` / `--country` / `--max-price` / `--node` (or the plan's live roster). | `none` | `<cli> nodes list --online --json, then widen --protocol / --country / --max-price` | `<cli> agent up --basis <the other one> --yes` |
| `not-funded` | The wallet holds less than 0.02 SOL (before its first connect) or less tDVPN than the deposit shown. | `none` | `send at least <n> SOL and/or <n> tDVPN to <address>, then <cli> agent up --yes` | `<cli> agent up --units <fewer> --yes` (a smaller deposit) |
| `price-cap` | rc.6 and later. With no `--max-price` and no `--plan`, the deposit (price × units) is above the default cap: the Settings spending limit / 10, which is 5 tDVPN by default. This applies to the quick pick and to `--node`. Refused before paying. | `none` | `<cli> agent up --node <node> --basis <b> --units <n> --max-price <its price> --yes (you accept this price), or fewer --units, or another node` | `<cli> agent up --units <fewer> --yes` |
| `node-refused` | The connect failed with no specific code after the deposit opened (E-37). The node refused after it was paid. It is skipped next time. | `open` | the open-deposit sentence above | `<cli> agent down --yes` (closes it, refunds the unused part) |
| `connect-failed` | `connect()` failed and gave no code, with no deposit open. | `unclear` | `<cli> agent status` (read `error`) | `<cli> agent down --yes` (closes any deposit that is open) |

## agent up: from connect()

`action` = `nextFor(code)`. Each code here is in `CONNECT_CODES` (`src/core/session/state.ts`).
`tests/unit/connect-codes.test.ts` fails when the connect path answers a code outside that list.
A spending-limit shortfall, whatever its code, answers the `spending-limit` command.

### Refused before anything starts

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `not-confirmed` | The connect was asked without `--yes`. `agent up` itself always passes the confirm, so this comes only from a direct `connect`. | `none` | `<cli> agent up --yes (add --yes: nothing is paid without it)` | none |
| `wallet-switch-needed` | This computer is set up for another wallet, so the loaded key cannot pay here. Comes from `connect()` only, so `agent up` only. | `none` | `load the key file of the wallet named in "error", or <cli> device switch --yes (sets this computer up for the loaded wallet; the other wallet's deposits stay refundable)` | `<cli> agent status` (names the loaded address) |
| `clock-skew` | This computer's clock is off by N minutes. Refused before any deposit. | `none` | `set this computer's clock to the right time (it is off by about N minutes), then <cli> agent up --yes` | none |
| `device-permission` | This computer has no spending permission, or the permission or wallet switch could not be set up. | `none` | `<cli> device setup --yes, then <cli> agent up --yes` | `<cli> daemon doctor` |
| `plan-limit` | The plan does not allow a new node here. | `none` | `<cli> agent up --plan <subscription> --node <a node you already use> --yes` | `<cli> agent up --yes` without `--plan` (pays a deposit) |
| `busy` | Another connect was already running. | `none` | `<cli> agent up --yes again in a few seconds (another connect was running)` | `<cli> agent status` |
| `test-running` | A node test holds the VPN service. | `none` | `<cli> test stop, then <cli> agent up --yes` | none |
| `unsupported` | This system cannot do what was asked. | `none` | `<cli> agent status` (read `error`) | none |
| `daemon-missing` | The VPN service is not installed. | `none` | Linux/macOS: `<cli> daemon install --yes (administrator/root once: passwordless sudo, or a person types the password), then <cli> agent up --yes`. Windows: `<cli> daemon install --yes from an elevated shell or an administrator SSH login (a normal shell shows a UAC prompt an agent cannot answer), then <cli> agent up --yes` | `<cli> daemon doctor` |
| `daemon-relogin` | The service does not accept this account yet (Windows: the service pipe has not been granted to this account). | `none` | as `daemon-missing` (Windows: `… once from an elevated shell …`) | `<cli> daemon doctor` |
| `daemon-restarting` | The VPN service is restarting. | `none` | `<cli> agent up --yes again in a few seconds (the VPN service is restarting); if it keeps failing, <cli> daemon doctor` | `<cli> daemon doctor` |
| `daemon-unavailable` | The VPN service does not answer. | `none` | `<cli> daemon doctor` | `<cli> daemon install --yes` (administrator once) |
| `network-mismatch` | The installed service is for another network. | `none` | `<cli> daemon install --yes (administrator once: it installs the service for this network), then <cli> agent up --yes` | none |

### The check before paying (nothing has been paid for any of these)

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `session-active` | A VPN session is already running (from the command line or another window). | `none` | `<cli> agent down --yes, then <cli> agent up --yes` | `<cli> agent status` |
| `node-gone`, `node-stale`, `node-offline` | The node is no longer listed, has not checked in recently, or did not answer its probe. | `none` | `<cli> nodes list --online --json, then <cli> agent up --node <another node> --yes` | `<cli> agent up --yes` (the quick pick skips it for 10 min) |
| `protocol-blocked` | The kill switch blocks this protocol here. | `none` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <another ready one> --yes` | `<cli> daemon restore-network` |
| `driver-missing` | A network adapter or protocol program is missing from this computer. | `none` | `<cli> daemon repair-drivers --yes, then <cli> agent up --yes` | `<cli> agent up --protocol <another ready one> --yes` |
| `basis-unavailable` | The node does not sell per GB, or does not sell per hour. | `none` | `<cli> agent up --basis <the other one: per_gb or per_hour> --yes` | `<cli> agent up --node <another node> --yes` |
| `not-enough-tdvpn` | The wallet holds too little tDVPN for this deposit. | `none` | `send tDVPN to the wallet address (<cli> agent status shows it), then <cli> agent up --yes` | `<cli> agent up --units <fewer> --yes` |
| `spending-limit` | The spending approval or device limit is below this deposit. | `none` | `<cli> device setup --allowance <N> --yes (N = grant.allowance from "devnet-dvpn device show --json" divided by 1000000, plus the deposit, in tDVPN), then <cli> agent up --yes` | `<cli> agent up --units <fewer> --yes` |
| `device-sol` | The device or wallet is out of SOL for network fees. | `none` | `<cli> device setup --yes, then <cli> agent up --yes` | send SOL to the wallet address, then `<cli> agent up --yes` |
| `preflight` | A blocker with no code of its own. When it carries an app button ("Open diagnostics", "Open settings", "Repair drivers"), `action` is that button's command followed by `, then <cli> agent up --yes`. "Pick another server" gives the `node-gone` command. | `none` | `read "error": it names what to change (nothing was paid), then <cli> agent up --yes` | `<cli> agent status` |
| `kill-switch-held` | The kill switch still blocks the internet and lets through only the last node. | `none` | `<cli> daemon restore-network, then <cli> agent up --yes` | `<cli> agent down --yes` |
| `switch-reconnecting` | A node switch was asked while the session is reconnecting. | `none` | `<cli> agent status until "connected" is true, or <cli> agent down --yes first` | `<cli> agent down --yes` |
| `price-changed` | The node's price rose above the deposit `agent up` showed. | `none` | `<cli> agent up --yes again (nothing was paid; it reads the price fresh)` | `<cli> agent up --max-price <cap> --yes` |
| `deposit-unusable` | Your open deposit with this node has started closing, so it cannot be used, and a new deposit is never paid without being shown. | `none` | as `price-changed` | `<cli> agent up --node <another node> --yes` |
| `deposits-unread` | Your open deposits could not be read, so no second deposit was opened beside one you may already have. | `none` | as `price-changed` | `<cli> agent status` (lists `deposits`) |

### After the start was asked of the service (a deposit may be open)

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `switch-offline` | A switch failed with the old session gone. | `open` | `<cli> agent up --yes again in a moment` | `<cli> agent down --yes` |
| `cancelled` | The connect was stopped before it finished. The unused part of a sent deposit is refunded. | `open` | `<cli> agent up --yes again (it was stopped before it finished)` | `<cli> agent down --yes` |
| `waiting-for-network` | The service has no network yet. | `open` | `<cli> agent up --yes again in a minute (this computer has no network yet)` | `<cli> agent down --yes` |
| `ticket-other-owner` | The plan access belongs to another wallet than this computer's. | `open` | `<cli> device setup --yes, then <cli> agent up --yes` | `<cli> agent down --yes` |
| `approval-revoked` | This wallet's spending approval for this computer was revoked. | `open` | `<cli> device setup --yes, then <cli> agent up --yes` | `<cli> agent down --yes` |
| `service-stopped-connecting` | The service stopped while connecting. With the kill switch on, the internet stays blocked. | `open` | `<cli> quality ip; if it shows no address, <cli> daemon restore-network; then <cli> agent up --yes` | `<cli> agent down --yes` |
| `node-identity`, `node-ledger` | The node failed its identity check, or billed more than this device measured. | `open` | `<cli> nodes list --online --json, then <cli> agent up --node <another node> --yes` | `<cli> agent down --yes` |
| `node-price` | The node's price does not match the deposit. | `open` | `<cli> agent down --yes, then <cli> agent up --yes (a new deposit)` | `<cli> agent up --node <another node> --yes` |
| `node-error` | The node had a problem starting the session. The deposit is kept for the next try. | `open` | `<cli> agent up --yes again in a minute` | `<cli> agent down --yes` |
| `kill-switch-failed` | The service could not turn on the kill switch, so it stopped. | `open` | `<cli> agent up --yes again, or <cli> daemon set --kill-switch off --yes` | `<cli> agent down --yes` |
| `tunnel-failed`, `tunnel-dead`, `tunnel-mtu`, `port-in-use` | The tunnel did not come up, carries no traffic, hits packet-size drops, or its port is taken. | `open` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <another ready one> --yes` | `<cli> agent down --yes` |
| `tunnel-closing` | The previous node's tunnel is still closing. | `open` | `<cli> agent up --yes again in a few seconds` | `<cli> agent down --yes` |
| `dns-apply` | The VPN's DNS could not be applied. | `open` | `<cli> daemon set --dns-mode none --yes (the VPN's DNS off), then <cli> agent up --yes` | `<cli> agent down --yes` |
| `protocol-missing` | The node's protocol program is not on this computer. The deposit is kept. | `open` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <a ready one> --yes; or <cli> daemon repair-drivers --yes` | `<cli> agent down --yes` (refunds it) |
| `deposit-pending` | The deposit is still being confirmed. It is never paid twice. | `open` | `<cli> agent up --yes again in a few minutes (it never pays twice)` | `<cli> agent status` |
| `rpc-network`, `rpc-quota` | The network intercepts Solana RPC (login page, proxy, filter), or the service's RPC quota ran out. | `open` | `<cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` | `<cli> agent down --yes` |
| `rpc-timeout` | The service's RPC endpoint did not answer in time. | `open` | `<cli> agent up --yes again in a minute; if it keeps failing, <cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` | `<cli> agent down --yes` |
| `rpc-busy` | The RPC endpoint is rate-limiting. | `unclear` | `<cli> agent up --yes again in a minute (the network was busy)` | `<cli> agent status` (lists any deposit) |
| `timeout` | The node did not answer in time. | `open` | `<cli> agent up --yes again in a moment` | `<cli> agent down --yes` |
| `chain-encoding` | The network program rejected the payment transaction. | `open` | `<cli> agent up --basis per_hour --yes (pay per hour instead)` | `<cli> agent down --yes` |

### A node's own refusal (it comes after the deposit)

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `peer_limit_reached`, `terms_rejected` | The node is full, or refused the terms. | `open` | `<cli> nodes list --online --json, then <cli> agent up --node <another node> --yes` | `<cli> agent down --yes` |
| `credit_exhausted`, `lease_insufficient`, `voucher_exceeds_escrow`, `voucher_signature_invalid` | The deposit ran out or no longer covers the session. | `open` | `<cli> agent down --yes, then <cli> agent up --yes (a new deposit)` | `<cli> agent up --node <another node> --yes` |
| `subscription_invalid` | The plan subscription is not valid at this node. | `open` | `<cli> plans subscriptions, then <cli> agent up --plan <an active one> --yes, or <cli> agent up --yes without --plan` | `<cli> agent down --yes` |
| `ticket_request_stale`, `ticket_invalid`, `channel_node_reopened` | A ticket or channel race. Usually passes on a retry. | `open` | `<cli> agent up --yes again in a moment` | `<cli> agent down --yes` |
| `provider_unreachable` | The plan provider did not answer. | `open` | `<cli> agent up --yes again in a minute (the plan provider did not answer)` | `<cli> agent down --yes` |
| `rate_limited` | The node is rate-limiting. | `open` | `<cli> agent up --yes again in a minute` | `<cli> agent up --node <another node> --yes` |
| `unauthorized` | The node refused the device. A wrong clock causes this too (E-22). | `open` | `<cli> device show --json: if the grant is there and not revoked, set this computer's clock to the right time (a wrong clock makes the node refuse), then <cli> agent up --yes; otherwise <cli> device setup --yes, then <cli> agent up --yes` | `<cli> agent down --yes` |
| `cannot cover the prepay` | The deposit is below the node's minimum. | `open` | `<cli> agent up --units <more> --yes (a deposit large enough for the node's minimum)` | `<cli> agent down --yes` |
| `mode_not_voucher` | The node does not take per-GB vouchers. | `open` | `<cli> agent up --basis per_hour --yes` | `<cli> agent down --yes` |
| `mode_not_stream` | The node does not take per-hour streams. | `open` | `<cli> agent up --basis per_gb --yes` | `<cli> agent down --yes` |

### Leaving, and the catch-all

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `stop-failed` | Stopping the previous session failed during a switch. The internet may not work. | `open` | `<cli> daemon doctor, then <cli> agent up --yes` | `<cli> daemon restore-network` |
| `dns-revert-failed`, `tunnel-left` | DNS or a tunnel was left behind. | `open` | `<cli> daemon restore-network` | `<cli> agent down --yes` |
| `unknown` | Nothing more specific is known. | `unclear` | `<cli> agent status` (read `error`) | `<cli> agent down --yes` (closes any open deposit) |

## agent down

`agent down` runs `disconnect` and then one `settle run`. If the disconnect fails, nothing is settled.

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `no-wallet` | This CLI has no wallet, so it cannot read or close deposits. Nothing ran. | `none` | `<cli> disconnect to leave the VPN now; <cli> wallet import <file> (the wallet that paid), then <cli> agent down --yes to close the deposits` | `<cli> disconnect` (needs no wallet) |
| `keyfile-missing` | The named key file is gone. Nothing ran. | `none` | `<cli> disconnect to leave the VPN now; restore the key file named in "error" from your backup (it is the only key to this wallet), then <cli> agent down --yes` | `<cli> disconnect` |
| `stop-failed` | The disconnect failed with no plainer code. No deposit was closed, and a per-hour deposit keeps billing while the session is up. | `open` | `<cli> daemon doctor, then <cli> agent down --yes again` | `<cli> daemon restore-network` |
| `dns-revert-failed` | The session **did** stop, but DNS could not be restored. On rc5 the message still begins "Could not disconnect, so no deposit was closed". The first half is wrong; the second is right, because the settle step did not run. rc.6: "The session stopped, but this computer's DNS could not be put back. No deposit was closed yet." | `open` | rc5: `<cli> daemon doctor, then <cli> agent down --yes again` (the second `agent down` finds no session and closes the deposits). rc.6: `<cli> daemon restore-network, then <cli> agent down --yes again (it closes the deposits)` | `<cli> daemon restore-network` (the fix for the DNS) |
| `service-down`, `service-not-ready`, `rpc-unavailable` | The disconnect failed in the VPN service, or on every RPC endpoint (plain copy; see "Any of the three" below). No deposit was closed. | `none` / `none` / `unclear` | `<cli> daemon doctor, then <cli> agent down --yes again` | `<cli> daemon restore-network` |
| `approval-revoked`, `not-enough-tdvpn`, `session-active` | Plain copy of a service error. With the disconnect these mean a service fault. No deposit was closed. | `open` / `none` / `none` | `<cli> daemon doctor, then <cli> agent down --yes again` | `<cli> disconnect` |
| `busy` | Disconnected, but another refund run in this process held the lock, so nothing was closed. A per-hour deposit bills until closed. | `none` | `<cli> settle run --yes` | `<cli> settle list` |
| `settle-failed` | Disconnected. Some deposits could not be refunded yet; the others are done. | `refund` | `<cli> settle list` | `<cli> settle run --yes` |
| `daemon-gone` | Disconnected, but the VPN service stopped during the refund. Nothing was lost, and the settle runs again later. | `unclear` on rc5 (unclassified; the true state is refund) · rc.6: `refund` | `<cli> settle list` | `<cli> settle run --yes` |

A successful `agent down` whose deposits another device of this wallet opened (E-72) is `ok: true` with `notClosed` and
`warning`. Its `next` is `<cli> device revoke --device <D> --yes (if it is not revoked yet), then <cli> settle run --device <D> --yes`.

## agent status

`agent status` reads only and never fails with a code of its own. Its one code is a field on an `ok: true` answer:

| Code | Meaning | Money moved? | Next | alsoNext |
|---|---|---|---|---|
| `server-stopped` | The node stopped serving. The exit address is this computer's own, or the daemon ended the session in the last 30 min. `connected: false`. The deposit is safe. | `open` (no `money` field: `ok` is true) | `<cli> agent up --yes` (the dead node is skipped for 10 min). With `blocked`: `<cli> daemon restore-network (lifts the block; then <cli> agent up --yes to reconnect, or <cli> agent down --yes)` | `<cli> agent down --yes` (an `alsoNext` field) |

## Any of the three: replaced on the way out

`index.ts` (`plainError`) replaces a raw service or RPC failure with the shared copy. This happens for any
throw that `agent-cmd` did not turn into its own code: for example, the wallet or node read before `agent up`,
or the deposit read in `agent down`.

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `service-down` | The VPN service is off. | `none` | the service start hint, or null | `<cli> daemon doctor` |
| `service-not-ready` | The service is starting or stopping. | `none` | null: run the same command again in a moment | `<cli> daemon doctor` |
| `rpc-unavailable` | Every RPC endpoint failed (rate limit, not a Solana RPC endpoint, or a timeout). | `unclear` | the RPC hint (check the network, or set another RPC) | `<cli> daemon set --rpc <https url> --yes` |
| `approval-revoked` | The spending approval for this computer was revoked. | `open` | `devnet-dvpn device setup --yes` | `<cli> agent status` |
| `not-enough-tdvpn` | The wallet lacks tDVPN for the deposit. | `none` | null: fund the wallet or use fewer `--units` | `<cli> agent status` (shows the address) |
| `session-active` | A session is already active. | `none` | `devnet-dvpn disconnect` | `<cli> agent down --yes` |
| (`code: null`) | A throw with no code (e.g. the key store locked over SSH, E-66). | `unclear` | null: read `error` | `<cli> agent status` |

Exit 2 (`needsConfirm: true`) and exit 3 (usage) carry no `code`. See `docs/AGENT-COMMANDS.md`.

## Follow-up commands the answers name

These are not `agent` commands, so they carry **no `money` field**. The column gives the true state.

| Code | From | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|---|
| `no-wallet` | `settle list / run / withdraw`, `device switch` | No wallet in this CLI. | `no field`: nothing ran | none (the message says `wallet create` or `wallet import <file>`) | import the wallet that paid, then run it again |
| `keyfile-missing` | same | The named key file is gone. | `no field`: nothing ran | none: restore the file from your backup | none |
| `busy` | `settle run` | Another refund run in this process. | `no field`: nothing closed | none: run `<cli> settle run --yes` again | `<cli> settle list` |
| `settle-failed` | `settle run` | Some deposits could not be refunded yet; the others are done. | `no field`: refund still held | none: `<cli> settle run --yes` again later | `<cli> settle list` |
| `daemon-gone` | `settle run` | The VPN service stopped during the refund. Nothing was lost. | `no field`: refund still held | none: `<cli> settle run --yes` again | `<cli> daemon doctor` |
| `withdraw-failed` | `settle withdraw` | The withdraw transaction failed. A zero balance is not this code: it prints "Nothing to withdraw" with exit 0. | `no field`: balance still held | none: `<cli> settle withdraw --yes` again | `<cli> settle list` |
| `no-device-key` | `device setup` (rc.6) | `device setup` ran before `daemon init`. On rc5 this was the same sentence with `code: null`. | `no field`: nothing signed | none: the message says `devnet-dvpn daemon init`, then `device setup` again | `<cli> agent status` |
| `wallet-is-device` | `device setup` | The wallet and the device key are the same key. | `no field`: nothing signed | none: use a separate wallet key | `<cli> device show --json` |
| `device-setup-failed` | `device setup` | The setup transaction failed. | `no field`: nothing set up (a SOL top-up may have landed) | none: run `device setup --yes` again | `<cli> daemon doctor` |
| `device-permission`, `device-sol` | `device switch` | The switch could not finish (read, stage or service step), or the wallet lacks SOL for it. This computer stays set up for the other wallet. | `no field`: nothing paid | the app's button as a command, or none | send SOL, then `<cli> device switch --yes` |
| `switch-failed` | `device switch` | The switch failed with no code. | `no field`: nothing paid | none | `<cli> daemon doctor` |
| `revoke-failed` | `device revoke [--device D]` | The revoke transaction failed. | `no field`: nothing changed | none: run it again | `<cli> device show --json` |
| `bad-device`, `own-device` | `device revoke --device D` | `D` is not a device address, or it is this computer's own device. | `no field`: nothing ran | none: `device revoke` without `--device` for this computer | `<cli> device show --json` |
| `device-key-unreadable` | `device register` | The service's key folder is admin-only. | `no field`: nothing ran | the `device register <address>` form (no administrator needed) | none |
| `invalid-address`, `invalid-amount`, `send-failed` | `wallet send` | Bad recipient, bad amount, or a failed transfer. | `no field`: nothing sent (`send-failed`: check the wallet) | none | `<cli> agent status` (balances) |

`settle run --device <this computer's device>`, the daemon commands, and (rc5 only) `device setup` with no
device key yet fail with `code: null` and a plain sentence that names the fix.

## rc.6: built in the app's source, not released yet

Read this section only when `devnet-dvpn version --json` says `0.3.0-rc.6` or newer. Every row above still
holds, apart from the changes listed here.

**Exit codes by class** (`src/cli/exit-codes.ts`). The `code` field stays the precise reason.

| Exit | Class | Codes |
|---|---|---|
| 0 | ok | none |
| 1 | error | any code not listed below, and `code: null`. Includes `rpc-timeout`, `rpc-network`, `rpc-quota` and `timeout`: network codes whose money class is `open` (a deposit may be open) |
| 2 | needs `--yes` | no code (`needsConfirm: true`) |
| 3 | wrong usage | no code |
| 4 | needs you or your operator | `not-funded`, `spending-limit`, `price-cap`, `no-wallet` |
| 5 | refused for safety | `kill-switch-held` (money `none`), `kill-switch-failed` (money `open`: read `money`), and `kill-switch` |
| 6 | network or RPC, no deposit possibly open: retry later | `rpc-busy`, `rpc-unavailable` (money `unclear`), and `rpc-ws` |

Exit 6 is given only to a network code whose money class is not `open` (`exitCodeFor`: `moneyOf(code) !== 'open'`).
A network failure after which a deposit may be open exits 1. Exit 5 can still follow an open deposit
(`kill-switch-failed`). On any non-zero exit, read `money` before you retry.

**Changed answers:**
- `spending-limit` on `agent up --yes`: with the limit below the deposit and no `--raise-limit`, the
  answer is a refusal with nothing paid. `action` = `<cli> agent up --node <node> --basis <b> --units <n> --raise-limit --yes`.
  rc5 raised the limit inside `--yes` and said so in `limitRaised`.
- `node-refused` and `connect-failed`: "Something went wrong" no longer reaches the agent. With a deposit
  open: "The node did not start the session after your deposit was paid … The deposit is safe". Without
  one: "Connect failed for a reason this app does not name … Nothing was paid", pointing to `<cli> logs --lines 80`.
- New code `price-cap` (see its row under "agent up: refused by agent-cmd itself"): a default deposit cap
  of the Settings limit / 10 when `--max-price` is not given.
- `dns-revert-failed` on `agent down`: see its row.
- `daemon-gone`: money class `refund`.
- `agent status` with the service down and no device yet (E-84): `next` is the service install
  (`daemon-missing`), not `agent up --yes`.
- Amounts gain base-unit siblings: `solLamports`, `tdvpnBase`, `heldBase`, `spentBase` (status);
  `spentBase`, `refundableBase` (down); `deposit.tdvpnBase` (up).
- `version --json` adds `programId` and `mint` (E-81).
