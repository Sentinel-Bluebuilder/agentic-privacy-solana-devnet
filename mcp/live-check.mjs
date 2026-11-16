#!/usr/bin/env node
// ─── MCP live check: the real server, the real CLI, real JSON-RPC over stdio ───
// By default it spends NOTHING: read-only tools, plus vpn_up WITHOUT yes (a preview).
// With --paid --yes (both, explicitly) it also runs ONE paid session through the MCP server:
// vpn_up {protocol, basis, units: 1, yes: true} → vpn_agent_status (connected) → vpn_down {yes: true}
// → vpn_agent_status (not connected). Unless vpn_up cleanly refused (an answer with a non-zero
// exit and no session), vpn_down runs: always when vpn_up gave no answer (it may still have
// connected and paid), otherwise when the status says connected or cannot be read. A down with
// nothing connected is harmless. It never calls vpn_connect / vpn_disconnect / vpn_settle.
// The paid session needs the agent commands (v0.3.0-rc.3 or newer).
//
//   node mcp/live-check.mjs --out <dir> [--bundle <devnet-dvpn.cjs>]
//   node mcp/live-check.mjs --out <dir> --paid --yes [--protocol wireguard] [--basis per_gb|per_hour]
//          [--max-price <tDVPN>]   highest price per unit of basis (vpn_up max_price); e.g. 0.01 keeps a quick pick off 50/GB nodes
//
// Needs: Node 22, devnet-dvpn installed and set up (AGENTS.md sections 1-4: funded wallet, device,
// service), DVPN_KEYFILE set in the environment. The paid session costs one deposit (per GB: about
// 0.002 tDVPN on devnet; unused part refunded after the two-hour close).
//
// Pass "installed": the installed devnet-dvpn, found as the server finds it (PATH; on macOS also
//   /usr/local/bin and the app bundle). Expected: the six CLI tools answer; vpn_agent_status /
//   vpn_up answer as the agent commands (rc.3 or newer) or, on v0.3.0-rc2, with the
//   "use vpn_nodes + vpn_connect" fallback.
// Pass "bundle" (only with --bundle): DEVNET_DVPN_BIN = that bundle, a `out/cli/devnet-dvpn.cjs`
//   built from source (an installed app's copy sits inside app.asar; plain Node cannot read it).
//   Expected: vpn_agent_status answers with `next`; vpn_up without yes = exit-2 preview (or exit 0
//   `reused` if a session is already live: agent up answers a live session without paying).
// The key comes from DVPN_KEYFILE in the environment (never an argument).
// Output: <dir>/mcp-live-<pass>.jsonl, one JSON line per call, plus mcp-live-summary.json.
// Exit 0 = every expectation met; 1 = a mismatch; 2 = bad usage.
// Imported (by the unit tests) it runs nothing: only the decision helpers are used.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdirSync, writeFileSync, appendFileSync, existsSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SERVER = join(HERE, 'server.js');
const CALL_TIMEOUT_MS = { default: 90_000, vpn_nodes: 150_000, vpn_up: 300_000 };
const ALLOWED = new Set(['vpn_status', 'vpn_wallet', 'vpn_nodes', 'vpn_agent_status', 'vpn_up']);
const BASE58 = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;

// ─── paid-session decisions (pure; exported for the unit tests) ───
// `up` / `status` are a tools/call result, or null when the call got no answer (timeout, error).
const sc = (r) => r?.structuredContent;

/** vpn_up answered and clearly did not connect: a real (numeric) non-zero exit and no session.
 *  An answer without an exit code (an MCP tool error, a server timeout) is NOT a clean refusal. */
export const upCleanlyRefused = (up) => up != null && typeof sc(up)?.exitCode === 'number' && sc(up).exitCode !== 0
  && typeof sc(up)?.result?.session !== 'string';

/** Whether to read the status after the paid vpn_up (everything but a clean refusal). */
export const checkAfterUp = (up) => !upCleanlyRefused(up);

/** Whether vpn_down must run, given the paid vpn_up and the status read after it. */
export const mustRunDown = (up, status) => {
  if (upCleanlyRefused(up)) return false;
  if (up == null) return true;                                   // no answer: it may have connected and paid
  if (sc(up)?.exitCode === 0 || typeof sc(up)?.result?.session === 'string') return true;
  return sc(status)?.result?.connected !== false;                // connected, or the status cannot be read
};

