// ─── MCP server unit tests ───────────────────────────────────────────────────
// node --test mcp/server.test.js   (Node 20 or newer; a bare `mcp/`
// directory argument fails on Node 22). No real CLI runs:
// spawn is replaced by a fake that records argv/env and replies with fixed output.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TOOLS, callTool, checkInput, handleMessage, resolveCli, serve } from './server.js';

const NODE = '6AaXvhZ1Q2w3e4r5t6y7u8i9o1p2a3s4d5f6g7h8j9k1';

const fakeSpawn = ({ stdout = '', stderr = '', code = 0 } = {}) => {
  const calls = [];
  const fn = (file, args, opts) => {
    calls.push({ file, args, opts });
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = () => {};
    setImmediate(() => {
      child.stdout.end(stdout);
      child.stderr.end(stderr);
      setImmediate(() => child.emit('close', code, null));
    });
    return child;
  };
  return { fn, calls };
};

const fakeInstall = (platform) => {
  const root = mkdtempSync(join(tmpdir(), 'ap-mcp-'));
  if (platform === 'win32') {
    mkdirSync(join(root, 'bin'));
    writeFileSync(join(root, 'bin', 'devnet-dvpn.cmd'), '@echo off\r\n');
    writeFileSync(join(root, 'Devnet dVPN.exe'), '');
    return { bin: join(root, 'bin', 'devnet-dvpn.cmd'), root };
  }
  writeFileSync(join(root, 'devnet-dvpn'), '#!/bin/sh\n');
  return { bin: join(root, 'devnet-dvpn'), root };
};

test('the six CLI tools plus the three agent tools, each with an object schema', () => {
  assert.deepEqual(TOOLS.map((t) => t.name), [
    'vpn_status', 'vpn_wallet', 'vpn_nodes', 'vpn_connect', 'vpn_disconnect', 'vpn_settle',
    'vpn_up', 'vpn_down', 'vpn_agent_status',
  ]);
  for (const t of TOOLS) assert.equal(t.inputSchema.type, 'object');
});

test('agent argv matches devnet-dvpn docs/CLI.md (agent up/down/status); --yes only on explicit consent', () => {
  const tool = (n) => TOOLS.find((t) => t.name === n);
  const argv = (n, input = {}) => tool(n).args(checkInput(tool(n), input));
  assert.deepEqual(argv('vpn_agent_status'), ['agent', 'status']);
  assert.deepEqual(argv('vpn_up'), ['agent', 'up']);
  assert.deepEqual(argv('vpn_up', { protocol: 'v2ray', country: 'de', basis: 'per_gb', units: 2, max_price: '0.5', yes: true }),
    ['agent', 'up', '--protocol', 'v2ray', '--country', 'DE', '--basis', 'per_gb', '--units', '2', '--max-price', '0.5', '--yes']);
  assert.deepEqual(argv('vpn_up', { node: NODE, yes: false }), ['agent', 'up', '--node', NODE]);
  assert.deepEqual(argv('vpn_down'), ['agent', 'down']);
  assert.deepEqual(argv('vpn_down', { yes: false }), ['agent', 'down']);
  assert.deepEqual(argv('vpn_down', { yes: true }), ['agent', 'down', '--yes']);
});

test('yes must be a real boolean: "true" (string) never becomes --yes', async () => {
  const s = fakeSpawn();
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  for (const yes of ['true', 1, 'yes']) {
    const r = await callTool('vpn_down', { yes }, { env, platform: 'linux', spawnFn: s.fn });
    assert.equal(r.isError, true);
  }
  const bad = await callTool('vpn_up', { max_price: '1e3' }, { env, platform: 'linux', spawnFn: s.fn });
  assert.equal(bad.isError, true);
  assert.equal(s.calls.length, 0);
});

test('exit 2 without yes is a preview, not an error; exit 2 elsewhere stays an error', async () => {
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  const s = fakeSpawn({ stdout: '{"node":"x","deposit":{"tdvpn":"1"}}\n', code: 2 });
  const r = await callTool('vpn_up', {}, { env, platform: 'linux', spawnFn: s.fn });
  assert.equal(r.isError, false);
  assert.equal(r.structuredContent.preview, true);
  assert.equal(r.structuredContent.exitCode, 2);
  assert.match(r.content.at(-1).text, /"yes": true/);
  const s2 = fakeSpawn({ stdout: '{"ok":false}\n', code: 2 });
  const r2 = await callTool('vpn_disconnect', {}, { env, platform: 'linux', spawnFn: s2.fn });
  assert.equal(r2.isError, true);
});

