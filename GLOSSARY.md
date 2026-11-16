# Glossary

One plain line per term the page ([`AGENTS.md`](AGENTS.md)), [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md),
[`mcp/README.md`](mcp/README.md) and the JSON answers use, with the command that shows or changes it.
A line is `**term** (`other names`) — meaning. Shows: … Changes: …`. Every command starts with
`devnet-dvpn`. Failure `code` values are not listed here: each one is defined, with its message and its next
command, in the failure-code tables of [`docs/AGENT-COMMANDS.md`](docs/AGENT-COMMANDS.md).

## Money and accounts

- **tDVPN** (`tdvpn`) — the devnet token you pay nodes with. It has no value. Shows: `agent status --json` (`tdvpn`). Changes: a person asks the faucet (page, section 3), or `wallet send --to <ADDRESS> --tdvpn 100 --yes`.
- **SOL** (`sol`) — devnet SOL: pays transaction fees only. It has no value. Shows: `agent status --json` (`sol`). Changes: a person asks the Solana faucet.
- **devnet** — the Solana test network. Nothing on it is worth money. Shows: `version --json` (must say network devnet).
- **wallet** (`address`, `owner`) — your account: an address that holds tDVPN and SOL. Shows: `wallet show --json`, `agent status --json` (`address`). Changes: `wallet create --keyfile <path> --yes`, `wallet import <file>`.
- **key file** (`DVPN_KEYFILE`) — the file with your wallet's secret key; whoever has it owns the wallet. The environment variable `DVPN_KEYFILE` names it. Shows: `wallet show`. Changes: `wallet create`, `wallet import <file>`. Never print it or commit it.
- **base units** (`baseUnits`, `ownerLamports`, `ownerTdvpn`, `priceUnit`) — the same amount as a whole number: 1 tDVPN = 1000000, 1 SOL = 1000000000. Shows: any `--json` answer that carries the field.
- **userBalance** — tDVPN held for your wallet inside the program, in base units; `settle withdraw` moves it to the wallet. It is the number `agent status` calls `refundable`. Shows: `wallet show --json`. Changes: `settle withdraw --yes`.

## Deposits and refunds

- **deposit** (`channel`) — tDVPN you lock for one node. The part you do not use comes back. Shows: `settle list`. Changes: `agent up --yes` opens one, `agent down --yes` closes it.
- **per GB / per hour** (`per_gb`, `per_hour`, `perGb`, `perHour`, `basis`) — how a deposit is billed: by data or by time. Shows: `cost <node> --basis per_gb --units 1`. Changes: `agent up --basis per_gb|per_hour --units <N>`.
- **price** (`priceUnit`) — tDVPN per GB or per hour a node asks. Shows: `nodes list --json`, `cost <node>`. Changes: `agent up --max-price N` caps it.
- **open / in-use / closing / ready** (`pending`) — the state of a deposit: open = unused, in-use = the live session's, closing = refund started and waiting, ready = refund can be taken. Shows: `settle list`, `agent down --json` (`pending`).
- **readyAt** — the time (Unix seconds) a closing deposit becomes ready. Shows: `settle list`, `agent down --json`.
- **refundable** — in `settle list` and `agent down --json`: the tDVPN still to come back from deposits that are closing; a lower bound. In `agent status --json` it means something else: the tDVPN already held for your wallet (`userBalance`). Shows: `settle list`, `agent status --json`.
- **settle** — the two steps that return a deposit's unused part: `settle run --yes` starts closing, and again after the wait finishes it. Shows: `settle list`. Changes: `settle run --yes`.
- **withdraw** — moves the tDVPN held for your wallet (`userBalance`) into the wallet. Changes: `settle withdraw --yes`. Shows: `agent status --json` (`refundable`).
- **spent** — tDVPN the live session has used so far. Shows: `agent status --json` (`spent`).
- **plan** (`plan session`, `subscription`) — a prepaid subscription: one price up front, no refund, only the plan's own nodes. Shows: `plans list`. Changes: `plans subscribe <plan> --yes`, then `agent up --plan <subscription>`.
- **voucher** (`stream`) — how a node bills: voucher = per hour, stream = per GB. A node supports one; the codes `mode_not_voucher` and `mode_not_stream` mean the other. Changes: `agent up --basis per_hour|per_gb`.

## This computer

