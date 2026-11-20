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

## 9. Program errors the client flow can hit

A Solana transaction is atomic, so **a failed transaction moves no tokens and creates no account**.
You still pay the 5 000-lamport fee if you *sent* it; a simulation costs nothing. So "money moved"
is "no (fee only)" for every row. The column below says what money is *at stake* and how to recover.
Read the number from the log line `Error Number: N` or from `{"Custom": N}`. Rows marked
**live** were produced on devnet on 2026-11-20 (§10).

| code | name | where (client flow) | meaning | money moved | fix |
|---|---|---|---|---|---|
| 6000 | `Unauthorized` | every gated ix, `update_grant`, `close_grant` | signer is not the owner and no valid grant was passed; grantee == owner; wrong granter | no (fee only) | sign with the owner, or pass the right Grant PDA |
| 6001 | `OperationPaused` | `open_channel` | `Config.paused_mask` has `PAUSE_CHANNEL_OPENS` (32) set | no (fee only) | wait; read `Config.paused_mask` before opening |
| 6003 | `ParamOutOfRange` | `open_grant`, `update_grant` | bad grantee, unknown permission bits, `expires_at` in the past | no (fee only) | fix the args |
| 6015 | `NodeNotListed` | `open_channel` | `node.status != 1` | no (fee only) | pick another node |
| 6016 | `NodeNotLive` | `open_channel` | `now >= listed_at + node_listing_ttl_seconds` | no (fee only) | filter by liveness (§5) |
| 6017 | `NodePriceChanged` | `open_channel` (stream) | `expected_rate_per_hour` ≠ node price | no (fee only) | re-read the node, retry with the new price |
| 6023 | `BalanceZero` | `withdraw_user_balance` | balance is 0 and channels are still open | no (fee only) | close channels first, or nothing to withdraw |
| 6024 | `AmountExceedsAllowance` | `open_channel`, `fund_channels` (delegated) | escrow > remaining grant allowance | no (fee only) | owner raises it with `update_grant` |
| 6032 | `ChannelNotOpen` | `fund_channels`, `start_close_channel` | channel is already closing | no (fee only) | open a new channel |
| 6033 | `ChannelNotClosing` | `close_channel` (voucher) | `start_close_channel` was not called | no (fee only) | call `start_close_channel` first. **live** |
| 6034 | `VoucherExceedsEscrow` | node's redeem | voucher above escrow (protects you) | no | client: never sign above escrow |
| 6035 | `GraceNotElapsed` | `close_channel` (voucher) | less than 7200 s since `close_started_at` | no (fee only) | wait until `close_started_at + 7200`. **live** |
| 6036 | `RedeemableZero` | node's redeem | nothing new to redeem | no | (node side) |
| 6037 | `ModeNotVoucher` | `start_close_channel` | stream channel | no (fee only) | call `close_channel` directly |
| 6039 | `InvalidVoucherSignature` | node's redeem | voucher not signed by `voucher_signer` over the §4 step 6 message | no | fix the message bytes or signing key |
| 6040 | `BatchLengthMismatch` | `fund_channels` | `amounts.len()` ≠ remaining accounts, or 0 | no (fee only) | one amount per channel |
| 6041 | `BatchNotSorted` | `fund_channels` | remaining channels not strictly ascending by bytes | no (fee only) | sort by `pubkey.toBytes()`, dedupe |
| 6042 | `NodeReopened` | node's redeem | node closed and reopened since the channel opened | no | close the channel, open a new one |
| 6043 | `ArithmeticOverflow` | any | u64 overflow (absurd amounts) | no (fee only) | client bug |
| 6045 | `GrantExpired` | any delegated ix | `now >= grant.expires_at` (≠ 0) | no (fee only) | owner extends it (`update_grant`) |
| 6046 | `PermissionNotGranted` | any delegated ix | permission bit missing | no (fee only) | owner adds the bit |
| 6047 | `GrantTargetMismatch` | any delegated ix | grant `target` is not 111…1, the node or the channel | no (fee only) | use a grant with the right target |
| 6048 | `InvalidVoucherSigner` | `open_channel` (voucher) | `voucher_signer` not a prime-order ed25519 point | no (fee only) | use a real ed25519 public key |
| 6049 | `MissingRentRecipient` | `open_channel`, `open_grant` | a rent recipient arg is 111…1 | no (fee only) | pass the signer or rent payer. **live** (simulated) |
| 6050 | `InvalidRentRecipient` | `open_channel`, `open_grant` | rent recipient is neither signer nor rent payer | no (fee only) | same |

The other IDL errors (6002, 6004–6014, 6018–6022, 6025–6031, 6038, 6044) belong to governance,
node, provider, plan, lease and subscription instructions. A pure channel client does not hit them.
`6044 VaultFrozen` is raised only by governance code at 26de5240.

Anchor framework errors you can also see (standard Anchor numbers, not in the dvpn IDL, none
observed in this run): 2001 `ConstraintHasOne` (a funded channel is not the owner's), 2006
`ConstraintSeeds` (wrong PDA), 2012 `ConstraintAddress` (wrong vault, mint, token program or rent
recipient), 2014/2015 `ConstraintTokenMint`/`ConstraintTokenOwner` (`owner_token` is not the
owner's Token-2022 account for the mint), 2020 `ConstraintAccountIsNone` (stream close without
`node`), 3012 `AccountNotInitialized` (no User yet for fund/withdraw), 102
`InstructionDidNotDeserialize` (args encoded for a different program version).

## 10. Examples (run on 2026-11-20)

All runs: Azure VM, Ubuntu 24.04, Node 22.23.5, Go 1.27.3 (via `GOTOOLCHAIN=auto`), public devnet
RPC, a fresh wallet `<your-wallet-address>` funded with 0.05 SOL and 1 tDVPN.

### TypeScript (`@solana/web3.js` 1.98.4 + `@coral-xyz/anchor` 0.31.1 coders + the IDL)

Files: [`build-your-own-client/ts/`](build-your-own-client/ts/) (`common.ts`, `read.ts`,
`open-channel.ts`, `close-channel.ts`, `package.json`). Put `dvpn.json` from the public repo next to
them.

```bash
npm install
npx tsx read.ts <ownerPubkey>                                   # read
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

What the open transaction moved: wallet −3 418 760 lamports (User rent 1 244 600 + Channel rent
2 169 160 + fee 5 000); wallet ATA 1 000 000 → 500 000 base units; vault +500 000.
Explorer: [open](https://explorer.solana.com/tx/3D3s6MWY6LLxVgT2eNimyLcS8XfYo8kzWa423gK9UiM386NYm7Cc2znKXQSBM5Nrcb3ngfDK8pEuBisvRy3EAV3d?cluster=devnet),
[start_close](https://explorer.solana.com/tx/2pdoKkBLEwvc6G2tq9uc12GeKNbCpQ6wEkG4npZox4Z2AfBr4C6zvkrcyiwcf114EUkVKC5jjMc4PMJmUT7VrHtC?cluster=devnet).
The `finish` step (close + withdraw) has **not run yet**: it can only run after 10:49:28Z.

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
  mode, and `close_channel` + `withdraw_user_balance`. Their accounts, args and errors above come from
  the IDL and program source at 26de5240 only.
