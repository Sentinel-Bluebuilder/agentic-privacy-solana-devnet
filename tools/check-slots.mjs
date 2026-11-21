#!/usr/bin/env node
// ─── check-slots.mjs: no public file still holds a fill-in slot from a release swap ───
//
//   node tools/check-slots.mjs [dir]   # exit 0 none, 1 an unfilled slot (each printed), 4 the control failed
//
// A release swap is drafted with slots for what only the publish knows: a hash, a build commit, a date, a source
// link, a live result. Every other gate passes with them in place (a slot is plain text), so a swap applied
// before they are filled would ship `<sha256: …>` on the page. This gate reads public-files.txt and fails on
// any slot shape below. Only these exact shapes count: `<N>` / `<date>` alone are ordinary placeholders in
// command lines (`--allowance <N>`), so they match only in their slot forms ("`<N>` codes", "`<date>`:").
// Optional [dir]: check the listed files inside that folder (an export) instead of this tree.
// A self-control runs first: one planted line per shape must be caught, ordinary placeholders must pass.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HUB = join(dirname(fileURLToPath(import.meta.url)), '..');
const ROOT = process.argv[2] ?? HUB;

// ─── Slot shapes (each with a name for the report) ───
const SLOTS = [
  ['SLOT', /<SLOT:[^>]*>/],
  ['rc9-d', /<rc\d+-[a-z]+:[^>]*>/],
  ['sha256', /<sha256:[^>]*>/],
  ['build commit', /<rc\d+ commit>/],
  ['source link', /<(?:win|linux|mac)-src>/],
  ['build command', /<build:[^>]*>/],
  ['verified date', /`<date>`:/],
  ['code count', /`<N>` codes/],
];

/** Slots on one text: [{line, kind, text}]. */
export function slotsIn(text) {
  const out = [];
  text.split('\n').forEach((line, i) => {
    for (const [kind, re] of SLOTS) if (re.test(line)) out.push({ line: i + 1, kind, text: line.trim().slice(0, 140) });
  });
  return out;
}

// ─── Self-control ───
{
  const planted = [
    '- Live on Windows: `<SLOT: rc.9 live list result>`.',
    'Answered by `<rc9-d: the commands that answer it>`.',
    '| `x.deb` | `<sha256: fill from the rc9 SHA256SUMS>` |',
    '| [`repo`](repo) @ `<rc9 commit>` |',
    'Windows [`<win-src>`](<win-src>), Linux [`<linux-src>`], macOS [`<mac-src>`]',
    '| `<build: from the source README>` |',
    '| `<date>`: hash matches `SHA256SUMS` |',
    'For `v0.3.0` (`abc`): `<N>` codes, exit 0.',
  ];
  const clean = [
    '`devnet-dvpn device setup --allowance <N> --yes`',
    '`settle run --yes after <ISO>`, then `<cli> agent up --node <node> --units <n>`',
    'Last verified 2026-11-20 (<date> is when you ran it).',
    'export DVPN_KEYFILE=<full path>',
  ];
  const caught = planted.filter((l) => slotsIn(l).length > 0).length;
  const kinds = new Set(planted.flatMap((l) => slotsIn(l).map((s) => s.kind)));
  const flagged = clean.flatMap((l) => slotsIn(l));
  if (caught !== planted.length || kinds.size !== SLOTS.length || flagged.length) {
    console.error(`FAIL control: planted slots caught ${caught}/${planted.length} (${kinds.size}/${SLOTS.length} kinds), ordinary placeholders flagged ${flagged.length}/0 ${JSON.stringify(flagged)}`);
    process.exit(4);
  }
  console.log(`control: OK (${planted.length} planted slots caught, one per kind; ordinary placeholders pass)`);
}

const listPath = join(existsSync(join(ROOT, 'public-files.txt')) ? ROOT : HUB, 'public-files.txt');
const list = readFileSync(listPath, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
let bad = 0;
let checked = 0;
for (const rel of list) {
  if (rel === 'tools/check-slots.mjs') continue; // this file: its self-control plants slots on purpose
  const p = join(ROOT, rel);
  if (!existsSync(p)) continue;
  checked++;
  for (const s of slotsIn(readFileSync(p, 'utf8'))) {
    console.log(`SLOT ${rel}:${s.line}  [${s.kind}]  ${s.text}`);
    bad++;
  }
}
console.log(bad ? `FAIL ${bad} unfilled slot(s) in ${checked} public files: fill them before this ships` : `OK   ${checked} public files hold no unfilled slot`);
process.exit(bad ? 1 : 0);
