#!/usr/bin/env node
// ─── MCP live check: the real server, the real CLI, real JSON-RPC over stdio ───
// Spends NOTHING: it calls only read-only tools, plus vpn_up WITHOUT yes (a preview).
// It refuses to send `yes`, and never calls vpn_connect / vpn_disconnect / vpn_settle / vpn_down.
//
//   node mcp/live-check.mjs --out <dir> [--bundle <path to built devnet-dvpn.cjs>]
//
// Pass "installed": the installed devnet-dvpn, found as the server finds it (PATH; on macOS also
//   /usr/local/bin and the app bundle). Expected: the six CLI
//   tools answer; vpn_agent_status / vpn_up give the "use vpn_nodes + vpn_connect" fallback.
// Pass "bundle" (only with --bundle): DEVNET_DVPN_BIN = that bundle, a `out/cli/devnet-dvpn.cjs`
//   built from source (an installed app's copy sits inside app.asar; plain Node cannot read it). Expected: vpn_agent_status
//   answers with `next`; vpn_up without yes = exit-2 preview (or exit 0 `reused` if a session is
//   already live: agent up answers a live session without paying, agent-cmd.ts:112-121).
// The key comes from DVPN_KEYFILE in the environment (never an argument).
// Output: <dir>/mcp-live-<pass>.jsonl, one JSON line per call, plus mcp-live-summary.json.
// Exit 0 = every expectation met; 1 = a mismatch; 2 = bad usage.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdirSync, writeFileSync, appendFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SERVER = join(HERE, 'server.js');
const CALL_TIMEOUT_MS = { default: 90_000, vpn_nodes: 150_000, vpn_up: 300_000 };
const ALLOWED = new Set(['vpn_status', 'vpn_wallet', 'vpn_nodes', 'vpn_agent_status', 'vpn_up']);
const BASE58 = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;

// ─── args ───
const argv = process.argv.slice(2);
const opt = (name) => { const i = argv.indexOf(`--${name}`); return i >= 0 ? argv[i + 1] : undefined; };
const outDir = opt('out');
const bundle = opt('bundle');
if (!outDir || argv.includes('--help')) {
  process.stderr.write('usage: node mcp/live-check.mjs --out <dir> [--bundle <devnet-dvpn.cjs>]\n');
  process.exit(2);
}
if (bundle && !existsSync(bundle)) {
  process.stderr.write(`--bundle ${bundle} does not exist\n`);
  process.exit(2);
}
if (!process.env.DVPN_KEYFILE) process.stderr.write('note: DVPN_KEYFILE is not set; the CLI uses its own wallet store\n');
mkdirSync(outDir, { recursive: true });

