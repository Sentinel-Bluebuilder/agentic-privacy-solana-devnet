# JSON you will read: agent status and wallet show

For `devnet-dvpn` v0.3.0-rc8 (Windows, Linux, macOS Apple silicon). Moved here from the appendix of [`AGENTS.md`](../AGENTS.md).


Every answer of the three `agent` commands, as a JSON Schema (draft 2020-12):
[`docs/agent-answers.schema.json`](agent-answers.schema.json). Field by field:
[`docs/AGENT-COMMANDS.md`](AGENT-COMMANDS.md).

`agent status --json`: `address`, `sol`, `tdvpn`, `held` (decimal strings; `held` is the balance
`settle withdraw` moves, not the deposits still open), `device`, `service`, `connected`, and when
connected `session`, `node`, `protocol`, `spent`, `exitIp`, `socks`, `wholeDevice`; `deposits`
when the wallet has open or closing ones; `blocked` when the internet is blocked; `reconnecting` (rc7) while a live session reconnects;
always `next`, and `alsoNext` when there is a second way out.

`agent up --json` (rc7), preview and answer: `defaults` = `priceCap` (tDVPN, or "set by --max-price"),
`priceCapBase` (base units; null with `--max-price`), `spendingLimit` and `spendingLimitRecommended` (tDVPN),
`units`, `source` (`market` or `fixed`), `reason` (only when fixed), `market` (`p50`, `p75` in tDVPN per unit,
`nodes` read, `outliers` left out; null when fixed).

`agent down --json` (rc7): also `deposited` / `depositedBase`, the sum of the deposits still in `pending` (not only the session it ended).
`settle run --json` (rc7): `nextAfter`, Unix seconds when the last closing deposit is ready (null when none).

Every failure (rc7): `{"ok":false,"error","code","action","next","docUrl","money"}`. `next` is the same as
`action`; `docUrl` is the `docs/CODES.md` row of the code (`…/docs/CODES.md#code-<code>`).

From rc8:
- A usage error with `--json` (exit `3`): `{"ok":false,"code":"usage","error","usage","next":"devnet-dvpn help","docUrl","money"}`
  on stdout; `usage` is the command's usage line.
- `wallet send --json`, preview: `feeLamports`, `balanceAfter` (`lamports`, `tdvpnBase`) and `notes` (your own address,
  your own device). Refusals before signing: `insufficient-funds`, `bad-recipient`, `low-sol-after` (`docs/CODES.md`).
- `device plan --json`: `ok`, `steps`, `topUpLamports`, `approveTo`, `solCost`, `next`, and `warning` (`--allowance 0`).
  `device setup --json`: also `solSentToDevice` and `feeLamports`.
- `agent status --json`: `keyfileMode` when other users can read the key file. `daemon doctor --json`: a clock row
  (`clockSkewSec`).
- Path B (`direct/*.sh`): `then`, `alternatives` and `note` beside the one-line `next`; `channels[]` on `refund.sh`;
  `alreadyConnected` on `connect.sh`. Field by field: [`docs/DIRECT-REFERENCE.md`](DIRECT-REFERENCE.md).

`wallet show --json` (used by the single commands) reads the same wallet with other names and
other units:

| `agent status` | `wallet show` | How to compare |
|---|---|---|
| `address` | `owner` | the same address |
| `sol` | `ownerLamports` | a number in base units: `sol` = `ownerLamports` / 1000000000 |
| `tdvpn` | `ownerTdvpn` | base units, a string: `tdvpn` = `ownerTdvpn` / 1000000 (100 tDVPN = `"100000000"`) |
| `held` | `userBalance` | base units: `held` = `userBalance` / 1000000 |
| `device` | `device` | the same device key |
| `deposits` (one row each) | `userOpenChannels` (a count) | the count of open deposits |
| (none; `next` names what is missing) | `ready` | true when the spending permission, the approval and the device SOL are all in place |
| (none) | `delegated`, `deviceLamports`, `grant.allowance` | approval, device SOL and spending limit, in base units (`device show --json` shows `grant.allowance` too) |
