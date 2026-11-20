// ─── Read example: Config + live nodes (+ your User account) ───
// Usage: npx tsx read.ts [ownerPubkey]
import bs58 from 'bs58';
import { PublicKey } from '@solana/web3.js';
import BN from 'bn.js';
import { IDL, MINT, PROGRAM_ID, accounts, configPda, connection, fetchDecoded, userPda } from './common.ts';

type Config = {
  mint: PublicKey; decimals: number; vault: PublicKey; fee_bps: number;
  channel_close_grace_seconds: number; node_listing_ttl_seconds: number; paused_mask: number;
};
type Node = {
  owner: PublicKey; status: number; listed_at: BN; channel_price_per_gb: BN;
  channel_price_per_hour: BN; uri: number[]; uri_len: number; country: number[]; opened_at: BN;
};
type User = { owner: PublicKey; balance: BN; open_channels: number; rent_recipient: PublicKey };

const config = await fetchDecoded<Config>('Config', configPda());
console.log('config', configPda().toBase58());
console.log('  mint', config.mint.toBase58(), config.mint.equals(MINT) ? '(matches)' : '(MISMATCH)');
console.log('  decimals', config.decimals, 'fee_bps', config.fee_bps, 'paused_mask', config.paused_mask);
console.log('  channel_close_grace_seconds', config.channel_close_grace_seconds,
  'node_listing_ttl_seconds', config.node_listing_ttl_seconds);
console.log('  vault', config.vault.toBase58());

// Every Node account: filter on the 8-byte Anchor discriminator from the IDL.
const disc = IDL.accounts!.find((a) => a.name === 'Node')!.discriminator;
const raw = await connection.getProgramAccounts(PROGRAM_ID, {
  filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Buffer.from(disc)) } }],
});
const now = Math.floor(Date.now() / 1000);
const live = raw
  .map(({ pubkey, account }) => ({ pubkey, node: accounts.decode('Node', account.data) as Node }))
  .filter(({ node }) => node.status === 1
    && now < node.listed_at.toNumber() + config.node_listing_ttl_seconds);
console.log(`nodes: ${raw.length} accounts, ${live.length} listed and live`);
for (const { pubkey, node } of live.slice(0, 5)) {
  const uri = Buffer.from(node.uri.slice(0, node.uri_len)).toString();
  const country = Buffer.from(node.country).toString();
  console.log(`  ${pubkey.toBase58()} ${country} ${uri} per_gb=${node.channel_price_per_gb} per_hour=${node.channel_price_per_hour}`);
}

if (process.argv[2]) {
  const owner = new PublicKey(process.argv[2]);
  const info = await connection.getAccountInfo(userPda(owner));
  if (!info) console.log('user', userPda(owner).toBase58(), 'not created yet (open_channel creates it)');
  else {
    const user = accounts.decode('User', info.data) as User;
    console.log('user', userPda(owner).toBase58(), 'balance', user.balance.toString(),
      'open_channels', user.open_channels, 'rent_recipient', user.rent_recipient.toBase58());
  }
}
