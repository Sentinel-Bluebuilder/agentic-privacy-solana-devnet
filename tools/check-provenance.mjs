#!/usr/bin/env node
// ─── check-provenance.mjs: every hash a public page states equals the release's own SHA256SUMS ───
//
//   node tools/check-provenance.mjs --list [dir]              # the releases to fetch: "<owner>/<repo> <tag>" per line
//   node tools/check-provenance.mjs --fetch DIR [dir]         # gh release download each SHA256SUMS into DIR, then check
//   node tools/check-provenance.mjs --sums-dir DIR [dir]      # check against SHA256SUMS already in DIR (no network)
//   exit 0 every hash matches · 1 a mismatch, an asset the release does not list, or a release with no SHA256SUMS
//        3 usage · 4 the control failed
//
// What is checked (files from public-files.txt; [dir] = an export or a swap tree instead of this one):
//   - a table row naming an asset (`name`), a 64-hex hash and a `github.com/<owner>/<repo>/releases/tag/<tag>`
//     link: the hash must be that tag's SHA256SUMS line for that asset (PROVENANCE's app and direct-v1 rows);
//   - a SHA256SUMS-format line (`<hash>  <name>`, optional "(= <asset>)") naming an asset that a checked release
//     lists: the hash must match (DIRECT.md's and DIRECT-REFERENCE's direct-v1 blocks). A name no checked release
//     lists is a build-it-yourself output, not a release asset, and is counted, not checked;
//   - direct/SHA256SUMS (this repository's copy, which direct/install.sh checks against) must equal the direct-v1
//     release's lines for the same names.
// A stale real value (a hash from an earlier build of the same tag) is exactly what this catches; an unfilled slot
// is check-slots.mjs's job. SHA256SUMS files in DIR are named "<owner>__<repo>__<tag>.SHA256SUMS".
// A self-control runs first: a planted mismatch, an unlisted asset and an unpublished release must each fail, and a
// matching row must pass.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HUB = join(dirname(fileURLToPath(import.meta.url)), '..');

// ─── Parsing ───
const HEX = /\b([0-9a-f]{64})\b/;
const REL = /github\.com\/([\w.-]+)\/([\w.-]+)\/releases\/tag\/([\w.-]+)/;
const SUMLINE = /^\s*([0-9a-f]{64})\s+\*?(\S+)(?:\s+\(= ([^)\s]+)\))?/;

/** Rows of one page: [{line, asset, sha, rel: "owner/repo tag" | null}]. */
export function rowsIn(text) {
  const out = [];
  text.split('\n').forEach((l, i) => {
    const s = SUMLINE.exec(l);
    if (s) { out.push({ line: i + 1, asset: s[3] ?? s[2], sha: s[1], rel: null }); return; }
    const h = HEX.exec(l);
    const r = REL.exec(l);
    const a = /^\|\s*`([^`]+)`/.exec(l);
    if (h && r && a) out.push({ line: i + 1, asset: a[1], sha: h[1], rel: `${r[1]}/${r[2]} ${r[3]}` });
  });
  return out;
}

/** A SHA256SUMS text as Map(name -> sha). */
export function sumsOf(text) {
  const m = new Map();
  for (const l of text.split('\n')) { const s = SUMLINE.exec(l); if (s) m.set(s[2], s[1]); }
  return m;
}

/** Problems: rows against sums (Map "owner/repo tag" -> Map | null when the release has no SHA256SUMS). */
export function problems(rows, sums) {
  const out = [];
  let unchecked = 0;
  for (const r of rows) {
    if (r.rel) {
      const s = sums.get(r.rel);
      if (!s) { out.push(`${r.where}: ${r.asset}: release ${r.rel} has no SHA256SUMS (not published?)`); continue; }
      if (!s.has(r.asset)) { out.push(`${r.where}: ${r.asset}: not in ${r.rel}'s SHA256SUMS`); continue; }
      if (s.get(r.asset) !== r.sha) out.push(`${r.where}: ${r.asset}: page ${r.sha.slice(0, 12)}…, ${r.rel} ${s.get(r.asset).slice(0, 12)}…`);
      continue;
    }
    const hit = [...sums.entries()].filter(([, s]) => s && s.has(r.asset));
    if (!hit.length) { unchecked++; continue; }
    for (const [rel, s] of hit) if (s.get(r.asset) !== r.sha) out.push(`${r.where}: ${r.asset}: page ${r.sha.slice(0, 12)}…, ${rel} ${s.get(r.asset).slice(0, 12)}…`);
  }
  return { out, unchecked };
}

