# Troubleshooting: symptom → cause → command

For `devnet-dvpn` v0.3.0-rc6, macOS v0.3.0-rc4 ([`AGENTS.md`](../AGENTS.md); older releases: [`OLDER-RELEASES.md`](OLDER-RELEASES.md)). Every `code` here is a real one; its full row
(meaning, whether money moved, next, the other way out) is in [`CODES.md`](CODES.md). Terms:
[`GLOSSARY.md`](../GLOSSARY.md).

First, always:

```sh
devnet-dvpn agent status --json      # read "next" (and "alsoNext"); run it as printed
```

A failure line `{"ok":false,…}` carries `action`: run it. `money` says whether money moved. Use this page when
`action` is null, or when the symptom has no code.

| Symptom | Cause | Command |
|---|---|---|
| `agent up` connected but `exitIp` is `null` | The address check did not finish within 8 s. The tunnel may be fine. | `devnet-dvpn quality ip --json`: `direct.ip` (whole-device protocols) or `viaSocks.ip` (V2Ray / Xray on Linux) must differ from your own address. |
| `exitIp` (or `quality ip`) shows your **own** address while `connected` is true | The node stopped serving; for a few seconds `agent status` can still say `connected`. Then it answers `"code":"server-stopped"`. The deposit is safe. | `devnet-dvpn agent up --yes` (another node; the dead one is skipped 10 min), or `devnet-dvpn agent down --yes` (closes the deposit). With `"blocked": true` as well: `devnet-dvpn daemon restore-network` first (`next`), then one of those two (`alsoNext`). |
| `quality ip` shows **no** address after `agent down`, or `agent status` says `"blocked": true` | The kill switch still holds the block (the session had dropped before you disconnected). | `devnet-dvpn daemon restore-network` (now), then `devnet-dvpn daemon set --kill-switch off --yes` (so it does not come back). Or `devnet-dvpn agent up --yes` to reconnect with protection. |
| `"code":"kill-switch-held"` on `agent up` | The block lets through only the last node, so this connect cannot lift it. Nothing was paid. | `devnet-dvpn daemon restore-network, then devnet-dvpn agent up --yes` |
| SSH session lost after a connect or after turning the kill switch on | The kill switch blocks everything that is not the tunnel; over a LAN, `--allow-lan` was off. | From a second way in (cloud console, serial console, a person at the machine): `devnet-dvpn daemon restore-network`, then `devnet-dvpn daemon set --kill-switch off --yes`. Before next time: `devnet-dvpn daemon set --allow-lan true --yes` (LAN), and never the kill switch over internet SSH without another way in ([`agent-safety.md`](agent-safety.md)). |
| `"code":"spending-limit"` (exit `4`) | This computer's spending limit is below this deposit, and `--raise-limit` was not given. Nothing was paid. | Run the `action`: your same `agent up` line with `--raise-limit --yes`. Or set your own limit: `devnet-dvpn device setup --allowance N --yes` (N in tDVPN, above the deposit). Or a smaller deposit: fewer `--units`. |
| `"code":"price-cap"` (exit `4`) | No `--max-price` was given and the deposit is above the default cap (the spending limit / 10: 5 tDVPN by default). Nothing was paid. | Run the `action` (it names the node's price with `--max-price`), or ask for less: fewer `--units`, or `--max-price 0.01` for a cheaper node. |
| `agent up` answered `limitRaised` / `limitNote` and you did not want it | You ran it with `--raise-limit`, so it raised the limit for this deposit. A cap, not a charge. | Lower it: the command in `limitNote` (`devnet-dvpn device setup --allowance <N> --yes`). |
| `"code":"not-funded"` | Less than 0.02 SOL (before the first connect) or less tDVPN than the deposit. Nothing was paid. | Fund the address in `action`, then `devnet-dvpn agent up --yes`. Or `devnet-dvpn agent up --units <fewer> --yes`. |
| `"code":"not-enough-tdvpn"` | The node `agent up` picked costs more than you hold. Nothing was paid. | `devnet-dvpn agent up --max-price 0.01 --basis per_gb --yes`, or fund more tDVPN. |
| Funding: the operator sees a faucet limit message | Each faucet allows **2 requests every 8 hours**, shared by everyone on the network; the Sentinel faucet also has a daily total. | tDVPN: anyone holding some runs `devnet-dvpn wallet send --to <ADDRESS> --tdvpn 100 --yes`, or wait the time the faucet names. SOL: `solana airdrop 1 <ADDRESS> --url devnet`, or wait; about 0.06 SOL is enough. Done when `agent status --json` shows `sol` above 0.06 and `tdvpn` at least the deposit ([`AGENTS.md`](../AGENTS.md) section 3). |
| A deposit stays in `deposits` with `status` `closing` | A per-GB deposit takes about 2 hours to close (stage 1 of 2). Normal. | After `readyAt` (Unix seconds): `devnet-dvpn settle run --yes`, then `devnet-dvpn settle withdraw --yes`. `next` of `agent status` names the time. |
| A deposit stays `open` with no session | It was never closed (a failed connect after paying, `node-refused`, or a dropped session). | `devnet-dvpn agent down --yes`. Never `agent up` first: it would open a second deposit. |
| `agent down` answers `notClosed` / `warning` | The deposit was opened by another device of this wallet (a replaced computer); this computer cannot close it. | `devnet-dvpn device revoke --device <device> --yes` (if not revoked yet), then `devnet-dvpn settle run --device <device> --yes` |
| `agent down` answers `"code":"busy"`, `settle-failed` or `daemon-gone` | The disconnect is done; the refund run did not finish. Nothing was lost. | `devnet-dvpn settle list`, then `devnet-dvpn settle run --yes` |
| `settle withdraw` answers `withdraw-failed` | The withdraw transaction failed; the balance (`held`) is still there. | `devnet-dvpn settle withdraw --yes` again. "Nothing to withdraw" (exit 0) is not a failure. |
| `agent status` says `"service": false`, or `"code":"daemon-unavailable"` / `service-down` | The VPN service is not running or not answering. | `devnet-dvpn daemon doctor --json` (no check may say `"level": "fail"`); if it is not installed: `devnet-dvpn daemon install --yes` (administrator / root). |
| `"code":"service-not-ready"` | The service is starting or stopping. | The same command again in a moment. |
| `"code":"daemon-missing"` | The VPN service is not installed. Nothing was paid. | Linux / macOS: `devnet-dvpn daemon install --yes` as root or with passwordless `sudo`. Windows: see the next row. |
| Windows: a UAC prompt appears and nothing happens, or `"code":"daemon-relogin"` | The shell is not elevated (an agent cannot answer UAC), or the service pipe does not accept this account yet. | Run `devnet-dvpn daemon install --yes` once from an **elevated** PowerShell or an administrator SSH login. After `"relogin": true`, a non-elevated shell needs a new sign-in or SSH session. |
| macOS over SSH: "The login Keychain is locked in this session" | Without a key file the wallet is kept in the login Keychain, which stays locked in an SSH session. | Use a key file: `export DVPN_KEYFILE="$PWD/agent-key.json"` (or `--keyfile <path>`); a key-file wallet never touches the Keychain. Or unlock it: `security unlock-keychain` (needs the password). |
| `"code":"keyfile-missing"` | The file `DVPN_KEYFILE` / `--keyfile` names is gone. The funds stay with that key. | Restore the file from your backup and run the command again. Never `wallet create`: a new wallet holds none of the funds. |
| `"code":"no-wallet"` but you had a wallet | `DVPN_KEYFILE` is not set in this shell (it lives only in the shell that set it). | `export DVPN_KEYFILE=<full path>` (PowerShell: `$env:DVPN_KEYFILE = '<full path>'`), or `devnet-dvpn wallet import <file>`. Never `wallet create`. |
| `"code":"wallet-switch-needed"` | This computer is set up for another wallet. Nothing was paid. | Load that wallet's key file, or `devnet-dvpn device switch --yes`. |
| `"code":"clock-skew"` | This computer's clock is off (the error says by how much). Nothing was paid. | Set the clock right, then `devnet-dvpn agent up --yes`. |
| `"code":"node-refused"` | The node refused after the deposit opened. It is skipped next time. | `devnet-dvpn agent down --yes` (closes that deposit), not `agent up`. |
| Anything else | | `devnet-dvpn daemon doctor --json`, `devnet-dvpn logs --lines 80`, and the row for the `code` in [`CODES.md`](CODES.md). |
