#!/bin/sh
# ─── direct/install.sh: install Sentinel's own client tools for Solana devnet (Linux, no app) ───
#
#   sudo sh direct/install.sh       # from your normal user; creates your owner key if you have none
#
# What it does, in order (each command is printed before it runs; safe to run again):
#   1. checks it runs as root and finds the user who called sudo
#   2. apt-get installs wireguard-tools, jq, curl
#   3. puts sentinel-dvpnd + sentinel-dvpn in /usr/local/bin: from the release direct-v1, checked
#      against SHA256SUMS; or BUILD=1 builds them from the public source with direct/build.sh
#   4. sentinel-dvpnd init --instance c1 (client role, public devnet RPC). This creates the DEVICE
#      key: a second key that signs and pays fees for the daemon. Your owner key never enters the daemon
#   5. sets kill_switch = 'off' (see "Remote box" in docs/DIRECT.md: the upstream default 'on'
#      drops all outbound traffic except the tunnel, which cuts SSH). KILL_SWITCH=on keeps it on
#   6. registers and starts the systemd service sentinel-dvpnd@c1 (FOREGROUND=1: skip, run it yourself)
#   7. adds the calling user to the sentinel-dvpn group, so the CLI can reach the daemon socket
#
# Env: OWNER=<base58> (default: the calling user's "owner" key), BUILD=1, KILL_SWITCH=on, FOREGROUND=1
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
STEP=install
parse_args "$@"

RELEASE_URL=${RELEASE_URL:-https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/download/direct-v1}

[ "$(id -u)" = 0 ] || fail "$E_USAGE" needs-root "run as root" "sudo sh direct/install.sh"
CALLER=${SUDO_USER:-}

# ─── 1. packages ───
if ! command -v wg >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  run apt-get update -qq
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard-tools jq curl
fi

# ─── 2. binaries ───
case $(uname -m) in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) fail "$E_OTHER" unsupported "unsupported CPU $(uname -m)" "build from source: sh direct/build.sh" ;;
esac
if [ "${BUILD:-0}" = 1 ]; then
  [ -n "$CALLER" ] || fail "$E_USAGE" usage "BUILD=1 needs sudo from a normal user" "sudo BUILD=1 sh direct/install.sh"
  run sudo -u "$CALLER" env PATH="$PATH" sh "$HERE/build.sh"
  run install -m 0755 ./sentinel-solana/sentinel-dvpnd/bin/sentinel-dvpnd ./sentinel-solana/sentinel-dvpn/bin/sentinel-dvpn /usr/local/bin/
else
  TMP=$(mktemp -d)
  run curl -fsSL -o "$TMP/SHA256SUMS" "$RELEASE_URL/SHA256SUMS"
  for tool in sentinel-dvpnd sentinel-dvpn; do
    run curl -fsSL -o "$TMP/$tool-linux-$ARCH" "$RELEASE_URL/$tool-linux-$ARCH"
  done
  (cd "$TMP" && run sha256sum --ignore-missing -c SHA256SUMS) || fail "$E_SAFETY" checksum-mismatch "SHA-256 mismatch on the downloaded binaries; not installed" "do not run them; build from source: sudo BUILD=1 sh direct/install.sh"
  for tool in sentinel-dvpnd sentinel-dvpn; do
    run install -m 0755 "$TMP/$tool-linux-$ARCH" "/usr/local/bin/$tool"
  done
  rm -rf "$TMP"
fi
run sentinel-dvpn version

# ─── 3. owner address ───
OWNER=${OWNER:-}
if [ -z "$OWNER" ] && [ -n "$CALLER" ]; then
  OWNER=$(sudo -u "$CALLER" sentinel-dvpn key show owner 2>/dev/null | jq -r .public_key) || OWNER=
  if [ -z "$OWNER" ]; then
    # first run: create the owner (wallet) key for the calling user, a plain file under ~/.sentinel-dvpn/keys
    OWNER=$(run sudo -u "$CALLER" sentinel-dvpn key new owner --unencrypted | jq -r .public_key)
    echo "created owner key ~$CALLER/.sentinel-dvpn/keys/owner.json: never print it, never commit it; back it up:" >&2
    echo "  cp ~/.sentinel-dvpn/keys/owner.json /some/safe/place/owner.json && chmod 600 /some/safe/place/owner.json" >&2
  fi
fi
[ -n "$OWNER" ] || fail "$E_OPERATOR" no-wallet "no owner key: run 'sudo sh direct/install.sh' from your normal user (not a root shell), or pass OWNER=<address>" "sudo sh direct/install.sh"

# ─── 4. daemon instance ───
CFG=/var/lib/sentinel-dvpn/$INSTANCE/config.toml
if [ ! -f "$CFG" ]; then
  run sentinel-dvpnd init --instance "$INSTANCE" --owner "$OWNER" --plain-key
else
  echo "instance $INSTANCE already exists ($CFG); keeping it" >&2
fi

# ─── 5. kill switch ───
if [ "${KILL_SWITCH:-off}" = on ]; then
  run sed -i "s/^kill_switch = .*/kill_switch = 'on'/" "$CFG"
else
  run sed -i "s/^kill_switch = .*/kill_switch = 'off'/" "$CFG"
fi
grep '^kill_switch' "$CFG" >&2

# ─── 6. service ───
if [ "${FOREGROUND:-0}" != 1 ]; then
  if [ ! -f "/etc/systemd/system/sentinel-dvpnd@.service" ] && ! systemctl cat "sentinel-dvpnd@$INSTANCE" >/dev/null 2>&1; then
    run sentinel-dvpnd service install --instance "$INSTANCE"
  fi
  # Not started here: the daemon refuses to start until the grant exists ("preflight failed: grant").
  # connect.sh opens the grant, then starts it. Restart only if it already runs (config change).
  if systemctl is-active --quiet "sentinel-dvpnd@$INSTANCE.service"; then
    run sentinel-dvpnd service restart --instance "$INSTANCE"
  else
    run systemctl stop "sentinel-dvpnd@$INSTANCE.socket" "sentinel-dvpnd@$INSTANCE.service" 2>/dev/null || true
    run systemctl reset-failed "sentinel-dvpnd@$INSTANCE.service" 2>/dev/null || true
  fi
fi

# ─── 7. socket access ───
[ -n "$CALLER" ] && run usermod -aG sentinel-dvpn "$CALLER"

DEVICE=$(sentinel-dvpnd key show "$DEVICE_KEY_NAME" --instance "$INSTANCE" | jq -r .public_key)
if [ "${FOREGROUND:-0}" = 1 ]; then NEXT="sh direct/fund-request.sh; after connect.sh opened the grant, run: sudo sentinel-dvpnd run --instance $INSTANCE (in another shell)"; else NEXT="sh direct/fund-request.sh (the daemon starts in connect.sh, once the grant exists; no new login needed: the scripts use sudo for the daemon socket until a NEW ssh session, or newgrp sentinel-dvpn, gives you the group)"; fi
summary true install "$NEXT" "\"owner\":\"$OWNER\",\"device\":\"$DEVICE\",\"instance\":\"$INSTANCE\""