// ─── Self-control ───
{
  const A = 'a'.repeat(64), B = 'b'.repeat(64);
  const link = (tag) => `[${tag}](https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases/tag/${tag})`;
  const page = [
    `| \`app-1.deb\` | \`${A}\` | ${link('v1')} |`, // matches: pass
    `| \`app-1.rpm\` | \`${A}\` | ${link('v1')} |`, // stale real value: fail
    `| \`app-1.zip\` | \`${A}\` | ${link('v1')} |`, // not listed: fail
    `| \`app-2.deb\` | \`${A}\` | ${link('v2')} |`, // unpublished: fail
    `${A}  app-1.deb`, // sums line, matches: pass
    `${B}  tool-you-build.exe`, // not a release asset: counted only
  ].join('\n');
  const rows = rowsIn(page).map((r) => ({ ...r, where: `control:${r.line}` }));
  const sums = new Map([['Sentinel-Bluebuilder/sentinel-solana-dvpn-linux v1', sumsOf(`${A}  app-1.deb\n${B}  app-1.rpm\n`)]]);
  const { out, unchecked } = problems(rows, sums);
  const want = ['control:2', 'control:3', 'control:4'];
  const got = out.map((p) => p.split(':').slice(0, 2).join(':'));
  if (rows.length !== 6 || unchecked !== 1 || got.join() !== want.join()) {
    console.error(`FAIL control: rows ${rows.length}/6, unchecked ${unchecked}/1, failures ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
    process.exit(4);
  }
  console.log('control: OK (a stale hash, an unlisted asset and an unpublished release fail; matching rows pass)');
}

// ─── Arguments ───
const argv = process.argv.slice(2);
let mode = null, dir = null, root = HUB;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--list') mode = 'list';
  else if (a === '--fetch' || a === '--sums-dir') { mode = a.slice(2); dir = argv[++i]; if (!dir) { console.error(`usage: ${a} needs a directory`); process.exit(3); } }
  else if (a.startsWith('-')) { console.error(`usage: unknown option ${a}`); process.exit(3); }
  else root = a;
}
if (!mode) { console.error('usage: check-provenance.mjs --list | --fetch DIR | --sums-dir DIR  [tree]'); process.exit(3); }

// ─── Rows of every public page ───
const listFile = join(existsSync(join(root, 'public-files.txt')) ? root : HUB, 'public-files.txt');
const files = readFileSync(listFile, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
const SKIP = new Set(['tools/check-provenance.mjs', 'llms-full.txt', 'direct/SHA256SUMS']); // llms-full: a copy of the pages
const rows = [];
for (const rel of files) {
  if (SKIP.has(rel)) continue;
  const p = join(root, rel);
  if (!existsSync(p)) continue;
  for (const r of rowsIn(readFileSync(p, 'utf8'))) rows.push({ ...r, where: `${rel}:${r.line}` });
}
const releases = [...new Set(rows.filter((r) => r.rel).map((r) => r.rel))].sort();
if (mode === 'list') { for (const r of releases) console.log(r); process.exit(0); }

// ─── SHA256SUMS per release ───
const fileOf = (rel) => join(dir, `${rel.replace('/', '__').replace(' ', '__')}.SHA256SUMS`);
if (mode === 'fetch') {
  mkdirSync(dir, { recursive: true });
  for (const rel of releases) {
    const [repo, tag] = rel.split(' ');
    try {
      execFileSync('gh', ['release', 'download', tag, '-R', repo, '-p', 'SHA256SUMS', '-O', fileOf(rel), '--clobber'], { stdio: ['ignore', 'ignore', 'pipe'] });
    } catch (e) {
      console.log(`no SHA256SUMS fetched for ${rel}: ${String(e.stderr ?? e.message).trim().split('\n')[0]}`);
    }
  }
}
const sums = new Map(releases.map((rel) => [rel, existsSync(fileOf(rel)) ? sumsOf(readFileSync(fileOf(rel), 'utf8')) : null]));

// ─── Check ───
const { out, unchecked } = problems(rows, sums);
const directRel = releases.find((r) => / direct-v\d+$/.test(r));
const local = join(root, 'direct/SHA256SUMS');
if (directRel && existsSync(local)) {
  const s = sums.get(directRel);
  for (const [name, sha] of sumsOf(readFileSync(local, 'utf8'))) {
    if (!s) break;
    if (s.get(name) !== sha) out.push(`direct/SHA256SUMS: ${name}: ${sha.slice(0, 12)}…, ${directRel} ${(s.get(name) ?? 'not listed').slice(0, 12)}`);
  }
}
for (const p of out) console.log(`MISMATCH ${p}`);
const checked = rows.length - unchecked;
console.log(out.length
  ? `FAIL ${out.length} hash(es) on the pages differ from the release's SHA256SUMS (${checked} checked, ${releases.length} releases)`
  : `OK   ${checked} page hashes equal their release's SHA256SUMS (${releases.length} releases; ${unchecked} build-it-yourself lines not release assets)`);
process.exit(out.length ? 1 : 0);
