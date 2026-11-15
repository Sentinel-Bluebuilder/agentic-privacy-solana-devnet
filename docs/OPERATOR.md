# For the person whose agent is asking for help

Your AI agent wants a private internet connection. It uses Sentinel dVPN: instead of signing up
with a VPN company, it pays a VPN server (a "node") directly, from a small wallet of its own, on
Solana **devnet**. Devnet is the test network: its tokens are free and have no value.

The agent does almost everything itself. It needs a person for two things only: **getting its
wallet funded** (the faucets are web pages for people) and, on some machines, **one
administrator prompt** during setup.

The guide your agent follows: <https://github.com/Sentinel-Bluebuilder/agentic-privacy-solana-devnet/blob/main/AGENTS.md>.

## 1. "Please fund my wallet"

The agent sends you a message with its wallet address. It looks like a long string of letters
and numbers. You need a GitHub account. It takes about two minutes and costs nothing.

**tDVPN, to pay the VPN.** Open <https://faucet.sentinel.co>.

1. Click **Connect GitHub** first (in the "Connect your GitHub." box) and approve. Do this before
   pasting anything: the page reloads on sign-in and an address typed earlier is lost. The big
   button that says "Connect GitHub to request" stays greyed out until you have done this.
2. Back on the page (it shows "GitHub connected"), paste the address into
   **Solana wallet address**.
3. Click **Request 100 tDVPN**. Done when you see **"100 tDVPN received"**.

**SOL, for network fees.** On the same page, the "Claim Devnet Sol" card has **Open official
faucet** (it opens <https://faucet.solana.com>).

1. Check the network says **devnet**, paste the same address into **Wallet Address**.
2. Click **Amount**, choose **0.5** (the choices are 0.5, 1, 2.5 and 5), then **Confirm Airdrop**.
3. A **Cloudflare Verification** box asks you to complete a captcha. Do it. Done when a
   **"Success!"** message appears.

No sign-in is needed on this page. Its "Connect your GitHub" box only raises the limit.

Then tell the agent you have seen "100 tDVPN received" and "Success!". It checks the balance
itself.

**If it does not work:**

- Each faucet allows **2 requests every 8 hours**. Once signed in, the Sentinel faucet shows
  "N / 2 remaining" and, after a request, "Next request available …". When none are left, its
  button reads "Claim limit reached". People on the same network share one allowance. (Its
  subtitle says "Claim 100 tDVPN every 8 hours"; the real limit is 2.)
- The Sentinel faucet also has a daily total for everyone. If it says the limit is reached and
  your 8 hours have passed, waiting will not help that day. Anyone with a funded Devnet dVPN
  wallet can send tDVPN instead: `devnet-dvpn wallet send --to <ADDRESS> --tdvpn 100 --yes`.
- The Solana faucet is often busy. Try again later. If the agent's machine has the Solana command
  line, the agent may get the SOL itself.
- Taking funds back from an agent's wallet later: sending all of its SOL is refused ("This would
  leave an account below Solana's minimum balance … Send a little less"). Leave about 0.001 SOL.

## 2. The one administrator moment

Setting up the VPN on the machine needs administrator / root rights once: when the app is
installed and when the agent installs its VPN service. Afterwards the agent runs as a normal
user. Whether you are needed depends on the machine.

| OS | No prompt when… | Otherwise | Can the agent answer it? |
|---|---|---|---|
| Linux | the agent's user has passwordless `sudo`, or it runs as root | the system asks for a password | No, not over SSH: run the step as root or allow passwordless `sudo` |
| Windows | the agent's shell already runs as administrator (an elevated terminal, or SSH as an administrator) | one UAC "allow changes?" prompt | No. With no desktop session the step fails |
| macOS | the agent's user has passwordless `sudo` | a password dialog on the screen | No: only a person at the screen can type it |

If the agent says it is stuck at this step, it is waiting for you: either answer the prompt at
the machine, or give its account the rights above. In a sandbox where nobody can become
administrator, the VPN service cannot be installed, and the agent will tell you so.

On Windows the agent may also say the account can use the service only after its next sign-in.
That is normal once, after the first install.

## 3. What it costs

Nothing real. Everything is on devnet with free test tokens: 100 tDVPN and 0.5 SOL last a long
time. The agent puts a small deposit on each connection and gets back what it does not use.

## 4. The key file

The agent's wallet is one file, usually named `agent-key.json`. Whoever has the file has the
wallet. **Never send it to anyone, never paste it into a chat or a website, never commit it to
git.** Nobody (no faucet, no support person, no agent) ever needs it from you. You only ever share
the address, which is safe to share.

## 5. Stopping the VPN and getting the deposit back

The agent normally does this itself. To do it yourself, open a terminal on the agent's machine
with the same key file set (`DVPN_KEYFILE`) and run:

```sh
devnet-dvpn disconnect              # stops the VPN: the machine uses its own connection again
devnet-dvpn settle run --yes        # starts closing the deposit
```

The deposit can be refunded about two hours later (`devnet-dvpn settle list` shows when). Then:

```sh
devnet-dvpn settle run --yes        # finishes closing
devnet-dvpn settle withdraw --yes   # moves the refund back to the wallet
```

Nobody has to stay online for the two hours.

If the internet on that machine stays blocked after the VPN is stopped (`devnet-dvpn quality ip`
shows no address), the kill switch is still blocking; this happens when the VPN session had
already dropped. `devnet-dvpn daemon restore-network` lifts the block for now; it can come back.
`devnet-dvpn daemon set --kill-switch off --yes` stops it coming back.

## 6. Not supported yet

- **Android:** the app works on a phone, but an agent cannot drive the released Android app from
  outside it.
- **Windows on ARM:** no build of the release the agent needs (v0.3.0-rc2 or newer) yet.
- **Windows machines not in a domain** (most cloud and home machines): v0.3.0-rc2's service
  install fails there until the agent runs one extra line first; the agent's guide has it.
- **Apple silicon Macs:** the build exists but has not been tested; Intel Macs are tested.
- **Machines where nobody can be administrator** (most sandboxes): the VPN service cannot be
  installed.

What has been tested on each system, step by step: [`PROOF.md`](PROOF.md).
