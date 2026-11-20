// ─── Decode a failed dvpn transaction into one row: number → name → meaning → money moved? → fix ───
// Sources: names and messages of 6000+ = the IDL `errors` list (public upstream dvpn.json at 26de5240);
// Anchor framework names = anchor-lang 1.2.2 (sentinel-programs/Cargo.lock), the same set the Devnet dVPN
// app decodes. `meaning` adds where the program raises it (program source at 26de5240); `fix` is the
// client guidance of BUILD-YOUR-OWN-CLIENT.md. gen-error-table.ts prints this file as the §9 table.
import { IDL } from './common.ts';

export type ErrorRow = { code: number | null; name: string; meaning: string; moneyMoved: string; fix: string };

// A failed transaction is atomic: no token moves and no account is created or closed.
export const MONEY = 'No. A sent transaction still pays its 5000-lamport fee; a simulation pays nothing.';

// code → [where / why, fix]. Every IDL error has a row.
const PROGRAM: Record<number, [string, string]> = {
  6000: ['every owner-or-grantee instruction, update_grant, close_grant: the signer is not the owner and no valid grant names it', 'sign with the owner, or pass the Grant PDA ["grant", owner, signer, target]'],
  6001: ['open_* instructions: Config.paused_mask has that open paused (channels: bit 32)', 'wait; read Config.paused_mask before opening'],
  6002: ['governance (set_params): fee_bps above the limit', 'governance only'],
  6003: ['open_grant / update_grant: grantee is 111…1 or the granter, unknown permission bits, or expires_at not 0 and not in the future; governance: a parameter out of range', 'fix the arguments'],
  6004: ['governance (accept_authority): no pending authority', 'governance only'],
  6005: ['initialize_config: the mint is not a valid Token-2022 mint', 'governance only'],
  6006: ['initialize_config: the mint has a forbidden extension', 'governance only'],
  6007: ['initialize_config: the mint still has a mint or freeze authority', 'governance only'],
  6008: ['governance: the vault is not the Config PDA’s associated token account', 'governance only'],
  6009: ['governance: the vault lacks the immutable-owner extension', 'governance only'],
  6010: ['governance (set_treasury / initialize_config): the treasury is the vault or Config-owned', 'governance only'],
  6011: ['open_node / open_provider: the bond is below Config.min_node_bond / min_provider_bond', 'bond at least the minimum'],
  6012: ['open_node / open_provider: a parked bond for this id is still unbonding', 'withdraw the old bond after the unbonding window, then open'],
  6013: ['withdraw_node_bond / withdraw_provider_bond: Config.unbonding_seconds has not passed', 'wait for the unbonding window'],
  6014: ['node / provider instructions: the URI is longer than its 128-byte field', 'use a shorter URI'],
  6015: ['open_channel / open_lease: node.status is not 1 (listed)', 'pick another node'],
  6016: ['open_channel / open_lease: now >= node.listed_at + Config.node_listing_ttl_seconds', 'pick a node listed within the TTL'],
  6017: ['open_channel / open_lease (stream): expected_rate_per_hour differs from the node’s current price', 'read the node again and retry with its current price'],
  6018: ['withdraw_node_revenue / withdraw_provider_revenue: amount above the revenue held', 'withdraw at most the revenue'],
  6019: ['sweep_*_fees: nothing accrued to sweep', 'nothing to do'],
  6020: ['open_lease / open_subscription: the provider is not listed', 'pick another provider or plan'],
  6021: ['close_provider: the provider still has open plans', 'close its plans first'],
  6022: ['close_provider: the provider still has open leases', 'close its leases first'],
  6023: ['withdraw_user_balance / withdraw_provider_balance: the balance is 0 and positions are still open', 'close the open channels first; there is nothing to withdraw yet'],
  6024: ['delegated open_channel / fund_channels (and leases): escrow above the grant’s remaining allowance', 'the owner raises it with update_grant'],
  6025: ['open_subscription: the plan is not listed', 'pick another plan'],
  6026: ['close_plan: the plan is still listed', 'delist the plan first'],
  6027: ['open_subscription: the plan’s terms differ from the ones passed', 'read the plan again and retry with its current terms'],
  6028: ['close_subscription by someone who is not the owner, its grantee or the provider: not expired yet', 'wait until it expires'],
  6029: ['close_subscription by the provider before expiry: allowed only when the subscription price is 0', 'wait until it expires (a paid subscription)'],
  6030: ['lease instructions: the lease is not open', 'open a new lease'],
  6031: ['close_lease (voucher): start_close_lease was not called', 'call start_close_lease first'],
  6032: ['fund_channels / start_close_channel: the channel is already closing', 'open a new channel'],
  6033: ['close_channel (voucher): start_close_channel was not called', 'call start_close_channel first'],
  6034: ['redeem_channel_vouchers (node side): the voucher is above the escrow; protects the client', 'never sign a voucher above Channel.escrow'],
  6035: ['close_channel (voucher): less than Config.channel_close_grace_seconds (7200 s) since close_started_at', 'wait until close_started_at + channel_close_grace_seconds'],
  6036: ['redeem_* (node side): nothing new to redeem', 'nothing to do'],
  6037: ['start_close_channel / redeem_channel_vouchers on a stream channel', 'stream channel: call close_channel directly, no start_close'],
  6038: ['redeem_*_streams on a voucher position', 'use the voucher redeem instead'],
  6039: ['redeem_*_vouchers: not signed by voucher_signer over the 80-byte voucher message', 'sign the exact 80-byte message with the channel’s voucher_signer'],
  6040: ['batch instructions (fund_channels, redeem_*): number of amounts ≠ number of accounts, or none', 'pass one amount per account, at least one'],
  6041: ['batch instructions: accounts not strictly ascending by pubkey bytes', 'sort by pubkey bytes and remove duplicates'],
  6042: ['redeem / stream settle: the node was closed and reopened after the channel opened', 'close the channel (refund) and open a new one'],
  6043: ['any: a u64 sum or product overflowed', 'use sane amounts (a client bug)'],
  6044: ['governance: the vault is frozen', 'wait; payments are frozen network-wide'],
  6045: ['any delegated instruction: now >= grant.expires_at (not 0)', 'the owner extends it with update_grant'],
  6046: ['any delegated instruction: the grant lacks this action’s permission bit', 'the owner adds the bit with update_grant'],
  6047: ['any delegated instruction: grant.target is not 111…1, the node or the channel', 'use a grant whose target covers the account'],
  6048: ['open_channel / open_lease (voucher): voucher_signer is not a prime-order ed25519 point', 'use a real ed25519 public key'],
  6049: ['open_channel / open_grant (and other opens): a rent recipient argument is 111…1', 'pass the signer or the rent payer'],
  6050: ['the same opens: the rent recipient is neither the signer nor the rent payer', 'pass the signer or the rent payer'],
};

