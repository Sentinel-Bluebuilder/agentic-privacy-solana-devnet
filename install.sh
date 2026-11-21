#!/bin/sh
# ─── install.sh: install devnet-dvpn (Sentinel dVPN on Solana devnet) on Linux or macOS ───
#
#   curl -fsSL https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh | sh
#
# or, to read it first:
#
#   curl -fsSLO https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.sh
#   sh install.sh
#
# What it does: finds your OS, CPU and package type (deb / rpm / pacman; macOS dmg), takes the
# newest release (pre-releases included) that has that file and is v0.3 or newer (the guide pins v0.3.0-rc9), downloads
# the file and the release's SHA256SUMS, checks the file, installs it with no questions, and runs
# `devnet-dvpn version --json`. Needs root or passwordless sudo (`sudo -n true` must work).
#
# Options, as environment variables:
#   DVPN_VERSION=v0.3.0-rc9   use this release tag instead of the newest (AGENTS.md pins it)
#
# Output: progress and errors on stderr; on success one JSON line on stdout:
#   {"ok":true,"tag":…,"file":…,"version":{…},"path":"export PATH=…"|null,"next":…}
# and on failure {"ok":false,"error":"<the sentence>"}.
# Exit codes: 0 installed · 1 failed (the reason is printed as one sentence).
# Nothing runs until the whole script has been read (everything is inside main, called last).

set -eu

LINUX_REPO='Sentinel-Bluebuilder/sentinel-solana-dvpn-linux'
MAC_REPO='Sentinel-Bluebuilder/sentinel-solana-dvpn-macos'
GUIDE='https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/blob/main/AGENTS.md'
MAC_BIN='/Applications/Devnet dVPN.app/Contents/Resources/bin'

say() { printf 'install.sh: %s\n' "$*" >&2; }
# Messages never contain a double quote or a backslash, so they go into the JSON line as they are: the only
# user text in them is DVPN_VERSION, which is refused below unless it is tag characters only.
# Inside main, fd 3 is the real stdout and fd 1 points at stderr (see the exec there).
fail() { printf 'install.sh: %s\n' "$*" >&2; printf '{"ok":false,"error":"%s"}\n' "$*" >&3; exit 1; }

# ─── a tag is usable when it is v0.3 or newer (older releases cannot make a key file) ───
tag_ok() {
  printf '%s\n' "$1" | sed 's/^v//' | awk -F'[.-]' '{ exit !(($1 + 0) > 0 || ($2 + 0) >= 3) }'
}

# ─── pick the file name matching $2 (an extended regex) out of a SHA256SUMS file $1 ───
file_from_sums() {
  awk '{ f = $2; sub(/^\*/, "", f); print f }' "$1" | grep -E "$2" | head -n 1
}

