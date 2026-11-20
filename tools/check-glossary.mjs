// ─── check-glossary.mjs ───
// Every backticked term and JSON field on the page (AGENTS.md), in docs/AGENT-COMMANDS.md, and on the Path B pages
// (docs/DIRECT.md, docs/BUILD-YOUR-OWN-CLIENT.md: their own table terms, other tools and upstream program names aside) must be
// defined in GLOSSARY.md. Text only: it reads three files and never runs the CLI.
//
//   node tools/check-glossary.mjs [--root DIR] [--src DEVNET_DVPN_DIR] [--require-src] [--page codes|commands]
//
// Codes (with --src, or DVPN_SRC, or <root>/../devnet-dvpn when it exists): every failure code reachable
// from the app's src/cli/agent-cmd.ts (its own fail() codes, connect()'s CONNECT_CODES, the plain service/RPC copy,
// runSettlement's codes) and from the follow-up commands it names (settle, device, wallet) must have a row on
// the page: docs/CODES.md (default when it exists) or the failure tables of docs/AGENT-COMMANDS.md
// (--page commands). On docs/CODES.md each row must fill every cell, and an agent row's money class must
// equal src/cli/money-note.ts. Each edge is only followed while agent-cmd.ts still holds the call that makes it
// reachable (a guard); a guard that no longer matches exits 4 (re-trace by hand). With no source found the
// code check is skipped and says so; --require-src makes that exit 4.
//
// What counts as a term: a backticked span that is one word (letters, digits, `_`, `-`, dots between
// words) or a JSON key inside a span (`"key":`). Not counted: spans in code fences, file names
// (.md .sh .json …), numbers and versions, anything with a space or `/` or `--`.
// Defined = in GLOSSARY.md, on a line `- **term** (`alias`, …) — meaning`: the bold term (split on `/` and `,`)
// and every backticked alias before the ` — `. Or = a failure code in the failure-code tables of
// docs/AGENT-COMMANDS.md (those tables are their definition). Or = in ALLOW below.
//
// Exit: 0 ok · 1 an undefined term · 4 the checker failed its own control (do not trust it).
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// ─── Words that are syntax or names of other tools, not terms of ours ───
const ALLOW = new Set([
  'true', 'false', 'null', 'on', 'off', 'any', 'sudo', 'x64', 'arm64', 'aarch64',
  // internal source names in AGENT-COMMANDS.md's preamble: docs/ENGLISH-REVIEW.md asks for them to go
  'connect_codes', 'daemonerrorcopy',
]);
const FILE_EXT = /\.(md|sh|ps1|exe|json|ts|js|mjs|txt|cmd|deb|rpm|dmg)$/i;
const WORD = /^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z][A-Za-z0-9_-]*)*$/;

// ─── Terms defined by GLOSSARY.md ───
export function definedTerms(glossary) {
  const set = new Set();
  for (const line of glossary.split('\n')) {
    if (!line.startsWith('- **')) continue;
    const head = line.split(' — ')[0];
    for (const m of head.matchAll(/\*\*([^*]+)\*\*/g)) {
      for (const p of m[1].split(/[/,]/)) set.add(p.trim().toLowerCase());
    }
    for (const m of head.matchAll(/`([^`]+)`/g)) set.add(m[1].trim().toLowerCase());
  }
  return set;
}

// ─── Failure codes: the first cell of every table row from "## Failure codes" on ───
export function failureCodes(commandsDoc) {
  const set = new Set();
  let inFail = false;
  for (const line of commandsDoc.split('\n')) {
    if (/^## Failure codes/.test(line)) inFail = true;
    if (inFail && line.startsWith('|')) {
      const cell = line.split('|')[1] ?? '';
      for (const m of cell.matchAll(/`([^`]+)`/g)) set.add(m[1].trim().toLowerCase());
    }
  }
  return set;
}

// ─── Candidate terms of a text: [{ term, line }]. A paragraph is joined first, so a span that
// wraps over two lines is one span. stopAtFail: stop at "## Failure codes" (those tables define codes). ───
export function candidates(text, stopAtFail) {
  const out = [];
  const lines = text.split('\n');
  let fence = false;
  let para = [];
  let start = 0;
  const flush = () => {
    if (para.length === 0) return;
    const joined = para.join(' ');
    for (const m of joined.matchAll(/`([^`]+)`/g)) {
      const span = m[1].trim();
      for (const k of span.matchAll(/"([A-Za-z][A-Za-z0-9_]*)"\s*:/g)) out.push({ term: k[1], line: start });
      const t = span.replace(/^"|"$/g, '');
      if (WORD.test(t) && !FILE_EXT.test(t)) out.push({ term: t, line: start });
    }
    para = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (stopAtFail && /^## Failure codes/.test(line)) { flush(); break; }
    if (/^```/.test(line)) { flush(); fence = !fence; continue; }
    if (fence) continue;
    if (line.trim() === '' || /^#/.test(line)) { flush(); continue; }
    if (para.length === 0) start = i + 1;
    para.push(line);
  }
  flush();
  return out;
}