// anchor-lang 1.2.2 framework codes (the set the Devnet dVPN app decodes) → [name, meaning, fix].
const ANCHOR: Record<number, [string, string, string]> = {
  100: ['InstructionMissing', 'no 8-byte instruction discriminator in the data', 'encode the instruction with the IDL'],
  101: ['InstructionFallbackNotFound', 'unknown instruction discriminator', 'encode with the IDL of the deployed program'],
  102: ['InstructionDidNotDeserialize', 'the args do not match this program version', 're-encode with the IDL of the deployed program'],
  2000: ['ConstraintMut', 'an account that must be writable was passed read-only', 'mark it writable (IDL "writable")'],
  2001: ['ConstraintHasOne', 'an account does not belong to the owner it must (e.g. a funded channel of another wallet)', 'pass the owner’s own accounts'],
  2002: ['ConstraintSigner', 'an account that must sign did not', 'add its signature (IDL "signer")'],
  2003: ['ConstraintRaw', 'a custom account constraint failed', 'check the accounts against the IDL'],
  2006: ['ConstraintSeeds', 'a PDA does not match its seeds (also: a grant passed while the owner signs)', 'derive the PDA again; pass no grant when the owner signs'],
  2012: ['ConstraintAddress', 'an account is not the one stored on chain (vault, mint, token program, rent recipient)', 'pass Config.vault, Config.mint, Token-2022 and the stored rent_recipient'],
  2014: ['ConstraintTokenMint', 'owner_token is for another mint', 'use the owner’s Token-2022 account for Config.mint'],
  2015: ['ConstraintTokenOwner', 'owner_token belongs to another wallet', 'use the owner’s Token-2022 account for Config.mint'],
  2019: ['ConstraintSpace', 'an account was created with the wrong size', 'a client or program bug: report it'],
  2020: ['ConstraintAccountIsNone', 'a required optional account was None (e.g. node on a stream close)', 'pass the account (node on a stream close_channel)'],
  3005: ['AccountDidNotSerialize', 'the program could not write an account', 'a program bug: report it'],
  3007: ['AccountOwnedByWrongProgram', 'an account is owned by another program (e.g. a plain SPL Token account)', 'pass the dvpn / Token-2022 account the IDL names'],
  3012: ['AccountNotInitialized', 'an account the instruction reads does not exist yet (e.g. User before the first channel)', 'open a channel first (it creates the User account)'],
};

/** Every row, program errors first: what gen-error-table.ts prints. */
export function allRows(): ErrorRow[] {
  const rows: ErrorRow[] = [];
  for (const e of IDL.errors ?? []) rows.push(explainCode(e.code));
  for (const code of Object.keys(ANCHOR).map(Number)) rows.push(explainCode(code));
  return rows;
}

/** The program error number from simulation/send logs or a {Custom: N} error object. */
export function errorCode(logs: string[] | null | undefined, err?: unknown): number | null {
  const blob = [...(logs ?? []), err === undefined ? '' : JSON.stringify(err)].join('\n');
  let m = blob.match(/Error Number: (\d+)/);
  if (m) return Number(m[1]);
  m = blob.match(/custom program error: 0x([0-9a-f]+)/i);
  if (m) return parseInt(m[1], 16);
  m = blob.match(/"Custom":\s*(\d+)/);
  return m ? Number(m[1]) : null;
}

/** The row for one number. */
export function explainCode(code: number): ErrorRow {
  const idl = (IDL.errors ?? []).find((e) => e.code === code);
  if (idl) {
    const [where, fix] = PROGRAM[code] ?? ['', 'see the program source'];
    return { code, name: idl.name, meaning: `${idl.msg ?? ''}${where ? `: ${where}` : ''}`, moneyMoved: MONEY, fix };
  }
  const fw = ANCHOR[code];
  if (fw) return { code, name: fw[0], meaning: fw[1], moneyMoved: MONEY, fix: fw[2] };
  if (code === 0) return { code, name: 'AccountAlreadyInUse (System)', meaning: 'an account the instruction creates already exists (e.g. a reused channel_id)', moneyMoved: MONEY, fix: 'pick a new channel_id' };
  return { code, name: `error ${code}`, meaning: 'not a dvpn or known Anchor error (System or Token program?)', moneyMoved: MONEY, fix: 'read the logs' };
}

/** The row for a failed simulation or send. */
export function explain(logs: string[] | null | undefined, err?: unknown): ErrorRow {
  const code = errorCode(logs, err);
  if (code === null) return { code, name: 'unknown', meaning: JSON.stringify(err ?? null), moneyMoved: MONEY, fix: 'read the logs' };
  return explainCode(code);
}