test('an older CLI without `agent` → clear fallback to vpn_nodes + vpn_connect', async () => {
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  for (const name of ['vpn_up', 'vpn_down', 'vpn_agent_status']) {
    const s = fakeSpawn({ stderr: 'unknown command: agent\n\nUsage: devnet-dvpn <command>\n', code: 3 });
    const r = await callTool(name, {}, { env, platform: 'linux', spawnFn: s.fn });
    assert.equal(r.isError, true, name);
    assert.equal(r.structuredContent.exitCode, 3);
    assert.match(r.content[0].text, /vpn_nodes/);
    assert.match(r.content[0].text, /vpn_connect/);
  }
  // A real usage error from a CLI that HAS agent is passed through, not turned into the fallback.
  const s = fakeSpawn({ stderr: 'unknown option --foo for "agent up"', code: 3 });
  const r = await callTool('vpn_up', {}, { env, platform: 'linux', spawnFn: s.fn });
  assert.doesNotMatch(r.content.map((c) => c.text).join(' '), /vpn_nodes/);
});

test('argv per tool matches docs/CLI.md of devnet-dvpn', () => {
  const argv = (name, input = {}) => TOOLS.find((t) => t.name === name).args(checkInput(TOOLS.find((t) => t.name === name), input));
  assert.deepEqual(argv('vpn_status'), ['status']);
  assert.deepEqual(argv('vpn_wallet'), ['wallet', 'show']);
  assert.deepEqual(argv('vpn_nodes', { country: 'de', protocol: 'wireguard', sort: 'price' }), ['nodes', 'list', '--online', '--country', 'DE', '--protocol', 'wireguard', '--sort', 'price']);
  assert.deepEqual(argv('vpn_connect', { node: NODE, basis: 'per_hour', units: 2, yes: true }), ['connect', NODE, '--basis', 'per_hour', '--units', '2', '--yes']);
  assert.deepEqual(argv('vpn_disconnect'), ['disconnect']);
  assert.deepEqual(argv('vpn_settle', { yes: true }), ['settle', 'run', '--yes']);
});

test('spending tools send --yes only with yes:true (connect, settle, up, down)', () => {
  const argv = (name, input = {}) => TOOLS.find((t) => t.name === name).args(checkInput(TOOLS.find((t) => t.name === name), input));
  for (const [name, input] of [['vpn_connect', { node: NODE }], ['vpn_settle', {}], ['vpn_up', {}], ['vpn_down', {}]]) {
    assert.equal(argv(name, input).includes('--yes'), false, `${name} without yes`);
    assert.equal(argv(name, { ...input, yes: false }).includes('--yes'), false, `${name} with yes:false`);
    assert.equal(argv(name, { ...input, yes: true }).includes('--yes'), true, `${name} with yes:true`);
  }
});

test('vpn_connect without yes: the exit-2 answer is a preview, not an error', async () => {
  const s = fakeSpawn({ stdout: '{"needsConfirm":true,"what":"Connect to X: deposit up to 50 tDVPN"}\n', code: 2 });
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  const r = await callTool('vpn_connect', { node: NODE }, { env, platform: 'linux', spawnFn: s.fn });
  assert.equal(s.calls[0].args.includes('--yes'), false);
  assert.equal(r.isError, false);
  assert.equal(r.structuredContent.preview, true);
  assert.match(r.content.at(-1).text, /nothing was spent/);
});

test('the CLI that is actually spawned gets --yes for connect / settle only with yes:true', async () => {
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  for (const [name, input] of [['vpn_connect', { node: NODE }], ['vpn_settle', {}]]) {
    for (const [extra, want] of [[{}, false], [{ yes: false }, false], [{ yes: true }, true]]) {
      const s = fakeSpawn({ stdout: '{"ok":true}\n', code: want ? 0 : 2 });
      await callTool(name, { ...input, ...extra }, { env, platform: 'linux', spawnFn: s.fn });
      assert.equal(s.calls.length, 1);
      assert.equal(s.calls[0].args.includes('--yes'), want, `${name} ${JSON.stringify(extra)}: spawned ${s.calls[0].args.join(' ')}`);
    }
  }
});

test('a call that never ends times out: isError, says so, and for connect / up how to recover a deposit', async () => {
  const hanging = () => {
    const calls = [];
    const fn = (file, args, opts) => {
      calls.push({ file, args, opts });
      const child = new EventEmitter();
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      child.kill = () => setImmediate(() => child.emit('close', null, 'SIGTERM'));
      return child;
    };
    return { fn, calls };
  };
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  for (const [name, input, recover] of [['vpn_connect', { node: NODE, yes: true }, true], ['vpn_status', {}, false]]) {
    const s = hanging();
    const r = await callTool(name, input, { env, platform: 'linux', spawnFn: s.fn, timeoutMs: 50 });
    const text = r.content.map((c) => c.text).join(' ');
    assert.equal(r.isError, true, name);
    assert.match(text, /timed out after 0\.05 s/, name);
    assert.equal(/deposit may already be paid/.test(text), recover, name);
  }
});