export function undefinedTerms(text, stopAtFail, defined, codes) {
  return candidates(text, stopAtFail).filter(({ term }) => {
    const k = term.toLowerCase();
    return !defined.has(k) && !codes.has(k) && !ALLOW.has(k);
  });
}

// ─── Self-control: a planted unknown term is caught, a defined one and a code pass ───
function control() {
  const gl = '- **widget** (`gizmo`) — a thing. Shows: `x`.\n- **a / b** — two.\n';
  const defined = definedTerms(gl);
  const codes = new Set(['some-code']);
  const text = 'Uses `widget`, `gizmo`, `a`, `b`, `some-code`, `true`, `file.json` and `"gizmo":1`.\n\nBut `plantedterm` and `"plantedkey":` are not in it.\n```sh\n`insidefence`\n```\n';
  const bad = undefinedTerms(text, false, defined, codes).map((c) => c.term).sort();
  if (bad.join() !== 'plantedkey,plantedterm') {
    console.error(`FAIL control: wanted plantedkey,plantedterm, got ${bad.join() || '(none)'}`);
    process.exit(4);
  }
  const wrap = undefinedTerms('A span `widget\nthat wraps` and `gizmo`.\n', false, defined, codes);
  if (wrap.some((c) => c.term === 'of')) { console.error('FAIL control: a wrapped span was split'); process.exit(4); }
}

// ─── Reachable failure codes, read from the app's source as text (it never runs the CLI) ───
const CODE = '[a-z][a-z0-9_-]*';

/** The source of one exported function, up to the next top-level export; null when it is not there. */
export function fnBody(src, name) {
  const i = src.search(new RegExp(`export (?:async )?function ${name}\\(`));
  if (i < 0) return null;
  const j = src.indexOf('\nexport ', i + 1);
  return src.slice(i, j < 0 ? undefined : j);
}

/** `code: 'a'` and `code: 'a' | 'b'` literals. */
export function codeLiterals(src) {
  const out = new Set();
  for (const m of src.matchAll(new RegExp(`\\bcode: ('${CODE}'(?:\\s*\\|\\s*'${CODE}')*)`, 'g'))) {
    for (const q of m[1].matchAll(new RegExp(`'(${CODE})'`, 'g'))) out.add(q[1]);
  }
  return out;
}

/** agent-cmd.ts's own codes: code literals, fail(…, 'x', …) on one line, `?? 'x'` and `? 'x' :` fallbacks. */
export function ownCodes(agentCmd) {
  const out = codeLiterals(agentCmd);
  for (const line of agentCmd.split('\n')) {
    const f = new RegExp(`\\bfail\\(.*?,\\s*'(${CODE})'`).exec(line);
    if (f) out.add(f[1]);
  }
  // Guarded (rc.6 gate): a `?? 'x'` fallback counts only after a `code` (`r.code ?? 'connect-failed'`), and a
  // `? 'x' :` ternary only on a line that calls fail( or names a code. `owner ?? 'none'` and `a._[1] ?? 'status'`
  // are a printed word and the default subcommand, not codes.
  for (const m of agentCmd.matchAll(new RegExp(`\\bcode \\?\\?\\s*'(${CODE})'`, 'g'))) out.add(m[1]);
  for (const line of agentCmd.split('\n')) {
    if (!/\bfail\(|\bcode\b/.test(line)) continue;
    for (const m of line.matchAll(new RegExp(`\\? '(${CODE})' :`, 'g'))) out.add(m[1]);
  }
  return out;
}

const quotedIn = (s) => [...s.replace(/\/\/[^\n]*/g, '').matchAll(/'([^']+)'/g)].map((m) => m[1]);

/** CONNECT_CODES of state.ts, with ...PREFLIGHT_CODES expanded; null when the lists are not found. */
export function connectCodes(state) {
  const pre = /PREFLIGHT_CODES = \[([^\]]*)\]/.exec(state);
  const all = /CONNECT_CODES: readonly string\[\] = \[([\s\S]*?)\];/.exec(state);
  if (!pre || !all) return null;
  const out = quotedIn(all[1]);
  if (/\.\.\.PREFLIGHT_CODES/.test(all[1])) out.push(...quotedIn(pre[1]));
  return out;
}

