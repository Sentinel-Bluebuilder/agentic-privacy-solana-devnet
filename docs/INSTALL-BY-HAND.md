# Install by hand (no installer script)

The same steps as `install.sh` / `install.ps1`, one release, for `devnet-dvpn` v0.3.0-rc8 (macOS: Apple silicon; Intel Macs: [`OLDER-RELEASES.md`](OLDER-RELEASES.md)).
Moved here from [`AGENTS.md`](../AGENTS.md), section 1. Where each file comes from: [`PROVENANCE.md`](PROVENANCE.md).


The same steps, one release. File names carry the version with a dot, the tag without (tag
`v0.3.0-rc8` holds `…0.3.0-rc.8…`), so take the name from `SHA256SUMS`.

Linux, Debian / Ubuntu x64 (rpm: `\.x86_64\.rpm$` and `sudo dnf install -y`; Arch:
`-x64\.pkg\.tar\.zst$` and `sudo pacman -U --noconfirm`; arm64: `_arm64` / `aarch64`):

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/download/v0.3.0-rc8
curl -fsSLO "$U/SHA256SUMS"
F=$(awk '{print $2}' SHA256SUMS | grep -E '^devnet-dvpn_.*_amd64\.deb$')
curl -fsSLO "$U/$F"
grep " $F\$" SHA256SUMS | sha256sum -c -             # must print: <file name>: OK
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "./$F"
```

Without the update a fresh machine fails with "libsecret-tools … not installable"; without `-y`
the install waits for an answer you cannot give.

macOS, Apple silicon (`arm64`; v0.3.0-rc8 has no Intel build: Intel Macs use [`OLDER-RELEASES.md`](OLDER-RELEASES.md)). An older app in `/Applications` goes first:
`sudo -n rm -rf "/Applications/Devnet dVPN.app"` (`ditto` merges into an existing app).

```sh
U=https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/download/v0.3.0-rc8
A=x64; [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && A=arm64
curl -fsSLO "$U/SHA256SUMS"
F=$(awk '{print $2}' SHA256SUMS | grep -E "^Devnet-dVPN-.*-$A\.dmg\$")
[ -n "$F" ] || { echo "no $A build in this release (Intel Macs: docs/OLDER-RELEASES.md)"; exit 1; }
curl -fsSLO "$U/$F"
grep " $F\$" SHA256SUMS | shasum -a 256 -c -         # must print: <file name>: OK
M=$(hdiutil attach -nobrowse -readonly "./$F" | tail -1 | cut -f3-)
sudo -n ditto "$M/Devnet dVPN.app" "/Applications/Devnet dVPN.app"
hdiutil detach -quiet "$M"
sudo -n xattr -dr com.apple.quarantine "/Applications/Devnet dVPN.app"   # the app is not notarized
export PATH="/Applications/Devnet dVPN.app/Contents/Resources/bin:$PATH"
brew install wireguard-tools wireguard-go openvpn bash   # as your user, never sudo (or: devnet-dvpn daemon repair-drivers --yes)
```

In the Finder instead of a shell: right-click the app > Open once. V2Ray, Xray and Hysteria2 need no `brew` line.

Windows x64, elevated PowerShell:

```powershell
$u = 'https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases/download/v0.3.0-rc8'
curl.exe -fsSLo SHA256SUMS "$u/SHA256SUMS"           # curl.exe, not curl (an alias in older PowerShell)
$l = Select-String -Path .\SHA256SUMS -Pattern 'Devnet-dVPN-Setup-.*-x64\.exe$' | Select-Object -First 1
$h, $f = ($l.Line -split '\s+')[0, 1]
curl.exe -fsSLo $f "$u/$f"
(Get-FileHash ".\$f" -Algorithm SHA256).Hash.ToLower() -eq $h   # must print True
$p = Start-Process -FilePath ".\$f" -ArgumentList '/S' -Wait -PassThru; $p.ExitCode      # 0 = installed
$env:Path += ";$env:ProgramFiles\Devnet dVPN\bin"     # this shell; new shells have it already
```

Use `Start-Process -Wait`: run directly, the installer returns at once. On Windows,
`daemon uninstall` refuses by design: remove the app in Settings > Apps.

Then: `devnet-dvpn version --json` must say network devnet, and (rc6 and later) the `programId` and `mint` in [`AGENTS.md`](../AGENTS.md).