test('a tools/call sent as a notification (no id) runs nothing and answers nothing', async () => {
  const s = fakeSpawn();
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  const r = await handleMessage({ jsonrpc: '2.0', method: 'tools/call', params: { name: 'vpn_connect', arguments: { node: NODE, yes: true } } },
    { env, platform: 'linux', spawnFn: s.fn });
  assert.equal(r, null);
  assert.equal(s.calls.length, 0);
});

test('output over the cap is cut and says so', async () => {
  const s = fakeSpawn({ stdout: `${'x'.repeat(4_100_000)}\n` });
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  const r = await callTool('vpn_nodes', {}, { env, platform: 'linux', spawnFn: s.fn });
  assert.match(r.content.map((c) => c.text).join(' '), /was cut/);
});

test('bad input never reaches the CLI', async () => {
  const s = fakeSpawn();
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  for (const [name, input] of [
    ['vpn_connect', {}],
    ['vpn_connect', { node: '--yes' }],
    ['vpn_connect', { node: `${NODE} & calc` }],
    ['vpn_connect', { node: NODE, units: 0 }],
    ['vpn_connect', { node: NODE, units: 1001 }],
    ['vpn_connect', { node: NODE, basis: 'per_day' }],
    ['vpn_nodes', { country: 'DEU' }],
    ['vpn_nodes', { protocol: 'ipsec' }],
    ['vpn_status', { extra: 1 }],
    ['nope', {}],
  ]) {
    const r = await callTool(name, input, { env, platform: 'linux', spawnFn: s.fn });
    assert.equal(r.isError, true, `${name} ${JSON.stringify(input)}`);
  }
  assert.equal(s.calls.length, 0);
});

test('CLI JSON and exit code come back untouched; --json appended; env passed through', async () => {
  const out = '{"ok":true,"connected":true,"node":"x"}';
  const s = fakeSpawn({ stdout: `warming up\n${out}\n`, code: 0 });
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin, DVPN_KEYFILE: '/tmp/k.json' };
  const r = await callTool('vpn_status', {}, { env, platform: 'linux', spawnFn: s.fn });
  assert.equal(r.isError, false);
  assert.equal(r.content[0].text, out);
  assert.deepEqual(r.structuredContent.result, JSON.parse(out));
  assert.equal(r.structuredContent.exitCode, 0);
  assert.deepEqual(s.calls[0].args, ['status', '--json']);
  assert.equal(s.calls[0].opts.env.DVPN_KEYFILE, '/tmp/k.json');
  assert.equal(s.calls[0].opts.shell, false);
});

test('non-zero exit is an error and keeps the exit code', async () => {
  const s = fakeSpawn({ stdout: '{"ok":false,"error":"needs --yes"}\n', stderr: 'boom', code: 2 });
  const env = { DEVNET_DVPN_BIN: fakeInstall('linux').bin };
  const r = await callTool('vpn_disconnect', {}, { env, platform: 'linux', spawnFn: s.fn });
  assert.equal(r.isError, true);
  assert.equal(r.structuredContent.exitCode, 2);
  assert.match(r.content[1].text, /boom/);
});

test('Windows: the .cmd shim is unwrapped, no cmd.exe', () => {
  const { bin, root } = fakeInstall('win32');
  const cli = resolveCli({ DEVNET_DVPN_BIN: bin }, 'win32');
  assert.equal(cli.file, join(root, 'Devnet dVPN.exe'));
  assert.deepEqual(cli.pre, [join(root, 'resources', 'app.asar', 'out', 'cli', 'devnet-dvpn.cjs')]);
  assert.equal(cli.env.ELECTRON_RUN_AS_NODE, '1');
});

test('PATH lookup uses the given env, not process.env (a real CLI on the test machine must not leak in)', () => {
  const { bin, root } = fakeInstall('linux');
  assert.equal(resolveCli({ PATH: root }, 'linux').file, bin);
  assert.equal(resolveCli({ PATH: '' }, 'linux'), null);
  assert.equal(resolveCli({}, 'linux'), null);
  const w = fakeInstall('win32');
  assert.equal(resolveCli({ Path: join(w.root, 'bin') }, 'win32').file, join(w.root, 'Devnet dVPN.exe'));
});

