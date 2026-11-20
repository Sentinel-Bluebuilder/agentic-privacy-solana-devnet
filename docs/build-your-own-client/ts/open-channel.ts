// ─── Write example: open one voucher-mode channel ───
// Usage: npx tsx open-channel.ts <keypair.json> <nodeAddress> <escrowBaseUnits> [--simulate] [--bad-rent]
//   --simulate  build + simulate only (nothing is sent, no money moves)
//   --bad-rent  simulate with channel_rent_recipient = 111…1 to prove error 6049 MissingRentRecipient
import crypto from 'node:crypto';
import BN from 'bn.js';
import {
  ComputeBudgetProgram, PublicKey, SystemProgram, TransactionInstruction,
  TransactionMessage, VersionedTransaction,
} from '@solana/web3.js';
import {
  MINT, PROGRAM_ID, TOKEN_2022, ata, channelPda, configPda, connection, fetchDecoded,
  ixCoder, loadKeypair, programErrorCode, userPda,
} from './common.ts';
import { explain } from './errors.ts';

const [keyPath, nodeArg, escrowArg] = process.argv.slice(2);
const simulateOnly = process.argv.includes('--simulate') || process.argv.includes('--bad-rent');
const badRent = process.argv.includes('--bad-rent');
if (!keyPath || !nodeArg || !escrowArg) throw new Error('usage: open-channel.ts <keypair.json> <node> <escrow> [--simulate] [--bad-rent]');

const wallet = loadKeypair(keyPath);
const owner = wallet.publicKey;
const node = new PublicKey(nodeArg);
const escrow = new BN(escrowArg);
const config = await fetchDecoded<{ vault: PublicKey }>('Config', configPda());

// channel_id is any 32 bytes you choose; it is part of the channel PDA seed.
const channelId = crypto.randomBytes(32);
const channel = channelPda(owner, channelId);

// Voucher mode: vouchers for this channel must be signed by voucher_signer.
// Here the owner's own key; a daemon that opens a channel for you uses its own key.
const data = ixCoder.encode('open_channel', {
  channel_id: [...channelId],
  escrow,
  terms: { Voucher: { voucher_signer: owner } },
  // Rent rule: each rent recipient must be the signer or the rent payer, never 111…1.
  channel_rent_recipient: badRent ? PublicKey.default : owner,
  user_rent_recipient: owner,
});

// Account order exactly as the IDL lists it. The optional `grant` is passed as
// the program id itself = "None" (the owner signs, no delegation).
const keys = [
  { pubkey: owner, isSigner: true, isWritable: true },                 // signer
  { pubkey: configPda(), isSigner: false, isWritable: false },         // config  ["config"]
  { pubkey: owner, isSigner: false, isWritable: false },               // owner
  { pubkey: PROGRAM_ID, isSigner: false, isWritable: false },          // grant (None)
  { pubkey: userPda(owner), isSigner: false, isWritable: true },       // user    ["user", owner]
  { pubkey: node, isSigner: false, isWritable: false },                // node    ["node", node.owner, node.node_id]
  { pubkey: channel, isSigner: false, isWritable: true },              // channel ["channel", owner, channel_id]
  { pubkey: config.vault, isSigner: false, isWritable: true },         // vault = config.vault
  { pubkey: MINT, isSigner: false, isWritable: false },                // mint
  { pubkey: ata(owner), isSigner: false, isWritable: true },           // owner_token (Token-2022 ATA)
  { pubkey: TOKEN_2022, isSigner: false, isWritable: false },          // token_program
  { pubkey: owner, isSigner: true, isWritable: true },                 // rent_payer
  { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
];
const ix = new TransactionInstruction({ programId: PROGRAM_ID, keys, data });

const { blockhash, lastValidBlockHeight } = await connection.getLatestBlockhash();
const msg = new TransactionMessage({
  payerKey: owner,
  recentBlockhash: blockhash,
  instructions: [ComputeBudgetProgram.setComputeUnitLimit({ units: 200_000 }), ix],
}).compileToV0Message();
const tx = new VersionedTransaction(msg);
tx.sign([wallet]);

console.log('channel', channel.toBase58(), 'channel_id', channelId.toString('hex'));
const sim = await connection.simulateTransaction(tx, { sigVerify: false });
const code = programErrorCode(sim.value.logs);
console.log('simulate:', sim.value.err ? `error ${JSON.stringify(sim.value.err)} program_error=${code}` : 'ok',
  'units', sim.value.unitsConsumed);
if (sim.value.err) {
  console.log(JSON.stringify(explain(sim.value.logs, sim.value.err)));
  process.exit(badRent && code === 6049 ? 0 : 1);
}
if (simulateOnly) process.exit(0);

const sig = await connection.sendTransaction(tx, { skipPreflight: false });
await connection.confirmTransaction({ signature: sig, blockhash, lastValidBlockHeight }, 'confirmed');
console.log('sent', sig);
const opened = await fetchDecoded<{ escrow: BN; status: number; opened_at: BN }>('Channel', channel);
console.log('channel escrow', opened.escrow.toString(), 'status', opened.status, 'opened_at', opened.opened_at.toString());
