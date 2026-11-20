// ─── Close example: start_close → (wait channel_close_grace_seconds) → close + withdraw ───
// Usage: npx tsx close-channel.ts <keypair.json> <channelAddress> start|finish [--simulate]
//   start   start_close_channel (voucher mode only; the node can still redeem during the grace)
//   finish  close_channel + withdraw_user_balance in one transaction, after the grace
import BN from 'bn.js';
import {
  PublicKey, TransactionInstruction, TransactionMessage, VersionedTransaction,
} from '@solana/web3.js';
import {
  MINT, PROGRAM_ID, TOKEN_2022, ata, configPda, connection, fetchDecoded, ixCoder,
  loadKeypair, programErrorCode, userPda,
} from './common.ts';
import { explain } from './errors.ts';

const [keyPath, channelArg, step] = process.argv.slice(2);
if (!keyPath || !channelArg || !['start', 'finish'].includes(step)) {
  throw new Error('usage: close-channel.ts <keypair.json> <channel> start|finish [--simulate]');
}
const wallet = loadKeypair(keyPath);
const owner = wallet.publicKey;
const channel = new PublicKey(channelArg);
const ch = await fetchDecoded<{ owner: PublicKey; rent_recipient: PublicKey; status: number; close_started_at: BN }>('Channel', channel);
const config = await fetchDecoded<{ vault: PublicKey; channel_close_grace_seconds: number }>('Config', configPda());
const NONE = { pubkey: PROGRAM_ID, isSigner: false, isWritable: false }; // optional account = None
const ro = (pubkey: PublicKey) => ({ pubkey, isSigner: false, isWritable: false });
const rw = (pubkey: PublicKey) => ({ pubkey, isSigner: false, isWritable: true });
const signer = { pubkey: owner, isSigner: true, isWritable: false };

const ixs: TransactionInstruction[] = [];
if (step === 'start') {
  ixs.push(new TransactionInstruction({
    programId: PROGRAM_ID,
    data: ixCoder.encode('start_close_channel', {}),
    keys: [signer, ro(configPda()), rw(channel), NONE],
  }));
} else {
  const ready = ch.close_started_at.toNumber() + config.channel_close_grace_seconds;
  console.log('grace ends at', new Date(ready * 1000).toISOString());
  const user = await fetchDecoded<{ rent_recipient: PublicKey }>('User', userPda(ch.owner));
  ixs.push(new TransactionInstruction({
    programId: PROGRAM_ID,
    data: ixCoder.encode('close_channel', {}),
    // node is required only on a Stream close; None for voucher mode.
    keys: [signer, ro(configPda()), rw(channel), rw(userPda(ch.owner)), NONE, NONE, rw(ch.rent_recipient)],
  }));
  ixs.push(new TransactionInstruction({
    programId: PROGRAM_ID,
    data: ixCoder.encode('withdraw_user_balance', {}),
    keys: [signer, ro(configPda()), ro(owner), NONE, rw(userPda(owner)), rw(user.rent_recipient),
      rw(ata(owner)), rw(config.vault), ro(MINT), ro(TOKEN_2022)],
  }));
}

const { blockhash, lastValidBlockHeight } = await connection.getLatestBlockhash();
const tx = new VersionedTransaction(new TransactionMessage({
  payerKey: owner, recentBlockhash: blockhash, instructions: ixs,
}).compileToV0Message());
tx.sign([wallet]);
const sim = await connection.simulateTransaction(tx, { sigVerify: false });
console.log('simulate:', sim.value.err ? `error program_error=${programErrorCode(sim.value.logs)}` : 'ok');
if (sim.value.err) { console.log(JSON.stringify(explain(sim.value.logs, sim.value.err))); process.exit(1); }
if (process.argv.includes('--simulate')) process.exit(0);
const sig = await connection.sendTransaction(tx);
await connection.confirmTransaction({ signature: sig, blockhash, lastValidBlockHeight }, 'confirmed');
console.log('sent', sig);