test('a built .cjs bundle runs on this Node', () => {
  const root = mkdtempSync(join(tmpdir(), 'ap-mcp-'));
  const cjs = join(root, 'devnet-dvpn.cjs');
  writeFileSync(cjs, '');
  const cli = resolveCli({ DEVNET_DVPN_BIN: cjs }, 'linux');
  assert.equal(cli.file, process.execPath);
  assert.deepEqual(cli.pre, [cjs]);
  assert.match(resolveCli({ DEVNET_DVPN_BIN: join(root, 'nope.cjs') }, 'linux').error, /does not exist/);
  // The injected `exists` decides for a bundle too.
  assert.equal(resolveCli({ DEVNET_DVPN_BIN: '/no/such/x.cjs' }, 'linux', () => true).file, process.execPath);
  assert.match(resolveCli({ DEVNET_DVPN_BIN: cjs }, 'linux', () => false).error, /does not exist/);
});

test('macOS: GUI-app PATH without devnet-dvpn → /usr/local/bin, then the app bundle, then ~/Applications', () => {
  const env = { PATH: '/usr/bin:/bin', HOME: '/srv/agent-home' };
  const bundle = '/Applications/Devnet dVPN.app/Contents/Resources/bin/devnet-dvpn';
  const only = (...ok) => (p) => ok.includes(p);
  assert.equal(resolveCli(env, 'darwin', only('/usr/local/bin/devnet-dvpn', bundle)).file, '/usr/local/bin/devnet-dvpn');
  assert.equal(resolveCli(env, 'darwin', only(bundle)).file, bundle);
  assert.equal(resolveCli(env, 'darwin', only(`/srv/agent-home${bundle}`)).file, `/srv/agent-home${bundle}`);
  assert.equal(resolveCli(env, 'darwin', only()), null);
  // Only macOS searches those places.
  assert.equal(resolveCli(env, 'linux', only('/usr/local/bin/devnet-dvpn', bundle)), null);
  // PATH still wins.
  assert.equal(resolveCli({ ...env, PATH: '/opt/x' }, 'darwin', only('/opt/x/devnet-dvpn', bundle)).file, '/opt/x/devnet-dvpn');
});

test('Windows: a client with the pre-install PATH finds the default install folder', () => {
  const cmd = 'C:\\Program Files\\Devnet dVPN\\bin\\devnet-dvpn.cmd';
  const exe = 'C:\\Program Files\\Devnet dVPN\\Devnet dVPN.exe';
  const only = (...ok) => (p) => ok.includes(p);
  const env = { Path: 'C:\\Windows\\system32', ProgramW6432: 'C:\\Program Files', ProgramFiles: 'C:\\Program Files (x86)' };
  const cli = resolveCli(env, 'win32', only(cmd, exe));
  assert.equal(cli.file, exe);
  assert.equal(cli.pre[0], 'C:\\Program Files\\Devnet dVPN\\resources\\app.asar\\out\\cli\\devnet-dvpn.cjs');
  assert.equal(cli.env.ELECTRON_RUN_AS_NODE, '1');
  // The shim without the exe next to it is an error, not a spawn.
  assert.match(resolveCli(env, 'win32', only(cmd)).error, /Devnet dVPN\.exe/);
  // Nothing installed → null; Linux never looks there.
  assert.equal(resolveCli(env, 'win32', only()), null);
  assert.equal(resolveCli(env, 'linux', only(cmd, exe)), null);
});

test('missing CLI → install hint, no spawn', async () => {
  const s = fakeSpawn();
  const r = await callTool('vpn_status', {}, { env: { PATH: '' }, platform: 'linux', spawnFn: s.fn });
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /sentinel-solana-dvpn-linux/);
  assert.equal(s.calls.length, 0);
});

test('JSON-RPC: initialize, tools/list, unknown method, notification', async () => {
  const init = await handleMessage({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } });
  assert.equal(init.result.protocolVersion, '2025-03-26');
  const list = await handleMessage({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
  assert.equal(list.result.tools.length, 9);
  assert.equal('agent' in list.result.tools[6], false);
  assert.equal('args' in list.result.tools[0], false);
  const bad = await handleMessage({ jsonrpc: '2.0', id: 3, method: 'resources/list' });
  assert.equal(bad.error.code, -32601);
  assert.equal(await handleMessage({ jsonrpc: '2.0', method: 'notifications/initialized' }), null);
});

test('stdio: one line in, one line out, parse errors answered', async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const lines = [];
  output.on('data', (c) => lines.push(...c.toString().split('\n').filter(Boolean)));
  const done = serve({ input, output });
  input.write('{"jsonrpc":"2.0","id":1,"method":"ping"}\n');
  input.write('not json\n');
  input.end();
  await done;
  const msgs = lines.map((l) => JSON.parse(l));
  assert.ok(msgs.some((m) => m.id === 1 && m.result));
  assert.ok(msgs.some((m) => m.error?.code === -32700));
});

