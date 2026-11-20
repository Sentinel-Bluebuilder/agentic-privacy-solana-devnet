# Build your own client: talk to the dvpn program directly

For an AI agent (or a developer) that wants to pay for Sentinel dVPN on Solana **with its own code**:
no Devnet dVPN app and no `sentinel-dvpn` CLI. You build the transactions yourself against the
on-chain `dvpn` program. To carry traffic you then either drive the `sentinel-dvpnd` daemon over
gRPC (section 6) or speak the node API yourself.

**Source of every fact here:** the public monorepo
[`sentinel-official/sentinel-solana` at `26de5240`](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0)
(committed 2026-11-02), plus live reads of devnet on 2026-11-20. Paths below are relative to that tree.

| what | public path |
|---|---|
| program IDL (instructions, accounts, errors, constants) | [`sentinel-programs/idl/dvpn.json`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/idl/dvpn.json) |
| program source | [`sentinel-programs/programs/dvpn/src/`](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/programs/dvpn/src) |
| generated Go client | [`sentinel-programs/clients/go/dvpn/`](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/clients/go/dvpn) |
| Go SDK wrapper | [`sentinel-go-sdk/program/`](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-go-sdk/program) |
| daemon gRPC protos (`ClientService`) | [`sentinel-go-sdk/daemon/v1/daemon.proto`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-go-sdk/daemon/v1/daemon.proto) |
| voucher message format | [`sentinel-programs/crates/dvpn/core/src/voucher.rs`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/crates/dvpn/core/src/voucher.rs) |

Runnable examples sit next to this file in [`build-your-own-client/`](build-your-own-client/). They
were **run on 2026-11-20** on an Ubuntu 24.04 Azure VM against public devnet (section 10).

---

## 1. Devnet constants

| name | value | how it was checked |
|---|---|---|
| RPC | `https://api.devnet.solana.com` (public; rate-limits bursts with HTTP 429, so add retries) | every read below |
| dvpn program | `J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs` | upgradeable program, last deploy slot 517924537 |
| token mint | `Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa` (**Token-2022**, 6 decimals: 1 tDVPN = 1 000 000 base units) | `Config.mint`, `Config.decimals` |
| token program | `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb` | pinned by the program (`address = token_2022::ID`) |
| Config PDA | `Cu5vofxVQgZXRVwfBqApw84ZWy1hjhDmHkznyDr6TRiQ` (seeds `["config"]`) | decoded live |
| vault | `EQJyAyWLGZSye3BMfDQVdhrfp1QKEByNX9q2J9TzFmfy` = the Token-2022 ATA of the Config PDA | `Config.vault` |
| `fee_bps` | 200 (2 % of every redemption goes to fees) | `Config` |
| `channel_close_grace_seconds` | **7200** (2 h) | `Config` |
| `node_listing_ttl_seconds` | 86400 (a node must re-list every 24 h to stay live) | `Config` |
| `paused_mask` | 0 (nothing paused) | `Config` |

**The IDL file carries a placeholder address** (`SentineLDVPN1111111111111111111111111111111`).
The same goes for the generated Go client's `dvpn.ProgramID`. The real id is chosen when you build.
Set it yourself: in TS, override `idl.address`; in Go, call `dvpn.SetProgramID(...)`.

**Is devnet running this source?** Yes, as far as anything outside the binary can show. Every
account type's on-chain size matches the 26de5240 layout: Channel 299 B, User 117 B, Config 277 B,
Node 337 B, Grant 201 B, Lease 331 B, Subscription 198 B, Plan 155 B, Provider 313 B, both Unbonding
153 B. The program also returns error **6049 `MissingRentRecipient`**, which only exists in the
newest error table. An `open_channel` encoded from this IDL was accepted, and a real one was sent.

## 2. The pieces

```
your code ──(Solana tx)──▶ dvpn program   escrow, vouchers, settlement, refunds
    │
    └──(gRPC, local socket)──▶ sentinel-dvpnd ──(HTTPS node API)──▶ node   the tunnel itself
```

The chain never sees traffic. It holds your escrow and lets the node redeem the **vouchers** you
sign as you use bandwidth. You can do all the chain work yourself. For the tunnel, either let the
daemon run the session (section 6), or implement the node API
([`sentinel-go-sdk/nodeapi/openapi.yaml`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-go-sdk/nodeapi/openapi.yaml)).

## 3. Accounts and PDA seeds (client side)

All PDAs belong to the dvpn program. Seeds are the raw UTF-8 string, then the 32 raw bytes of each key.

| account | seeds | size | holds |
|---|---|---|---|
| `Config` | `"config"` | 277 | mint, vault, fees, grace windows, pause mask |
| `User` | `"user"`, owner | 117 | `owner`, `balance` (refunds land here), `open_channels`, `rent_recipient` |
| `Node` | `"node"`, node.owner, node.node_id (32 B) | 337 | `status` (1 = listed), `listed_at`, `channel_price_per_gb`, `channel_price_per_hour`, `uri`, `country`, `opened_at` |
| `Channel` | `"channel"`, owner, channel_id (32 B, you choose it) | 299 | `owner`, `node`, `opener`, `mode` (0 voucher / 1 stream), `voucher_signer`, `escrow`, `redeemed`, `opened_at`, `close_started_at`, `status` (0 open / 1 closing), `rent_recipient`, `node_opened_at` |
| `Grant` | `"grant"`, granter (owner), grantee, target | 201 | `permissions` bitmask, `expires_at` (0 = never), `allowance` (u64::MAX = unlimited), `rent_recipient` |
| vault | ATA of `Config` (`[config, token_program, mint]` under the ATA program) | — | all escrowed tokens |

