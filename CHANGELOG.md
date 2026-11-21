# Changelog: the agent page and the `agent` answers

What changed for an agent between releases of `devnet-dvpn`, newest first. The page for the current
release is [`AGENTS.md`](AGENTS.md); what an older release still needs is in
[`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md). Field by field: [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md).
Terms: [`GLOSSARY.md`](GLOSSARY.md).

Check which release you have: `devnet-dvpn version --json`.

## v0.3.0

The v0.3.0-rc9 files, promoted unchanged: the same SHA256SUMS on all three OSes, so `devnet-dvpn version --json` still says `0.3.0-rc.9`. Nothing changed for an agent; pin `v0.3.0` (`DVPN_VERSION=v0.3.0`). The macOS app source is public ([`docs/PROVENANCE.md`](docs/PROVENANCE.md), Path A); the Windows and Linux source is not public yet.

## v0.3.0-rc9

Draft: each line ships only if its change is in the rc9 build (drop the line otherwise).

On Windows, Linux and macOS (Apple silicon only: Intel Macs stay on v0.3.0-rc4, [docs/OLDER-RELEASES.md](docs/OLDER-RELEASES.md), "Intel Mac").

### Breaking
- Spending limit, least privilege: `--raise-limit` and a first `device setup` raise only as far as needed, and
  `defaults.spendingLimit` is the live grant (`configuredDefault` = Settings). `device setup` with no `--allowance` is
  never refused: the smaller of Settings and the wallet, with a warning.

### Added
- `needs-admin` (Windows): `daemon install` from a standard account says so first, with the elevation line.
- `keyfile-unreadable`: an unreadable key file is a coded refusal with a `next`, not a bare `EPERM`.
- `keyfile-mode` on Windows: the key file's ACL is checked; `keyfile-lock-failed` when a new key file cannot be locked.
- `clock-skew` on Windows (`w32time` resync) and in `agent status` (`clockSkewSec`).
- `killSwitchHolding` in `agent status`: says when the kill switch is on but no longer blocking.
- The RPC: a dead RPC gets a way out (another RPC) instead of exit 1.

### Fixed
- A fresh data dir adopts the installed service's device key (no staging key in `wallet show`).
- `wallet show` warns about a key file other users can read.

## v0.3.0-rc8

Published on Windows and Linux, and (2026-11-20) on macOS for Apple silicon only: Intel Macs stay on v0.3.0-rc4
([`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md), "Intel Mac").

Breaking: read these before you run an rc7 script on rc8.

- **Usage errors with `--json` are a JSON line on stdout** (exit `3` stays): `{ok:false, code:"usage", error,
  usage, next:"devnet-dvpn help", docUrl, money:"Nothing was sent or signed."}`. rc7 printed a plain line on
  stderr and nothing on stdout. Text mode is unchanged.
- **`no-nodes` names the real blocker**, and its `action` never repeats the failing line: a price above
  `--max-price` (counted only from nodes that answer their check), no node in that `--country` (the line
  without it), only another `--protocol` (the line without it), or why the `--node` you gave is not picked
  (`--node` kept where a retry can work). With every probe failing and no internet, the answer is
  `kill-switch-held`, `next` = `daemon restore-network` (rc7: a lower price).
- **`session-active` `next` = `agent status --json`** (rc7: `agent down --yes, then agent up --yes`, which ended
  the live session). Only one paying `agent up` runs per computer: a second one waits up to 90 s, then
  answers `reused: true`.
- **After `agent down`, `agent status` gives the same line as `agent down`:** `settle run --yes after <ISO>, then
  settle withdraw --yes` (rc7 status said `agent down --yes after <ISO>`).
- **`clock-skew`** is exit `4`; its `next` is this OS's time-sync command (on Linux it also steps chrony),
  then `agent up --yes` (rc7: try another node). It no longer names an older deposit as open.
- **Money text for a value a command cannot read** (`invalid-amount`, `invalid-address`, `usage`) is class
  `none` for every command: "Nothing was sent or signed." (`agent`: "Nothing was paid."). rc7 said "It is not
  known whether the transaction went through".
