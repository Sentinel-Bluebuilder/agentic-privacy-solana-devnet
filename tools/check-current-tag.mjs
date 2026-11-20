#!/usr/bin/env node
// ─── check-current-tag.mjs: every public page names the current release tag ───
//
//   node tools/check-current-tag.mjs        # exit 0 OK, 1 a stale tag, 4 cannot check (or the control failed)
//
// The current tags are read from ONE place: the release box in AGENTS.md,
//   > **Release: `v0.3.0-rc7`** on Windows and Linux (…); macOS: `v0.3.0-rc4`.
// In every file in public-files.txt (except the HISTORY files below), a line that names a v0.3 app tag as the
// thing to install (a download or tag URL, DVPN_VERSION, "install … by name", "Use release", "pins", "tags look
// like", the release box) may name only those two. History stays: a line with a date, "earlier / older / was /
// proven", "from / since / before <tag>", "<tag> and later / or newer", "rc4 → rc5 → …" chains, or an ALLOW entry.
// So a release swap that misses a page (an install line, a download URL, an installer's example) fails here.
// A self-control runs first: a stale install line must be caught, history and current lines must pass.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Files that are history by design: every tag in them may be old. */
const HISTORY = [
  'CHANGELOG.md',
  'docs/OLDER-RELEASES.md',
  'llms-full.txt', // generated from the checked pages plus CHANGELOG; its freshness has its own CI step
  'tools/check-current-tag.mjs', // this file: its self-control plants old tags on purpose
  'tools/check-facts.mjs', // its self-control plants an old release box on purpose
];
const HISTORY_PREFIX = ['docs/RECOVERY-POINT-'];

const TAG = /\bv0\.3\.\d+(?:-rc\d+)?\b/g;
const BEFORE = /(?:\b(?:from|since|before|older than|until|than)\s+(?:release\s+)?`?|→\s*`?)$/i;
const AFTER = /^`?\s*(?:and (?:later|newer|older)|or (?:later|newer|older)|\+|\s*→)/i;
/** A line that names a tag as the thing to install or download. Only these lines are checked. */
const INSTALL = /install|releases\/(?:download|tag)\/|DVPN_VERSION|\bpins?\b|by name|Use release|\*\*Release:|tags look like|For `devnet-dvpn`|the release the agent needs/i;
/** A line that is plainly a record of the past: a date, "earlier/older", "only:" workarounds, a tag compare. */
const PAST = /\b20\d\d-\d\d-\d\d\b|\bearlier\b|\bolder\b|\bwas\b|\bproven\b|\bpassed\b|\bonly:|-eq\b/i;
/** Always checked, history words or not: a download or tag URL, or a DVPN_VERSION example. */
const STRONG = /releases\/(?:download|tag)\/v|DVPN_VERSION\s*=\s*'?v/;
/** Exact old-tag lines kept on purpose (with why). */
const ALLOW = [
  'install.ps1: v0.3.0-rc2 on a machine not in a domain', // the rc2-only USERDOMAIN workaround (install.ps1:122-125)
];

// ─── Read the current tags from the release box ───
export function currentTags(agentsText) {
  const m = /\*\*Release: `(v[^`]+)`\*\*[^\n]*?macOS: `(v[^`]+)`/.exec(agentsText);
  return m ? { current: m[1], mac: m[2] } : null;
}

// ─── Stale tags on the lines of one file ───
export function staleTags(text, tags) {
  const hits = [];
  text.split('\n').forEach((line, i) => {
    if (ALLOW.some((a) => line.includes(a))) return;
    if (!STRONG.test(line) && (!INSTALL.test(line) || PAST.test(line))) return;
    for (const m of line.matchAll(TAG)) {
      const tag = m[0];
      if (tag === tags.current || tag === tags.mac) continue;
      const before = line.slice(Math.max(0, m.index - 24), m.index);
      const after = line.slice(m.index + tag.length, m.index + tag.length + 16);
      if (BEFORE.test(before) || AFTER.test(after)) continue;
      hits.push({ line: i + 1, tag, text: line.trim().slice(0, 140) });
    }
  });
  return hits;
}

// ─── Self-control ───
function control() {
  const tags = { current: 'v0.3.0-rc7', mac: 'v0.3.0-rc4' };
  const box = currentTags('> **Release: `v0.3.0-rc7`** on Windows and Linux; macOS: `v0.3.0-rc4`. The same');
  const caught = staleTags('Install v0.3.0-rc6 by name.\nU=https://x/releases/download/v0.3.0-rc5\nolder than v0.3: use DVPN_VERSION=v0.3.0-rc5.\n', tags);
  const passed = staleTags('Install v0.3.0-rc7 by name (macOS: v0.3.0-rc4).\nFrom v0.3.0-rc6 every amount has a twin.\n'
    + 'Shows: version --json (v0.3.0-rc6 and newer).\ninstall on an older release (v0.3.0-rc2)\n'
    + 'A test run (public v0.3.0-rc2 package, 2026-11-15): install, key, connect\n', tags);
  if (!box || box.current !== 'v0.3.0-rc7' || box.mac !== 'v0.3.0-rc4' || caught.length !== 3 || passed.length !== 0) {
    console.error(`FAIL control: box ${JSON.stringify(box)}, caught ${caught.length}/3, history/current flagged ${passed.length}/0 ${JSON.stringify(passed)}`);
    process.exit(4);
  }
  console.log('control: OK (release box read; 3 planted stale tags caught; current, macOS and history lines pass)');
}

control();
const agents = join(ROOT, 'AGENTS.md');
const tags = existsSync(agents) ? currentTags(readFileSync(agents, 'utf8')) : null;
if (!tags) { console.error('FAIL: no release box (**Release: `v…`** … macOS: `v…`) in AGENTS.md'); process.exit(4); }
// docs/facts.json is the one source of the facts (tools/check-facts.mjs); its `release` must equal the release box.
const factsPath = join(ROOT, 'docs/facts.json');
if (existsSync(factsPath)) {
  let rel;
  try { rel = JSON.parse(readFileSync(factsPath, 'utf8')).release; } catch (e) { console.error(`FAIL: docs/facts.json does not parse: ${e.message}`); process.exit(4); }
  if (!rel || rel.current !== tags.current || rel.mac !== tags.mac) {
    console.error(`FAIL: docs/facts.json release ${JSON.stringify(rel)} differs from the AGENTS.md release box ${JSON.stringify(tags)}: change both together`);
    process.exit(1);
  }
}
const list = readFileSync(join(ROOT, 'public-files.txt'), 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
let bad = 0;
let checked = 0;
for (const rel of list) {
  if (HISTORY.includes(rel) || HISTORY_PREFIX.some((p) => rel.startsWith(p))) continue;
  const p = join(ROOT, rel);
  if (!existsSync(p)) continue;
  checked++;
  for (const h of staleTags(readFileSync(p, 'utf8'), tags)) {
    console.log(`STALE ${rel}:${h.line}  ${h.tag} (current ${tags.current}, macOS ${tags.mac})  ${h.text}`);
    bad++;
  }
}
console.log(bad ? `FAIL ${bad} stale tag(s) in ${checked} public files` : `OK   ${checked} public files name only ${tags.current} (macOS ${tags.mac}) as the install tag`);
process.exit(bad ? 1 : 0);