A node is **usable** only when `status == 1` **and** `now < listed_at + node_listing_ttl_seconds`.
Otherwise `open_channel` fails with 6015 or 6016. On 2026-11-20, 36 of 79 Node accounts were live.

**Optional accounts:** Anchor encodes "None" for an optional account (the `grant` everywhere, and
`node` in `close_channel`) by passing **the program id itself** in that slot. The generated Go
builders do this for you when `Grant` is `nil`.

## 4. The client flow, instruction by instruction

Every instruction is **owner-or-grantee**. If no grant is passed, `signer` must equal `owner`
(otherwise 6000). With a grant, the signer must be the grantee, the grant must hold the permission
bit (6046), it must not be expired (6045), and its `target` must be `111…1` (any) or the
node/channel the call touches (6047). Accounts are listed in IDL order. **w** = writable, **s** = signer.

### Step 0: prerequisites (not dvpn instructions)

- A Solana wallet with SOL for fees and rent. Each tx costs a 5 000-lamport fee. A first channel
  open also pays the User and Channel rent (section 8).
- A **Token-2022** associated token account for the mint holding tDVPN (`owner_token`). Plain SPL
  Token accounts are rejected (Anchor `token::mint` / `token::authority` constraints).

### Step 1: User account (no instruction of its own)

There is **no `open_user`**. `open_channel` creates `User` (`init_if_needed`) the first time an
owner opens a channel. It stores `user_rent_recipient` then. `withdraw_user_balance` closes it once
`open_channels == 0`.

### Step 2 (optional): delegate with a grant: `open_grant` / `update_grant` / `close_grant`

Use this when a different key (an agent's hot key, or the daemon's operator key) should spend for the owner.

`open_grant(grantee: pubkey, target: pubkey, permissions: u64, expires_at: i64, allowance: u64, grant_rent_recipient: pubkey)`

| # | account | flags | notes |
|---|---|---|---|
| 1 | `granter` | s | the owner |
| 2 | `rent_payer` | w s | pays the Grant rent |
| 3 | `grant` | w | PDA `["grant", granter, grantee, target]` |
| 4 | `system_program` | | |

Errors: **6003** `ParamOutOfRange` (grantee is `111…1` or the granter itself, unknown permission
bits, or `expires_at` not 0 and not in the future), **6049/6050** (rent recipient, section 8).

Client permission bits (IDL `constants`):

| bit | value |
|---|---|
| `PERM_OPEN_CHANNEL` | 16777216 (`0x1000000`) |
| `PERM_FUND_CHANNELS` | 33554432 (`0x2000000`) |
| `PERM_START_CLOSE_CHANNEL` | 67108864 (`0x4000000`) |
| `PERM_CLOSE_CHANNEL` | 134217728 (`0x8000000`) |
| `PERM_WITHDRAW_USER_BALANCE` | 268435456 (`0x10000000`) |
| `PERM_OPEN_SUBSCRIPTION` | 536870912 (`0x20000000`) |

The Go SDK's `program.PermsClient` = open | fund | start-close | close channel + open
subscription. It leaves out withdraw, so a delegate cannot pull your refunds out to your wallet.
`allowance` is charged by the escrow amount on every `open_channel` / `fund_channels`; going past
it gives **6024** `AmountExceedsAllowance`.

- `update_grant(permissions: Option<u64>, expires_at: Option<i64>, allowance: Option<u64>)`:
  accounts `signer` (s, must be the granter, else 6000), `grant` (w). Errors 6000, 6003.
- `close_grant()`: accounts `signer` (s), `grant` (w), `rent_recipient` (w, must equal
  `grant.rent_recipient`). The granter or grantee may close it, or anyone once it has expired (else
  6000). The rent goes to the stored rent recipient.

### Step 3: open a channel: `open_channel`

`open_channel(channel_id: [u8;32], escrow: u64, terms: PositionTerms, channel_rent_recipient: pubkey, user_rent_recipient: pubkey)`

`PositionTerms` is an enum:
- `Voucher { voucher_signer: pubkey }` (mode 0). Pay per use: the node redeems vouchers signed by
  `voucher_signer`. The key must be a valid prime-order ed25519 point (6048); any normal wallet key is.
- `Stream { expected_rate_per_hour: u64 }` (mode 1). Pay per time. The value must equal the node's
  current `channel_price_per_hour` (6017), so a price change between read and send is caught.

| # | account | flags | notes |
|---|---|---|---|
| 1 | `signer` | w s | owner, or a grantee holding `PERM_OPEN_CHANNEL` |
| 2 | `config` | | `["config"]` |
| 3 | `owner` | | the wallet the channel belongs to |
| 4 | `grant` | w, optional | `["grant", owner, signer, target]`; program id = None |
| 5 | `user` | w | `["user", owner]`, created if missing |
| 6 | `node` | | `["node", node.owner, node.node_id]` |
| 7 | `channel` | w | `["channel", owner, channel_id]`, created |
| 8 | `vault` | w | `Config.vault` |
| 9 | `mint` | | `Config.mint` |
| 10 | `owner_token` | w | owner's Token-2022 account for the mint |
| 11 | `token_program` | | Token-2022 |
| 12 | `rent_payer` | w s | pays User + Channel rent |
| 13 | `system_program` | | |

Money: the escrow is taken **from `User.balance` first** (old refunds), then the rest from
`owner_token`. Errors: **6001** (channel opens paused), **6015** `NodeNotListed`, **6016**
`NodeNotLive`, **6017** `NodePriceChanged` (stream), **6000/6045/6046/6047** (grant gate),
**6024** (allowance), **6048** `InvalidVoucherSigner`, **6049/6050** (rent recipient), **6043**
(overflow). Opening with a `channel_id` already used for this owner fails in the System program
("already in use").

