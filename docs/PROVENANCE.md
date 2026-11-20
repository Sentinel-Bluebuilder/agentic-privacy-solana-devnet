# Provenance: where every file an agent runs comes from

Every program and script this repository asks an agent to run, with how to check it. You always have a
choice: **download and verify** the published file, or (Path B only) **build it from source** and get
the same bytes. Terms: [`GLOSSARY.md`](../GLOSSARY.md).

How to verify a download: fetch the release's `SHA256SUMS` from the same release page, then
`sha256sum -c SHA256SUMS --ignore-missing` (Linux), `shasum -a 256 <file>` (macOS) or
`Get-FileHash <file> -Algorithm SHA256` (Windows) and compare. The installers (`install.sh`,
`install.ps1`, `direct/install.sh`) do this for you and stop on a mismatch.

## Path A: the Devnet dVPN app (download only)

**The app's source code is not public.** You can check that the file you have is the one released (the
hashes below come from each release's `SHA256SUMS`), but you cannot rebuild it. What you can check after
install is which chain program and token it pays: see "Program and mint" below.

**What is checked against the source.** Before each release, `node tools/check-glossary.mjs --require-src`
runs against the app's source at the release commit and must exit 0. It checks that every failure code the
CLI can print has exactly one row and one anchor in [`docs/CODES.md`](CODES.md), the page each failure's
`docUrl` opens. For `v0.3.0-rc7`: 118 codes, exit 0. Public CI runs the same tool without the source (its
self-tests and the page checks), because the release tags here hold the release files, not the source.

| File | SHA-256 | Release | Source @ commit | Build command | Toolchain | Reproducible? | Last verified |
|---|---|---|---|---|---|---|---|
| `Devnet-dVPN-Setup-0.3.0-rc.8-x64.exe` (Windows x64) | `c9fdecfd502b6ebc15647a34162dd173b638966be1d8e0a85e40976607c5eac0` | [v0.3.0-rc8](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases/tag/v0.3.0-rc8) | not public | not public | Electron (not published) | no | 2026-11-20: hash matches `SHA256SUMS` (rc8), download-back OK |
| `devnet-dvpn_0.3.0-rc.8_amd64.deb` (Linux x86_64) | `f53838de45dab4f8d2ed04fd5dfccd7269f34537f6b8e5ba6aea19a71df5ea68` | [v0.3.0-rc8](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/tag/v0.3.0-rc8) | not public | not public | Electron (not published) | no | 2026-11-20: hash matches the rc8 build's `SHA256SUMS` |
| `devnet-dvpn-0.3.0-rc.8.x86_64.rpm` (Linux x86_64) | `fd76cb4d90fcadc9714d2af4571ff6c4f241f603738a3c819013236bce1c6e14` | [v0.3.0-rc8](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/tag/v0.3.0-rc8) | not public | not public | Electron (not published) | no | 2026-11-20: hash matches the rc8 build's `SHA256SUMS` |
| `Devnet-dVPN-0.3.0-rc.8-x86_64.AppImage` (Linux x86_64) | `36014a992fb26d1249b06c97676c69d92d939d1ef3874c915794ee98bb855d63` | [v0.3.0-rc8](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/tag/v0.3.0-rc8) | not public | not public | Electron (not published) | no | 2026-11-20: hash matches the rc8 build's `SHA256SUMS` |
| `Devnet-dVPN-0.3.0-rc.4-arm64.dmg` (macOS Apple silicon) | `b558b8958848024fe947502998867cb41b352973e66bd223551e7d1249f8003d` | [v0.3.0-rc4](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/tag/v0.3.0-rc4) | not public | not public | Electron (not published) | no | 2026-11-16: release smoke test by the app team; the agent path is not run on macOS ([`PROOF.md`](PROOF.md)) |
| `Devnet-dVPN-0.3.0-rc.4-x64.dmg` (macOS Intel) | `5441414959e639b7be6931334a3540031f3f88be03215de3967f4f709901c977` | [v0.3.0-rc4](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/tag/v0.3.0-rc4) | not public | not public | Electron (not published) | no | as above |
| `Devnet-dVPN-0.3.0-rc.4-arm64-mac.zip` | `5d59d14f585b1e967b87725ca82b64c9ea417ad900e5368d92b32dab43e00644` | [v0.3.0-rc4](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/tag/v0.3.0-rc4) | not public | not public | Electron (not published) | no | as above |
| `Devnet-dVPN-0.3.0-rc.4-x64-mac.zip` | `5e73736763bdf5ae2fec72d033e9ec0c4699ad6bf5d9225f06a341ad5247bb0d` | [v0.3.0-rc4](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases/tag/v0.3.0-rc4) | not public | not public | Electron (not published) | no | as above |

