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

Source of truth: the `devnet-dvpn` app at 0.3.0-rc.9 (`68d0f22e8`, 124 traced codes, every one with a row), traced from `src/cli/agent-cmd.ts`.
`tools/check-glossary.mjs --src <devnet-dvpn checkout>` fails when a code those paths can return has no
row here, or when a row's money class differs from `src/cli/money-note.ts`.

**An open deposit wins over the code (E-22).** After a failed `agent up` past the check before paying,
if a deposit is open with that node, `action` is always
`a deposit of X tDVPN is open with this node (<channel>): <cli> agent up --yes picks another node (this node is skipped), or <cli> agent down --yes closes it and refunds the unused part …`,
whatever the code. The rows below give `action` for when no deposit is open.

## agent up: refused by agent-cmd itself

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| <a id="code-no-wallet"></a>`no-wallet` | No wallet in this CLI: no key file named, none in the vault. rc.9: `daemon init` says it too (exit 4). | `none` | `<cli> wallet create --keyfile <path> --yes, then fund the address it prints`. When this computer has a device record: `<cli> wallet import <the key file of <owner>, the wallet that set up this computer's device>, then <cli> agent up --yes (a new wallet would not hold its funds)` | `<cli> agent status` (shows `address: null`) |
| <a id="code-keyfile-missing"></a>`keyfile-missing` | The key file that `--keyfile` or `DVPN_KEYFILE` names is gone. Not "no wallet": the funds stay with the lost key. | `none` | `restore the key file named in "error" from your backup (it is the only key to this wallet), then <cli> agent up --yes` | none: never `wallet create` (a new wallet holds none of the funds) |
| <a id="code-keyfile-mode"></a>`keyfile-mode` | Linux and macOS since rc.7, Windows since rc.9 (the file's ACL gives Users, Everyone or Authenticated Users access). The key file can be read by other users (its mode or ACL is in `error`). Refused before anything is signed. Exit 4: a person fixes it. | `none` | `chmod 600 <the key file>, then <cli> agent up --yes` (Windows: the `icacls "<the key file>" /inheritance:r /grant:r …` line in `next`) | none |
| <a id="code-keyfile-unreadable"></a>`keyfile-unreadable` | rc.9. This user cannot read the key file that `--keyfile` or `DVPN_KEYFILE` names (`EACCES` or `EPERM`; the path is in `error`). Nothing was sent or signed. Exit 4: a person fixes it. Not `keyfile-missing` (the file is there) and not `keyfile-mode` (that one is readable by too many). | `none` | Linux and macOS: `sudo chown $(id -un) <the key file> && chmod 600 <the key file>, then <cli> wallet show --json`. Windows: `icacls "<the key file>" /grant "<DOMAIN\user>:R", then <cli> wallet show --json` | none: never `wallet create` (a new wallet holds none of the funds) |
| <a id="code-no-device"></a>`no-device` | `daemon init` could not create this computer's device key. | `none` | `<cli> daemon doctor` | `<cli> device setup --yes, then <cli> agent up --yes` |
| <a id="code-no-subscription"></a>`no-subscription` | `--plan` names a subscription this wallet does not hold, or one that is not active. rc.9: `connect` raises it too. | `none` | `<cli> plans list, then <cli> plans subscribe <plan> --yes` | `<cli> agent up --yes` without `--plan` (pays a deposit) |
| <a id="code-no-nodes"></a>`no-nodes` | No online node matches `--protocol` / `--country` / `--max-price` / `--node` (or the plan's live roster). Under `--max-price` (rc7) the message names the cheapest matching price above it. From rc.8 it names the real blocker, and its `next` never repeats the failing line: a price above the cap (only from nodes that answer their check, plus how many at or under the cap do not answer); no node in that country but some elsewhere (`next` drops `--country`); only another protocol (`next` drops `--protocol`); with `--node`, why that node is not picked (not on the network, the one in use now, does not offer the protocol, …), keeping `--node` where a retry can work. | `none` | Under `--max-price` with a match above it (rc7): `<cli> agent up [--protocol <p>] [--country <c>] --basis <b> --units <n> --max-price <the cheapest price> --yes` (runnable as printed). Otherwise: `<cli> nodes list --online --json, then widen --protocol / --country / --max-price` | `<cli> agent up --basis <the other one> --yes` |
| <a id="code-not-funded"></a>`not-funded` | The wallet holds less than 0.06 SOL (rc7; 0.02 before) before its first connect, or less tDVPN than the deposit shown. rc7 names the exact shortfall and, when larger, a recommended amount that also covers a reconnect. | `none` | `send at least <n> SOL and/or <n> tDVPN (<m> recommended: it also covers a reconnect) to <address>, then <cli> agent up --yes` | `<cli> agent up --units <fewer> --yes` (a smaller deposit) |
| <a id="code-price-cap"></a>`price-cap` | rc.6 and later. With no `--max-price` and no `--plan`, the deposit (price × units) is above the default cap, `defaults.priceCap` in the preview. rc7: the larger of the spending limit / 10 and the p75 price of the matching online nodes × `--units`, never above the limit; with fewer than 3 priced nodes, the limit / 10 (rc.6: always the limit / 10). The message names the node's price and the `--max-price` that accepts it. This applies to the quick pick and to `--node`. Refused before paying. | `none` | `<cli> agent up --node <node> --basis <b> --units <n> --max-price <its price> --yes (you accept this price), or fewer --units, or another node` | `<cli> agent up --units <fewer> --yes` |
| <a id="code-node-refused"></a>`node-refused` | The connect failed with no specific code after the deposit opened (E-37). The node refused after it was paid. It is skipped next time. | `open` | the open-deposit sentence above | `<cli> agent down --yes` (closes it, refunds the unused part) |
| <a id="code-connect-failed"></a>`connect-failed` | `connect()` failed and gave no code, with no deposit open. | `unclear` | `<cli> agent status` (read `error`) | `<cli> agent down --yes` (closes any deposit that is open) |

## agent up: from connect()

`action` = `nextFor(code)`. Each code here is in `CONNECT_CODES` (`src/core/session/state.ts`).
`tests/unit/connect-codes.test.ts` fails when the connect path answers a code outside that list.
A spending-limit shortfall, whatever its code, answers the `spending-limit` command.

### Refused before anything starts

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| <a id="code-not-confirmed"></a>`not-confirmed` | The connect was asked without `--yes`. `agent up` itself always passes the confirm, so this comes only from a direct `connect`. | `none` | `<cli> agent up --yes (add --yes: nothing is paid without it)` | none |
| <a id="code-wallet-switch-needed"></a>`wallet-switch-needed` | This computer is set up for another wallet, so the loaded key cannot pay here. Answered by `agent status` and `daemon install`, and named in `daemon doctor`'s service-wallet row; restarting the service does not clear it. | `none` | `load the key file of the wallet named in "error", or <cli> device switch --yes (sets this computer up for the loaded wallet; the other wallet's deposits stay refundable)` | `<cli> agent status` (names the loaded address) |
| <a id="code-clock-skew"></a>`clock-skew` | This computer's clock is off by N minutes. Refused before any deposit (rc.9: also named by `agent status`, `clockSkewSec`, and by `agent up` before any device or funding check). | `none` | the time-sync line for this OS, then `<cli> agent up --yes`: Linux `sudo timedatectl set-ntp true && (sudo chronyc makestep 2>/dev/null \|\| true)`, macOS `sudo sntp -sS time.apple.com`, Windows `Start-Service w32time; w32tm /resync /force` (elevated PowerShell). Exit 4 | none |
| <a id="code-device-permission"></a>`device-permission` | This computer has no spending permission, or the permission or wallet switch could not be set up. | `none` | `<cli> device setup --yes, then <cli> agent up --yes` | `<cli> daemon doctor` |
| <a id="code-plan-limit"></a>`plan-limit` | The plan does not allow a new node here. | `none` | `<cli> agent up --plan <subscription> --node <a node you already use> --yes` | `<cli> agent up --yes` without `--plan` (pays a deposit) |
| <a id="code-busy"></a>`busy` | Another connect was already running. | `none` | `<cli> agent up --yes again in a few seconds (another connect was running)` | `<cli> agent status` |
| <a id="code-test-running"></a>`test-running` | A node test holds the VPN service. | `none` | `<cli> test stop, then <cli> agent up --yes` | none |
| <a id="code-unsupported"></a>`unsupported` | This system cannot do what was asked. | `none` | `<cli> agent status` (read `error`) | none |
| <a id="code-daemon-missing"></a>`daemon-missing` | The VPN service is not installed. | `none` | Linux/macOS: `<cli> daemon install --yes (administrator/root once: passwordless sudo, or a person types the password), then <cli> agent up --yes`. Windows: `<cli> daemon install --yes from an elevated shell or an administrator SSH login (a normal shell shows a UAC prompt an agent cannot answer), then <cli> agent up --yes` | `<cli> daemon doctor` |
| <a id="code-daemon-relogin"></a>`daemon-relogin` | The service does not accept this account yet (Windows: the service pipe has not been granted to this account). | `none` | as `daemon-missing` (Windows: `… once from an elevated shell …`) | `<cli> daemon doctor` |
| <a id="code-daemon-restarting"></a>`daemon-restarting` | The VPN service is restarting. | `none` | `<cli> agent up --yes again in a few seconds (the VPN service is restarting); if it keeps failing, <cli> daemon doctor` | `<cli> daemon doctor` |
| <a id="code-daemon-unavailable"></a>`daemon-unavailable` | The VPN service does not answer. | `none` | `<cli> daemon doctor` | `<cli> daemon install --yes` (administrator once). rc.9, from `daemon restore-network`: `next` = Windows `Start-Service 'sentinel-dvpnd$c0' in an administrator PowerShell, then <cli> daemon restore-network`; Linux `sudo systemctl restart sentinel-dvpnd@c0, then <cli> daemon restore-network`; macOS `sudo launchctl kickstart -k system/co.sentinel.sentinel-dvpnd.c0, then <cli> daemon restore-network` |
| <a id="code-network-mismatch"></a>`network-mismatch` | The installed service is for another network. | `none` | `<cli> daemon install --yes (administrator once: it installs the service for this network), then <cli> agent up --yes` | none |

### The check before paying (nothing has been paid for any of these)

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| <a id="code-session-active"></a>`session-active` | A VPN session is already running (from the command line or another window). | `none` | `<cli> agent status --json` (another run holds the session: look, never end it) | `<cli> agent status` |
| <a id="code-node-gone"></a><a id="code-node-stale"></a><a id="code-node-offline"></a>`node-gone`, `node-stale`, `node-offline` | The node is no longer listed, has not checked in recently, or did not answer its probe. rc.9: `connect` raises `node-gone` too. | `none` | `<cli> nodes list --online --json, then <cli> agent up --node <another node> --yes` | `<cli> agent up --yes` (the quick pick skips it for 10 min) |
| <a id="code-protocol-blocked"></a>`protocol-blocked` | The kill switch blocks this protocol here. | `none` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <another ready one> --yes` | `<cli> daemon restore-network` |
| <a id="code-driver-missing"></a>`driver-missing` | A network adapter or protocol program is missing from this computer. | `none` | `<cli> daemon repair-drivers --yes, then <cli> agent up --yes` | `<cli> agent up --protocol <another ready one> --yes` |
| <a id="code-basis-unavailable"></a>`basis-unavailable` | The node does not sell per GB, or does not sell per hour. | `none` | `<cli> agent up --basis <the other one: per_gb or per_hour> --yes` | `<cli> agent up --node <another node> --yes` |
| <a id="code-not-enough-tdvpn"></a>`not-enough-tdvpn` | The wallet holds too little tDVPN for this deposit. | `none` | `send tDVPN to the wallet address (<cli> agent status shows it), then <cli> agent up --yes` | `<cli> agent up --units <fewer> --yes` |
| <a id="code-spending-limit"></a>`spending-limit` | The spending approval or device limit is below this deposit. On `agent up --yes` without `--raise-limit` (rc.6 and later) nothing is paid; the message names the limit, the deposit and the raised limit. | `none` | rc.9: `<cli> device setup --allowance <this deposit> --yes, then <cli> agent up --node <node> [--protocol <p>] --basis <b> --units <n> [--max-price <m>] --yes`: the limit set to this deposit only, then your own line, pinned to the node `agent up` picked, every flag you gave kept (E-88); `alsoNext` = the same line with `--raise-limit --yes` (raises it to the Settings limit). From `connect()` (no `--raise-limit` path): `<cli> device setup --allowance <N> --yes, then <cli> agent up --yes` | `<cli> agent up --units <fewer> --yes` |
| <a id="code-device-sol"></a>`device-sol` | The device or wallet is out of SOL for network fees. | `none` | `<cli> device setup --yes, then <cli> agent up --yes` | send SOL to the wallet address, then `<cli> agent up --yes` |
| <a id="code-preflight"></a>`preflight` | A blocker with no code of its own. When it carries an app button ("Open diagnostics", "Open settings", "Repair drivers"), `action` is that button's command followed by `, then <cli> agent up --yes`. "Pick another server" gives the `node-gone` command. | `none` | `read "error": it names what to change (nothing was paid), then <cli> agent up --yes` | `<cli> agent status` |
| <a id="code-kill-switch-held"></a>`kill-switch-held` | The kill switch still blocks the internet and lets through only the last node. | `none` | `<cli> daemon restore-network, then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-switch-reconnecting"></a>`switch-reconnecting` | A node switch was asked while the session is reconnecting. | `none` | `<cli> agent status until "connected" is true, or <cli> agent down --yes first` | `<cli> agent down --yes` |
| <a id="code-price-changed"></a>`price-changed` | The node's price rose above the deposit `agent up` showed. | `none` | `<cli> agent up --yes again (nothing was paid; it reads the price fresh)` | `<cli> agent up --max-price <cap> --yes` |
| <a id="code-deposit-unusable"></a>`deposit-unusable` | Your open deposit with this node has started closing, so it cannot be used, and a new deposit is never paid without being shown. | `none` | as `price-changed` | `<cli> agent up --node <another node> --yes` |
| <a id="code-deposits-unread"></a>`deposits-unread` | Your open deposits could not be read, so no second deposit was opened beside one you may already have. | `none` | as `price-changed` | `<cli> agent status` (lists `deposits`) |

### After the start was asked of the service (a deposit may be open)

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| <a id="code-switch-offline"></a>`switch-offline` | A switch failed with the old session gone. | `open` | `<cli> agent up --yes again in a moment` | `<cli> agent down --yes` |
| <a id="code-cancelled"></a>`cancelled` | The connect was stopped before it finished. The unused part of a sent deposit is refunded. | `open` | `<cli> agent up --yes again (it was stopped before it finished)` | `<cli> agent down --yes` |
| <a id="code-waiting-for-network"></a>`waiting-for-network` | The service cannot reach the Solana network yet (its own RPC check failed). rc.9: nothing was paid, exit 6 on every command (rc.8: money `open`, exit 1). | `none` | `<cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` | `<cli> agent up --yes` again in a minute, if the network was only late |
| <a id="code-ticket-other-owner"></a>`ticket-other-owner` | The plan access belongs to another wallet than this computer's. | `open` | `<cli> device setup --yes, then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-approval-revoked"></a>`approval-revoked` | This wallet's spending approval for this computer was revoked. | `open` | `<cli> device setup --yes, then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-service-stopped-connecting"></a>`service-stopped-connecting` | The service stopped while connecting. With the kill switch on, the internet stays blocked. | `open` | `<cli> quality ip; if it shows no address, <cli> daemon restore-network; then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-node-identity"></a><a id="code-node-ledger"></a>`node-identity`, `node-ledger` | The node failed its identity check, or billed more than this device measured. | `open` | `<cli> nodes list --online --json, then <cli> agent up --node <another node> --yes` | `<cli> agent down --yes` |
| <a id="code-node-price"></a>`node-price` | The node's price does not match the deposit. | `open` | `<cli> agent down --yes, then <cli> agent up --yes (a new deposit)` | `<cli> agent up --node <another node> --yes` |
| <a id="code-node-error"></a>`node-error` | The node had a problem starting the session. The deposit is kept for the next try. | `open` | `<cli> agent up --yes again in a minute` | `<cli> agent down --yes` |
| <a id="code-kill-switch-failed"></a>`kill-switch-failed` | The service could not turn on the kill switch, so it stopped. | `open` | `<cli> agent up --yes again, or <cli> daemon set --kill-switch off --yes` | `<cli> agent down --yes` |
| <a id="code-tunnel-failed"></a><a id="code-tunnel-dead"></a><a id="code-tunnel-mtu"></a><a id="code-port-in-use"></a>`tunnel-failed`, `tunnel-dead`, `tunnel-mtu`, `port-in-use` | The tunnel did not come up, carries no traffic, hits packet-size drops, or its port is taken. | `open` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <another ready one> --yes` | `<cli> agent down --yes` |
| <a id="code-tunnel-closing"></a>`tunnel-closing` | The previous node's tunnel is still closing. | `open` | `<cli> agent up --yes again in a few seconds` | `<cli> agent down --yes` |
| <a id="code-dns-apply"></a>`dns-apply` | The VPN's DNS could not be applied. | `open` | `<cli> daemon set --dns-mode none --yes (the VPN's DNS off), then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-protocol-missing"></a>`protocol-missing` | The node's protocol program is not on this computer. The deposit is kept. | `open` | `<cli> daemon drivers (it lists the protocols ready on this computer), then <cli> agent up --protocol <a ready one> --yes; or <cli> daemon repair-drivers --yes` | `<cli> agent down --yes` (refunds it) |
| <a id="code-deposit-pending"></a>`deposit-pending` | The deposit is still being confirmed. It is never paid twice. | `open` | `<cli> agent up --yes again in a few minutes (it never pays twice)` | `<cli> agent status` |
| <a id="code-rpc-network"></a><a id="code-rpc-quota"></a>`rpc-network`, `rpc-quota` | The network intercepts Solana RPC (login page, proxy, filter), or the service's RPC quota ran out. | `open` | `<cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-rpc-timeout"></a>`rpc-timeout` | The service's RPC endpoint did not answer in time. | `open` | `<cli> agent up --yes again in a minute; if it keeps failing, <cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-rpc-busy"></a>`rpc-busy` | The RPC endpoint is rate-limiting. | `unclear` | `<cli> agent up --yes again in a minute (the network was busy)` | `<cli> agent status` (lists any deposit) |
| <a id="code-rpc-ws"></a>`rpc-ws` | rc.7. The service could not keep its Solana websocket (the RPC pair's ws side). Exit 6 (rc.9: exit 1 from `agent up`). | `unclear` | `<cli> daemon set --rpc <https url> --yes (the VPN service's Solana connection), then <cli> agent up --yes` | `<cli> agent status` (lists any deposit) |
| <a id="code-timeout"></a>`timeout` | The node did not answer in time. | `open` | `<cli> agent up --yes again in a moment` | `<cli> agent down --yes` |
| <a id="code-chain-encoding"></a>`chain-encoding` | The network program rejected the payment transaction. | `open` | `<cli> agent up --basis per_hour --yes (pay per hour instead)` | `<cli> agent down --yes` |

### A node's own refusal (it comes after the deposit)

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| <a id="code-peer_limit_reached"></a><a id="code-terms_rejected"></a>`peer_limit_reached`, `terms_rejected` | The node is full, or refused the terms. | `open` | `<cli> nodes list --online --json, then <cli> agent up --node <another node> --yes` | `<cli> agent down --yes` |
| <a id="code-credit_exhausted"></a><a id="code-lease_insufficient"></a><a id="code-voucher_exceeds_escrow"></a><a id="code-voucher_signature_invalid"></a>`credit_exhausted`, `lease_insufficient`, `voucher_exceeds_escrow`, `voucher_signature_invalid` | The deposit ran out or no longer covers the session. | `open` | `<cli> agent down --yes, then <cli> agent up --yes (a new deposit)` | `<cli> agent up --node <another node> --yes` |
| <a id="code-subscription_invalid"></a>`subscription_invalid` | The plan subscription is not valid at this node. | `open` | `<cli> plans subscriptions`, then `<cli> agent up --plan <an active one> --yes`, or `<cli> agent up --yes` without `--plan` | `<cli> agent down --yes` |
| <a id="code-ticket_request_stale"></a><a id="code-ticket_invalid"></a><a id="code-channel_node_reopened"></a>`ticket_request_stale`, `ticket_invalid`, `channel_node_reopened` | A ticket or channel race. Usually passes on a retry. | `open` | `<cli> agent up --yes again in a moment` | `<cli> agent down --yes` |
| <a id="code-provider_unreachable"></a>`provider_unreachable` | The plan provider did not answer. | `open` | `<cli> agent up --yes again in a minute (the plan provider did not answer)` | `<cli> agent down --yes` |
| <a id="code-rate_limited"></a>`rate_limited` | The node is rate-limiting. | `open` | `<cli> agent up --yes again in a minute` | `<cli> agent up --node <another node> --yes` |
| <a id="code-unauthorized"></a>`unauthorized` | The node refused the device. A wrong clock causes this too (E-22). | `open` | `<cli> device show --json: if the grant is there and not revoked, set this computer's clock to the right time (a wrong clock makes the node refuse), then <cli> agent up --yes; otherwise <cli> device setup --yes, then <cli> agent up --yes` | `<cli> agent down --yes` |
| <a id="code-cannot cover the prepay"></a>`cannot cover the prepay` | The deposit is below the node's minimum. | `open` | `<cli> agent up --units <more> --yes (a deposit large enough for the node's minimum)` | `<cli> agent down --yes` |
| <a id="code-mode_not_voucher"></a>`mode_not_voucher` | The node does not take per-GB vouchers. | `open` | `<cli> agent up --basis per_hour --yes` | `<cli> agent down --yes` |
| <a id="code-mode_not_stream"></a>`mode_not_stream` | The node does not take per-hour streams. | `open` | `<cli> agent up --basis per_gb --yes` | `<cli> agent down --yes` |

### Leaving, and the catch-all

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| <a id="code-stop-failed"></a>`stop-failed` | Stopping the previous session failed during a switch. The internet may not work. | `open` | `<cli> daemon doctor, then <cli> agent up --yes` | `<cli> daemon restore-network` |
| <a id="code-dns-revert-failed"></a><a id="code-tunnel-left"></a>`dns-revert-failed`, `tunnel-left` | DNS or a tunnel was left behind. | `open` | `<cli> daemon restore-network` | `<cli> agent down --yes` |
| <a id="code-unknown"></a>`unknown` | Nothing more specific is known. | `unclear` | `<cli> agent status` (read `error`) | `<cli> agent down --yes` (closes any open deposit) |

## agent down

`agent down` runs `disconnect` and then one `settle run`. If the disconnect fails, nothing is settled.

| Code | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|
| `no-wallet` | This CLI has no wallet, so it cannot read or close deposits. Nothing ran. | `none` | `<cli> disconnect to leave the VPN now; <cli> wallet import <file> (the wallet that paid), then <cli> agent down --yes to close the deposits` | `<cli> disconnect` (needs no wallet) |
| `keyfile-missing` | The named key file is gone. Nothing ran. | `none` | `<cli> disconnect to leave the VPN now; restore the key file named in "error" from your backup (it is the only key to this wallet), then <cli> agent down --yes` | `<cli> disconnect` |
| `stop-failed` | The disconnect failed with no plainer code. No deposit was closed, and a per-hour deposit keeps billing while the session is up. | `open` | `<cli> daemon doctor, then <cli> agent down --yes again` | `<cli> daemon restore-network` |
| `dns-revert-failed` | The session **did** stop, but DNS could not be restored. On rc5 the message still begins "Could not disconnect, so no deposit was closed". The first half is wrong; the second is right, because the settle step did not run. rc.6: "The session stopped, but this computer's DNS could not be put back. No deposit was closed yet." | `open` | rc5: `<cli> daemon doctor, then <cli> agent down --yes again` (the second `agent down` finds no session and closes the deposits). rc.6: `<cli> daemon restore-network, then <cli> agent down --yes again (it closes the deposits)` | `<cli> daemon restore-network` (the fix for the DNS) |
| <a id="code-service-down"></a><a id="code-service-not-ready"></a><a id="code-rpc-unavailable"></a>`service-down`, `service-not-ready`, `rpc-unavailable` | The disconnect failed in the VPN service, or on every RPC endpoint (plain copy; see "Any of the three" below). No deposit was closed. | `none` / `none` / `unclear` | `<cli> daemon doctor, then <cli> agent down --yes again` | `<cli> daemon restore-network` |
| `approval-revoked`, `not-enough-tdvpn`, `session-active` | Plain copy of a service error. With the disconnect these mean a service fault. No deposit was closed. | `open` / `none` / `none` | `<cli> daemon doctor, then <cli> agent down --yes again` | `<cli> disconnect` |
| `busy` | Disconnected, but another refund run in this process held the lock, so nothing was closed. A per-hour deposit bills until closed. | `none` | `<cli> settle run --yes` | `<cli> settle list` |
| <a id="code-settle-failed"></a>`settle-failed` | Disconnected. Some deposits could not be refunded yet; the others are done. | `refund` | `<cli> settle list` | `<cli> settle run --yes` |
| <a id="code-daemon-gone"></a>`daemon-gone` | Disconnected, but the VPN service stopped during the refund. Nothing was lost, and the settle runs again later. | `unclear` on rc5 (unclassified; the true state is refund) · rc.6: `refund` | `<cli> settle list` | `<cli> settle run --yes` |

A successful `agent down` whose deposits another device of this wallet opened (E-72) is `ok: true` with `notClosed` and
`warning`. Its `next` is `<cli> device revoke --device <D> --yes (if it is not revoked yet), then <cli> settle run --device <D> --yes`.

## agent status

`agent status` reads only and never fails with a code of its own. Its one code is a field on an `ok: true` answer:

| Code | Meaning | Money moved? | Next | alsoNext |
|---|---|---|---|---|
| <a id="code-server-stopped"></a>`server-stopped` | The node stopped serving. The exit address is this computer's own, or the daemon ended the session in the last 30 min. `connected: false`. The deposit is safe. | `open` (no `money` field: `ok` is true) | `<cli> agent up --yes` (the dead node is skipped for 10 min). With `blocked` (rc.6, one command): `<cli> daemon restore-network` | `<cli> agent down --yes` (an `alsoNext` field); with `blocked`: `then <cli> agent up --yes to reconnect, or <cli> agent down --yes to close the deposit` |

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
| `session-active` | A session is already active. | `none` | `devnet-dvpn agent status --json` (another run may hold the session: look, never end it). rc8 and older printed `devnet-dvpn disconnect` here: do not run it | `<cli> agent down --yes` only for a session this run started |
| (`code: null`) | A throw with no code (e.g. the key store locked over SSH, E-66). | `unclear` | null: read `error` | `<cli> agent status` |

Exit 2 (`needsConfirm: true`) carries no `code`. Exit 3 (wrong usage) is plain text with no `code` up to rc7; from
rc.8, with `--json` it is a coded answer on stdout (the text output is unchanged). See `docs/AGENT-COMMANDS.md`.

| Code | Meaning | Money moved? | Next | alsoNext |
|---|---|---|---|---|
| <a id="code-usage"></a>`usage` | rc.8 and later, with `--json`: wrong usage (an unknown command, flag or value), exit 3. The answer is `{ok:false, code:"usage", error, usage, next, docUrl, money}`; `usage` is the command's usage line. | `none` ("Nothing was sent or signed.") on rc.8 · rc7 has no such code (money-note.ts reads an unknown code as `unclear`) | `devnet-dvpn help` | - |

## Follow-up commands the answers name

These are not `agent` commands, so they carry **no `money` field**. The column gives the true state.

| Code | From | Meaning | Money moved? | Next (`action`) | alsoNext |
|---|---|---|---|---|---|
| `no-wallet` | `settle list / run / withdraw`, `device switch` | No wallet in this CLI. | `no field`: nothing ran | none (the message says `wallet create` or `wallet import <file>`) | import the wallet that paid, then run it again |
| `keyfile-missing` | same | The named key file is gone. | `no field`: nothing ran | none: restore the file from your backup | none |
| `busy` | `settle run` | Another refund run in this process. | `no field`: nothing closed | none: run `<cli> settle run --yes` again | `<cli> settle list` |
| `settle-failed` | `settle run` | Some deposits could not be refunded yet; the others are done. | `no field`: refund still held | none: `<cli> settle run --yes` again later | `<cli> settle list` |
| `daemon-gone` | `settle run` | The VPN service stopped during the refund. Nothing was lost. | `no field`: refund still held | none: `<cli> settle run --yes` again | `<cli> daemon doctor` |
| <a id="code-withdraw-failed"></a>`withdraw-failed` | `settle withdraw` | The withdraw transaction failed. A zero balance is not this code: it prints "Nothing to withdraw" with exit 0. | `no field`: balance still held | none: `<cli> settle withdraw --yes` again | `<cli> settle list` |
| <a id="code-no-device-key"></a>`no-device-key` | `device setup` (rc.6) | `device setup` ran before `daemon init`. On rc5 this was the same sentence with `code: null`. | `no field`: nothing signed | none: the message says `devnet-dvpn daemon init`, then `device setup` again (rc.9 `next`: `<cli> daemon init --yes, then <cli> device setup --yes`) | `<cli> agent status` |
| <a id="code-wallet-is-device"></a>`wallet-is-device` | `device setup` | The wallet and the device key are the same key. | `no field`: nothing signed | none: use a separate wallet key | `<cli> device show --json` |
| <a id="code-device-setup-failed"></a>`device-setup-failed` | `device setup` | The setup transaction failed. | `no field`: nothing set up (a SOL top-up may have landed) | none: run `device setup --yes` again | `<cli> daemon doctor` |
| `device-permission`, `device-sol` | `device switch` | The switch could not finish (read, stage or service step), or the wallet lacks SOL for it. This computer stays set up for the other wallet. | `no field`: nothing paid | the app's button as a command, or none | send SOL, then `<cli> device switch --yes` |
| <a id="code-switch-failed"></a>`switch-failed` | `device switch` | The switch failed with no code. | `no field`: nothing paid | none | `<cli> daemon doctor` |
| <a id="code-revoke-failed"></a>`revoke-failed` | `device revoke [--device D]` | The revoke transaction failed. | `no field`: nothing changed | none: run it again | `<cli> device show --json` |
| <a id="code-bad-device"></a><a id="code-own-device"></a>`bad-device`, `own-device` | `device revoke --device D` | `D` is not a device address, or it is this computer's own device. | `no field`: nothing ran | none: `device revoke` without `--device` for this computer | `<cli> device show --json` |
| <a id="code-device-key-unreadable"></a>`device-key-unreadable` | `device register` | The service's key folder is admin-only. | `none` (rc.9; rc.8: no field): nothing ran | the `device register <address>` form (no administrator needed) | none |
| <a id="code-invalid-address"></a><a id="code-invalid-amount"></a><a id="code-send-failed"></a>`invalid-address`, `invalid-amount`, `send-failed` | `wallet send` | Bad recipient, bad amount, or a failed transfer. | `no field`: nothing sent (`send-failed`: check the wallet) | none | `<cli> agent status` (balances) |
| <a id="code-tx-not-landed"></a>`tx-not-landed` | `wallet send` | The reply to the send was lost, and the signed transfer expired without reaching the chain (current v0.3.0-rc9 files). | `no field`: nothing was sent | `<cli> wallet show --json`, then the same `wallet send` again | none |
| <a id="code-tx-unknown"></a>`tx-unknown` | `wallet send` | The reply to the send was lost and the chain could not be read, so it is not known whether the transfer went through (current v0.3.0-rc9 files). Do not send again before checking. | `no field`: not known whether it was sent | `<cli> wallet show --json`: the balances show whether it moved, before any new send | none |

`settle run --device <this computer's device>`, the daemon commands, and (rc5 only) `device setup` with no
device key yet fail with `code: null` and a plain sentence that names the fix.