The program does **not** check the escrow against the node's price. A tiny escrow opens fine, but
the node or daemon may refuse to serve it (section 6).

### Step 4 (optional): top up: `fund_channels`

`fund_channels(amounts: Vec<u64>)`. Accounts: `signer` (w s), `config`, `owner`, `user` (w),
`grant` (w, optional, needs `PERM_FUND_CHANNELS`), `vault` (w), `mint`, `owner_token` (w),
`token_program`. **Remaining accounts:** the channels to fund, writable, **sorted ascending by
pubkey bytes with no duplicates** (6041 `BatchNotSorted`). There must be exactly one amount per
channel and at least one (6040 `BatchLengthMismatch`). Each channel must be `owner`'s (Anchor 2001)
and open (6032 `ChannelNotOpen`). Like open, this draws from `User.balance` first, then the wallet.

### Step 5: start a session (through the daemon)

See section 6. Your channel must be voucher-signable by the daemon. Either let the daemon open the
channel itself (`NewChannel`), or open it with `voucher_signer` = the daemon's operator key and pass
its address.

### Step 6: vouchers (what the node redeems)

A voucher is `{ cumulative_amount: u64, signature: [u8;64] }`. It is an **ed25519 signature by
`channel.voucher_signer`** over an 80-byte message:

```
bytes  0..32  domain   = sha256("sentinel-dvpn/channel-voucher/v1")
              = 0a34aa1e233037f6558a364baf39c430236bdfc99943bdeec1bae0ee7222b354
bytes 32..64  channel PDA (32 bytes)
bytes 64..72  channel.opened_at  (i64, little-endian)
bytes 72..80  cumulative_amount  (u64, little-endian)
```

`cumulative_amount` is the **running total** owed for the whole channel, not a delta. The node calls
`redeem_channel_vouchers(vouchers)` (accounts `signer`, `config`, `node` (w); remaining accounts =
the channels, sorted). It is paid `cumulative − redeemed` minus `fee_bps`. Rules a client can rely on:

- A voucher above `channel.escrow` is rejected (**6034** `VoucherExceedsEscrow`). The node can never
  take more than you escrowed.
- A voucher at or below `channel.redeemed` is skipped. Replaying an old voucher pays nothing. If
  nothing new is redeemable the call fails with 6036.
- `opened_at` is in the message, so a voucher cannot be replayed on a later channel at the same PDA.
  `channel.node_opened_at` must match `node.opened_at`, so a node that was closed and reopened cannot
  redeem old channels (6042).
- A bad signature gives 6039. Only sign what you have actually used. With the daemon, it signs for you.

### Step 7: get your money back: `start_close_channel` → wait → `close_channel` → `withdraw_user_balance`

**`start_close_channel()`** (voucher mode only). Accounts: `signer` (s, owner or grantee with `PERM_START_CLOSE_CHANNEL`), `config`, `channel` (w),
`grant` (optional). Sets `status = 1` (closing) and `close_started_at = now`. Errors: **6037**
`ModeNotVoucher` (it is a stream channel; close it directly), **6032** `ChannelNotOpen`, and the
grant gate. During the grace the node can still redeem vouchers you already signed. That is the
point of the wait.

**Wait `Config.channel_close_grace_seconds`, 7200 s (2 h) on devnet.** The deadline is
`close_started_at + 7200`, inclusive.

**`close_channel()`.** Accounts: `signer` (s), `config`, `channel` (w; closed), `user` (w,
`["user", channel.owner]`), `grant` (optional), `node` (w, optional: **required for stream**,
None for voucher), `rent_recipient` (w, must equal `channel.rent_recipient`, Anchor 2012
otherwise).
- Voucher mode: must be closing (**6033** `ChannelNotClosing`) and past the grace (**6035**
  `GraceNotElapsed`). There is **no signer check** in voucher mode: once the grace is over, **anyone**
  can pay the fee to close it. The refund still goes only to the owner's `User.balance`.
- Stream mode: owner or grantee with `PERM_CLOSE_CHANNEL`. It settles what accrued so far to the
  node and closes at once, with no grace. If the node account is gone or was reopened, the accrued
  part is forfeited (not paid to anyone) and the rest is refunded.
- Effect: `User.balance += escrow − redeemed`, `User.open_channels −= 1`, Channel rent goes to
  `channel.rent_recipient`.

**`withdraw_user_balance()`** has no args and withdraws the **whole** balance. Accounts: `signer`
(s, owner or grantee with `PERM_WITHDRAW_USER_BALANCE`), `config`, `owner`, `grant` (optional),
`user` (w), `rent_recipient` (w, must equal `user.rent_recipient`), `owner_token` (w), `vault` (w),
`mint`, `token_program`. It sends `User.balance` from the vault to `owner_token`. If
`open_channels == 0` it also **closes the User account** and sends its rent to
`user.rent_recipient`. It fails with **6023** `BalanceZero` only when the balance is 0 *and*
channels are still open. With 0 balance and no open channels it just closes the account.

`close_channel` + `withdraw_user_balance` fit in one transaction. `close-channel.ts finish` does that.

## 5. Reading state (what to poll)

- `Config`: fetch once and cache `vault`, `mint`, `decimals` and the grace windows.
- Live nodes: `getProgramAccounts(program, memcmp offset 0 = Node discriminator)`, then keep those
  with `status == 1 && now < listed_at + ttl`. Discriminators are in the IDL (`accounts[].discriminator`).
  The Go client has `dvpn.NodeFilter()` and `program.Live()`.