## Path B: Sentinel's own tools (download or build)

Built from Sentinel's public source, [`sentinel-official/sentinel-solana`](https://github.com/sentinel-official/sentinel-solana),
with the devnet ids passed at link time. The release `direct-v1` holds the same bytes as a build from source
with the same Go version: build it yourself and the hashes match.

| File | SHA-256 | Release | Source @ commit | Build command | Toolchain | Reproducible? | Last verified |
|---|---|---|---|---|---|---|---|
| `sentinel-dvpnd-linux-amd64` | `7040b5740f89fa05c419ba74b9bd692310b494dbc48e49a0a91a69636c18faf1` | [direct-v1](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/tag/direct-v1) | [sentinel-solana @ 26de52407c5b722cfecad1772dcbeefd984ef6d0](https://github.com/sentinel-official/sentinel-solana/tree/26de52407c5b722cfecad1772dcbeefd984ef6d0) | `sh direct/build.sh` | Go 1.27.3, `CGO_ENABLED=0`, `-trimpath` | yes: two separate builds, identical hashes | 2026-11-20: full session and refund, fresh Ubuntu 24.04 x86_64 (Azure), `direct/selftest.sh` |
| `sentinel-dvpn-linux-amd64` | `7131e22a37a945063b8e6758ef4702f081cbfd0b580cbef55ddc9d086dbc7095` | [direct-v1](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/tag/direct-v1) | as above | `sh direct/build.sh` | as above | yes | as above |
| `sentinel-dvpnd-linux-arm64` | `62fd806b1c59ea9cffa76bf22cb9a09d20af44f0580e02cd98f4163c7f657f8b` | [direct-v1](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/tag/direct-v1) | as above | `sh direct/build.sh` (builds amd64 and arm64) | as above | yes | 2026-11-20: built twice, same hash; not run on an arm64 machine |
| `sentinel-dvpn-linux-arm64` | `01858093aea92693eed2cb2e82bb767349567e20edad5e28d14a3bf5a67755f7` | [direct-v1](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/releases/tag/direct-v1) | as above | `sh direct/build.sh` (builds amd64 and arm64) | as above | yes | as above |

The exact `git` and `make` lines `build.sh` runs, and the expected `sentinel-dvpn version` output, are in
[`DIRECT.md`](DIRECT.md), "1. Get the tools". The same four lines are in this repository's
[`direct/SHA256SUMS`](../direct/SHA256SUMS), which `direct/install.sh` checks the download against.

## Program and mint (both paths)

| What | Id on devnet | Source | Check |
|---|---|---|---|
| dVPN program (`programId`) | `J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs` | IDL: [`sentinel-programs/idl/dvpn.json` @ 26de5240](https://github.com/sentinel-official/sentinel-solana/blob/26de52407c5b722cfecad1772dcbeefd984ef6d0/sentinel-programs/idl/dvpn.json) (its `address` is a placeholder; the devnet id is set at link time) | Path A: `devnet-dvpn version --json` → `programId` (v0.3.0-rc7; macOS rc4 does not print it). Path B: `sentinel-dvpn version` → `program_id` |
| tDVPN token (`mint`) | `Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa` | the program's settings account holds it ([`GLOSSARY.md`](../GLOSSARY.md), **Config PDA**) | Path A: `version --json` → `mint`. Path B: `sentinel-dvpn version` → `mint` |

Any other `programId` or `mint`: you have the wrong build. Pay nothing.

## Scripts in this repository

`install.sh`, `install.ps1` and `direct/*.sh` are plain text in this repository; read them before you run
them. Their provenance is the commit you cloned or downloaded:

| File | Source @ commit | Check |
|---|---|---|
| [`install.sh`](../install.sh) (Linux, macOS app installer) | [this repository's commits](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/commits/main/install.sh) | `git log -1 --format=%H -- install.sh` names the commit; `sha256sum install.sh` |
| [`install.ps1`](../install.ps1) (Windows app installer) | [commits](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/commits/main/install.ps1) | `git log -1 --format=%H -- install.ps1`; `Get-FileHash install.ps1` |
| [`direct/`](../direct) (`install.sh`, `build.sh`, `fund-request.sh`, `fund-device.sh`, `connect.sh`, `disconnect.sh`, `refund.sh`, `selftest.sh`, `lib.sh`) | [commits](https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/commits/main/direct) | `git log -1 --format=%H -- direct`; `sha256sum direct/*.sh` |

Fetched with `curl … | sh` instead of `git clone`, a script comes from `main` at that moment: to pin it,
replace `main` in the URL with a commit id from the commit list above.
