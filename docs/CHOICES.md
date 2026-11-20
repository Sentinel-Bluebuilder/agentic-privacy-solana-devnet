# Choices: protocol, country, pricing, split tunnelling, kill switch

For `devnet-dvpn` v0.3.0-rc8 (Windows, Linux, macOS Apple silicon). Moved here from [`AGENTS.md`](../AGENTS.md) to keep that page short; the steps there do not need any of these.

**Protocol:** WireGuard, AmneziaWG, OpenVPN, V2Ray, Xray, Hysteria2; a node serves one.
`agent up --protocol <name>`, or `nodes list --online --protocol <name> --json`.
`daemon drivers` lists the tools this machine has; `daemon repair-drivers --yes` adds the missing.

**Location:** `agent up --country DE` (the country the node reports).

**Pricing:**

| | how | notes |
|---|---|---|
| per GB | `agent up --basis per_gb --units <GB>` | unused deposit comes back |
| per hour | `agent up --basis per_hour --units <hours>` | `agent down` straight after, so it stops billing |
| plan | `plans list` → `plans subscribe <plan> --yes` → `agent up --plan <subscription>` | one price up front, no refund. An empty `--plan` value is refused (exit `3`) |

`daemon set` (below) needs administrator / root like `daemon install` and restarts the VPN
service: change settings **before** you connect.

**Split tunnelling:** `split status`;
`daemon set --split-mode exclude --split-routes 10.0.0.0/8 --yes`. To undo it, set both:
`daemon set --split-mode off --split-routes none --yes` (otherwise the routes stay; Windows /
macOS, if you set apps: add `--split-apps none`).

**Kill switch:** block the internet whenever the tunnel is not up.

```sh
devnet-dvpn daemon set --allow-lan true --yes        # first, if you reach this machine over its LAN
devnet-dvpn daemon set --kill-switch on --yes        # off | on | persist
```

In these apps the kill switch `on` and `persist` are the same setting. After `disconnect` / `agent
down`, check `devnet-dvpn quality ip` (`status` can say not connected while it blocks). If it shows no address, the kill switch is still blocking —
this happens when the session had already dropped before you disconnected. `devnet-dvpn daemon
restore-network` lifts the block for now; it can come back at the next dropped session or service
restart. `devnet-dvpn daemon set --kill-switch off --yes` stops it coming back.

(`disconnect` with no session may still print "keeps the internet blocked until you reconnect":
reconnecting does not lift it for good; use the two commands above.)

To change node with the kill switch on, do not disconnect first: `agent up --node <other>
--yes` (or `connect <other node> --switch --yes`) switches in one step and the block holds.

Per-OS details: [`docs/agent-safety.md`](agent-safety.md).