- Your channels: memcmp on the Channel discriminator, plus `owner` at byte offset 40 (8-byte
  discriminator + 32-byte `channel_id`).
- Your refunds: `User.balance` at PDA `["user", owner]`.

## 6. Running the session with `sentinel-dvpnd` (`ClientService` gRPC)

The daemon listens on a **local** endpoint, not TCP
([`daemon/instance/instance.go`](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-go-sdk/daemon/instance/instance.go)):
Linux `/var/lib/sentinel-dvpn/<tag>/daemon.sock`, macOS
`/Library/Application Support/sentinel-dvpn/<tag>/daemon.sock`, Windows
`\\.\pipe\ProtectedPrefix\Administrators\sentinel-dvpn\<tag>` (`<tag>` is the instance name, e.g.
`client`). `DaemonService.GetVersion` returns the `network`, `program_id` and `mint` it was built
for. Check them against section 1 before you trust it.

`service ClientService` (package `sentinel.daemon.v1`):

| rpc | request → response |
|---|---|
| `StartSession` | `{ node, credential, terms }` → `{ session }` |
| `StopSession` | `{ id }` → `{ session, kill_switch_released, dns_revert_failed }` |
| `GetSession` / `WatchSession` (server stream) | `{ id }` → `{ session }` |
| `ListSessions` / `ListChannels` / `ListTickets` | `{}` → lists |

`Credential` is a `oneof`:
- `channel: "<channel address>"`: use a channel you opened yourself.
- `new_channel: { mode, escrow }`: the daemon opens one. **`escrow = 0` means the daemon's
  `escrow_base_units` default, 1 000 000 000 base units = 1 000 tDVPN.** Always set it.
- `ticket_request` / `ticket_hash`: the subscription path (not covered here).

`Terms { basis, price, prepay }` mirror the node's listed price.

What the daemon enforces (`sentinel-dvpnd/internal/client/`):
- The daemon signs vouchers with its **operator key** (`client.key`). For an existing voucher
  channel, that key must equal `channel.voucher_signer`, or the session fails with *"the operator
  key is not the voucher signer of this channel"*. Open your channel with
  `voucher_signer = <daemon operator pubkey>`.
- `client.owner` is the wallet that owns the channels. If the operator key is not the owner, the
  daemon looks up a **Grant** from owner to operator covering the call. Create it in step 2 with
  `program.PermsClient` bits.
- For `new_channel` in voucher mode it refuses an escrow under half the node's minimum prepay block
  (*"channel escrow below node minimum: fund or close the channel"*). Check this before you spend.

## 7. Two-hour close, as a timeline

```
t0           start_close_channel   status=closing; node may still redeem signed vouchers
t0 … t0+7199 close_channel         → 6035 GraceNotElapsed (simulated live, see §10)
t0+7200 …    close_channel         anyone may send it; refund → User.balance; Channel rent → channel.rent_recipient
any time     withdraw_user_balance  User.balance → owner_token; closes User when open_channels == 0
```

Stream channels skip the wait: `close_channel` directly (`start_close_channel` → 6037).

## 8. Rent rules

1. **Who gets rent back.** Every account the client creates stores a `rent_recipient`: the Channel
   (`channel_rent_recipient`), the User (`user_rent_recipient`) and the Grant
   (`grant_rent_recipient`). When that account closes, its lamports go **to that stored address**,
   checked by `address = …rent_recipient`, so pass exactly that account.
2. **What you may pass.** At open time each rent recipient must be **the signer or the
   `rent_payer`** (6050 `InvalidRentRecipient`) and must not be `111…1` (6049
   `MissingRentRecipient`). So the rent can only go back to whoever paid it or whoever signed. A
   relayer that pays rent can name itself.
3. **How much.** The rent is the rent-exempt minimum for the account size. Measured on devnet on
   2026-11-20 (`getMinimumBalanceForRentExemption`): User 117 B = **1 244 600** lamports, Channel
   299 B = **2 169 160**, Grant 201 B = 1 671 320. The open in §10 moved exactly 1 244 600 + 2 169 160
   + 5 000 fee lamports out of the wallet.
4. **The 0-or-rent-exempt rule (Solana runtime, not dvpn).** After any transaction, a plain wallet
   account must hold either **0 lamports or at least the rent-exempt minimum for 0 bytes**. Otherwise
   the transaction fails (`InsufficientFundsForRent`). So never drain a fee payer to a few lamports,
   and do not send dust to a fresh address. **Query the minimum, do not hard-code it:** on devnet on
   2026-11-20 `getMinimumBalanceForRentExemption(0)` returned **650 240**, not the 890 880 often quoted
   (890 880 is the classic `3480 lamports/byte-year × 2 years × 128 bytes` figure).

## 9. Program errors

A Solana transaction is atomic, so **a failed transaction moves no tokens and creates or closes no
account**. You still pay the 5 000-lamport fee if you *sent* it; a simulation costs nothing. That is
why every row's "money moved?" is "No". Read the number from the log line `Error Number: N`, from
`custom program error: 0x…`, or from `{"Custom": N}`. On devnet on 2026-11-20 these were produced
live: 6033, 6035 and 6049 (§10).

**Decode it in code:** [`ts/errors.ts`](build-your-own-client/ts/errors.ts) turns a failed
simulation or send into exactly one row of this table, `{ code, name, meaning, moneyMoved, fix }`.
`open-channel.ts` and `close-channel.ts` print it on every failure.
[`ts/explain-failure.ts`](build-your-own-client/ts/explain-failure.ts) shows it with no key at all:
it simulates `close_channel` on a live voucher channel still in its grace, unsigned (§10).