// ─── Agent failure codes: every code of docs/AGENT-COMMANDS.md has a line in mcp/README.md ───
// Copy of the codes in the "Failure codes (exit 1)" section of docs/AGENT-COMMANDS.md. The tests
// below check it against this repository's copy of that doc (always) and that copy against the app
// source (when the source sits next to this repo, ../devnet-dvpn).
const AGENT_CODES = [
  'no-wallet', 'no-device', 'no-subscription', 'no-nodes', 'not-funded', 'connect-failed', 'settle-failed',
  'daemon-missing', 'daemon-relogin', 'protocol-missing', 'device-permission', 'daemon-unavailable', 'daemon-restarting',
  'test-running', 'rpc-busy', 'price-changed', 'deposit-unusable', 'deposits-unread',
  'not-confirmed', 'plan-limit', 'busy', 'unsupported', 'network-mismatch',
  'session-active', 'node-gone', 'node-stale', 'node-offline', 'protocol-blocked', 'driver-missing', 'basis-unavailable',
  'not-enough-tdvpn', 'spending-limit', 'price-cap', 'rpc-ws', 'keyfile-mode', 'device-sol', 'preflight', 'kill-switch-held', 'kill-switch-remote', 'disconnect-failed', 'apply-busy', 'apply-while-connecting', 'apply-failed', 'switch-reconnecting', 'switch-offline',
  'cancelled',
  'waiting-for-network', 'ticket-other-owner', 'approval-revoked', 'service-stopped-connecting', 'node-identity', 'node-ledger',
  'node-price', 'node-error', 'kill-switch-failed', 'tunnel-failed', 'tunnel-dead', 'tunnel-mtu', 'tunnel-closing', 'port-in-use',
  'dns-apply', 'deposit-pending', 'rpc-network', 'rpc-timeout', 'rpc-quota', 'timeout', 'chain-encoding',
  'credit_exhausted', 'peer_limit_reached', 'lease_insufficient', 'subscription_invalid', 'ticket_request_stale',
  'provider_unreachable', 'ticket_invalid', 'unauthorized', 'cannot cover the prepay', 'voucher_exceeds_escrow',
  'channel_node_reopened', 'terms_rejected', 'rate_limited', 'voucher_signature_invalid', 'mode_not_voucher', 'mode_not_stream',
  'stop-failed', 'dns-revert-failed', 'tunnel-left', 'unknown',
  'service-down', 'service-not-ready', 'rpc-unavailable',
  'keyfile-missing', 'wallet-switch-needed', 'clock-skew',
];

// Codes in a doc's failure section: the first cell of each table row and every item of a bullet list.
const HERE = dirname(fileURLToPath(import.meta.url));
const codesIn = (md, from = /^## Failure codes/m, to = /^### Usage/m) => {
  const start = md.search(from);
  const rest = start < 0 ? '' : md.slice(start);
  const end = rest.search(to);
  const section = end < 0 ? rest : rest.slice(0, end);
  const codes = new Set();
  for (const line of section.split(/\r?\n/)) {
    let cells = null;
    if (/^\|/.test(line) && !/^\|\s*-/.test(line)) cells = line.split('|')[1];
    else if (/^- /.test(line)) cells = line;
    if (!cells) continue;
    for (const m of cells.matchAll(/`([^`]+)`/g)) if (!m[1].startsWith('-') && !m[1].startsWith('<')) codes.add(m[1]);
  }
  return codes;
};

test('every agent failure code has a line in the mcp/README.md failure table', () => {
  const readme = readFileSync(join(HERE, 'README.md'), 'utf8');
  const table = codesIn(readme, /^### Failure codes of the agent tools/m, /^Usage errors/m);
  const missing = AGENT_CODES.filter((c) => !table.has(c));
  assert.deepEqual(missing, [], `add these codes to the README failure table: ${missing.join(', ')}`);
});

// This repository carries a copy of the doc (docs/AGENT-COMMANDS.md), so this runs everywhere.
const HUB_DOC = join(HERE, '..', 'docs', 'AGENT-COMMANDS.md');

test('the code list matches the copy in this repository of docs/AGENT-COMMANDS.md', () => {
  const inDoc = codesIn(readFileSync(HUB_DOC, 'utf8'));
  assert.ok(inDoc.size > 50, `parsed only ${inDoc.size} codes: did the doc's headings change?`);
  const copy = new Set(AGENT_CODES);
  assert.deepEqual([...inDoc].filter((c) => !copy.has(c)), [], 'codes in the doc but not in AGENT_CODES');
  assert.deepEqual([...copy].filter((c) => !inDoc.has(c)), [], 'codes in AGENT_CODES but no longer in the doc');
});

