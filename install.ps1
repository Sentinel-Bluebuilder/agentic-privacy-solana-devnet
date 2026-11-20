# --- install.ps1: install devnet-dvpn (Sentinel dVPN on Solana devnet) on Windows ---
#
# In an ELEVATED PowerShell (an elevated terminal, or SSH as an administrator):
#
#   irm https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1 | iex
#
# or, to read it first:
#
#   curl.exe -fsSLO https://raw.githubusercontent.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/main/install.ps1
#   Set-ExecutionPolicy -Scope Process Bypass -Force; . .\install.ps1
#
# Both forms run in your own shell, so the PATH it sets stays set there.
#
# What it does: takes the newest release (pre-releases included) that has the x64 installer and
# is v0.3 or newer (the guide pins v0.3.0-rc6), downloads it and the release's SHA256SUMS, checks it, runs the silent
# install and waits for it, adds devnet-dvpn to this shell's PATH and runs `devnet-dvpn version --json`.
#
# Options: $env:DVPN_VERSION = 'v0.3.0-rc6'   use this release tag instead of the newest (AGENTS.md pins it)
#
# Output: progress on the host; one JSON line as output, on success
#   {"ok":true,"tag":...,"file":...,"version":{...},"path":"<bin folder added to PATH>","next":...}
# and on failure {"ok":false,"error":"<the sentence>"}, then it stops with an error (so a script
# calling it sees it failed); it never closes your shell. Windows PowerShell 5.1 and 7. ASCII only.