- **device** (`device key`) — what signs for you on this computer: a key kept here that spends from your wallet only up to the spending limit. Shows: `device show --json`. Changes: `daemon init`, `device setup --yes`, `device switch --yes` (Windows rc.3.1).
- **spending limit** (`allowance`, `grant.allowance`, `token approval`, `spending approval`) — the most tDVPN the device may spend from your wallet; a cap, not a charge. It is a token approval, and repeated setups can leave it larger than you set. Shows: `device show --json` (`grant.allowance`, base units). Changes: `device setup --allowance N --yes`.
- **device SOL** — a little SOL (about 0.05) that `device setup` sends the device to pay its own fees. Shows: `device show --json`. Changes: `device setup --yes`.
- **service** (`dvpnd`, `no-service`) — the VPN program that runs in the background on this computer and builds the tunnel. Shows: `daemon doctor --json`. Changes: `daemon install --yes`, `daemon uninstall`.
- **drivers** (`repair-drivers`) — the protocol tools the service needs on this computer. Shows: `daemon drivers`. Changes: `daemon repair-drivers --yes`.
- **relogin** — the service does not accept this account yet in a normal shell: start a new sign-in or SSH session. Shows: `daemon install --json` (`"relogin": true`).
- **RPC** — the Solana connection the service uses. Shows: `daemon settings --json`. Changes: `daemon set --rpc <https url> --yes`.
- **kill switch** (`persist`, `on`, `off`, `blocked`, `blockedBefore`) — blocks the internet whenever the tunnel is not up. `persist` and `on` are the same setting in this app. `blocked` = no session and the internet is blocked. Shows: `daemon settings --json`, `quality ip`, `agent status --json` (`blocked`). Changes: `daemon set --kill-switch on|off --yes`, `daemon restore-network`.
- **split tunnelling** — sends some addresses or apps around the tunnel. Shows: `split status`. Changes: `daemon set --split-mode exclude --split-routes <list> --yes`.
- **whole device** (`wholeDevice`) — the whole computer goes through the node, not only apps that use the proxy. Shows: `agent status --json` (`wholeDevice`), `daemon settings --json`. Changes: `daemon set --whole-device false --yes`.

## Nodes and the connection

- **node** (`server`) — a computer that sells VPN traffic; you pay it a deposit. The page says node; `server` means the same. Shows: `nodes list --online --json`. Changes: `agent up --node N`.
- **protocol** — how the tunnel is built; a node serves one. WireGuard, AmneziaWG, OpenVPN and Hysteria2 carry the whole computer. V2Ray and Xray carry the whole computer on a new Windows or macOS install and only proxy users on Linux. Shows: `daemon drivers`, `nodes list --protocol <name>`. Changes: `agent up --protocol <name>`.
- **country** — the two-letter country the node reports. Changes: `agent up --country DE`.
- **tunnel** — the encrypted link between this computer and the node. Shows: `quality ip --json`.
- **connected** (`disconnected`, `session`) — a session with a node is live; `session` is its id. Shows: `agent status --json`. Changes: `agent up --yes`, `agent down --yes`.
- **exitIp / directIp** (`direct`, `direct.ip`, `viaSocks.ip`) — the address the internet sees. `directIp` is this computer's own address; `exitIp` is the node's. If they are equal you are not tunnelled. Shows: `quality ip --json`, `agent up --json` (`exitIp`, `directIp`).
- **socks** (`viaSocks`) — the local proxy address (`socks5h://host:port`) for apps; the only traffic that uses a V2Ray or Xray tunnel on Linux. Shows: `agent status --json` (`socks`), `quality ip --json` (`viaSocks`).
- **reused** — `agent up` kept the live session because it already matches what you asked; nothing was paid. Shows: `agent up --json` (`reused`).
- **switchFrom** — the node a switch would leave. Shows: `agent up` without `--yes` (`switchFrom`).

## Answers and flags

- **devnet-dvpn** (`DVPN_CLI_NAME`, `<cli>`) — the command-line program of the Sentinel dVPN apps; every command here starts with it. When an app's shortcut renames it, `DVPN_CLI_NAME` holds the new name and `<cli>` stands for it. Shows: `version --json`.
- **signatures** — the transactions a command signed; an empty list means none. Shows: `agent down --json` (`signatures`).
- **agent** (`connect`, `disconnect`, `status`) — `agent up`, `agent down` and `agent status` do the whole flow with one command each; `connect`, `disconnect` and `status` are the single steps. Shows: `agent status --json`.
- **ok** — `true` when the command worked, `false` when it failed. Shows: every `--json` answer.
- **code** — a short name for what failed; the list is in the failure-code tables of `docs/AGENT-COMMANDS.md`. Shows: any failed `--json` answer.
- **error** — the sentence saying what failed. Shows: any failed `--json` answer.
- **action** — the command that fixes the failure, or null. Run it as printed. Shows: any failed `--json` answer.
- **next** — the command to run next, or the funding step. Run it as printed. Shows: any successful `agent` answer.
- **needsConfirm** (`what`) — exit `2`: nothing was signed; `what` is the sentence of what it would do. Changes: run it again with `--yes`.
- **dry run** — a command without `--yes`: it prints what it would do and changes nothing (exit `2`). Shows: any command that spends money or changes the system.
- **`--yes`** — the flag that lets a command spend money or change the system. Without it nothing happens.
- **`--json`** — the flag that makes a command print one line of JSON.
- **ready** — in `wallet show --json`: `true` when this wallet is set up to connect. Shows: `wallet show --json`.
- **version, tag, file, path** — the installer's answer: the app version it installed, the release tag, the file it used and the program's path. Shows: the last line of `install.sh` or `install.ps1`.
- **SHA256SUMS** — the list of checksums in a release; the installer compares the file to it. Shows: the release page.