// ─── B40: the hub copy = the app's file at a NAMED commit, plus a listed set of hub corrections ───
// The app source is a git checkout of devnet-dvpn: DVPN_SRC, else ../devnet-dvpn. The file is read at APP_PIN
// with `git show`, so the checkout's own branch or state does not matter. Each correction's `app` text must occur
// exactly once in the pinned file; after the corrections the two files must be equal. When the hub copy moves to a
// new app commit, move APP_PIN with it and re-check each correction (drop the ones the app took).
// No source: a skip, except with DVPN_REQUIRE_SRC=1 (the release gate, docs/RELEASE-CHECKLIST.md), where it fails.
const APP_PIN = 'f4009a9594e5ef9c512bcafd7119290a97d38794'; // app source rc9-f2 (v0.3.0-rc9), the rc.9 page push
// rc9-f2 carries every earlier correction (B41 x2, clock-skew, LIM-1, exit 5 and 6, the sudo case, the B6 rows).
const HUB_CORRECTIONS = [];

// The pinned app file with the corrections applied; throws when a correction no longer matches exactly once.
const correctedAppDoc = (appText, corrections = HUB_CORRECTIONS) => {
  let text = appText.replace(/\r\n/g, '\n');
  for (const c of corrections) {
    const n = text.split(c.app).length - 1;
    if (n !== 1) throw new Error(`correction "${c.why}": its app text occurs ${n} times in the pinned file (want 1)`);
    text = text.replace(c.app, () => c.hub);
  }
  return text;
};