/** money-note.ts as a function code -> class, in moneyOf's order (none, open, refund, else unclear). */
export function moneyClasses(moneyNote, state) {
  const pre = /PREFLIGHT_CODES = \[([^\]]*)\]/.exec(state);
  const list = (name) => {
    const m = new RegExp(`const ${name}: readonly string\\[\\] = \\[([\\s\\S]*?)\\];`).exec(moneyNote);
    if (!m) return null;
    const out = quotedIn(m[1]);
    if (/\.\.\.PREFLIGHT_CODES/.test(m[1]) && pre) out.push(...quotedIn(pre[1]));
    return out;
  };
  const cls = new Map();
  for (const [k, name] of [['none', 'NONE'], ['open', 'OPEN'], ['refund', 'REFUND']]) {
    const a = list(name);
    if (!a) return null;
    for (const c of a) if (!cls.has(c)) cls.set(c, k);
  }
  return (code) => cls.get(code) ?? 'unclear';
}

/** Codes a follow-up command answers that are not failures (exit 0 or a usage error). */
const NOT_FAILURE = new Map([['nothing', 'settle withdraw prints "Nothing to withdraw" with exit 0']]);

/**
 * Every code reachable from agent-cmd.ts and the follow-ups it names. files: { rel path -> text }.
 * Returns { codes: Map code -> where, broken: [why] }. `broken` = a guard no longer matches: re-trace.
 */
