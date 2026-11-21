#!/usr/bin/env node
// ─── check-facts.mjs: every public page states the same facts as docs/facts.json ───
//
//   node tools/check-facts.mjs        # exit 0 OK, 1 a page disagrees, 4 cannot check (or the control failed)
//
// docs/facts.json is the one source for the facts the pages repeat: the SOL needed before setup, the default
// spending limit, the default cap rule, the verb after `agent down`, the close wait, the voucher / stream basis,
// the deposit rent, the exit codes of usage and of a dry run, and the release tags. Each RULE below pulls a
// value out of a line; a value other than the fact's is a contradiction. Lines that read as history (a release
// before the current one named, "was", "said", a date) are skipped, as are the files that are history by design.
// A self-control runs first: one planted contradiction per rule must be caught, a page of current facts must pass.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Files that are history by design, or generated from the checked pages. */
const SKIP = ['CHANGELOG.md', 'docs/OLDER-RELEASES.md', 'llms-full.txt', 'docs/facts.json', 'tools/check-facts.mjs'];
const SKIP_PREFIX = ['docs/RECOVERY-POINT-'];
/** A line about an older release or the past: its numbers may be old on purpose. */
const HISTORY = /\brc\.?[2-6]\b|\bv0\.3\.0-rc[2-6]\b|\bwas\b|\bsaid\b|\bused to\b|\bold(?:er)?\b|\b20\d\d-\d\d-\d\d\b|\(rc7:|rc7 (?:said|printed|status said|refused)/i;

// ─── Rules: a pattern whose group 1 is the value, and the fact it must equal ───
export function rules(f) {
  return [
    { id: 'voucher-basis', re: /voucher\s*=\s*per (GB|hour)/gi, want: [f.voucherBasis] },
    { id: 'voucher-basis', re: /per-(GB|hour) vouchers/gi, want: [f.voucherBasis] },
    { id: 'stream-basis', re: /stream\s*=\s*per (GB|hour)/gi, want: [f.streamBasis] },
    { id: 'stream-basis', re: /per-(GB|hour) streams/gi, want: [f.streamBasis] },
    { id: 'sol-before-setup', re: /SOL under (\d+\.\d+) before the first connect/gi, want: [f.solBeforeSetup] },
    { id: 'sol-before-setup', re: /(\d+\.\d+) SOL before (?:the first connect|setup)/gi, want: [f.solBeforeSetup] },
    { id: 'default-limit', re: /(\d+) tDVPN on a new install/gi, want: [f.defaultSpendingLimitTdvpn] },
    { id: 'default-limit', re: /a new install's limit is (\d+)/gi, want: [f.defaultSpendingLimitTdvpn] },
    // The cap rule: "limit / 10" alone (no p75 / market on the line) is the rc.6 rule.
    { id: 'cap-rule', re: /(spending limit \/ 10|limit\/10|limit \/ 10)(?![^\n]*(?:p75|market))/gi, want: [], what: 'the rc.6 cap rule (limit / 10 only)' },
    { id: 'settle-after-down', re: /\b(agent down|settle run) --yes after\b/gi, want: [f.settleAfterDown.replace(/ --yes after$/, '')] },
    { id: 'close-wait', re: /closing deposit waits (\d+) ?h/gi, want: [f.closeWaitHours] },
    { id: 'deposit-rent', re: /(0\.00\d+) SOL (?:channel |account )?rent/gi, want: f.depositRentSol },
    { id: 'deposit-rent', re: /holds about (0\.\d+) SOL/gi, want: f.depositRentSol },
    { id: 'exit-usage', re: /exit `?(\d)`? \((?:wrong )?usage\)/gi, want: [f.exitUsage] },
    { id: 'exit-needs-confirm', re: /exit `?(\d)`? \(`?needsConfirm/gi, want: [f.exitNeedsConfirm] },
    { id: 'release-box', re: new RegExp('\\*\\*Release: `(v[^`]+)`\\*\\*', 'g'), want: [f.release.current] },
    { id: 'release-box-mac', re: /\*\*Release: `v[^`]+`\*\*[^\n]*?macOS: `(v[^`]+)`/g, want: [f.release.mac] },
    { id: 'version-check', re: /version --json` says `(\d+\.\d+\.\d+-rc\.\d+)`/g, want: [f.release.appVersion ?? f.release.current.replace(/^v/, '').replace(/-rc(\d+)$/, '-rc.$1')] }, // appVersion: a promoted tag (v0.3.0 = the rc.9 files) keeps the build's version
    { id: 'tag-must-be', re: /`tag` must be `(v[^`]+)`/g, want: [f.release.current] },
  ];
}

// ─── Contradictions in one file ───
export function contradictions(text, f) {
  const out = [];
  const rs = rules(f);
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    if (HISTORY.test(line)) return;
    for (const r of rs) {
      // A wrapped sentence goes on: the cap rule's "p75" / the thin-market fallback may sit on the next line.
      if (r.id === 'cap-rule' && /p75|market|fewer than 3|fixed/i.test(`${line} ${lines[i + 1] ?? ''}`)) continue;
      for (const m of line.matchAll(r.re)) {
        const got = m[1];
        if (r.want.length === 0 || !r.want.some((w) => w.toLowerCase() === got.toLowerCase())) {
          out.push({ line: i + 1, id: r.id, got, want: r.what ?? r.want.join(' or '), text: line.trim().slice(0, 140) });
        }
      }
    }
  });
  return out;
}

// ─── Self-control ───
function control(f) {
  const planted = [
    'voucher = per hour, stream = per GB.',
    'The node does not take per-hour vouchers.',
    'SOL under 0.02 before the first connect → fund it.',
    'The spending limit (50 tDVPN on a new install).',
    'The cap is the Settings spending limit / 10.',
    'agent status says `agent down --yes after <ISO>`.',
    '(a closing deposit waits 3 h)',
    'Each open deposit holds about 0.004 SOL until settled.',
    'Exit 4 (usage) carries no code.',
    '> **Release: `v0.3.0-rc7`** on Windows and Linux; macOS: `v0.3.0-rc7`.',
  ].join('\n');
  const clean = [
    'voucher = per GB, stream = per hour.',
    'The node does not take per-GB vouchers. The node does not take per-hour streams.',
    'SOL under 0.06 before the first connect (rc7; 0.02 on rc.6).',
    'The spending limit (150 tDVPN on a new install).',
    'The larger of the spending limit / 10 and the market p75 price × units.',
    '`settle run --yes after <ISO>, then settle withdraw --yes` (a closing deposit waits 2 h).',
    'about 0.0022 SOL rent for the deposit account; the device pays 0.00217 SOL channel rent.',
    'Exit 3 (usage). Exit 2 (`needsConfirm: true`).',
    `> **Release: \`${f.release.current}\`** on Windows and Linux; macOS: \`${f.release.mac}\`.`,
    'rc.6: the cap was the spending limit / 10 (5 tDVPN with the default 50).',
  ].join('\n');
  const caught = new Set(contradictions(planted, f).map((c) => c.line));
  const flagged = contradictions(clean, f);
  const want = planted.split('\n').length;
  if (caught.size !== want || flagged.length) {
    console.error(`FAIL control: planted contradictions caught ${caught.size}/${want}, clean lines flagged ${flagged.length}/0 ${JSON.stringify(flagged)}`);
    process.exit(4);
  }
  console.log(`control: OK (${want} planted contradictions caught, one per fact; a page of current facts passes)`);
}

const factsPath = join(ROOT, 'docs/facts.json');
if (!existsSync(factsPath)) { console.error('FAIL: docs/facts.json not found'); process.exit(4); }
let facts;
try { facts = JSON.parse(readFileSync(factsPath, 'utf8')); } catch (e) { console.error(`FAIL: docs/facts.json does not parse: ${e.message}`); process.exit(4); }
control(facts);
const list = readFileSync(join(ROOT, 'public-files.txt'), 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
let bad = 0;
let checked = 0;
for (const rel of list) {
  if (SKIP.includes(rel) || SKIP_PREFIX.some((p) => rel.startsWith(p))) continue;
  if (!/\.(md|txt)$/.test(rel)) continue; // the pages; scripts and tools also state other accounts' numbers
  const p = join(ROOT, rel);
  if (!existsSync(p)) continue;
  checked++;
  for (const c of contradictions(readFileSync(p, 'utf8'), facts)) {
    console.log(`DISAGREES ${rel}:${c.line}  [${c.id}] says ${c.got}, docs/facts.json: ${c.want}  ${c.text}`);
    bad++;
  }
}
console.log(bad ? `FAIL ${bad} line(s) disagree with docs/facts.json in ${checked} public files` : `OK   ${checked} public files agree with docs/facts.json`);
process.exit(bad ? 1 : 0);
