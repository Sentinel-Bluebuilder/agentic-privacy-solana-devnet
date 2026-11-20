// ─── Decode a failing transaction into its error row, with no key and nothing signed ───
// Usage: npx tsx explain-failure.ts [channelAddress]
// Without an address it picks a voucher channel that is closing and still inside its grace
// (close_channel → 6035 GraceNotElapsed), or else an open one (→ 6033 ChannelNotClosing).
// close_channel needs no owner signature in voucher mode, so the simulation uses the channel's
// owner as fee payer and signer WITHOUT its key: sigVerify is off and nothing is sent.
import bs58 from 'bs58';
import BN from 'bn.js';
import {
  PublicKey, TransactionInstruction, TransactionMessage, VersionedTransaction,
} from '@solana/web3.js';
import { IDL, PROGRAM_ID, accounts, configPda, connection, fetchDecoded, ixCoder, userPda } from './common.ts';
import { explain } from './errors.ts';

type Channel = { owner: PublicKey; rent_recipient: PublicKey; status: number; mode: number; close_started_at: BN };

// Channel layout offsets (8-byte discriminator first): mode at 136, status at 225.
const MODE_OFFSET = 136;
const STATUS_OFFSET = 225;

async function pickChannel(graceSeconds: number): Promise<{ address: PublicKey; ch: Channel; why: string }> {
  const disc = bs58.encode(Buffer.from(IDL.accounts!.find((a) => a.name === 'Channel')!.discriminator));
  const find = (status: number) => connection.getProgramAccounts(PROGRAM_ID, {
    filters: [
      { memcmp: { offset: 0, bytes: disc } },
      { memcmp: { offset: MODE_OFFSET, bytes: bs58.encode(Buffer.from([0])) } },
      { memcmp: { offset: STATUS_OFFSET, bytes: bs58.encode(Buffer.from([status])) } },
    ],
  });
  const now = Math.floor(Date.now() / 1000);
  for (const { pubkey, account } of await find(1)) {
    const ch = accounts.decode('Channel', account.data) as Channel;
    if (ch.close_started_at.toNumber() + graceSeconds > now + 60) return { address: pubkey, ch, why: 'closing, inside its grace' };
  }
  const open = await find(0);
  if (!open.length) throw new Error('no voucher channel found to simulate against');
  return { address: open[0].pubkey, ch: accounts.decode('Channel', open[0].account.data) as Channel, why: 'open, start_close not called' };
}

const config = await fetchDecoded<{ channel_close_grace_seconds: number }>('Config', configPda());
const picked = process.argv[2]
  ? { address: new PublicKey(process.argv[2]), ch: await fetchDecoded<Channel>('Channel', new PublicKey(process.argv[2])), why: 'given' }
  : await pickChannel(config.channel_close_grace_seconds);
const { address, ch } = picked;
console.log('channel', address.toBase58(), `(${picked.why})`, 'status', ch.status);

const NONE = { pubkey: PROGRAM_ID, isSigner: false, isWritable: false };
const payer = ch.owner; // pays the (simulated) fee; its key is never needed
const ix = new TransactionInstruction({
  programId: PROGRAM_ID,
  data: ixCoder.encode('close_channel', {}),
  keys: [
    { pubkey: payer, isSigner: true, isWritable: true },
    { pubkey: configPda(), isSigner: false, isWritable: false },
    { pubkey: address, isSigner: false, isWritable: true },
    { pubkey: userPda(ch.owner), isSigner: false, isWritable: true },
    NONE, // grant
    NONE, // node (only for a stream close)
    { pubkey: ch.rent_recipient, isSigner: false, isWritable: true },
  ],
});
const { blockhash } = await connection.getLatestBlockhash();
const tx = new VersionedTransaction(new TransactionMessage({ payerKey: payer, recentBlockhash: blockhash, instructions: [ix] }).compileToV0Message());
// Unsigned: sigVerify off, so nothing is signed and nothing can be sent.
const sim = await connection.simulateTransaction(tx, { sigVerify: false, replaceRecentBlockhash: true });
if (!sim.value.err) {
  console.log('simulation succeeded: this channel can be closed now');
} else {
  console.log(JSON.stringify(explain(sim.value.logs, sim.value.err), null, 2));
}