## Other commands: rc.7 codes (every failure has one)

rc.7 (R2) gives every failure outside `agent` that used to be a bare `code: null` a code and an `action`
(`cliErr` in `src/cli/cli-fail.ts`). None of them pays, so the class is `none` (money-note.ts) and the exit is 1.
Only `test` failures print a `money` field; the others carry none.

| Code | From | Meaning | Exit | Money moved? | Next (`action`) |
|---|---|---|---|---|---|
| <a id="code-device-home-gone"></a>`device-home-gone` | `device setup` | The VPN service's home folder (its device key and settings) is gone. | 1 | `no field`: nothing paid | `<cli> daemon install --yes` |
| <a id="code-no-plan"></a>`no-plan` | `plans roster <plan>` | No plan with that id on devnet. | 1 | `no field`: nothing paid | `<cli> plans list` |
| <a id="code-driver-repair-failed"></a>`driver-repair-failed` | `daemon repair-drivers` | The driver repair did not finish; `error` holds its log. | 1 | `no field`: nothing paid | `<cli> daemon doctor --json` |
| <a id="code-migrate-failed"></a>`migrate-failed` | `daemon migrate` | The upgrade of the VPN service home stopped at the step named in `error`. | 1 | `no field`: nothing paid | `<cli> daemon doctor --json` |
| <a id="code-device-not-ready"></a>`device-not-ready` | `daemon install` | The device is not funded and permitted yet, so the service will not start. | 1 | `no field`: nothing paid | `<cli> device setup --yes, then <cli> daemon install --yes` (rc.9, no device key yet: `<cli> daemon init --yes, then <cli> device setup --yes, then <cli> daemon install --yes`) |
| <a id="code-install-failed"></a>`install-failed` | `daemon install` | The service install failed; `error` says where. | 1 | `no field`: nothing paid | `<cli> daemon doctor --json` |
| <a id="code-daemon-settings-empty"></a>`daemon-settings-empty` | `daemon set` | The service's settings file is empty. | 1 | `no field`: nothing paid | `<cli> daemon install --yes` |
| <a id="code-kill-switch-remote"></a>`kill-switch-remote` | `daemon set` | Refused: `--kill-switch on` / `persist` from an SSH or Remote Desktop session. If the VPN connection is lost, the kill switch blocks every new connection to this computer, SSH included. It keeps blocking after a reboot until `devnet-dvpn daemon restore-network` is run locally or from the provider's console. Nothing was changed. In the current v0.3.0-rc9 files (the hashes in `docs/PROVENANCE.md`) the check also reads the login session and the parent processes, so it is refused under sudo and in a root shell opened with sudo -i or su - too. Earlier downloads of v0.3.0-rc9 did not check this: there, keep the kill switch off yourself. | 5 | `no field`: nothing paid | `<cli> agent up --yes` (connect without the kill switch); alsoNext `<cli> daemon set --kill-switch on --allow-remote-lockout --yes` (only with console access to this computer) |
| <a id="code-daemon-settings-unreadable"></a>`daemon-settings-unreadable` | `daemon set` | The service's settings file cannot be read (a missing file is `daemon-missing`). | 1 | `no field`: nothing paid | `<cli> daemon install --yes` |
| <a id="code-dns-no-answer"></a>`dns-no-answer` | `daemon dns-check` | The DNS check got no answer. Exit 1 on purpose, so a script can gate on it. | 1 | `no field`: nothing paid | `<cli> daemon doctor --json` |
| <a id="code-uninstall-failed"></a>`uninstall-failed` | `daemon uninstall` | The service uninstall failed; `error` says where. | 1 | `no field`: nothing paid | `<cli> daemon doctor --json` |
| <a id="code-checks-off"></a>`checks-off` | `quality` (ip, dns, …) | Third-party checks are turned off in settings. | 1 | `no field`: nothing paid | `<cli> settings set thirdPartyChecks=true` |
| <a id="code-test-plan-failed"></a>`test-plan-failed` | `test run` | The test run could not be planned (`error` says why). Nothing was opened. | 1 | `none` | `<cli> test servers` |
| <a id="code-no-test-run"></a>`no-test-run` | `test show / export [<run>]` | No test run with that id, or none yet. | 1 | `none` | `<cli> test history` |
| <a id="code-keystore-unavailable"></a>`keystore-unavailable` | `wallet create / import` (Windows) | Windows cannot encrypt a wallet for this logon (no password session, e.g. an SSH key login), or the encryption failed. | 1 | `no field`: nothing paid | `<cli> wallet create --keyfile <path> --yes` |
| <a id="code-keyfile-read-only"></a>`keyfile-read-only` | `wallet create / import / logout` | A `--keyfile` / `DVPN_KEYFILE` wallet is read-only: this CLI never writes or deletes it. | 1 | `no field`: nothing paid | `unset DVPN_KEYFILE, then run the command again` |
| <a id="code-disconnect-failed"></a>`disconnect-failed` | `connect --follow` (Ctrl+C) | rc.9: Ctrl+C asked for the disconnect and it failed (`error` says why). The session may still be up, and a per-hour deposit keeps billing while it is. | 1 | `no field`: nothing paid by this command | `<cli> agent status --json` |
| <a id="code-apply-failed"></a>`apply-failed` | `daemon set` | rc.9: the settings could not be applied, or the service did not restart on them (`error` says where). | 1 | `no field`: nothing paid | `<cli> agent status --json` |
| <a id="code-apply-busy"></a>`apply-busy` | `daemon set` | rc.9: another apply is still running (from the app or another command). Nothing was changed. | 1 | `no field`: nothing paid | `<cli> agent status --json` |
| <a id="code-apply-while-connecting"></a>`apply-while-connecting` | `daemon set` | rc.9: a connect is running (here or in another process). Nothing was changed; apply after it finishes. | 1 | `no field`: nothing paid | `<cli> agent status --json` |

