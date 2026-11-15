# Agent safety — kill switch, split tunnelling, DNS, proxy (per OS)

For an AI agent driving `devnet-dvpn`. Every value below comes from the app's own CLI reference
([Windows](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/blob/main/docs/CLI.md),
[Linux](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/blob/main/docs/CLI.md),
[macOS](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/blob/main/docs/CLI.md),
[Android](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-android/blob/main/docs/CLI.md))
and network-safety docs; every "proven" line is a test run of the app on that OS, named by
release and date. Proof overview: [`PROOF.md`](PROOF.md).

## The one rule: never cut your own line

Every one of these settings is applied by **`daemon set … --yes`**, which needs administrator /
root and **restarts the VPN service**. Change settings while disconnected.

1. **Your control channel is traffic too.** With the kill switch `on` or `persist`, the machine
   drops everything that is not the tunnel, the Solana RPC and the node — including the SSH or
   API connection you are being driven through (seen on Linux and on macOS: with LAN off the
   kill switch drops SSH, by design). If you are remote, keep the kill switch `off`, or `on`
   only with `--allow-lan true` **and** a control channel that comes from the LAN.
2. **In this app the kill switch `on` and `persist` are the same setting.** When a session
   drops, it keeps the internet blocked, including across restarts. It has already locked a
   test machine out for good. Unattended with no one to run rule 3, keep it `off`.
3. **Lost the network → `devnet-dvpn daemon restore-network`.** It ends any session and releases
   the kill switch and the proxy (every OS, every released version). It removes only the app's
   own tunnels, rules and DNS — never a firewall flush or a tunnel of your own. Proven on
   v0.3.0-rc2, every OS (2026-11-13): after a reboot with the kill switch on, "Internet blocked
   by the kill switch", then Restore → direct. It lifts the block for now; it can come back at
   the next dropped session or service restart. `devnet-dvpn daemon set --kill-switch off --yes`
   stops it coming back.
4. **After every `disconnect` / `agent down`, check `devnet-dvpn quality ip`.** If it shows no
   address, the kill switch is still blocking — this happens when the session had already
   dropped before you disconnected. Run rule 3. Also check `devnet-dvpn status --json` shows no
   session. On Android, disconnect releases the block.
5. **`status` can say "Not connected" while the kill switch still blocks.** About a minute after
   a tunnel is lost, `status` changes from "Reconnecting — internet blocked to protect you" to
   "Not connected", with no hint that the block is still on (seen on Windows, v0.3.0-rc2). Never
   take "Not connected" to mean you are back on your own connection: `quality ip` is the test.

## Changing server with the kill switch on

Use `connect <other node> --switch --yes`. Do **not** `disconnect` first: with the kill switch
`on`, `disconnect` releases the block, so the gap between the two sessions goes out on your real IP.

Earlier switch failures all **failed closed — nothing leaked**:
- VPN service 6.13 and older, every OS: the new connect was refused ("not admitted") and the
  internet stayed blocked until Disconnect / Restore network. Fixed in service 6.14.
- macOS, service 6.15: the switch could fail with "Solana endpoint didn't answer"; the block held
  and nothing was paid. Fixed in service 6.16.

Proven on the v0.3.0-rc2 builds (2026-11-13 to 11-15):

| OS (VPN service) | switch under the kill switch |
|---|---|
| Windows (6.14) | PASS, 0 leaks; a watcher saw the direct IP 0 times in 226 samples |
| Android (6.14) | PASS under `persist`: WireGuard→WireGuard in 11 s, WireGuard→V2Ray in 14 s |
| Linux (October 0.1.9 build) | V2Ray→WireGuard, V2Ray→Xray, Xray→V2Ray connect and are direct after; no leak sampling during the switch |
| macOS (6.16) | WireGuard→WireGuard PASS, 68 probes, 0 leaks |

**Known issue (Windows, open):** re-picking the **same** server can fail late and release the
block. Switch only to a **different** server. If a switch fails, the block holds: try another
node, or `daemon restore-network`.

## Values each OS accepts (released packages)

`daemon set` has the same flags on every OS, but each OS accepts only its own DNS backend, and the
released packages differ (the `daemon set` row of each release's CLI reference:
[Windows v0.2.1](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/blob/v0.2.1/docs/CLI.md),
[Linux v0.1.21](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/blob/v0.1.21/docs/CLI.md),
[macOS v0.1.3](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/blob/v0.1.3/docs/CLI.md)).

**Install v0.3.0-rc2 or newer** (see [`AGENTS.md`](../AGENTS.md)). The stable releases cannot
make a key file: their `wallet create` has no `--keyfile`. Columns below = the stable releases'
`daemon set` row.

| flag | Windows v0.2.1 | Linux v0.1.21 | macOS v0.1.3 |
|---|---|---|---|
| `--kill-switch` | `off` `on` `persist` | `off` `on` `persist` | `off` `on` `persist` |
| `--allow-lan` | `true` `false` | `true` `false` | `true` `false` |
| `--dns` | `handshake` `cloudflare` or `ip,ip` | same | same |
| `--dns-mode` | `netsh` `none` | `resolvectl` `resolvconf` `none` | `networksetup` `none` |
| `--whole-device` | `true` `false` | **not offered** on Linux | `true` `false` |
| `--split-mode` | `off` `include` `exclude` | same | same |
| `--split-apps` | `"C:\path\app.exe;…"` or `none` | listed, but **refused** ("Choosing apps does not work on Linux…", also in v0.3.0-rc2) | `"PATH;…"` or `none` |
| `--split-routes` | `IP-or-CIDR,…` or `none` | same | `CIDR,…` or `none` |

Read back with `devnet-dvpn daemon settings`; what split does right now with `devnet-dvpn split status`.