main() {
  # The one JSON line goes to fd 3 (the real stdout). Everything else any command prints, the
  # package managers included, goes to stderr, so stdout is exactly one line.
  exec 3>&1 1>&2
  command -v curl >/dev/null 2>&1 || fail 'curl is not installed; install curl and run this again.'

  # ─── root or passwordless sudo ───
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=''
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO='sudo -n'
  else
    fail 'installing needs root or passwordless sudo (sudo -n true failed); run this as root, or ask your operator to install the app.'
  fi

  # ─── OS, CPU, package type → repo and file pattern ───
  os=$(uname -s)
  cpu=$(uname -m)
  case "$os" in
    Linux)
      REPO=$LINUX_REPO
      case "$cpu" in
        x86_64|amd64) deb=amd64; rpm=x86_64; pac=x64 ;;
        aarch64|arm64) deb=arm64; rpm=aarch64; pac=aarch64 ;;
        *) fail "this CPU ($cpu) has no Linux package; only x86_64 and aarch64 are built." ;;
      esac
      if command -v apt-get >/dev/null 2>&1; then
        KIND=deb; PAT="^devnet-dvpn_.*_${deb}\\.deb\$"
      elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        KIND=rpm; PAT="^devnet-dvpn-.*\\.${rpm}\\.rpm\$"
      elif command -v pacman >/dev/null 2>&1; then
        KIND=pacman; PAT="^devnet-dvpn-.*-${pac}\\.pkg\\.tar\\.zst\$"
      else
        fail 'no apt-get, dnf, yum or pacman found; download the AppImage from the releases page instead.'
      fi
      SUM='sha256sum -c -'
      ;;
    Darwin)
      REPO=$MAC_REPO
      KIND=dmg
      # Under Rosetta uname -m says x86_64 on Apple silicon; ask the hardware.
      if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then a=arm64; else a=x64; fi
      PAT="^Devnet-dVPN-.*-${a}\\.dmg\$"
      SUM='shasum -a 256 -c -'
      ;;
    *) fail "this OS ($os) is not covered by install.sh; on Windows use install.ps1." ;;
  esac

  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t dvpn)
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 1' INT TERM

  # ─── which release ───
  if [ -n "${DVPN_VERSION:-}" ]; then
    TAG=$DVPN_VERSION
    # tag characters only: the tag goes into a URL and the JSON line (a quote would break it); not echoed back
    case "$TAG" in *[!A-Za-z0-9._+-]*) fail "DVPN_VERSION is not a release tag (letters, digits and . _ + - only), e.g. DVPN_VERSION=v0.3.0-rc9." ;; esac
    case "$TAG" in v*) ;; *) TAG="v$TAG" ;; esac
    tag_ok "$TAG" || fail "release $TAG is older than v0.3 and cannot make a key file; use DVPN_VERSION=v0.3.0-rc9."
    BASE="https://github.com/$REPO/releases/download/$TAG"
    curl -fsSL -o "$tmp/SHA256SUMS" "$BASE/SHA256SUMS" || fail "release $TAG has no SHA256SUMS (is the tag right? tags look like v0.3.0-rc9)."
    FILE=$(file_from_sums "$tmp/SHA256SUMS" "$PAT") || true
    [ -n "$FILE" ] || fail "release $TAG has no $KIND package for this CPU."
  else
    curl -fsSL -o "$tmp/releases.json" "https://api.github.com/repos/$REPO/releases?per_page=30" \
      || fail 'could not read the release list from GitHub (rate limit or no network); set DVPN_VERSION=<tag> and run again.'
    # The API lists releases newest-CREATED first, and the first usable one wins: a release made
    # later on an older line would be picked over a newer version. Pin DVPN_VERSION to rule that out.
    urls=$(grep -o '"browser_download_url": *"[^"]*"' "$tmp/releases.json" | sed 's/.*"\(https[^"]*\)"$/\1/') || true
    pick=$(printf '%s\n' "$urls" | while IFS= read -r u; do
      f=${u##*/}
      t=${u%/*}; t=${t##*/}
      if printf '%s\n' "$f" | grep -qE "$PAT" && tag_ok "$t"; then printf '%s\n' "$u"; break; fi
    done)
    [ -n "$pick" ] || fail "no release v0.3 or newer has a $KIND package for this CPU."
    FILE=${pick##*/}
    BASE=${pick%/*}
    TAG=${BASE##*/}
    curl -fsSL -o "$tmp/SHA256SUMS" "$BASE/SHA256SUMS" || fail "release $TAG has no SHA256SUMS; not installing an unchecked file."
  fi

  say "release $TAG, file $FILE"
  curl -fsSL -o "$tmp/$FILE" "$BASE/$FILE" || fail "download of $FILE failed."

  # ─── check the file against SHA256SUMS ───
  line=$(awk -v f="$FILE" '{ g = $2; sub(/^\*/, "", g); if (g == f) { print $1 "  " f; exit } }' "$tmp/SHA256SUMS")
  [ -n "$line" ] || fail "SHA256SUMS of $TAG has no line for $FILE; not installing an unchecked file."
  (cd "$tmp" && printf '%s\n' "$line" | $SUM >/dev/null) || fail "$FILE does not match SHA256SUMS; not installing it."
  say 'checksum OK'

  # ─── install, no questions ───
  case "$KIND" in
    deb)
      # Without the update a fresh machine fails with "libsecret-tools … not installable".
      $SUDO apt-get update -qq || fail 'apt-get update failed.'
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/$FILE" || fail "apt-get install of $FILE failed."
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y "$tmp/$FILE" || fail "dnf install of $FILE failed."
      else
        $SUDO yum install -y "$tmp/$FILE" || fail "yum install of $FILE failed."
      fi
      ;;
    pacman)
      $SUDO pacman -U --noconfirm "$tmp/$FILE" || fail "pacman -U of $FILE failed."
      ;;
    dmg)
      mnt=$(hdiutil attach -nobrowse -readonly "$tmp/$FILE" | tail -n 1 | cut -f3-) || fail "could not open $FILE."
      [ -d "$mnt/Devnet dVPN.app" ] || { hdiutil detach -quiet "$mnt" || true; fail "$FILE has no Devnet dVPN.app inside."; }
      if [ -d '/Applications/Devnet dVPN.app' ]; then
        say 'replacing the installed /Applications/Devnet dVPN.app'
        $SUDO rm -rf '/Applications/Devnet dVPN.app' || fail 'could not remove the old app.'
      fi
      $SUDO ditto "$mnt/Devnet dVPN.app" '/Applications/Devnet dVPN.app' || { hdiutil detach -quiet "$mnt" || true; fail 'copying the app to /Applications failed.'; }
      hdiutil detach -quiet "$mnt" || say 'could not detach the disk image (harmless).'
      PATH="$MAC_BIN:$PATH"
      ;;
  esac

  command -v devnet-dvpn >/dev/null 2>&1 || fail 'installed, but devnet-dvpn is not on PATH.'
  ver=$(devnet-dvpn version --json) || fail 'installed, but devnet-dvpn version failed.'
  printf '%s\n' "$ver" >&2
  # One line, whatever the CLI printed (JSON allows newlines between tokens, never inside strings).
  ver=$(printf '%s' "$ver" | tr -d '\n\r')
  case "$ver" in '{'*'}') ;; *) ver=null ;; esac

  # ─── what next: human lines on stderr, one JSON line on stdout ───
  pathline=null
  if [ "$KIND" = dmg ]; then
    say 'macOS: a script cannot change the PATH of the shell that started it. Run this in your shell first:'
    printf '  export PATH="%s:$PATH"\n' "$MAC_BIN" >&2
    pathline="\"export PATH=\\\"$MAC_BIN:\$PATH\\\"\""
  fi
  rc=0
  devnet-dvpn agent status --json >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 3 ]; then
    next="this release has no agent commands: follow section 2 of $GUIDE"
  else
    next='devnet-dvpn agent status --json'
  fi
  say "next: $next"
  printf '{"ok":true,"tag":"%s","file":"%s","version":%s,"path":%s,"next":"%s"}\n' \
    "$TAG" "$FILE" "$ver" "$pathline" "$next" >&3
}

main "$@"
