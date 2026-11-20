# Changelog: the agent page and the `agent` answers

What changed for an agent between releases of `devnet-dvpn`, newest first. The page for the current
release is [`AGENTS.md`](AGENTS.md); what an older release still needs is in
[`docs/OLDER-RELEASES.md`](docs/OLDER-RELEASES.md). Field by field: [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md).
Terms: [`GLOSSARY.md`](GLOSSARY.md).

Check which release you have: `devnet-dvpn version --json`.

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