export function reachableCodes(files) {
  const codes = new Map();
  const broken = [];
  const add = (set, where) => { for (const c of set) if (!codes.has(c) && !NOT_FAILURE.has(c)) codes.set(c, where); };
  const need = (file, re, why) => {
    const t = files[file];
    if (t == null) { broken.push(`${file} not found (${why})`); return false; }
    if (!re.test(t)) { broken.push(`${file}: no ${re} (${why})`); return false; }
    return true;
  };
  const ac = files['src/cli/agent-cmd.ts'];
  if (ac == null) return { codes, broken: ['src/cli/agent-cmd.ts not found'] };
  add(ownCodes(ac), 'agent-cmd.ts');
  // agent up -> connect(): its Result code goes out as is.
  if (need('src/cli/agent-cmd.ts', /await connect\(\{/, 'agent up calls connect()') && need('src/cli/agent-cmd.ts', /r\.code \?\? 'connect-failed'/, 'agent up forwards connect()\'s code')) {
    const cc = connectCodes(files['src/core/session/state.ts'] ?? '');
    if (!cc) broken.push('src/core/session/state.ts: CONNECT_CODES / PREFLIGHT_CODES not found'); else add(cc, 'connect() CONNECT_CODES');
  }
  // agent down -> disconnect(): its failure goes through daemonErrorCopy / rpcUnavailableCopy, else e.code.
  if (need('src/cli/agent-cmd.ts', /disconnectCmd\(/, 'agent down runs disconnect')) {
    const dis = fnBody(files['src/main/services/connection.ts'] ?? '', 'disconnect');
    if (!dis) broken.push('src/main/services/connection.ts: disconnect() not found'); else add(codeLiterals(dis), 'disconnect()');
  }
  if (need('src/cli/agent-cmd.ts', /daemonErrorCopy\(e\.message\)/, 'agent down maps a service error')) add(codeLiterals(files['src/core/daemon/link-copy.ts'] ?? ''), 'daemonErrorCopy');
  // agent down -> runSettlement(): its code, else settle-failed.
  if (need('src/cli/agent-cmd.ts', /await runSettlement\(\)/, 'agent down settles') && need('src/cli/agent-cmd.ts', /r\.code \?\? 'settle-failed'/, 'agent down forwards the settle code')) {
    const rs = fnBody(files['src/main/services/settlement.ts'] ?? '', 'runSettlement');
    if (!rs) broken.push('src/main/services/settlement.ts: runSettlement() not found'); else add(codeLiterals(rs), 'runSettlement()');
  }
  // Any agent command: index.ts -> plainError replaces a raw service / RPC failure.
  if (need('src/cli/error-out.ts', /daemonErrorCopy\(e\.message\)/, 'plainError maps a service error') && need('src/cli/error-out.ts', /code: 'rpc-unavailable'/, 'plainError maps an RPC failure')) {
    add(codeLiterals(files['src/core/daemon/link-copy.ts'] ?? ''), 'plainError');
    add(['rpc-unavailable'], 'plainError');
  }
  // The follow-ups the answers name: settle run / withdraw, device setup / switch / revoke / register, wallet send.
  add(codeLiterals(files['src/main/wallet/vault.ts'] ?? ''), 'noWallet (settle, device switch)');
  for (const fn of ['runSettlement', 'withdraw']) {
    const b = fnBody(files['src/main/services/settlement.ts'] ?? '', fn);
    if (!b) broken.push(`src/main/services/settlement.ts: ${fn}() not found`); else add(codeLiterals(b), `settle (${fn})`);
  }
  for (const fn of ['deviceSetupPlan', 'deviceSetup', 'revokeDeviceAccess', 'revokeOtherDevice', 'switchWallet', 'send']) {
    const b = fnBody(files['src/main/services/wallet.ts'] ?? '', fn);
    if (!b) broken.push(`src/main/services/wallet.ts: ${fn}() not found`); else add(codeLiterals(b), `device / wallet (${fn})`);
  }
  const cmds = files['src/cli/commands.ts'] ?? '';
  add(codeLiterals(cmds), 'commands.ts');
  for (const m of cmds.matchAll(new RegExp(`code: [\\w.?]+ \\?\\? '(${CODE})'`, 'g'))) add([m[1]], 'commands.ts');
  if (!/r\.code === 'nothing'/.test(cmds)) broken.push('src/cli/commands.ts: settle withdraw no longer turns \'nothing\' into exit 0');
  // rc.7 (R2): every cliErr('code', next, message) in src/cli is a code an agent can see, on any command (docUrl).
  for (const f of CLIERR_FILES) {
    const t = files[f];
    if (t == null) continue; // rc.6 and older have no cliErr
    for (const m of t.matchAll(new RegExp(`\\bcliErr\\(\\s*(?:[^,']*\\? )?'(${CODE})'(?: : '(${CODE})')?`, 'g'))) add([m[1], m[2]].filter(Boolean), `${f.replace('src/cli/', '')} (cliErr)`);
  }
  // Anchors: a parser that lost its way returns far fewer codes.
  for (const a of ['no-nodes', 'node-refused', 'connect-failed', 'unknown', 'daemon-gone', 'rpc-unavailable', 'cannot cover the prepay']) {
    if (!codes.has(a)) broken.push(`anchor code '${a}' not found: the source changed or the parser broke`);
  }
  return { codes, broken };
}

// ─── The page: rows of docs/CODES.md ───
const splitRow = (line) => line.replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map((c) => c.trim());

/** [{ line, section, codes, cells, header }]: every body row of every table. */
export function pageRows(md) {
  const rows = [];
  let section = '';
  let header = null;
  md.split('\n').forEach((line, i) => {
    if (/^## /.test(line)) { section = line.slice(3).trim(); header = null; return; }
    if (!line.startsWith('|')) { header = null; return; }
    const cells = splitRow(line);
    if (!header) { header = cells; return; }
    if (cells.every((c) => /^:?-+:?$/.test(c))) return;
    const codes = [...(cells[0] ?? '').matchAll(/`([^`]+)`/g)].map((m) => m[1].trim()).filter((c) => !c.includes(':'));
    const anchors = [...line.matchAll(/<a id="code-([^"]+)"><\/a>/g)].map((m) => m[1]);
    rows.push({ line: i + 1, section, codes, cells, header, anchors });
  });
  return rows;
}

/** Problems with the page against the reachable codes: [string]. moneyOf null = no money check. */
export function checkCodes(reachable, rows, moneyOf) {
  const problems = [];
  const onPage = new Set(rows.flatMap((r) => r.codes));
  for (const [c, where] of reachable) if (!onPage.has(c)) problems.push(`\`${c}\` (from ${where}) has no row`);
  // S5: each code has exactly one stable anchor <a id="code-<code>"></a>, so a docUrl can point at its row.
  const anchorCount = new Map();
  for (const r of rows) for (const a of r.anchors ?? []) anchorCount.set(a, (anchorCount.get(a) ?? 0) + 1);
  for (const [c] of reachable) if (onPage.has(c) && !anchorCount.has(c)) problems.push(`\`${c}\` has no anchor <a id="code-${c}"></a>`);
  for (const [a, n] of anchorCount) if (n > 1) problems.push(`anchor code-${a} appears ${n} times`);
  for (const r of rows) {
    r.cells.forEach((c, k) => { if (c === '') problems.push(`line ${r.line}: empty "${r.header[k] ?? k}" cell`); });
    if (r.cells.length !== r.header.length) problems.push(`line ${r.line}: ${r.cells.length} cells, header has ${r.header.length}`);
    const mi = r.header.findIndex((h) => /^Money/.test(h));
    if (!moneyOf || mi < 0 || !/^(agent|Any of the three)/.test(r.section)) continue;
    // A part may name one class per release (`unclear` on rc5 · rc.6: `refund`): the source's class must be one of them.
    const cell = r.cells[mi] ?? '';
    const parts = cell.split(' / ');
    const per = parts.length === r.codes.length ? parts : r.codes.map(() => cell);
    r.codes.forEach((code, k) => {
      const named = [...per[k].matchAll(/`(none|open|unclear|refund)`/g)].map((m) => m[1]);
      const got = named.length ? named : [per[k].replace(/`/g, '').trim().split(/[\s(:]/)[0]];
      const want = moneyOf(code);
      if (!got.includes(want)) problems.push(`line ${r.line}: \`${code}\` money says ${got.join(' or ')}, money-note.ts answers ${want}`);
    });
  }
  return problems;
}

// ─── Self-control for the code check: a planted missing code, wrong class and empty cell fail; a full page passes ───
function codeControl() {
  const files = {
    'src/cli/agent-cmd.ts': [
      "fail('No x.', 'planted-own', 'n');",
      'const r = await connect({ node });',
      "fail(r.error ?? 'Connect failed.', open && generic ? 'node-refused' : r.code ?? 'connect-failed', next);",
      "fail('A', dc?.code ?? (rpc ? 'rpc-unavailable' : e.code ?? 'stop-failed'), `n`); disconnectCmd(a); daemonErrorCopy(e.message);",
      "const r = await runSettlement(); fail(r.error ?? 'S.', r.code ?? 'settle-failed', `n`);",
      // Negative control (rc.6 gate false positives): none of these is a code, so none may be extracted.
      "o.print(`Wallet ${owner ?? 'none'}`); const sub = a._[1] ?? 'status'; const ip = r.exitIp ?? 'planted-ip';",
      "const word = wholeDevice ? 'planted-ternary' : 'x';",
    ].join('\n'),
    'src/core/session/state.ts': "export const PREFLIGHT_CODES = ['pf-a'] as const;\nexport const CONNECT_CODES: readonly string[] = [\n  // a node's own (x)\n  'c-b', ...PREFLIGHT_CODES, 'cannot cover the prepay', 'unknown', 'no-nodes',\n];\n",
    'src/main/services/connection.ts': "export async function disconnect() { return { code: 'dis-c' }; }\n",
    'src/core/daemon/link-copy.ts': "return { code: 'svc-d', message: '' };",
    'src/cli/error-out.ts': "daemonErrorCopy(e.message); { code: 'rpc-unavailable' }",
    'src/main/services/settlement.ts': "export async function runSettlement() { return { code: 'daemon-gone' }; }\nexport async function withdraw() { return { code: 'nothing' }; }\n",
    'src/main/services/wallet.ts': ['deviceSetupPlan', 'deviceSetup', 'revokeDeviceAccess', 'revokeOtherDevice', 'switchWallet', 'send'].map((f) => `export async function ${f}() { return {}; }`).join('\n'),
    'src/main/wallet/vault.ts': "export function noWallet(): { code: 'no-wallet' | 'keyfile-missing' } {}",
    'src/cli/commands.ts': "if (r.code === 'nothing') ok(); throw Object.assign(e, { code: r.code ?? 'switch-failed' });",
    // rc.7: cliErr codes in a non-agent file count, a ternary names two; a function definition does not.
    'src/cli/daemon-cmd.ts': "throw cliErr('planted-clierr', `n`, 'm'); throw cliErr(cur.missing ? 'planted-ca' : 'planted-cb', `n`, m);\nexport function cliErr(code: string) {}",
  };
  const { codes, broken } = reachableCodes(files);
  const want = ['cannot cover the prepay', 'c-b', 'connect-failed', 'daemon-gone', 'dis-c', 'keyfile-missing', 'no-nodes', 'no-wallet', 'node-refused', 'pf-a', 'planted-ca', 'planted-cb', 'planted-clierr', 'planted-own', 'rpc-unavailable', 'settle-failed', 'stop-failed', 'svc-d', 'switch-failed', 'unknown'].sort();
  const got = [...codes.keys()].sort();
  const leaked = ['none', 'status', 'planted-ip', 'planted-ternary'].filter((c) => codes.has(c));
  if (leaked.length) { console.error(`FAIL code control: non-codes extracted as codes: ${leaked.join(', ')}`); process.exit(4); }
  if (broken.length || got.join() !== want.join()) {
    console.error(`FAIL code control: extraction wanted ${want.join()}, got ${got.join()}${broken.length ? ` · broken: ${broken.join('; ')}` : ''}`);
    process.exit(4);
  }
  const moneyOf = (c) => (c === 'node-refused' ? 'open' : 'none');
  const head = '## agent up\n\n| Code | Meaning | Money moved? | Next | alsoNext |\n|---|---|---|---|---|\n';
  const row = (c, m = 'none', meaning = 'm') => `| <a id="code-${c}"></a>\`${c}\` | ${meaning} | \`${m}\` | n | a |\n`;
  const full = head + want.map((c) => row(c, moneyOf(c))).join('');
  const neg = checkCodes(codes, pageRows(full), moneyOf);
  if (neg.length) { console.error(`FAIL code control: a full page should pass, got ${neg.join('; ')}`); process.exit(4); }
  const missing = checkCodes(codes, pageRows(full.replace(row('c-b'), '')), moneyOf);
  if (missing.length !== 1 || !missing[0].includes('`c-b`')) { console.error(`FAIL code control: planted missing c-b not caught exactly (${missing.join('; ') || 'none'})`); process.exit(4); }
  const wrong = checkCodes(codes, pageRows(full.replace(row('node-refused', 'open'), row('node-refused', 'none'))), moneyOf);
  if (wrong.length !== 1 || !wrong[0].includes('node-refused')) { console.error(`FAIL code control: planted wrong money class not caught (${wrong.join('; ') || 'none'})`); process.exit(4); }
  const empty = checkCodes(codes, pageRows(full.replace(row('pf-a'), row('pf-a', 'none', ''))), moneyOf);
  if (empty.length !== 1 || !empty[0].includes('empty')) { console.error(`FAIL code control: planted empty cell not caught (${empty.join('; ') || 'none'})`); process.exit(4); }
  const noAnchor = checkCodes(codes, pageRows(full.replace('<a id="code-svc-d"></a>', '')), moneyOf);
  if (noAnchor.length !== 1 || !noAnchor[0].includes('code-svc-d')) { console.error(`FAIL code control: planted missing anchor not caught exactly (${noAnchor.join('; ') || 'none'})`); process.exit(4); }
  const noClierr = checkCodes(codes, pageRows(full.replace(row('planted-clierr'), '')), moneyOf);
  if (noClierr.length !== 1 || !noClierr[0].includes('`planted-clierr` (from daemon-cmd.ts (cliErr))')) { console.error(`FAIL code control: planted cliErr code with no row not caught exactly (${noClierr.join('; ') || 'none'})`); process.exit(4); }
  const dupAnchor = checkCodes(codes, pageRows(full.replace(row('dis-c'), row('dis-c').replace('<a id="code-dis-c"></a>', '<a id="code-dis-c"></a><a id="code-svc-d"></a>'))), moneyOf);
  if (dupAnchor.length !== 1 || !dupAnchor[0].includes('code-svc-d appears 2 times')) { console.error(`FAIL code control: planted duplicate anchor not caught exactly (${dupAnchor.join('; ') || 'none'})`); process.exit(4); }
  // A per-release cell passes when it names the source's class, and fails when it names only others.
  const rel = (m) => checkCodes(codes, pageRows(full.replace(row('node-refused', 'open'), `| <a id="code-node-refused"></a>\`node-refused\` | m | ${m} | n | a |\n`)), moneyOf);
  if (rel('`unclear` on rc5 · rc.6: `open`').length) { console.error('FAIL code control: a per-release money cell naming the right class failed'); process.exit(4); }
  if (rel('`unclear` on rc5 · rc.6: `refund`').length !== 1) { console.error('FAIL code control: a per-release money cell with no right class passed'); process.exit(4); }
}

/** Files whose cliErr('code', …) calls are codes too (rc.7). Missing files are skipped: older sources have none. */
const CLIERR_FILES = ['src/cli/commands.ts', 'src/cli/daemon-cmd.ts', 'src/cli/info-cmd.ts', 'src/cli/keystore.ts', 'src/cli/test-cmd.ts', 'src/cli/agent-cmd.ts', 'src/cli/status-cmd.ts', 'src/cli/index.ts'];

const SRC_FILES = ['src/cli/agent-cmd.ts', 'src/core/session/state.ts', 'src/main/services/connection.ts', 'src/core/daemon/link-copy.ts',
  'src/cli/error-out.ts', 'src/main/services/settlement.ts', 'src/main/services/wallet.ts', 'src/main/wallet/vault.ts', 'src/cli/commands.ts', 'src/cli/money-note.ts', ...CLIERR_FILES.filter((f) => !['src/cli/commands.ts', 'src/cli/agent-cmd.ts'].includes(f))];

/** The code check. Returns the count of problems; exits 4 when the source cannot be traced. */
function runCodeCheck(root, opts) {
  const src = opts.src ?? process.env.DVPN_SRC ?? (existsSync(join(root, '..', 'devnet-dvpn', 'src', 'cli', 'agent-cmd.ts')) ? join(root, '..', 'devnet-dvpn') : null);
  if (!src || !existsSync(join(src, 'src', 'cli', 'agent-cmd.ts'))) {
    if (opts.requireSrc) { console.error(`FAIL: no devnet-dvpn source at ${src ?? '(none given)'}: pass --src <checkout>`); process.exit(4); }
    console.log('SKIP codes: no devnet-dvpn source (pass --src <checkout> to check every reachable code)');
    return 0;
  }
  const files = {};
  for (const f of SRC_FILES) { const p = join(src, f); files[f] = existsSync(p) ? readFileSync(p, 'utf8').replace(/\r/g, '') : null; }
  const { codes, broken } = reachableCodes(files);
  if (broken.length) { console.error(`FAIL: cannot trace the codes (re-trace by hand):\n  ${broken.join('\n  ')}`); process.exit(4); }
  const codesPage = join(root, 'docs', 'CODES.md');
  const page = opts.page ?? (existsSync(codesPage) ? 'codes' : 'commands');
  let problems;
  if (page === 'codes') {
    const moneyOf = moneyClasses(files['src/cli/money-note.ts'] ?? '', files['src/core/session/state.ts'] ?? '');
    if (!moneyOf) { console.error('FAIL: src/cli/money-note.ts lists not found (re-trace by hand)'); process.exit(4); }
    problems = checkCodes(codes, pageRows(readFileSync(codesPage, 'utf8').replace(/\r/g, '')), moneyOf);
  } else {
    const fc = failureCodes(readFileSync(join(root, 'docs', 'AGENT-COMMANDS.md'), 'utf8').replace(/\r/g, ''));
    problems = [...codes].filter(([c]) => !fc.has(c.toLowerCase())).map(([c, where]) => `\`${c}\` (from ${where}) has no row`);
  }
  const name = page === 'codes' ? 'docs/CODES.md' : 'docs/AGENT-COMMANDS.md';
  console.log(`codes: ${codes.size} reachable from ${src} (agent-cmd.ts and its follow-ups)`);
  if (!problems.length) { console.log(`OK   ${name} (every reachable code has a row and one anchor)`); return 0; }
  console.log(`FAIL ${name}`);
  for (const p of problems) console.log(`       ${name}: ${p}`);
  return problems.length;
}

/** Path B pages checked against GLOSSARY.md (each skipped when absent, so an older tree still runs). */
const PATH_B_PAGES = ['docs/DIRECT.md', 'docs/BUILD-YOUR-OWN-CLIENT.md'];

/** Other people's tools a Path B page tells you to run or install: names, not terms of ours. */
const PATH_B_TOOLS = new Set(['openssl', 'jq', 'curl', 'python3', 'usermod', 'resolvectl', 'sha256sum', 'make', 'git', 'go',
  'wireguard-tools', 'systemctl', 'journalctl', 'ip', 'wg', 'newgrp', 'apt-get', 'npx', 'tsx', 'node', 'npm']);

/**
 * The on-chain program's and the daemon's own names, which a Path B page quotes from their IDL / proto: snake_case
 * instructions and fields (`open_channel`, `rent_payer`), CamelCase errors and RPCs (`GraceNotElapsed`,
 * `StartSession`), `Account.field` (`Config.vault`), `PERM_*`, proto packages, base58 ids, and Go file names.
 * Our own terms keep other shapes (kebab-case codes, UPPER_SNAKE env vars, camelCase JSON fields), so they stay
 * checked. Path B pages only.
 */
export function upstreamName(term) {
  return /^[a-z][a-z0-9]*(_[a-z0-9]+)+$/.test(term)
    || /^[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+$/.test(term)
    || /^[A-Za-z][A-Za-z0-9]*\.[A-Za-z_][A-Za-z0-9_]*$/.test(term) && /[_A-Z]/.test(term.split('.')[1] + term[0])
    || /^PERM_[A-Z_]+$/.test(term)
    || /^sentinel\.daemon\.v1(\.[A-Za-z]+)?$/.test(term)
    || /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(term)
    || /^[\w-]+\.(go|mod|sum|proto|sock|log)$/.test(term);
}

/**
 * Terms a page defines itself: the backticked names in the first column of its tables (the error, code and step
 * tables are their own definitions, as AGENT-COMMANDS.md's failure tables are).
 */
export function tableDefined(text) {
  const out = new Set();
  for (const line of text.split('\n')) {
    const m = /^\|\s*([^|]+?)\s*\|/.exec(line);
    if (!m || /^-+$/.test(m[1].replace(/[\s:|]/g, ''))) continue;
    for (const t of m[1].matchAll(/`([^`]+)`/g)) out.add(t[1].replace(/\s*\(\d+\)$/, '').toLowerCase());
  }
  return out;
}

// ─── Self-control for the Path B pages: a Path B code with a CODES.md row passes, a planted term does not ───
function pathBControl(defined, allCodes, codesMdText) {
  // Positive: with CODES.md's Path B section present, its codes must have been read (else the parser lost them).
  if (/id="code-direct-/.test(codesMdText) && !['route-failed', 'download-failed', 'session-dropped'].every((c) => allCodes.has(c))) {
    console.error('FAIL Path B control: CODES.md has a Path B section but its codes were not read'); process.exit(4);
  }
  // Negative: a planted term on a Path B-shaped line is caught; a known Path B code beside it is not.
  const text = 'Run `sh direct/connect.sh`; on `route-failed` read the row. The `plantedpathbterm` is not defined.';
  const known = /id="code-direct-/.test(codesMdText) ? allCodes : new Set([...allCodes, 'route-failed']);
  const miss = undefinedTerms(text, false, defined, known).map((m) => m.term);
  if (miss.join() !== 'plantedpathbterm') { console.error(`FAIL Path B control: wanted plantedpathbterm, got ${miss.join() || '(none)'}`); process.exit(4); }
  // A table's first column defines its terms; a term only in another column, or in prose, does not.
  const tab = tableDefined('| `GraceNotElapsed` (6035) | `close-channel` too early |\n|---|---|\n| `x` / `y` | z |\nprose `plantedprose`\n');
  // Upstream names pass on a Path B page; our own shapes (a code, an env var, a JSON field, a word) never do.
  const up = ['open_channel', 'GraceNotElapsed', 'Config.vault', 'PERM_OPEN_CHANNEL', 'main.go'].filter((t) => !upstreamName(t));
  const ours = ['route-failed', 'MONEY_STATE', 'moneyNote', 'plantedpathbterm', 'UNITS'].filter((t) => upstreamName(t));
  if (up.length || ours.length) { console.error(`FAIL Path B control: upstream names not passed (${up.join()}) or ours passed (${ours.join()})`); process.exit(4); }
  if ([...tab].sort().join() !== 'gracenotelapsed,x,y') {
    console.error(`FAIL Path B control: table terms wrong: ${[...tab].join()}`); process.exit(4);
  }
}

function main() {
  const args = process.argv.slice(2);
  const here = dirname(fileURLToPath(import.meta.url));
  const val = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined; };
  const root = val('--root') ?? join(here, '..');
  control();
  codeControl();
  const glossary = readFileSync(join(root, 'GLOSSARY.md'), 'utf8').replace(/\r/g, '');
  const agents = readFileSync(join(root, 'AGENTS.md'), 'utf8').replace(/\r/g, '');
  const commands = readFileSync(join(root, 'docs', 'AGENT-COMMANDS.md'), 'utf8').replace(/\r/g, '');
  const defined = definedTerms(glossary);
  const codes = failureCodes(commands);
  if (defined.size < 50) { console.error(`FAIL: GLOSSARY.md defines only ${defined.size} terms (unreadable?)`); process.exit(1); }
  console.log(`control: OK · glossary ${defined.size} terms · ${codes.size} codes from AGENT-COMMANDS.md`);
  let bad = 0;
  // Path B (S13): DIRECT.md and BUILD-YOUR-OWN-CLIENT.md use the same glossary. A code is defined by its row in
  // docs/CODES.md (the app's and the `direct-` Path B section) as well as by AGENT-COMMANDS.md's tables.
  const pathB = PATH_B_PAGES.filter((p) => existsSync(join(root, p)));
  const codesMd = join(root, 'docs', 'CODES.md');
  const codesMdText = existsSync(codesMd) ? readFileSync(codesMd, 'utf8').replace(/\r/g, '') : '';
  const allCodes = new Set([...codes, ...pageRows(codesMdText).flatMap((r) => r.codes)]);
  pathBControl(defined, allCodes, codesMdText);
  const pages = [['AGENTS.md', agents, false, codes], ['docs/AGENT-COMMANDS.md', commands, true, codes],
    ...pathB.map((p) => {
      const t = readFileSync(join(root, p), 'utf8').replace(/\r/g, '');
      return [p, t, false, new Set([...allCodes, ...tableDefined(t), ...PATH_B_TOOLS]), true];
    })];
  for (const [name, text, stop, known, upstream] of pages) {
    const miss = undefinedTerms(text, stop, defined, known).filter(({ term }) => !(upstream && upstreamName(term)));
    if (miss.length === 0) { console.log(`OK   ${name}`); continue; }
    bad += miss.length;
    console.log(`FAIL ${name}`);
    for (const { term, line } of miss) console.log(`       ${name}:${line}  \`${term}\` is not in GLOSSARY.md`);
  }
  const page = val('--page');
  if (page && page !== 'codes' && page !== 'commands') { console.error('--page must be codes or commands'); process.exit(4); }
  bad += runCodeCheck(root, { src: val('--src'), requireSrc: args.includes('--require-src'), page });
  process.exit(bad > 0 ? 1 : 0);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