**What the table covers:**
- Every IDL error, 6000–6050.
- Every Anchor framework code the client flow can hit. These numbers are from anchor-lang **1.2.2**,
  the version in `sentinel-programs/Cargo.lock`, checked against its `lang/error/src/lib.rs`. They
  are the same 16 codes the Devnet dVPN app decodes.

`meaning` is the IDL `msg`, followed by where the program raises it (source at 26de5240). A row a
channel-only client never hits says "governance only" or names the node or provider instruction.

The table is generated from `errors.ts` and the IDL. Regenerate it with `npx tsx gen-error-table.ts`;
`npx tsx gen-error-table.ts --check BUILD-YOUR-OWN-CLIENT.md` fails when it drifts.

<!-- error-table:start (generated by ts/gen-error-table.ts) -->
| number | name | meaning | money moved? | fix |
|---|---|---|---|---|
| 6000 | `Unauthorized` | signer is not authorized for this action: every owner-or-grantee instruction, update_grant, close_grant: the signer is not the owner and no valid grant names it | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | sign with the owner, or pass the Grant PDA ["grant", owner, signer, target] |
| 6001 | `OperationPaused` | this operation is paused: open_* instructions: Config.paused_mask has that open paused (channels: bit 32) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | wait; read Config.paused_mask before opening |
| 6002 | `FeeBpsOutOfRange` | fee bps out of range: governance (set_params): fee_bps above the limit | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6003 | `ParamOutOfRange` | parameter out of range: open_grant / update_grant: grantee is 111…1 or the granter, unknown permission bits, or expires_at not 0 and not in the future; governance: a parameter out of range | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | fix the arguments |
| 6004 | `MissingPendingAuthority` | pending authority is missing: governance (accept_authority): no pending authority | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6005 | `InvalidMint` | mint is invalid: initialize_config: the mint is not a valid Token-2022 mint | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6006 | `MintExtensionForbidden` | mint has a forbidden extension: initialize_config: the mint has a forbidden extension | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6007 | `MintNotSealed` | mint is not sealed: initialize_config: the mint still has a mint or freeze authority | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6008 | `VaultNotAssociated` | vault is not the config associated token account: governance: the vault is not the Config PDA’s associated token account | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6009 | `VaultNotImmutable` | vault is not immutable-owner: governance: the vault lacks the immutable-owner extension | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6010 | `InvalidTreasury` | treasury may not be the vault or config-owned: governance (set_treasury / initialize_config): the treasury is the vault or Config-owned | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | governance only |
| 6011 | `BondBelowMinimum` | bond below minimum: open_node / open_provider: the bond is below Config.min_node_bond / min_provider_bond | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | bond at least the minimum |
| 6012 | `BondPending` | a parked bond is pending for this id: open_node / open_provider: a parked bond for this id is still unbonding | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | withdraw the old bond after the unbonding window, then open |
| 6013 | `UnbondingNotElapsed` | unbonding window not elapsed: withdraw_node_bond / withdraw_provider_bond: Config.unbonding_seconds has not passed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | wait for the unbonding window |
| 6014 | `UriTooLong` | uri too long: node / provider instructions: the URI is longer than its 128-byte field | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use a shorter URI |
| 6015 | `NodeNotListed` | node is not listed: open_channel / open_lease: node.status is not 1 (listed) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pick another node |
| 6016 | `NodeNotLive` | node is not live: open_channel / open_lease: now >= node.listed_at + Config.node_listing_ttl_seconds | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pick a node listed within the TTL |
| 6017 | `NodePriceChanged` | node price changed: open_channel / open_lease (stream): expected_rate_per_hour differs from the node’s current price | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | read the node again and retry with its current price |
| 6018 | `InsufficientRevenue` | insufficient revenue: withdraw_node_revenue / withdraw_provider_revenue: amount above the revenue held | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | withdraw at most the revenue |
| 6019 | `FeesZero` | fees to sweep are zero: sweep_*_fees: nothing accrued to sweep | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | nothing to do |
| 6020 | `ProviderNotListed` | provider is not listed: open_lease / open_subscription: the provider is not listed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pick another provider or plan |
| 6021 | `OpenPlansRemain` | open plans remain: close_provider: the provider still has open plans | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | close its plans first |
| 6022 | `OpenLeasesRemain` | open leases remain: close_provider: the provider still has open leases | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | close its leases first |
| 6023 | `BalanceZero` | balance to withdraw is zero: withdraw_user_balance / withdraw_provider_balance: the balance is 0 and positions are still open | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | close the open channels first; there is nothing to withdraw yet |
| 6024 | `AmountExceedsAllowance` | amount exceeds allowance: delegated open_channel / fund_channels (and leases): escrow above the grant’s remaining allowance | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | the owner raises it with update_grant |
| 6025 | `PlanNotListed` | plan is not listed: open_subscription: the plan is not listed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pick another plan |
| 6026 | `PlanNotDelisted` | plan is not delisted: close_plan: the plan is still listed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | delist the plan first |
| 6027 | `PlanTermsChanged` | plan terms changed: open_subscription: the plan’s terms differ from the ones passed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | read the plan again and retry with its current terms |
| 6028 | `SubscriptionNotExpired` | subscription not expired: close_subscription by someone who is not the owner, its grantee or the provider: not expired yet | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | wait until it expires |
| 6029 | `SubscriptionPriceNotZero` | subscription price is not zero: close_subscription by the provider before expiry: allowed only when the subscription price is 0 | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | wait until it expires (a paid subscription) |
| 6030 | `LeaseNotOpen` | lease is not open: lease instructions: the lease is not open | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | open a new lease |
| 6031 | `LeaseNotClosing` | lease is not closing: close_lease (voucher): start_close_lease was not called | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | call start_close_lease first |
| 6032 | `ChannelNotOpen` | channel is not open: fund_channels / start_close_channel: the channel is already closing | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | open a new channel |
| 6033 | `ChannelNotClosing` | channel is not closing: close_channel (voucher): start_close_channel was not called | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | call start_close_channel first |
| 6034 | `VoucherExceedsEscrow` | voucher exceeds escrow: redeem_channel_vouchers (node side): the voucher is above the escrow; protects the client | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | never sign a voucher above Channel.escrow |
| 6035 | `GraceNotElapsed` | grace window not elapsed: close_channel (voucher): less than Config.channel_close_grace_seconds (7200 s) since close_started_at | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | wait until close_started_at + channel_close_grace_seconds |
| 6036 | `RedeemableZero` | redeemable amount is zero: redeem_* (node side): nothing new to redeem | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | nothing to do |
| 6037 | `ModeNotVoucher` | position mode is not voucher: start_close_channel / redeem_channel_vouchers on a stream channel | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | stream channel: call close_channel directly, no start_close |
| 6038 | `ModeNotStream` | position mode is not stream: redeem_*_streams on a voucher position | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use the voucher redeem instead |
| 6039 | `InvalidVoucherSignature` | voucher signature is invalid: redeem_*_vouchers: not signed by voucher_signer over the 80-byte voucher message | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | sign the exact 80-byte message with the channel’s voucher_signer |
| 6040 | `BatchLengthMismatch` | batch length mismatch: batch instructions (fund_channels, redeem_*): number of amounts ≠ number of accounts, or none | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass one amount per account, at least one |
| 6041 | `BatchNotSorted` | batch not sorted: batch instructions: accounts not strictly ascending by pubkey bytes | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | sort by pubkey bytes and remove duplicates |
| 6042 | `NodeReopened` | position belongs to an earlier incarnation of this node: redeem / stream settle: the node was closed and reopened after the channel opened | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | close the channel (refund) and open a new one |
| 6043 | `ArithmeticOverflow` | arithmetic overflow: any: a u64 sum or product overflowed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use sane amounts (a client bug) |
| 6044 | `VaultFrozen` | vault is frozen: governance: the vault is frozen | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | wait; payments are frozen network-wide |
| 6045 | `GrantExpired` | grant has expired: any delegated instruction: now >= grant.expires_at (not 0) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | the owner extends it with update_grant |
| 6046 | `PermissionNotGranted` | grant does not include the permission for this action: any delegated instruction: the grant lacks this action’s permission bit | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | the owner adds the bit with update_grant |
| 6047 | `GrantTargetMismatch` | grant target does not cover this account: any delegated instruction: grant.target is not 111…1, the node or the channel | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use a grant whose target covers the account |
| 6048 | `InvalidVoucherSigner` | voucher signer is not a valid key: open_channel / open_lease (voucher): voucher_signer is not a prime-order ed25519 point | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use a real ed25519 public key |
| 6049 | `MissingRentRecipient` | rent recipient is missing: open_channel / open_grant (and other opens): a rent recipient argument is 111…1 | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass the signer or the rent payer |
| 6050 | `InvalidRentRecipient` | rent recipient is neither the signer nor the rent payer: the same opens: the rent recipient is neither the signer nor the rent payer | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass the signer or the rent payer |
| 100 | `InstructionMissing` | no 8-byte instruction discriminator in the data | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | encode the instruction with the IDL |
| 101 | `InstructionFallbackNotFound` | unknown instruction discriminator | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | encode with the IDL of the deployed program |
| 102 | `InstructionDidNotDeserialize` | the args do not match this program version | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | re-encode with the IDL of the deployed program |
| 2000 | `ConstraintMut` | an account that must be writable was passed read-only | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | mark it writable (IDL "writable") |
| 2001 | `ConstraintHasOne` | an account does not belong to the owner it must (e.g. a funded channel of another wallet) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass the owner’s own accounts |
| 2002 | `ConstraintSigner` | an account that must sign did not | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | add its signature (IDL "signer") |
| 2003 | `ConstraintRaw` | a custom account constraint failed | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | check the accounts against the IDL |
| 2006 | `ConstraintSeeds` | a PDA does not match its seeds (also: a grant passed while the owner signs) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | derive the PDA again; pass no grant when the owner signs |
| 2012 | `ConstraintAddress` | an account is not the one stored on chain (vault, mint, token program, rent recipient) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass Config.vault, Config.mint, Token-2022 and the stored rent_recipient |
| 2014 | `ConstraintTokenMint` | owner_token is for another mint | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use the owner’s Token-2022 account for Config.mint |
| 2015 | `ConstraintTokenOwner` | owner_token belongs to another wallet | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | use the owner’s Token-2022 account for Config.mint |
| 2019 | `ConstraintSpace` | an account was created with the wrong size | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | a client or program bug: report it |
| 2020 | `ConstraintAccountIsNone` | a required optional account was None (e.g. node on a stream close) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass the account (node on a stream close_channel) |
| 3005 | `AccountDidNotSerialize` | the program could not write an account | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | a program bug: report it |
| 3007 | `AccountOwnedByWrongProgram` | an account is owned by another program (e.g. a plain SPL Token account) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | pass the dvpn / Token-2022 account the IDL names |
| 3012 | `AccountNotInitialized` | an account the instruction reads does not exist yet (e.g. User before the first channel) | No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing. | open a channel first (it creates the User account) |
<!-- error-table:end -->