const appSrcDir = () => process.env.DVPN_SRC || join(HERE, '..', '..', 'devnet-dvpn');
const pinnedAppDoc = (dir) => execFileSync('git', ['-C', dir, 'show', `${APP_PIN}:docs/AGENT-COMMANDS.md`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

test('the copy in this repository of docs/AGENT-COMMANDS.md = the app file at APP_PIN + HUB_CORRECTIONS', (t) => {
  const dir = appSrcDir();
  let appText = null;
  let why = `no app source at ${dir}`;
  if (existsSync(join(dir, '.git')) || existsSync(join(dir, 'HEAD'))) {
    try { appText = pinnedAppDoc(dir); } catch (err) { why = `git show ${APP_PIN.slice(0, 9)} in ${dir} failed: ${String(err.stderr || err.message).trim()}`; }
  }
  if (appText === null) {
    if (process.env.DVPN_REQUIRE_SRC === '1') assert.fail(`DVPN_REQUIRE_SRC=1 and ${why}: set DVPN_SRC to a devnet-dvpn checkout that has ${APP_PIN}`);
    t.skip(`${why} (set DVPN_SRC; the release gate sets DVPN_REQUIRE_SRC=1)`);
    return;
  }
  assert.equal(readFileSync(HUB_DOC, 'utf8').replace(/\r\n/g, '\n'), correctedAppDoc(appText),
    `docs/AGENT-COMMANDS.md differs from the app source ${APP_PIN.slice(0, 9)} + HUB_CORRECTIONS: copy the app file again (or move APP_PIN), then update AGENT_CODES and the README table`);
});

test('correctedAppDoc refuses a correction that no longer matches exactly once', () => {
  const c = [{ why: 'x', app: 'AAA', hub: 'BBB' }];
  assert.equal(correctedAppDoc('1 AAA 2', c), '1 BBB 2');
  assert.throws(() => correctedAppDoc('1 2', c), /occurs 0 times/);
  assert.throws(() => correctedAppDoc('AAA AAA', c), /occurs 2 times/);
});

test('vpn_up refuses max_price without basis (it is per unit of a basis that defaults to the saved setting)', async () => {
  const s = fakeSpawn();
  const r = await callTool('vpn_up', { max_price: '0.5' }, { env: { PATH: '' }, platform: 'linux', spawnFn: s.fn });
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /basis/);
  assert.equal(s.calls.length, 0);
});
// ─── live-check: when the paid session must be closed ───
// Imported, live-check.mjs runs nothing (it starts only as the entry point).
test('live-check runs vpn_down after any paid vpn_up that is not a clean refusal', async () => {
  const { upCleanlyRefused, checkAfterUp, mustRunDown } = await import('./live-check.mjs');
  const ans = (exitCode, result) => ({ isError: exitCode !== 0, structuredContent: { exitCode, result } });
  const connected = ans(0, { connected: true, node: NODE });
  const notConnected = ans(0, { connected: false });

  // No answer at all (timeout, transport error): it may have connected and paid → always down.
  assert.equal(checkAfterUp(null), true);
  assert.equal(mustRunDown(null, notConnected), true);
  assert.equal(mustRunDown(null, null), true);

  // Connected (exit 0 with a session) → down, whatever the status says.
  const ok = ans(0, { ok: true, session: 's1', node: NODE });
  assert.equal(upCleanlyRefused(ok), false);
  assert.equal(mustRunDown(ok, notConnected), true);

  // Already connected (reused): the check paid nothing and did not open the session → never down (B20).
  const reused = ans(0, { ok: true, reused: true, session: 's0', node: NODE });
  assert.equal(mustRunDown(reused, connected), false);
  assert.equal(mustRunDown(reused, notConnected), false);

  // A failure that still carries a session → down.
  assert.equal(mustRunDown(ans(1, { ok: false, code: 'node-error', session: 's2' }), notConnected), true);

  // A failure without a session is a clean refusal → no status read, no down.
  const refused = ans(1, { ok: false, code: 'not-enough-tdvpn', action: 'fund' });
  assert.equal(upCleanlyRefused(refused), true);
  assert.equal(checkAfterUp(refused), false);
  assert.equal(mustRunDown(refused, connected), false);

  // The rc2 fallback (the server's answer to "unknown command: agent": exit code 3) is a clean refusal.
  const rc2 = await callTool('vpn_up', { yes: true }, {
    env: { DEVNET_DVPN_BIN: fakeInstall('linux').bin }, platform: 'linux',
    spawnFn: fakeSpawn({ stderr: 'unknown command: agent\n', code: 3 }).fn,
  });
  assert.equal(rc2.structuredContent.exitCode, 3);
  assert.equal(upCleanlyRefused(rc2), true);

  // An answer with no exit code (an MCP tool error, a server timeout) is not a clean refusal:
  // the status is read, and down runs unless the status says not connected.
  const toolError = { isError: true, content: [{ type: 'text', text: 'internal error' }] };
  const timedOut = { isError: true, structuredContent: { exitCode: null, timedOut: true } };
  for (const up of [toolError, timedOut]) {
    assert.equal(upCleanlyRefused(up), false);
    assert.equal(checkAfterUp(up), true);
    assert.equal(mustRunDown(up, connected), true);
    assert.equal(mustRunDown(up, null), true);
    assert.equal(mustRunDown(up, notConnected), false);
  }
});

test('S15: every tool has a title and annotations; read-only tools never spend, spending tools say destructive', async () => {
  const list = await handleMessage({ jsonrpc: '2.0', id: 9, method: 'tools/list' });
  for (const t of list.result.tools) {
    assert.equal(typeof t.title, 'string', `${t.name} has a title`);
    assert.equal(typeof t.annotations, 'object', `${t.name} has annotations`);
    assert.equal(t.inputSchema.additionalProperties, false, `${t.name} rejects unknown arguments`);
  }
  const by = Object.fromEntries(list.result.tools.map((t) => [t.name, t.annotations]));
  for (const n of ['vpn_status', 'vpn_wallet', 'vpn_nodes', 'vpn_agent_status']) assert.equal(by[n].readOnlyHint, true, n);
  for (const n of ['vpn_connect', 'vpn_up', 'vpn_down', 'vpn_disconnect']) assert.equal(by[n].destructiveHint, true, n);
});

test('S7: vpn_up raise_limit maps to --raise-limit, only when true', () => {
  const up = TOOLS.find((t) => t.name === 'vpn_up');
  assert.deepEqual(up.args(checkInput(up, { raise_limit: true, yes: true })), ['agent', 'up', '--raise-limit', '--yes']);
  assert.deepEqual(up.args(checkInput(up, { raise_limit: false, yes: true })), ['agent', 'up', '--yes']);
  assert.throws(() => checkInput(up, { raise_limit: 'yes' }), /raise_limit must be true or false/);
});

// ─── R5: CLI fields pass through unchanged (stub answers shaped like rc.7 agent-cmd.ts) ───
const runStub = (tool, input, line, code) => callTool(tool, input, {
  env: { DEVNET_DVPN_BIN: fakeInstall('linux').bin }, platform: 'linux',
  spawnFn: fakeSpawn({ stdout: `${line}\n`, code }).fn,
});

test('R5 failure: isError + error, code, action, money, next, alsoNext, docUrl exactly as the CLI sent them', async () => {
  const cli = {
    ok: false,
    error: 'The deposit (2.4 tDVPN) is above this computer\'s spending limit (1 tDVPN). Nothing was paid.',
    code: 'spending-limit',
    action: 'devnet-dvpn agent up --raise-limit --yes',
    next: 'devnet-dvpn agent up --raise-limit --yes',
    alsoNext: 'devnet-dvpn agent status',
    money: 'Nothing was paid. Your tDVPN is still in your wallet.',
    docUrl: 'https://example.invalid/docs/AGENT-COMMANDS.md#spending-limit',
  };
  const line = JSON.stringify(cli);
  const r = await runStub('vpn_up', { yes: true }, line, 1);
  assert.equal(r.isError, true);
  assert.equal(r.structuredContent.isError, true);
  assert.equal(r.content[0].text, line, 'the text is the CLI line, byte for byte');
  for (const k of ['error', 'code', 'action', 'money', 'next', 'alsoNext', 'docUrl']) {
    assert.equal(r.structuredContent[k], cli[k], `${k} unchanged`);
  }
  assert.deepEqual(r.structuredContent.result, cli);
  assert.equal('defaults' in r.structuredContent, false, 'no success fields on a failure');
});

test('R5 failure: a field the CLI did not send is not invented; null stays null', async () => {
  const cli = { ok: false, error: 'The network is busy (429). Nothing was paid.', code: 'rpc-busy', action: null, money: 'Nothing was paid.' };
  const r = await runStub('vpn_agent_status', {}, JSON.stringify(cli), 6);
  assert.equal(r.isError, true);
  assert.equal(r.structuredContent.exitCode, 6);
  assert.equal(r.structuredContent.action, null);
  assert.equal(r.structuredContent.money, cli.money);
  for (const k of ['next', 'alsoNext', 'docUrl']) assert.equal(k in r.structuredContent, false, `${k} absent`);
});

test('R5 failure: exits 4 and 5 lift the same fields', async () => {
  for (const [exit, code] of [[4, 'operator-needed'], [5, 'kill-switch']]) {
    const cli = { ok: false, error: `e${exit}`, code, action: 'devnet-dvpn agent status', next: 'devnet-dvpn daemon restore-network', money: `m${exit}` };
    const r = await runStub('vpn_down', { yes: true }, JSON.stringify(cli), exit);
    assert.equal(r.isError, true);
    assert.equal(r.structuredContent.code, code);
    assert.equal(r.structuredContent.next, cli.next);
    assert.equal(r.structuredContent.money, cli.money);
  }
});

test('R5 success: next, defaults and alsoNext pass through unchanged; failure fields are not lifted', async () => {
  const defaults = {
    basis: { value: 'per_gb', from: 'settings' },
    units: { value: 2, from: 'settings' },
    maxPrice: { value: '0.5', from: 'market' },
  };
  const cli = {
    ok: true, session: 's-1', node: NODE, protocol: 'v2ray', exitIp: '203.0.113.7', directIp: '198.51.100.2',
    next: 'devnet-dvpn agent down --yes', alsoNext: 'devnet-dvpn agent status', defaults, code: 'unused-here',
  };
  const r = await runStub('vpn_up', { yes: true }, JSON.stringify(cli), 0);
  assert.equal(r.isError, false);
  assert.equal(r.structuredContent.isError, false);
  assert.equal(r.structuredContent.next, cli.next);
  assert.equal(r.structuredContent.alsoNext, cli.alsoNext);
  assert.deepEqual(r.structuredContent.defaults, defaults);
  assert.equal('code' in r.structuredContent, false, 'a success does not lift failure fields');
  assert.equal(r.content[0].text, JSON.stringify(cli));
});

test('R5 preview (exit 2): not an error, and its next / defaults pass through', async () => {
  const cli = { ok: false, needsConfirm: true, what: 'Connect to … Nothing is signed until you pass --yes.', next: 'devnet-dvpn agent up --yes', defaults: { units: { value: 1, from: 'default' } } };
  const r = await runStub('vpn_up', {}, JSON.stringify(cli), 2);
  assert.equal(r.isError, false);
  assert.equal(r.structuredContent.preview, true);
  assert.equal(r.structuredContent.next, cli.next);
  assert.deepEqual(r.structuredContent.defaults, cli.defaults);
});

test('R5 the output schema names every lifted field', async () => {
  const { OUTPUT_SCHEMA, FAIL_FIELDS, OK_FIELDS } = await import('./server.js');
  for (const k of [...FAIL_FIELDS, ...OK_FIELDS, 'isError']) assert.ok(OUTPUT_SCHEMA.properties[k], k);
});