function Install-DevnetDvpn {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'   # 5.1 downloads are very slow with the progress bar
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  $repo = 'Sentinel-Bluebuilder/sentinel-solana-dvpn-windows'
  $guide = 'https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/blob/main/AGENTS.md'
  $pattern = '^Devnet-dVPN-Setup-.*-x64\.exe$'

  function Stop-Install([string]$why) {
    Write-Output ([ordered]@{ ok = $false; error = $why } | ConvertTo-Json -Compress)
    throw "install.ps1: $why"
  }
  function Test-Tag([string]$tag) {
    # v0.3 or newer: older releases cannot make a key file.
    $p = ($tag -replace '^v', '') -split '[.-]'
    if ($p.Count -lt 2) { return $false }
    $maj = 0; $min = 0
    if (-not [int]::TryParse($p[0], [ref]$maj) -or -not [int]::TryParse($p[1], [ref]$min)) { return $false }
    return ($maj -gt 0 -or $min -ge 3)
  }

  # --- elevated? ---
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Install 'this shell is not elevated; open an elevated PowerShell (or SSH in as an administrator) and run this again.'
  }
  $arch = $env:PROCESSOR_ARCHITEW6432
  if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
  if ($arch -ne 'AMD64') { Stop-Install "this CPU ($arch) has no installer; only x64 is built (v0.3.0-rc6 included)." }

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvpn-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    # --- which release ---
    if ($env:DVPN_VERSION) {
      $tag = $env:DVPN_VERSION
      if ($tag -notmatch '^v') { $tag = "v$tag" }
      if (-not (Test-Tag $tag)) { Stop-Install "release $tag is older than v0.3 and cannot make a key file; use `$env:DVPN_VERSION = 'v0.3.0-rc6'." }
      $base = "https://github.com/$repo/releases/download/$tag"
      try { Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile "$tmp\SHA256SUMS" }
      catch { Stop-Install "release $tag has no SHA256SUMS (is the tag right? tags look like v0.3.0-rc6): $($_.Exception.Message)" }
      $file = Get-Content "$tmp\SHA256SUMS" | ForEach-Object { (($_ -split '\s+')[1]) -replace '^\*', '' } |
        Where-Object { $_ -match $pattern } | Select-Object -First 1
      if (-not $file) { Stop-Install "release $tag has no x64 installer." }
    } else {
      try { $releases = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$repo/releases?per_page=30" }
      catch { Stop-Install "could not read the release list from GitHub (rate limit or no network); set `$env:DVPN_VERSION = '<tag>' and run again: $($_.Exception.Message)" }
      # The API lists releases newest-CREATED first, and the first usable one wins: a release made
      # later on an older line would be picked over a newer version. Pin DVPN_VERSION to rule that out.
      $pick = $null
      foreach ($r in $releases) {
        if ($r.draft -or -not (Test-Tag $r.tag_name)) { continue }
        $a = $r.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if ($a) { $pick = @{ tag = $r.tag_name; file = $a.name }; break }
      }
      if (-not $pick) { Stop-Install 'no release v0.3 or newer has an x64 installer.' }
      $tag = $pick.tag; $file = $pick.file
      $base = "https://github.com/$repo/releases/download/$tag"
      try { Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile "$tmp\SHA256SUMS" }
      catch { Stop-Install "release $tag has no SHA256SUMS; not installing an unchecked file." }
    }

    Write-Host "install.ps1: release $tag, file $file"
    try { Invoke-WebRequest -UseBasicParsing -Uri "$base/$file" -OutFile "$tmp\$file" }
    catch { Stop-Install "download of $file failed: $($_.Exception.Message)" }

    # --- check the file against SHA256SUMS ---
    $want = $null
    foreach ($line in Get-Content "$tmp\SHA256SUMS") {
      $f = $line -split '\s+'
      if ($f.Count -ge 2 -and (($f[1] -replace '^\*', '') -eq $file)) { $want = $f[0].ToLower(); break }
    }
    if (-not $want) { Stop-Install "SHA256SUMS of $tag has no line for $file; not installing an unchecked file." }
    $got = (Get-FileHash "$tmp\$file" -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $want) { Stop-Install "$file does not match SHA256SUMS; not installing it." }
    Write-Host 'install.ps1: checksum OK'

    # --- silent install; -Wait, or it returns before it has finished ---
    $p = Start-Process -FilePath "$tmp\$file" -ArgumentList '/S' -Wait -PassThru
    if ($p.ExitCode -eq 3) { Stop-Install 'the installer says this CPU is the wrong one (exit code 3).' }
    if ($p.ExitCode -ne 0) { Stop-Install "the installer failed (exit code $($p.ExitCode))." }
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }

  # --- PATH for this shell (new shells get it from the installer) ---
  $bin = Join-Path $env:ProgramFiles 'Devnet dVPN\bin'
  if (-not (($env:Path -split ';') -contains $bin)) { $env:Path += ";$bin" }
  if (-not (Get-Command devnet-dvpn -ErrorAction SilentlyContinue)) { Stop-Install "installed, but devnet-dvpn is not in $bin." }
  $ver = devnet-dvpn version --json
  if ($LASTEXITCODE -ne 0) { Stop-Install 'installed, but devnet-dvpn version failed.' }
  Write-Host $ver
  $verObj = $null
  # A native command's lines arrive as an array; 5.1's ConvertFrom-Json needs them as one string.
  try { $verObj = ($ver -join "`n") | ConvertFrom-Json } catch { Write-Host "install.ps1: version output is not JSON ($($_.Exception.Message))" }

  # --- v0.3.0-rc2 only: daemon install fails on a machine not joined to a domain ---
  if ($tag -eq 'v0.3.0-rc2' -and $env:USERDOMAIN -eq 'WORKGROUP') {
    $env:USERDOMAIN = $env:COMPUTERNAME
    Write-Host 'install.ps1: v0.3.0-rc2 on a machine not in a domain: set $env:USERDOMAIN = $env:COMPUTERNAME in this shell, which daemon install needs. In a new shell, set it again before daemon install.'
  }

  devnet-dvpn agent status --json *> $null
  if ($LASTEXITCODE -eq 3) {
    $next = "this release has no agent commands: follow section 2 of $guide"
  } else {
    $next = 'devnet-dvpn agent status --json'
  }
  Write-Host "install.ps1: next: $next"
  # The one line for a program to read (human lines above go to the host, not the output).
  Write-Output ([ordered]@{ ok = $true; tag = $tag; file = $file; version = $verObj; path = $bin; next = $next } | ConvertTo-Json -Compress -Depth 5)
}

Install-DevnetDvpn