**To undo split tunnelling, clear the list too:**
`devnet-dvpn daemon set --split-mode off --split-routes none --split-apps none --yes`.
`--split-mode off` on its own KEEPS the saved route and app lists, and `--split-routes ""`
answers ok but keeps them too: only `none` clears a list. Then check `daemon settings`
shows no split routes or apps (finding M11, v0.3.0-rc2). On Linux leave out `--split-apps`,
which Linux refuses.

## Windows

| what | do this | proven |
|---|---|---|
| Kill switch `on` | `daemon set --kill-switch on --yes` | all six protocols (October 2026 builds); holds when the protocol process dies and when the VPN service dies |
| Kill switch `persist` | avoid (rule 2) | all six across restart / reboot |
| `--allow-lan` | `--allow-lan true` to keep LAN hosts reachable | all six |
| DNS | keep the kill switch **on** if DNS privacy matters | with the kill switch **off**, WireGuard / AmneziaWG / OpenVPN / Hysteria2 **leak DNS** (known gap); with it on, no leak and the first lookup takes under 3 s. V2Ray / Xray resolve through the proxy |
| Split per app | `split apps` → `daemon set --split-mode exclude --split-apps "C:\…\app.exe" --yes` | all six |
| Split per address | `daemon set --split-mode exclude --split-routes 10.0.0.0/8 --yes` | all six |
| Split + kill switch | possible, proven only on two protocols | WireGuard and Xray; AmneziaWG / OpenVPN / Hysteria2 / V2Ray **not yet run** |
| Whole device (V2Ray / Xray) | `--whole-device true` | all six |
| Proxy (V2Ray / Xray only) | `proxy status` → `proxy on --yes` / `proxy off`; `proxy browser` = one window through the VPN | the system proxy is saved and restored exactly |

Later Windows runs (2026-10-25) passed split by app and by address and the kill switch on /
persist / service killed / reboot / allow-LAN on every protocol; the reboot cases also pass on
v0.3.0-rc2-era code (2026-11-13).

## Linux

| what | do this | proven |
|---|---|---|
| Kill switch `on` | `daemon set --kill-switch on --yes` (nftables, all six; no protocol refused) | 167 checks, 0 failed (October 2026); path lost, protocol killed, service killed → no leak |
| Kill switch `persist` | avoid (rule 2) | 197 checks, 0 failed |
| `--allow-lan` | `--allow-lan true` | LAN in and out with the kill switch on; link-local and the gateway stay on the network card during a full tunnel |
| DNS | `--dns-mode` is chosen by setup (`resolvectl`, or `resolvconf` without systemd-resolved, e.g. EL9) | 49 checks, 0 failed: kill switch off → no lookup leaves on the network card; on → VPN DNS on the tunnel. **Limit:** a name that does not exist is retried with the machine's search domains and goes to the LAN DNS |
| Split per app | **not on Linux**: `--split-apps` is refused. V2Ray / Xray are per-app by nature: only what you send to the SOCKS proxy uses the node | October 0.1.9 build; same refusal in the v0.3.0-rc2 source |
| Split per address | `daemon set --split-mode include\|exclude --split-routes <CIDR,…> --yes`, kill switch **off** | WireGuard / AmneziaWG / OpenVPN / Hysteria2, October 0.1.9 build (not yet run on v0.3.0-rc2): include → the chosen range exits at the node, the rest direct; exclude → the reverse; direct again after disconnect. V2Ray with split set: the proxy still exits at the node |
| Split + kill switch | with the kill switch on, a split setting is not applied: the full tunnel is kept and `split status` says why | 61 checks, 0 failed |
| Whole device (V2Ray / Xray) | **not offered**: they are a proxy only on Linux | — |
| Proxy (V2Ray / Xray only) | `proxy status` → `proxy on --yes` (GNOME / KDE) / `proxy off`; `proxy browser` | GNOME and KDE, settings restored byte for byte |

**Best split on Linux:** by address on WireGuard / AmneziaWG / OpenVPN / Hysteria2 (kill switch
off), or a V2Ray / Xray node with only the traffic you want protected sent to the SOCKS
endpoint from `proxy status`.

## macOS

| what | do this | proven |
|---|---|---|
| Kill switch `on` | `daemon set --kill-switch on --yes` (pf anchor, both directions; no protocol refused) | the block holds when the path to the node is lost (never the direct IP); v0.3.0-rc2 (service 6.16): 3 reboots with the kill switch on, 0 leaks in 30 checks |
| Kill switch `persist` | avoid (rule 2) | holds; uninstalling while it is armed leaves the internet direct, reinstalling arms nothing |
| `--allow-lan` | `--allow-lan true` (LAN passes both ways only when true) | PASS (2026-10-27): with LAN off a new SSH from the LAN fails, with LAN on it works. Older test machines failed this check; the current one passes |
| DNS | `--dns-mode networksetup` (VPN DNS on every network service) or `none` | 61 checks, 0 failed |
| Split per address | `daemon set --split-mode include\|exclude --split-routes <CIDR,…> --yes` | all six protocols, include and exclude, nothing left behind after |
| Split per app | `split apps` → `daemon set --split-apps "<path>;…" --yes` | the setting is applied; per-app traffic not yet measured separately |
| Whole device (V2Ray / Xray) | `--whole-device true` | 55 checks, 0 failed |
| Proxy (V2Ray / Xray only) | `proxy status` → `proxy on --yes` (every enabled network service) / `proxy off`; `proxy browser` | saved and restored exactly, also after the service and the protocol are killed |

## Android

The Android app has the same commands inside it, plus Android-only `split show`, `split set` and
`split routes`. A released Android build cannot be driven from outside the app, so an agent does
not run on Android and it is not covered here.
