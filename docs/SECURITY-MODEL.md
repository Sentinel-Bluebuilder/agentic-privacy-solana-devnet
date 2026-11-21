# Security model

What holds your money, what can spend it, what a node sees, and what we run. For `devnet-dvpn` v0.3.0-rc9.
Devnet only: SOL and tDVPN here have no value. Terms: [`GLOSSARY.md`](../GLOSSARY.md).

## What we host: nothing

No account, no API key, no server of ours sits between you and a node. You download a release from
GitHub (checked against its `SHA256SUMS`), your computer talks to Solana devnet RPC and to the node you pay.
This repository holds documents, the installers and an MCP server that runs on your own computer.

**Windows install folder.** Install Windows into Program Files (the default); with /D use only an admin-owned or new folder. A folder that other users can write to lets them change the app's files
while it installs, before the folder is locked.

## Two keys

| Key | Where it lives | What it can sign |
|---|---|---|
| **Wallet key** (the key file) | The file `DVPN_KEYFILE` / `--keyfile` names. Or, without a key file, the OS key store (Windows: DPAPI; macOS: the login Keychain). | Everything the wallet can do: send tDVPN and SOL anywhere (`wallet send`), set up and revoke devices, set the spending limit, withdraw. |
| **Device key** | This computer, made by `daemon init`; used by the VPN service. | Only what the wallet granted it in `device setup`: open, fund, start closing and close deposits with nodes, and open plan subscriptions. It spends tDVPN from your wallet only up to the **spending limit**. It pays its own fees from the **device SOL** (about 0.05 SOL). |

- **Spending limit:** a cap, not a charge. A new install may spend up to 150 tDVPN (an existing limit is kept). `agent up` never raises it by
  itself: with a deposit above it, it refuses (`spending-limit`, nothing paid) until you add `--raise-limit`. Without
  `--max-price` it also refuses a deposit above the default cap (`price-cap`): the larger of the limit / 10 and the
  p75 price of the matching online nodes times `--units`, never above the limit; `defaults` in the `agent up` answer
  says which (`source` `market` or `fixed`). (rc5 raised the limit by itself and said so:
  [`OLDER-RELEASES.md`](OLDER-RELEASES.md).) See it:
  `devnet-dvpn device show --json` (`grant.allowance`, base units). Set it: `devnet-dvpn device setup --allowance N --yes`.
- **Take a device's rights away:** `devnet-dvpn device revoke --device <device> --yes`. Its open deposits stay
  refundable with the wallet key (`devnet-dvpn settle run --device <device> --yes`).
- **Deposits:** money you pay a node goes into a deposit on chain, not to the node. The node can claim only
  what you used (it signs, you check its count; the client refuses a count above its own). The rest comes back
  to your wallet after `agent down` (per GB: after about 2 hours).

## The key file

- `wallet create --keyfile <path>` never writes over an existing file. On Linux and macOS it makes the file
  readable only by you (`0600`) in a folder only you can open (`0700`). On Windows, keep it in your own profile
  folder.
- Whoever has the file owns the wallet. **Never print it, never paste it into a chat or a log, never commit it.**
  Keep one copy somewhere safe: there is no recovery phrase and no reset.
- Use a full path. `DVPN_KEYFILE` lives only in the shell that set it.
- Lost the file: the funds stay with that key. Never `wallet create` in its place (`keyfile-missing`).

## What a node can see

- **Your IP address** (it is the other end of the tunnel) and **the traffic you send through it**: where it goes,
  how much, and when. Anything not encrypted end to end (plain HTTP, plain DNS sent through it) it can read.
  Use HTTPS.
- **Your wallet address and device key** (they pay it), and the deposit.
- It does **not** see your key file, other wallets on the computer, or traffic you route around the tunnel.
- The internet sees the node's address (`exitIp`), not yours.

## Kill switch, DNS, LAN

- **Kill switch** (`daemon set --kill-switch on --yes`): blocks the internet whenever the tunnel is not up, so
  a dropped session does not fall back to your own address. `on` and `persist` are the same setting here.
  **On a remote server, keep it off.** If the VPN connection is lost, the kill switch blocks every new connection to this computer, SSH included. It keeps blocking after a reboot until `devnet-dvpn daemon restore-network` is run locally or from the provider's console.
  Then `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back. From Devnet dVPN 0.3.0-rc.9 (the rc9
  release), turning it on from an SSH or Remote Desktop session is refused (`kill-switch-remote`, exit 5, nothing
  changed) unless you add `--allow-remote-lockout`, and with it on, `agent status` warns (`killSwitchRemoteRisk`).
  In the current v0.3.0-rc9 files (the hashes in `docs/PROVENANCE.md`) the check also reads the login session and the parent processes, so it is refused under sudo and in a root shell opened with sudo -i or su - too. Earlier downloads of v0.3.0-rc9 did not check this: there, keep the kill switch off yourself. A command started from cron or a system service is not part of a remote login, so it is not refused.
  `devnet-dvpn daemon restore-network` lifts the block; `--kill-switch off` stops it coming back.
- **Known gap (every OS, every release so far; rc9 reports it: `killSwitchHolding: false`; only a release of the upstream VPN service, `dvpnd`, can fix it): the block holds only while the VPN service keeps the session.** When a
  node drops, the block holds while the service reconnects. But if the service ends the session itself
  (seen ~22 s after the drop), traffic goes direct, from your own address, with no command run. `agent status`
  then says `server-stopped` with no `blocked`, and `disconnect` says `killSwitchReleased: false`. Until this
  is fixed, treat a `server-stopped` status as "not protected" on every OS: stop sending, and run `agent up --yes` before sending
  anything private. The service is Sentinel's own `dvpnd`: the fix has to come in an upstream `dvpnd` release, not in this app.
- **DNS:** with the kill switch **off**, WireGuard, AmneziaWG, OpenVPN and Hysteria2 can send DNS lookups
  outside the tunnel (a known gap). If DNS privacy matters, keep the kill switch on. V2Ray and Xray resolve
  through the proxy.
- **LAN:** `--allow-lan true` keeps hosts on your local network reachable (and a LAN SSH session alive) while
  the kill switch is on. Off means LAN traffic is blocked too.
- **What goes through the node:** WireGuard, AmneziaWG, OpenVPN and Hysteria2 carry the whole computer. V2Ray
  and Xray carry only what uses the local SOCKS proxy (`socks`) on Linux, the whole computer by default on a
  new Windows or macOS install (`wholeDevice`). Split tunnelling sends chosen addresses or apps around it.

Per OS details and the evidence: [`agent-safety.md`](agent-safety.md). What is proven: [`PROOF.md`](PROOF.md).

## What an agent must not do

- Run a command that spends without reading its preview first: without `--yes` nothing is signed (exit `2`).
- Run `agent up` without `--max-price`.
- Make a new wallet when one existed.
- Print, log or commit the key file.