- **`wallet send` refuses before signing:** `insufficient-funds` (exit `4`), `bad-recipient` (the system program,
  the app's program or the tDVPN mint; exit `5`), `low-sol-after` (under 0.01 SOL left; exit `5`, `--allow-empty`
  overrides). `--tdvpn 0` / `--sol 0` is `usage`.
- **`device plan` / `device setup --allowance <N>` above the wallet's tDVPN** is `allowance-above-balance` (exit `4`;
  `--force` sets it anyway). `--allowance 0` warns that it blocks every deposit.

Added, not breaking:

- `agent status` names a key file other users can read (`keyfileMode`), and its `next` is the `chmod` line first
  (a block's `restore-network` stays first).
- `no-device-key` has one command in `next` (`agent up --yes`, or `daemon install --yes`).
- A no-flags quick pick widens the default cap to the cheapest node that answers within the spending limit,
  and says so in `defaults.reason` (rc7 refused at a price above the cap after a node dropped).
- `agent status` clears `server-stopped` once no session is live, the direct internet answers and no open
  deposit with that node is left.
- `daemon doctor` has a clock row (`clockSkewSec`).
- The `wallet send` preview carries `feeLamports`, `balanceAfter {lamports, tdvpnBase}` and `notes` (your own
  address, your own device).
- `device plan` answers `{ok, steps, topUpLamports, approveTo, solCost, next}` (and `warning`); `device setup`
  reports `solSentToDevice` and `feeLamports`.
- `docs/AGENT-COMMANDS.md`: the failure shape (with `next`, `docUrl`), exit 6 money, the rc7 cap rule, 0.06 SOL,
  the `settle run` line, the flags a `spending-limit` action keeps, and the `payer`, `defaults`, `deposited` rows.

Path B (`direct/*.sh`, Sentinel's own tools), in the same update:

- `install.sh` takes an existing key file (`KEYFILE=<file>`); a file other users can read is `key-unsafe` (exit `5`).
- `connect.sh` opens a grant cap of 10 deposits at the picked node's price (0.02 tDVPN today; was 150);
  `ALLOWANCE=<base units>` sets another. Connecting again while connected answers `alreadyConnected: true`.
- Every `next` is one runnable line; `then` / `alternatives` / `note` carry the rest. `--help` and unknown
  flags print usage and a `usage` line before anything runs. `refund.sh` lists `channels[]`.
- The tables moved to `docs/DIRECT-REFERENCE.md`; `docs/DIRECT.md` is the quick path.

Known, for rc9: on Windows the kill-switch block holds only while the VPN service keeps the session
(`docs/SECURITY-MODEL.md`); `rpc set` probe and `rpc reset`; least-privilege `--raise-limit`; clock skew in
`agent status` and the preview; macOS still on rc4.

## v0.3.0-rc7

Breaking: read these before you run an rc6 script on rc7.

- **Market-sized default cap.** Without `--max-price`, the cap is the larger of the spending limit / 10 and
  the p75 price of the matching online nodes times `--units`, never above the spending limit (rc6: always
  the spending limit / 10). With fewer than 3 priced nodes the fixed cap applies.
- **Spending limit 50 → 150 tDVPN** on a new install. An existing install keeps its stored limit; `defaults.spendingLimitRecommended` shows the market's suggestion; `settings set allowanceTdvpn=<n>` takes effect at the next raise (`--raise-limit`, or `device setup --allowance <n> --yes`).
- **`not-funded` text** names the exact shortfall plus "(X recommended: it also covers a reconnect)".
- **Exit `4` for `keyfile-missing` and `keyfile-mode`** (rc6: exit `1`).
- **`no-nodes` under `--max-price`** names the cheapest matching price, and its `action` is a runnable
  `agent up … --max-price <that price> --yes` line (rc6: "widen the filters").

Added, not breaking:

- `defaults` on every `agent up` preview and answer: `priceCap`, `priceCapBase`, `spendingLimit`,
  `spendingLimitRecommended`, `units`, `source` (`market` or `fixed`), `reason`, `market` (`p50`, `p75`,
  `nodes`, `outliers`).
- The `--raise-limit` action is your line pinned to the node `agent up` picked, keeping your
  `--protocol` and `--max-price` (E-88).
- A session reconnecting under the kill switch reads `connected: false`, `reconnecting` and `blocked: true`,
  and `next` is `devnet-dvpn daemon restore-network` (E-87).
- Every failure carries `next` (the same as `action`, which stays).
- `rpc-unavailable`, `rpc-ws`, `rpc-network`, `rpc-quota`: `next` is the `daemon set --rpc <https url> --yes` line.
- `agent status` with the internet blocked and no session: `next` = `agent up --yes`, `alsoNext` = `daemon restore-network`.
- `agent status` names the preview (`agent up`, no `--yes`) when the device has no spending permission or under
  1 tDVPN is held in all.
- `agent down` adds `deposited` and `depositedBase`.
- A runnable `next` on success for the step commands (`wallet`, `device`, `settle`, `disconnect`, `daemon install`);
  `settle run` adds `nextAfter` (Unix seconds). A failed `wallet` / `device` / `settle` says "Nothing was sent or
  signed." when nothing was, not the deposit words.

## v0.3.0-rc6 (Windows, Linux; macOS stays v0.3.0-rc4)

Breaking: read these before you run an rc5 script on rc6.

- **Exit codes 4, 5, 6.** A failure no longer always exits `1`: `4` = needs you or your operator
  (`not-funded`, `spending-limit`, `price-cap`, `no-wallet`; nothing was paid), `5` = refused for safety
  (`kill-switch`, `kill-switch-held`, `kill-switch-failed`), `6` = network or RPC with no deposit open
  (`rpc-busy`, `rpc-unavailable`, `rpc-ws`). Other failures still exit `1`. The JSON line is the same.
- **`--raise-limit`.** `agent up` no longer raises this computer's spending limit by itself. A deposit
  above it is refused with `spending-limit` (nothing paid); `action` is an `agent up … --raise-limit --yes`
  line (read its node and units first). `limitRaised` / `limitNote` appear only when you passed it.
- **Default price cap (`price-cap`).** Without `--max-price`, a deposit above the spending limit / 10
  (5 tDVPN by default) is refused (nothing paid); `action` names the node's price with `--max-price`.
- **Version fields.** `version --json` adds `programId` and `mint`. On devnet they must read
  `J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs` and `Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa`; any
  other value is the wrong build: pay nothing.

Added, not breaking:

- Base-unit twins of every amount, as strings: `solLamports`, `tdvpnBase`, `heldBase`, `spentBase`,
  `refundableBase`, `deposit.tdvpnBase` (`deposit.baseUnits` stays, the older name).
- A connect that fails with no known cause names it: `node-refused` (a deposit was paid; `agent down --yes`
  closes it) or `unknown` ("Nothing was paid"). rc5 could say only "Something went wrong. Retry." (E-71).
- With the node stopped and the kill switch holding the block, `next` is one runnable command,
  `devnet-dvpn daemon restore-network`, and `alsoNext` names the reconnect or the close (E-86).

## v0.3.0-rc5

Breaking from rc4:

- **`refundable` → `held`** in `agent status`: the tDVPN held for your wallet in the program (what
  `settle withdraw` moves). `refundable` now appears only in `agent down`, where it means the tDVPN still
  to come back from closing deposits.
- **`serverStopped` → `nodeStopped`** in `agent status` (code `server-stopped` is unchanged).

Added:

- `agent up --yes` says when it raised the spending limit: `limitRaised` (`from`, `to`) and `limitNote`
  (the command that lowers it). rc4 could raise it silently (E-73).
- With the VPN service down and a deposit open, `agent status` names the service fix first (E-75).
- `agent down` reports deposits another device of this wallet opened: `notClosed` and `warning` (E-72).
- With the node stopped and the kill switch holding the block, `next` names
  `daemon restore-network` first (E-82).

## v0.3.0-rc4

The first release with `agent status`, `agent up` and `agent down`. Earlier releases (rc2) have only the
single commands: [`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md), "Step by step".