// ─── one MCP client over stdio ───
const startServer = (env) => {
  const child = spawn(process.execPath, [SERVER], { env, stdio: ['pipe', 'pipe', 'pipe'] });
  const waiting = new Map();
  let stderr = '';
  child.stderr.setEncoding('utf8').on('data', (c) => { stderr += c; });
  createInterface({ input: child.stdout }).on('line', (line) => {
    let msg;
    try {
      msg = JSON.parse(line);
    } catch (err) {
      process.stderr.write(`[live-check] server wrote a non-JSON line (${err.message}): ${line.slice(0, 200)}\n`);
      return;
    }
    const w = waiting.get(msg.id);
    if (w) { waiting.delete(msg.id); w(msg); }
  });
  let nextId = 1;
  const request = (method, params, timeoutMs) => new Promise((done) => {
    const id = nextId++;
    const timer = setTimeout(() => { waiting.delete(id); done({ id, timeout: true }); }, timeoutMs);
    waiting.set(id, (m) => { clearTimeout(timer); done(m); });
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  });
  const notify = (method) => child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method })}\n`);
  const stop = () => new Promise((done) => { child.on('close', done); child.stdin.end(); setTimeout(() => child.kill(), 5000); });
  return { request, notify, stop, stderr: () => stderr };
};

// ─── what we keep of a result (node lists are long) ───
const keep = (sc) => {
  if (!sc) return sc;
  const r = sc.result;
  if (Array.isArray(r)) return { ...sc, result: { count: r.length, online: r.filter((n) => n?.probe?.ok).length, first: r.slice(0, 2) } };
  return sc;
};

// ─── expectations ───
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const EXPECT = {
  vpn_status: (sc) => sc.exitCode === 0 && isObj(sc.result) || 'exit 0 with a JSON object',
  vpn_wallet: (sc) => sc.exitCode === 0 && BASE58.test(sc.result?.owner ?? '') && typeof sc.result.ownerLamports === 'number' && typeof sc.result.ownerTdvpn === 'string'
    || 'exit 0 with owner (base58), ownerLamports (number), ownerTdvpn (string)',
  vpn_nodes: (sc) => sc.exitCode === 0 && Array.isArray(sc.result) && sc.result.length > 0 || 'exit 0 with a non-empty node array',
};
const FALLBACK = (r) => r.isError === true && /vpn_nodes/.test(r.content?.[0]?.text ?? '') && /vpn_connect/.test(r.content?.[0]?.text ?? '')
  || 'isError with the "use vpn_nodes + vpn_connect" fallback';
const BUNDLE_AGENT = {
  vpn_agent_status: (r) => r.structuredContent?.exitCode === 0 && r.structuredContent.result?.ok === true && typeof r.structuredContent.result.next === 'string'
    || 'exit 0, ok true, a `next` string',
  vpn_up: (r) => (r.structuredContent?.preview === true && r.structuredContent.exitCode === 2 && r.isError === false)
    || (r.structuredContent?.exitCode === 0 && r.structuredContent.result?.reused === true)
    // An unfunded wallet: the CLI refuses before paying, and says what to send in `action`.
    || (r.structuredContent?.exitCode === 1 && r.structuredContent.result?.code === 'not-funded'
      && typeof r.structuredContent.result.action === 'string' && r.structuredContent.result.action.length > 0)
    || 'exit-2 preview (isError false), exit 0 reused (already connected), or exit 1 not-funded with an action (unfunded wallet)',
};

// ─── one pass ───
const runPass = async (pass, env) => {
  const file = join(outDir, `mcp-live-${pass}.jsonl`);
  writeFileSync(file, '');
  const srv = startServer(env);
  const results = [];
  const record = (step, ok, expect, got, ms) => {
    const line = { at: new Date().toISOString(), pass, step, ok, expect, ms, got };
    appendFileSync(file, `${JSON.stringify(line)}\n`);
    results.push(line);
    process.stdout.write(`${ok ? 'PASS' : 'FAIL'}  ${pass}  ${step}${ok ? '' : `  (want: ${expect})`}\n`);
  };
  const timed = async (fn) => { const t = Date.now(); const v = await fn(); return [v, Date.now() - t]; };

  const [init, mi] = await timed(() => srv.request('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'live-check', version: '1' } }, 15_000));
  record('initialize', init.result?.serverInfo?.name === 'agentic-privacy', 'serverInfo.name agentic-privacy', init.result ?? init, mi);
  srv.notify('notifications/initialized');

  const [list, ml] = await timed(() => srv.request('tools/list', {}, 15_000));
  const names = list.result?.tools?.map((t) => t.name) ?? [];
  record('tools/list', names.length === 9, '9 tools', { names }, ml);

  const call = async (name, args, check) => {
    if (!ALLOWED.has(name) || 'yes' in args) throw new Error(`live-check refuses ${name} ${JSON.stringify(args)}: it may spend`);
    const [m, ms] = await timed(() => srv.request('tools/call', { name, arguments: args }, CALL_TIMEOUT_MS[name] ?? CALL_TIMEOUT_MS.default));
    if (m.timeout || m.error) { record(name, false, 'an answer', m, ms); return; }
    const r = m.result;
    const verdict = check(r);
    record(name, verdict === true, verdict === true ? 'met' : verdict, { isError: r.isError, ...keep(r.structuredContent), text: r.content?.map((c) => c.text).join(' | ').slice(0, 1500) }, ms);
  };

  for (const name of ['vpn_status', 'vpn_wallet']) await call(name, {}, (r) => EXPECT[name](r.structuredContent));
  await call('vpn_nodes', {}, (r) => EXPECT.vpn_nodes(r.structuredContent));
  if (pass === 'installed') {
    await call('vpn_agent_status', {}, FALLBACK);
    await call('vpn_up', {}, FALLBACK);
  } else {
    await call('vpn_agent_status', {}, BUNDLE_AGENT.vpn_agent_status);
    await call('vpn_up', {}, BUNDLE_AGENT.vpn_up);
  }
  await srv.stop();
  const errTail = srv.stderr().trim();
  if (errTail) writeFileSync(join(outDir, `mcp-live-${pass}.stderr.txt`), errTail.slice(-20000));
  return results;
};

// ─── main ───
const base = { ...process.env };
delete base.DEVNET_DVPN_BIN; // pass "installed" must use what is on PATH
const passes = [['installed', base]];
if (bundle) passes.push(['bundle', { ...base, DEVNET_DVPN_BIN: resolve(bundle) }]);

const all = [];
for (const [pass, env] of passes) all.push(...await runPass(pass, env));
const failed = all.filter((r) => !r.ok).map((r) => `${r.pass}/${r.step}`);
const summary = { at: new Date().toISOString(), node: process.version, passes: passes.map(([p]) => p), calls: all.length, failed, ok: failed.length === 0 };
writeFileSync(join(outDir, 'mcp-live-summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
process.stdout.write(`${summary.ok ? 'OK' : 'FAILED'}  ${all.length} calls, ${failed.length} failed${failed.length ? `: ${failed.join(', ')}` : ''}\n`);
process.exit(summary.ok ? 0 : 1);