// ─── run-time settings (set by main) ───
let outDir;
let PAID = false;
let paidProtocol = 'wireguard';
let paidBasis = 'per_gb';
let paidMaxPrice; // --max-price: tDVPN per unit of basis, passed to vpn_up as max_price (unset = the CLI's own pick)
let passes = [];

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
const keep = (s) => {
  if (!s) return s;
  const r = s.result;
  if (Array.isArray(r)) return { ...s, result: { count: r.length, online: r.filter((n) => n?.probe?.ok).length, first: r.slice(0, 2) } };
  return s;
};

// ─── expectations ───
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const EXPECT = {
  vpn_status: (s) => s.exitCode === 0 && isObj(s.result) || 'exit 0 with a JSON object',
  vpn_wallet: (s) => s.exitCode === 0 && BASE58.test(s.result?.owner ?? '') && typeof s.result.ownerLamports === 'number' && typeof s.result.ownerTdvpn === 'string'
    || 'exit 0 with owner (base58), ownerLamports (number), ownerTdvpn (string)',
  vpn_nodes: (s) => s.exitCode === 0 && Array.isArray(s.result) && s.result.length > 0 || 'exit 0 with a non-empty node array',
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

// ─── the paid session (only with --paid --yes) ───
const PAID_TOOLS = new Set(['vpn_up', 'vpn_down']);
const PAID_EXPECT = {
  // Full-tunnel protocols must move the exit address; V2Ray / Xray may be a SOCKS proxy only.
  up: (r) => {
    const x = sc(r)?.result;
    if (!(sc(r)?.exitCode === 0 && x?.ok === true && typeof x.session === 'string' && r.isError === false)) return 'exit 0, ok true, a session (connected)';
    if (!['v2ray', 'xray'].includes(x.protocol) && typeof x.exitIp === 'string' && typeof x.directIp === 'string' && x.exitIp === x.directIp) {
      return `a full-tunnel protocol (${x.protocol}) with exitIp different from directIp`;
    }
    return true;
  },
  statusUp: (r) => (sc(r)?.exitCode === 0 && sc(r).result?.connected === true && typeof sc(r).result.node === 'string')
    || 'exit 0, connected true, a node',
  statusRead: (r) => (sc(r)?.exitCode === 0 && typeof sc(r).result?.connected === 'boolean') || 'exit 0 with connected true or false',
  down: (r) => (sc(r)?.exitCode === 0 && sc(r).result?.ok === true && r.isError === false)
    || 'exit 0, ok true (disconnected, refund started)',
  statusDown: (r) => (sc(r)?.exitCode === 0 && sc(r).result?.connected === false)
    || 'exit 0, connected false',
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

  // paidOk: only the paid steps may send yes, and only when --paid --yes was given.
  const call = async (name, args, check, step = name, paidOk = false) => {
    const spends = 'yes' in args || !ALLOWED.has(name);
    if (spends && !(paidOk && PAID && PAID_TOOLS.has(name))) throw new Error(`live-check refuses ${name} ${JSON.stringify(args)}: it may spend`);
    const [m, ms] = await timed(() => srv.request('tools/call', { name, arguments: args }, CALL_TIMEOUT_MS[name] ?? CALL_TIMEOUT_MS.default));
    if (m.timeout || m.error) { record(step, false, 'an answer', m, ms); return null; }
    const r = m.result;
    const verdict = check(r);
    record(step, verdict === true, verdict === true ? 'met' : verdict, { isError: r.isError, ...keep(r.structuredContent), text: r.content?.map((c) => c.text).join(' | ').slice(0, 1500) }, ms);
    return r;
  };
  const either = (a, b) => (r) => (a(r) === true || b(r) === true) || `${a(r)}; or ${b(r)}`;

  for (const name of ['vpn_status', 'vpn_wallet']) await call(name, {}, (r) => EXPECT[name](r.structuredContent));
  await call('vpn_nodes', {}, (r) => EXPECT.vpn_nodes(r.structuredContent));
  if (pass === 'installed') {
    // rc2: the fallback; rc.3 or newer: the agent commands themselves.
    await call('vpn_agent_status', {}, either(FALLBACK, BUNDLE_AGENT.vpn_agent_status));
    await call('vpn_up', {}, either(FALLBACK, BUNDLE_AGENT.vpn_up));
  } else {
    await call('vpn_agent_status', {}, BUNDLE_AGENT.vpn_agent_status);
    await call('vpn_up', {}, BUNDLE_AGENT.vpn_up);
  }

  // ─── the one paid session (last pass only, --paid --yes only) ───
  if (PAID && pass === passes[passes.length - 1][0]) {
    const up = await call('vpn_up', { protocol: paidProtocol, basis: paidBasis, units: 1, ...(paidMaxPrice ? { max_price: paidMaxPrice } : {}), yes: true }, PAID_EXPECT.up, 'paid/vpn_up', true);
    if (checkAfterUp(up)) {
      const connectedUp = up != null && sc(up)?.exitCode === 0;
      const status = await call('vpn_agent_status', {}, connectedUp ? PAID_EXPECT.statusUp : PAID_EXPECT.statusRead, 'paid/vpn_agent_status(after up)');
      if (mustRunDown(up, status)) {
        await call('vpn_down', { yes: true }, PAID_EXPECT.down, 'paid/vpn_down', true);
        await call('vpn_agent_status', {}, PAID_EXPECT.statusDown, 'paid/vpn_agent_status(after down)');
      }
    }
  }
  await srv.stop();
  const errTail = srv.stderr().trim();
  if (errTail) writeFileSync(join(outDir, `mcp-live-${pass}.stderr.txt`), errTail.slice(-20000));
  return results;
};

// ─── main ───
const main = async () => {
  const argv = process.argv.slice(2);
  const opt = (name) => { const i = argv.indexOf(`--${name}`); return i >= 0 ? argv[i + 1] : undefined; };
  outDir = opt('out');
  const bundle = opt('bundle');
  PAID = argv.includes('--paid');
  paidProtocol = opt('protocol') ?? 'wireguard';
  paidBasis = opt('basis') ?? 'per_gb';
  paidMaxPrice = opt('max-price');
  if (paidMaxPrice !== undefined && !/^\d+(\.\d{1,6})?$/.test(paidMaxPrice)) {
    process.stderr.write(`--max-price must be a tDVPN amount like 0.01, not ${paidMaxPrice}\n`);
    process.exit(2);
  }
  if (!outDir || argv.includes('--help')) {
    process.stderr.write('usage: node mcp/live-check.mjs --out <dir> [--bundle <devnet-dvpn.cjs>] [--paid --yes [--protocol P] [--basis per_gb|per_hour] [--max-price <tDVPN>]]\n');
    process.exit(2);
  }
  if (PAID && !argv.includes('--yes')) {
    process.stderr.write('--paid spends tDVPN: add --yes to confirm (nothing was run)\n');
    process.exit(2);
  }
  if (!['per_gb', 'per_hour'].includes(paidBasis)) {
    process.stderr.write(`--basis must be per_gb or per_hour, not ${paidBasis}\n`);
    process.exit(2);
  }
  if (bundle && !existsSync(bundle)) {
    process.stderr.write(`--bundle ${bundle} does not exist\n`);
    process.exit(2);
  }
  if (!process.env.DVPN_KEYFILE) process.stderr.write('note: DVPN_KEYFILE is not set; the CLI uses its own wallet store\n');
  mkdirSync(outDir, { recursive: true });

  const base = { ...process.env };
  delete base.DEVNET_DVPN_BIN; // pass "installed" must use what is on PATH
  passes = [['installed', base]];
  if (bundle) passes.push(['bundle', { ...base, DEVNET_DVPN_BIN: resolve(bundle) }]);

  const all = [];
  for (const [pass, env] of passes) all.push(...await runPass(pass, env));
  const failed = all.filter((r) => !r.ok).map((r) => `${r.pass}/${r.step}`);
  const summary = { at: new Date().toISOString(), node: process.version, passes: passes.map(([p]) => p), paid: PAID ? { protocol: paidProtocol, basis: paidBasis, units: 1, maxPrice: paidMaxPrice ?? null } : false, calls: all.length, failed, ok: failed.length === 0 };
  writeFileSync(join(outDir, 'mcp-live-summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
  process.stdout.write(`${summary.ok ? 'OK' : 'FAILED'}  ${all.length} calls, ${failed.length} failed${failed.length ? `: ${failed.join(', ')}` : ''}\n`);
  process.exit(summary.ok ? 0 : 1);
};

// Real paths on both sides: a symlinked folder (macOS /tmp → /private/tmp) must still count as main.
const real = (p) => {
  try {
    return realpathSync(p);
  } catch (err) {
    process.stderr.write(`[live-check] cannot resolve ${p} (${err.message}); comparing it as given\n`);
    return resolve(p);
  }
};
const isMain = process.argv[1] != null && real(process.argv[1]) === real(fileURLToPath(import.meta.url));
if (isMain) await main();
