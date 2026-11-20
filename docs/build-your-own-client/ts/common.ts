// ─── Shared setup for the TypeScript examples ───
// Talks to the public devnet RPC with @solana/web3.js and the public dvpn IDL
// (sentinel-programs/idl/dvpn.json at sentinel-official/sentinel-solana 26de5240).
import fs from 'node:fs';
import { Connection, Keypair, PublicKey } from '@solana/web3.js';
import { BorshAccountsCoder, BorshInstructionCoder, type Idl } from '@coral-xyz/anchor';

export const RPC_URL = process.env.RPC_URL ?? 'https://api.devnet.solana.com';
export const PROGRAM_ID = new PublicKey('J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs');
export const MINT = new PublicKey('Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa');
export const TOKEN_2022 = new PublicKey('TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb');
export const ATA_PROGRAM = new PublicKey('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL');

// The IDL file carries a placeholder address; the deployed program id is set here.
const idlPath = process.env.DVPN_IDL ?? 'dvpn.json';
const rawIdl = JSON.parse(fs.readFileSync(idlPath, 'utf8')) as Idl;
export const IDL: Idl = { ...rawIdl, address: PROGRAM_ID.toBase58() };
export const accounts = new BorshAccountsCoder(IDL);
export const ixCoder = new BorshInstructionCoder(IDL);

export const connection = new Connection(RPC_URL, 'confirmed');

// ─── PDAs (seeds from the IDL) ───
export const pda = (...seeds: (Buffer | Uint8Array)[]) =>
  PublicKey.findProgramAddressSync(seeds, PROGRAM_ID)[0];
export const configPda = () => pda(Buffer.from('config'));
export const userPda = (owner: PublicKey) => pda(Buffer.from('user'), owner.toBuffer());
export const channelPda = (owner: PublicKey, channelId: Uint8Array) =>
  pda(Buffer.from('channel'), owner.toBuffer(), channelId);
export const ata = (owner: PublicKey) =>
  PublicKey.findProgramAddressSync(
    [owner.toBuffer(), TOKEN_2022.toBuffer(), MINT.toBuffer()],
    ATA_PROGRAM,
  )[0];

export function loadKeypair(path: string): Keypair {
  return Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(path, 'utf8'))));
}

export async function fetchDecoded<T>(name: string, address: PublicKey): Promise<T> {
  const info = await connection.getAccountInfo(address);
  if (!info) throw new Error(`${name} ${address.toBase58()} not found`);
  if (!info.owner.equals(PROGRAM_ID)) throw new Error(`${name} ${address.toBase58()} is not owned by the dvpn program`);
  return accounts.decode(name, info.data) as T;
}

// Pulls the program error number out of a failed simulation or send.
export function programErrorCode(logs: string[] | null | undefined): number | null {
  for (const line of logs ?? []) {
    const m = line.match(/Error Number: (\d+)/) ?? line.match(/custom program error: 0x([0-9a-f]+)/i);
    if (m) return line.includes('0x') ? parseInt(m[1], 16) : Number(m[1]);
  }
  return null;
}