Also coded in rc.7 by `cliErr`, with rows above: `rpc-busy` (`wallet show`), `no-device` (`device switch`),
`no-device-key` (`device setup`, `daemon init`), `no-wallet` and `daemon-missing` (`daemon install` / `set`), `no-nodes` (`test run`),
`node-gone` (`nodes show / probe <node>`), `driver-missing` (`daemon drivers`).

## rc.8 and later: `wallet send` and `device setup` check before they sign

rc.8 checks a send before the `--yes` preview, so nothing is signed when one of these comes back. The preview
also carries `feeLamports`, `balanceAfter {lamports, tdvpnBase}` and `notes` (a send to your own address or your
own device is a note, not a refusal). `device plan` gains `ok`, `solCost`, `next` and a `warning` (`--allowance 0`: "0 blocks every deposit"); `device setup` reports `solSentToDevice` and `feeLamports`. Up to rc7 none of these codes exists.

| Code | From | Meaning | Exit | Money moved? | Next (`action`) |
|---|---|---|---|---|---|
| <a id="code-bad-recipient"></a>`bad-recipient` | `wallet send` | `--to` is the system program, this app's program or the tDVPN mint; the message says which. Checked first, before any balance read. | 5 | `none` ("Nothing was sent or signed.") | `<cli> wallet send --to <a wallet address> … --yes` |
| <a id="code-insufficient-funds"></a>`insufficient-funds` | `wallet send` | The send asks for more than the wallet holds (tDVPN above the balance, or SOL plus the 5000-lamport fee above it). | 4 | `none` ("Nothing was sent or signed.") | `<cli> wallet show --json` |
| <a id="code-low-sol-after"></a>`low-sol-after` | `wallet send --sol` | The send would leave under 0.01 SOL, too little for the next fees. | 5 | `none` ("Nothing was sent or signed.") | send less, or add `--allow-empty` |
| <a id="code-allowance-above-balance"></a>`allowance-above-balance` | `device setup` / `device plan` (`--allowance <N>`) | N is more tDVPN than the wallet holds, so the device could be approved for money that is not there. `--force` sets it anyway. rc.9: only an explicit `--allowance N`; with no `--allowance` the limit becomes the wallet's balance, with a `warning` (rc.8: refused). | 4 | `none` ("Nothing was sent or signed.") | `<cli> device setup --allowance <at most the wallet balance> --yes` |