## 10. Examples (run on 2026-11-20)

All runs: Azure VM, Ubuntu 24.04, Node 22.23.5, Go 1.27.3 (via `GOTOOLCHAIN=auto`), public devnet
RPC, a fresh wallet `<your-wallet-address>` funded with 0.05 SOL and 1 tDVPN.

What each run proves, and where:

| Example | Run | Proof |
|---|---|---|
| `ts/read.ts` | live read, no key | the output below (Config, 79 nodes, 36 live) |
| `ts/open-channel.ts` | real `open_channel` + `start_close`, plus three simulated failures (6049, 6033, 6035) | the output below and the explorer links ([open](https://explorer.solana.com/tx/3D3s6MWY6LLxVgT2eNimyLcS8XfYo8kzWa423gK9UiM386NYm7Cc2znKXQSBM5Nrcb3ngfDK8pEuBisvRy3EAV3d?cluster=devnet), [start_close](https://explorer.solana.com/tx/2pdoKkBLEwvc6G2tq9uc12GeKNbCpQ6wEkG4npZox4Z2AfBr4C6zvkrcyiwcf114EUkVKC5jjMc4PMJmUT7VrHtC?cluster=devnet)) |
| `ts/close-channel.ts` | real `close_channel` + `withdraw_user_balance` at 10:52Z, after the grace | [hPKsn1mw…](https://explorer.solana.com/tx/hPKsn1mwMb77EVkGn9mfC8eiVCiK8JS2xapBirAW7N3HDueSQ9ET8SQmT4bnuA1eLHsS4EGvT17PRNUkBsrdSMC?cluster=devnet): the full 0.5 tDVPN escrow back |
| `ts/explain-failure.ts` | live unsigned simulation, no key, second VM | the 6035 output below |
| `go/main.go` | live read + simulated `open_channel` (no transaction sent) | the Go output below (`units=29683`) |

**Checked on every push** (CI, no wallet, no transaction): `go vet` and `go build` of `go/` against the
public repo at `26de5240`, and `ts/gen-error-table.ts --check`, which fails when the §9 error table
drifts from `errors.ts` and the public IDL. The live runs above are not repeated in CI: they need a funded wallet.

### TypeScript (`@solana/web3.js` 1.98.4 + `@coral-xyz/anchor` 0.31.1 coders + the IDL)

Files: [`build-your-own-client/ts/`](build-your-own-client/ts/) (`common.ts`, `errors.ts`, `read.ts`,
`open-channel.ts`, `close-channel.ts`, `explain-failure.ts`, `gen-error-table.ts`, `package.json`). Put `dvpn.json` from the
public repo next to them. All files typecheck with `tsc --strict` (TypeScript 5.9.3).

```bash
npm install
npx tsx read.ts <ownerPubkey>                                   # read
npx tsx explain-failure.ts                                      # decode a failing close_channel; no key, nothing signed
npx tsx open-channel.ts wallet.json <node> 500000 --bad-rent     # prove 6049, sends nothing
npx tsx open-channel.ts wallet.json <node> 500000                # open (sends)
npx tsx close-channel.ts wallet.json <channel> start             # start_close (sends)
npx tsx close-channel.ts wallet.json <channel> finish            # after 2 h: close + withdraw
```

The core of the open, with accounts in IDL order and the optional grant as the program id:

```ts
const data = ixCoder.encode('open_channel', {
  channel_id: [...channelId], escrow: new BN(500000),
  terms: { Voucher: { voucher_signer: owner } },
  channel_rent_recipient: owner, user_rent_recipient: owner,
});
const keys = [signer(owner, w), config, owner, PROGRAM_ID /* grant=None */, userPda(owner) /* w */,
  node, channelPda(owner, channelId) /* w */, config.vault /* w */, MINT, ata(owner) /* w */,
  TOKEN_2022, rentPayer(owner, w s), SystemProgram.programId];
```

Output (trimmed):

```
config Cu5vofxVQgZXRVwfBqApw84ZWy1hjhDmHkznyDr6TRiQ
  mint Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa (matches)
  decimals 6 fee_bps 200 paused_mask 0
  channel_close_grace_seconds 7200 node_listing_ttl_seconds 86400
nodes: 79 accounts, 36 listed and live
  Kg96W7ScKBycWHjDyoTPxeQZTv7ry15P7Ug663rC7yf BR https://163.176.182.147:41000 per_gb=50000000 per_hour=97500000
user <your-user-pda> not created yet (open_channel creates it)

--bad-rent:  simulate: error {"InstructionError":[1,{"Custom":6049}]}  … Error Code: MissingRentRecipient. Error Number: 6049.
open:        channel FXcFMT6GiaXQKVPw6FssF1FwpKWxksh1JYYzWB2sKRqy  simulate: ok units 32555
             sent 3D3s6MWY6LLxVgT2eNimyLcS8XfYo8kzWa423gK9UiM386NYm7Cc2znKXQSBM5Nrcb3ngfDK8pEuBisvRy3EAV3d
             channel escrow 500000 status 0 opened_at 1795164546
finish before start (simulated):  program_error=6033  ChannelNotClosing
start:       sent 2pdoKkBLEwvc6G2tq9uc12GeKNbCpQ6wEkG4npZox4Z2AfBr4C6zvkrcyiwcf114EUkVKC5jjMc4PMJmUT7VrHtC
finish inside grace (simulated):  grace ends at 2026-11-20T10:49:28.000Z  program_error=6035  GraceNotElapsed
```

`explain-failure.ts` (run later the same day on a second Ubuntu VM, no wallet, unsigned simulation):

```
channel <a-closing-channel> (closing, inside its grace) status 1
{
  "code": 6035,
  "name": "GraceNotElapsed",
  "meaning": "grace window not elapsed: close_channel (voucher): less than Config.channel_close_grace_seconds (7200 s) since close_started_at",
  "moneyMoved": "No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing.",
  "fix": "wait until close_started_at + channel_close_grace_seconds"
}
```

What the open transaction moved: wallet −3 418 760 lamports (User rent 1 244 600 + Channel rent
2 169 160 + fee 5 000); wallet ATA 1 000 000 → 500 000 base units; vault +500 000.
Explorer: [open](https://explorer.solana.com/tx/3D3s6MWY6LLxVgT2eNimyLcS8XfYo8kzWa423gK9UiM386NYm7Cc2znKXQSBM5Nrcb3ngfDK8pEuBisvRy3EAV3d?cluster=devnet),
[start_close](https://explorer.solana.com/tx/2pdoKkBLEwvc6G2tq9uc12GeKNbCpQ6wEkG4npZox4Z2AfBr4C6zvkrcyiwcf114EUkVKC5jjMc4PMJmUT7VrHtC?cluster=devnet).
`finish` ran at 10:52Z, after the grace: one transaction with `close_channel` + `withdraw_user_balance`,
[hPKsn1mw…](https://explorer.solana.com/tx/hPKsn1mwMb77EVkGn9mfC8eiVCiK8JS2xapBirAW7N3HDueSQ9ET8SQmT4bnuA1eLHsS4EGvT17PRNUkBsrdSMC?cluster=devnet).
No vouchers had been redeemed, so the whole 0.5 tDVPN escrow came back to the wallet's token account.
The Channel and User accounts closed (`open_channels` was 0), and their rent went to the wallet,
the stored `rent_recipient`. Afterwards the channel and User addresses read "no account" on the public RPC.

### Go (public SDK `sentinel-go-sdk/program` + generated `clients/go/dvpn`)

Files: [`build-your-own-client/go/`](build-your-own-client/go/) (`main.go`, `go.mod`; `go mod tidy` writes `go.sum`).
`go.mod` points both modules at a clone of the public repo in `../ss`:

```bash
git clone https://github.com/sentinel-official/sentinel-solana ../ss && git -C ../ss checkout 26de5240
GOTOOLCHAIN=auto go mod tidy                                    # fetches deps, writes go.sum
GOTOOLCHAIN=auto go run .                                       # read only
GOTOOLCHAIN=auto go run . wallet.json <node> 500000             # read + build + SIMULATE open_channel
```

```go
dvpn.SetProgramID(programID)                       // the generated client ships a placeholder id
client := program.NewClient(rpc.New(rpc.DevNet_RPC), programID, mint, rpc.CommitmentConfirmed)
client.CheckMint(ctx)                              // Config.mint must equal the mint you expect
cfg, _ := client.Config(ctx)
nodes, _ := client.FindNodeAccounts(ctx, dvpn.NodeFilter())
// live = Status == dvpn.ListingStatusListed && program.Live(node, cfg, now)
ix, _ := dvpn.BuildOpenChannelInstruction(programID, dvpn.OpenChannelParams{
  ChannelID: id, Escrow: 500000, Terms: &dvpn.PositionTermsVoucher{VoucherSigner: owner},
  ChannelRentRecipient: owner, UserRentRecipient: owner, Signer: owner, Owner: owner,
  Grant: nil, Node: node, Vault: cfg.Vault, Mint: mint, OwnerToken: ata, RentPayer: owner,
})
```

Output:

```
config: mint Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa decimals 6 fee_bps 200 close_grace 7200s listing_ttl 86400s paused_mask 0
  Kg96W7ScKBycWHjDyoTPxeQZTv7ry15P7Ug663rC7yf BR https://163.176.182.147:41000 per_gb=50000000 per_hour=97500000
nodes: 79 accounts, 36 listed and live
open_channel 7WkQr8zsMkHEZsGhL3N37xMxQBtmnh1S3iJUrh6Km31T simulate: err=<nil> units=29683
```

The Go open was **simulated only** (allowed: one real channel open per run, done in TS). The
simulation ran the real program against live accounts and succeeded.

## 11. What was checked, and where sources disagreed

- **Program version.** Older notes said devnet ran an earlier build: errors only up to 6048, an
  `OperatorMandate` account instead of `Grant`, a 3-argument `open_channel`. The live chain
  disagrees. It returned 6049, it accepted the 5-argument 26de5240 `open_channel`, and every account
  size matches 26de5240. **This doc follows the live chain = 26de5240.**
- **Close wait.** "2 h" is not a program constant. It is `Config.channel_close_grace_seconds`, read
  live as 7200. Read it from Config; governance can change it with `set_params`.
- **"Rent goes back to the rent payer."** Not exactly. It goes to the stored `rent_recipient`,
  which at open time must be **the signer or the rent payer**. In the common case (one wallet signs
  and pays) that is the same key.
- **"0 or ≥ 890 880 lamports."** The rule is real (Solana runtime), but the number is not fixed. On
  devnet on 2026-11-20 the 0-byte minimum was **650 240** lamports. Query
  `getMinimumBalanceForRentExemption(0)`.
- **Daemon escrow default** is 1 000 tDVPN (`escrow_base_units = 1000000000`) when
  `NewChannel.escrow` is 0 (`sentinel-dvpnd/internal/config/client.go`).
- **Not run here:** the daemon (`StartSession`), node redemption, `fund_channels`, grants, stream
  mode. Their accounts, args and errors above come from
  the IDL and program source at 26de5240 only.