`--tdvpn 0` / `--sol 0` is `usage` ("the amount must be more than 0"). From rc.8 `invalid-amount`,
`invalid-address` and `usage` are money class `none`: `wallet`, `device` and `settle` say "Nothing was sent or
signed.", `agent` says "Nothing was paid." (rc7 said "It is not known whether the transaction went through").

## rc.9 and later: Windows install and key-file checks

| Code | From | Meaning | Exit | Money moved? | Next (`action`) |
|---|---|---|---|---|---|
| <a id="code-needs-admin"></a>`needs-admin` | `daemon install` (Windows) | Installing the VPN service needs an administrator, and this Windows account is a standard user (no `S-1-5-32-544` in `whoami /groups`). Also when no UAC prompt can be shown (SSH, a service session). Checked first, before the wallet and device checks; not checked when `whoami` fails. | 4 | `none` ("Nothing was paid.") | `Start-Process devnet-dvpn -Verb RunAs -ArgumentList 'daemon install --yes'` (PowerShell; Windows asks for an administrator's name and password) |
| <a id="code-keyfile-lock-failed"></a>`keyfile-lock-failed` | `wallet create --keyfile` (Windows) | This account could not lock the new key file to itself (its ACL); nothing was written. | 1 | `none` ("Nothing was sent or signed.") | `devnet-dvpn wallet create --keyfile "$HOME\agent-key.json" --yes` (a path in your own profile folder) |
| <a id="code-setting-rejected"></a>`setting-rejected` | `settings set` | A setting name or value the app does not take (the reason is in `error`). Nothing changed. | 1 | `none` ("Nothing was changed.") | `devnet-dvpn settings get --json` (the names and the values each takes), then `settings set <name>=<value>` again |

## Path B (`direct/*.sh`): codes only the scripts print

The scripts use the app's code names where a twin exists (`docs/DIRECT.md`, the Path B → Path A table).
These are the codes that exist only on Path B. Their anchors carry `direct-` so they never clash with an app
code of the same name (`install-failed`, `no-device`). Every line has `money` and `moneyNote`
(`direct/lib.sh`) and matches `direct/schema/failure.json`.

| Code | Script | Meaning | Exit | Money moved? | Next |
|---|---|---|---|---|---|
| <a id="code-direct-download-failed"></a>`download-failed` | `install.sh` | `apt-get update` or the release download (`SHA256SUMS`, a binary) failed. | 6 | `none` | `sleep 60 && sudo sh direct/install.sh` |
| <a id="code-direct-install-failed"></a>`install-failed` | `install.sh` | A setup step failed: the packages, copying a binary, `sentinel-dvpnd init`, the kill-switch setting, the service, or adding you to the group. `error` names the step. | 1 | `none` | the step's own command, then `sudo sh direct/install.sh` |
| <a id="code-direct-key-unsafe"></a>`key-unsafe` | `install.sh` (`KEYFILE=`) | The key file given as `KEYFILE=` has a mode other than 600 or 400, so other users can read the secret key. Nothing is copied. | 5 | `none` | `chmod 600 <file> && sudo KEYFILE=<file> sh direct/install.sh` |
| <a id="code-direct-tx-mismatch"></a>`tx-mismatch` | `fund-device.sh`, `close-all.sh` | The transaction built to be signed differs from the intended send, or (`fund-device.sh`) from the payee its preview showed: `direct/soltx.py check` decodes the message from its bytes and compares signer, programs, accounts and amounts. Nothing is signed or sent. | 5 | `none` | the same command again; report it if it repeats (`error` names the field) |
| <a id="code-direct-unsupported-os"></a>`unsupported-os` | every script, `build.sh` too | The host is not Linux (macOS, Windows): Path B runs on Linux only today. Nothing runs. `--help` still works. `VERIFY_ONLY=1 sh direct/build.sh` still cross-builds the Linux files to compare their SHA-256. | 1 | `none` | `grep -n -A6 'Two paths' AGENTS.md` (the app, Path A) |
| <a id="code-direct-insecure-key"></a>`insecure-key` | any script that signs, with `--yes` | The owner key file (`~/.sentinel-dvpn/keys/owner.json`, or `OWNER_KEYFILE=`) has a mode other than 600 or 400, so other users can read the secret key. Refused before anything is signed. The preview (no `--yes`) only warns, in `warnings[]`. | 5 | `none` | `chmod 600 <file> && <the same command> --yes` |
| <a id="code-direct-keyfile-missing"></a>`keyfile-missing` | `install.sh` and every script | `KEYFILE=` or `OWNER_KEYFILE=` names no file. Nothing is read or signed, and neither the default key nor a new key is used in its place. | 4 | `none` | `ls -l <its folder>`, then rerun with the right path |
| <a id="code-direct-escrow-too-small"></a>`escrow-too-small` | `connect.sh` | `ESCROW=` is below the node's first 100 MB block (a tenth of its GB price): the daemon would refuse it after the grant. Checked before anything is signed. | 3 | `none` | `ESCROW=<the minimum> NODE=<node> sh direct/connect.sh` (the `next` gives the numbers) |
| <a id="code-direct-escrow-below-minimum"></a>`escrow-below-minimum` | `connect.sh` | The daemon refused the channel open: "channel escrow below node minimum" (a minimum the pre-check did not know). Nothing was deposited; the node routes are removed. | 3 | `none` | `env -u ESCROW sh direct/connect.sh` (the default escrow) |
| <a id="code-direct-build-failed"></a>`build-failed` | `build.sh`, `install.sh` (`BUILD=1`) | A build step failed: git clone, fetch or checkout of the pinned commit, `make build`, or copying the result (`error` names the step). A wrong checksum is `checksum-mismatch`, not this. | 1 | `none` | `sh direct/build.sh` (needs git, make and Go 1.27.3) |
| <a id="code-direct-no-device"></a>`no-device` | any script after install | The daemon has no device key: `install.sh` did not finish. | 1 | `none` | `sudo sh direct/install.sh` |
| <a id="code-direct-route-failed"></a>`route-failed` | `connect.sh` | The route that keeps the node's own IP outside the tunnel could not be added (no default route, or `ip route replace` failed). | 1 | `none` | `ip route show default`, or the exact `sudo ip route replace …` line |
| <a id="code-direct-session-dropped"></a>`session-dropped` | `selftest.sh` | The session dropped during the hold. | 1 | `refund` | `sh direct/disconnect.sh && sh direct/refund.sh` |
| <a id="code-direct-step-failed"></a>`step-failed` | `selftest.sh` | A script the selftest ran stopped with no JSON line. When the script did print one, the selftest passes on its code instead. | 1 | the step's, else `none` | `sh direct/<script>.sh` |
| <a id="code-direct-interrupted"></a>`interrupted` | any (lib.sh EXIT backstop) | The script was killed (exit 130 / 143) before it printed its line. | 1 | `MONEY_STATE`: how far it got (`none`, `unclear` before the session starts, `open` after) | the same command again (it is safe to repeat: `docs/DIRECT.md`, "Safe to run again?") |
| <a id="code-direct-unknown"></a>`unknown` | any (lib.sh EXIT backstop) | A `set -e` stop with no code of its own; `error` names the last command run. | 1 | `MONEY_STATE`, as above | `none`: the failure table in `docs/DIRECT.md`; otherwise `sh direct/refund.sh` |
| <a id="code-direct-checksum-mismatch"></a>`checksum-mismatch` | `install.sh`, `build.sh` | The downloaded binaries, or your own build (`BUILD=1`, or `build.sh` with Go 1.27.3), differ from `direct/SHA256SUMS`; nothing was installed. | 5 | `none` | `sudo BUILD=1 sh direct/install.sh` (download), or `sh direct/build.sh` (your build) |
| <a id="code-direct-close-wait"></a>`close-wait` | `refund.sh`, `close-all.sh` | A channel close is still in its 7200 s wait (on-chain `GraceNotElapsed`, 6035); nothing was swept yet. | 1 | `refund` | `close-all.sh`: `sleep <seconds> && sh direct/close-all.sh --to <address> --yes` (the wait it prints); `refund.sh`: `sh direct/refund.sh` after the time in `error` |
| <a id="code-direct-needs-root"></a>`needs-root` | `install.sh` | Run without root. | 3 | `none` | `sudo sh direct/install.sh` |
| <a id="code-direct-no-session"></a>`no-session` | `disconnect.sh` | The daemon has no active session: it had already ended. | 1 | `none` | `sentinel-dvpn client sessions --instance <instance>` (nothing to stop) |
| <a id="code-direct-no-token-account"></a>`no-token-account` | `close-all.sh` | The `--to` address has no tDVPN token account to receive the owner's tDVPN; nothing was sent. | 4 | `none` | `sh direct/close-all.sh --help` (send to an address that already holds tDVPN) |
| <a id="code-direct-not-closing"></a>`not-closing` | `refund.sh` | A close was asked before its start-close (on-chain `ChannelNotClosing`, 6033). | 1 | `refund` | `sh direct/refund.sh --yes` |
| <a id="code-direct-nothing-to-withdraw"></a>`nothing-to-withdraw` | `refund.sh` | The withdraw found a zero balance while channels are still open (on-chain `BalanceZero`, 6023). | 1 | `refund` | `sh direct/refund.sh` (close the channels first) |
| <a id="code-direct-sweep-incomplete"></a>`sweep-incomplete` | `close-all.sh` | After the sweep the owner or the device still holds tDVPN or SOL (`error` gives the amounts). | 1 | `none` | `sh direct/close-all.sh --to <address> --yes` again |
| <a id="code-direct-tool-missing"></a>`tool-missing` | every script | A tool the script needs is not on `PATH` (`error` names it). | 3 | `none` | the line for that tool: `sudo apt-get install -y <tool>` (`wg`: `wireguard-tools`; `sentinel-dvpn` / `sentinel-dvpnd`: `sudo sh direct/install.sh`) |
| <a id="code-direct-wrong-account"></a>`wrong-account` | `install.sh`, any script on-chain | `KEYFILE=` is not the `OWNER=` given, or the service already holds another owner (never overwritten); on-chain, a wrong account or seed (`ConstraintSeeds` 2006, `ConstraintAddress` 2012). | 1 | `none` | `install.sh`: the line it prints; on-chain: `grep -n -A1 wrong-account docs/DIRECT-REFERENCE.md` |

## rc.6 and later: exit codes and changed answers

This applies when `devnet-dvpn version --json` says `0.3.0-rc.6` or newer (released; rc7 = `8f458d71`). Every row
above still holds, apart from the changes listed here.

**Exit codes by class** (`src/cli/exit-codes.ts`). The `code` field stays the precise reason.

| Exit | Class | Codes |
|---|---|---|
| 0 | ok | none |
| 1 | error | any code not listed below, and `code: null`. Includes `rpc-timeout`, `rpc-network`, `rpc-quota` and `timeout`: network codes whose money class is `open` (a deposit may be open) |
| 2 | needs `--yes` | no code (`needsConfirm: true`) |
| 3 | wrong usage | no code up to rc7; from rc.8 with `--json`: `usage` |
| 4 | needs you or your operator | `not-funded`, `spending-limit`, `price-cap`, `no-wallet`, and since rc7 `keyfile-missing` and `keyfile-mode` (rc.6: exit 1); since rc.8 `clock-skew`, and `allowance-above-balance` (`device setup` / `plan`) and `insufficient-funds` (`wallet send`); since rc.9 `keyfile-unreadable` and `needs-admin` |
| 5 | refused for safety | `kill-switch-held` (money `none`), `kill-switch-failed` (money `open`: read `money`), `kill-switch` and `kill-switch-remote` (money `none`); since rc.8 `bad-recipient` and `low-sol-after` (`wallet send`, money `none`) |
| 6 | network or RPC, no deposit possibly open: retry later | `rpc-busy`, `rpc-unavailable` (money `unclear`), and `rpc-ws`; rc.9: these exit `1` from `agent`, `connect`, `device switch` and `test` (money `unclear`); since rc.9 `waiting-for-network` (money `none`: exit 6 everywhere) |

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
  when `--max-price` is not given; rc.6 = the Settings limit / 10, rc7 = market-sized (`defaults.priceCap`).
- rc7: every failure carries `next` (the same as `action`) and `docUrl` (this page, `#code-<code>`).
- `dns-revert-failed` on `agent down`: see its row.
- `daemon-gone`: money class `refund`.
- `agent status` with the service down and no device yet (E-84): `next` is the service install
  (`daemon-missing`), not `agent up --yes`.
- Amounts gain base-unit siblings: `solLamports`, `tdvpnBase`, `heldBase`, `spentBase` (status);
  `spentBase`, `refundableBase` (down); `deposit.tdvpnBase` (up).
- `version --json` adds `programId` and `mint` (E-81).
