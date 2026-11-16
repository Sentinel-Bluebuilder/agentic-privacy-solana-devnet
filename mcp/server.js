#!/usr/bin/env node
// ─── MCP server over the installed devnet-dvpn CLI ──────────────────────────
// Speaks the Model Context Protocol on stdio (newline-delimited JSON-RPC 2.0).
// No SDK, no build step, no dependency. Each tool runs ONE installed
// `devnet-dvpn <command> --json` (reference: devnet-dvpn docs/CLI.md) and
// returns the CLI's JSON line and exit code untouched.
//
//   node mcp/server.js          # in an MCP config: {"command":"node","args":["<repo>/mcp/server.js"]}
//
// Environment (passed through to the CLI unchanged): DVPN_KEYFILE, DVPN_DATA_DIR, …
//   DEVNET_DVPN_BIN   path to the CLI if it is not on PATH
//                     (Windows: …\Devnet dVPN\bin\devnet-dvpn.cmd; Linux: /usr/bin/devnet-dvpn;
//                     macOS: /usr/local/bin/devnet-dvpn after `daemon install`, else
//                     /Applications/Devnet dVPN.app/Contents/Resources/bin/devnet-dvpn, which is
//                     also searched by itself when PATH has no devnet-dvpn)
//
// stdout carries protocol messages only; diagnostics go to stderr.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { delimiter, dirname, join, resolve, win32 } from 'node:path';
import { pathToFileURL } from 'node:url';

const SUPPORTED_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];
const SERVER_NAME = 'agentic-privacy';
const SERVER_VERSION = '0.1.0';
const CLI_TIMEOUT_MS = { default: 60_000, vpn_connect: 300_000, vpn_up: 300_000, vpn_settle: 180_000, vpn_down: 180_000, vpn_nodes: 120_000 };
const MAX_OUTPUT_BYTES = 4_000_000;

// Same list as devnet-dvpn src/shared/protocols.ts.
export const PROTOCOLS = ['wireguard', 'amneziawg', 'openvpn', 'v2ray', 'xray', 'hysteria2'];
const BASE58_ADDRESS = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const TDVPN_AMOUNT = /^\d+(\.\d{1,6})?$/;

// Released CLIs before `agent` existed (v0.3.0-rc2 and older) answer `agent …` with
// "unknown command: agent" on stderr and exit 3 (devnet-dvpn src/cli/index.ts:69).
const NO_AGENT_FIX = 'This installed devnet-dvpn has no `agent` command (it was released before `agent up/down/status`). '
  + 'Use vpn_nodes to pick a node, then vpn_connect {node}; disconnect with vpn_disconnect and refund with vpn_settle. '
  + 'Or install a newer release that has `agent`.';
const YES = { type: 'boolean', description: 'true = do it (spends / signs). Omitted or false = only show what would happen (exit code 2, nothing spent).' };

// ─── Tools ───────────────────────────────────────────────────────────────────
// `args(input)` builds the CLI argv; every value is checked first, so nothing
// an agent sends can become a flag or reach a shell (none is used anyway).

const address = (what) => ({ type: 'string', pattern: BASE58_ADDRESS.source, description: what });

export const TOOLS = [
  {
    name: 'vpn_status',
    description: 'Wallet, device, service and session at a glance. Runs: devnet-dvpn status --json',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    args: () => ['status'],
  },
  {
    name: 'vpn_wallet',
    description: 'Address and balances (SOL, tDVPN, refundable, approved). Runs: devnet-dvpn wallet show --json',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    args: () => ['wallet', 'show'],
  },
  {
    name: 'vpn_nodes',
    description: 'Online nodes, checked live, with protocol, country and prices. Runs: devnet-dvpn nodes list --online --json',
    inputSchema: {
      type: 'object',
      properties: {
        country: { type: 'string', pattern: '^[A-Za-z]{2}$', description: 'two-letter country code, e.g. DE' },
        protocol: { type: 'string', enum: PROTOCOLS },
        sort: { type: 'string', enum: ['price'], description: 'cheapest first' },
      },
      additionalProperties: false,
    },
    args: (i) => [
      'nodes', 'list', '--online',
      ...(i.country ? ['--country', i.country.toUpperCase()] : []),
      ...(i.protocol ? ['--protocol', i.protocol] : []),
      ...(i.sort ? ['--sort', i.sort] : []),
    ],
  },
  {
    name: 'vpn_connect',
    description: 'Pay a deposit (or use a plan) and connect to one node. Spends tDVPN, so it runs only with yes:true; '
      + 'without it, a preview (exit 2): what, and the deposit it would pay. '
      + 'Runs: devnet-dvpn connect <node> [--basis per_gb|per_hour] [--units N] [--plan <subscription>] [--yes] --json',
    inputSchema: {
      type: 'object',
      properties: {
        node: address('node address from vpn_nodes'),
        basis: { type: 'string', enum: ['per_gb', 'per_hour'], description: 'pay per GB (default) or per hour' },
        units: { type: 'integer', minimum: 1, maximum: 1000, description: 'GB (per_gb) or hours (per_hour) the deposit covers' },
        plan: address('subscription address: connect on a plan instead of a deposit'),
        yes: YES,
      },
      required: ['node'],
      additionalProperties: false,
    },
    args: (i) => [
      'connect', i.node,
      ...(i.basis ? ['--basis', i.basis] : []),
      ...(i.units !== undefined ? ['--units', String(i.units)] : []),
      ...(i.plan ? ['--plan', i.plan] : []),
      ...(i.yes === true ? ['--yes'] : []),
    ],
  },
  {
    name: 'vpn_disconnect',
    description: 'Stop the session; the deposit settles later (then call vpn_settle). Runs: devnet-dvpn disconnect --json',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    args: () => ['disconnect'],
  },
  {
    name: 'vpn_settle',
    description: 'Start / finish closing finished deposits so unused tDVPN comes back. Signs transactions, so it runs only '
      + 'with yes:true; without it, a preview (exit 2): what, pending (the deposits it would settle). '
      + 'Runs: devnet-dvpn settle run [--channel C] [--yes] --json',
    inputSchema: {
      type: 'object',
      properties: { channel: address('one deposit (channel) address; default: all finished ones'), yes: YES },
      additionalProperties: false,
    },
    args: (i) => ['settle', 'run', ...(i.channel ? ['--channel', i.channel] : []), ...(i.yes === true ? ['--yes'] : [])],
  },
  // ─── agent up / down / status (devnet-dvpn releases after v0.3.0-rc2) ───
  {
    name: 'vpn_up',
    agent: true,
    description: 'Connect in one call: picks the best online node that matches, pays a deposit (or uses a plan) and connects. '
      + 'Result: session, node, protocol, country, exitIp, directIp, socks (socks5h://host:port or null), channel, '
      + 'deposit ({basis, units, tdvpn, baseUnits}; null when reused), next. Already connected to a match: reused:true, pays nothing. '
      + 'Without yes:true it pays nothing and answers a preview: what, node, deposit, switchFrom. '
      + 'Failure: {ok:false, error, code, action}; do what `action` says. '
      + 'Runs: devnet-dvpn agent up [--protocol P] [--country CC] [--node N] [--basis per_gb|per_hour] [--units N] [--plan S] [--max-price N] [--yes] --json',
    inputSchema: {
      type: 'object',
      properties: {
        protocol: { type: 'string', enum: ['any', ...PROTOCOLS], description: 'default any' },
        country: { type: 'string', pattern: '^[A-Za-z]{2}$', description: 'two-letter country code, e.g. DE' },
        node: address('exact node address (otherwise the best match is picked)'),
        basis: { type: 'string', enum: ['per_gb', 'per_hour'], description: 'pay per GB or per hour; default: the saved setting (not always per_gb)' },
        units: { type: 'integer', minimum: 1, maximum: 1000, description: 'GB (per_gb) or hours (per_hour) the deposit covers; default from settings' },
        plan: address('subscription address you hold: connect on the plan (no deposit, its live nodes only)'),
        max_price: { type: 'string', pattern: TDVPN_AMOUNT.source, description: 'highest price per unit of `basis` in tDVPN, e.g. "0.5"; needs `basis` too' },
        yes: YES,
      },
      additionalProperties: false,
    },
    // --max-price is per unit of --basis, and the basis defaults to the saved setting: never send one without the other.
    check: (i) => (i.max_price && !i.basis ? 'max_price is per unit of basis, which otherwise defaults to the saved setting: pass basis ("per_gb" or "per_hour") too' : null),
    args: (i) => [
      'agent', 'up',
      ...(i.protocol ? ['--protocol', i.protocol] : []),
      ...(i.country ? ['--country', i.country.toUpperCase()] : []),
      ...(i.node ? ['--node', i.node] : []),
      ...(i.basis ? ['--basis', i.basis] : []),
      ...(i.units !== undefined ? ['--units', String(i.units)] : []),
      ...(i.plan ? ['--plan', i.plan] : []),
      ...(i.max_price ? ['--max-price', i.max_price] : []),
      ...(i.yes === true ? ['--yes'] : []),
    ],
  },
  {
    name: 'vpn_down',
    agent: true,
    description: 'Disconnect, close per-hour deposits at once (they bill until closed) and start the 2-hour close of per-GB ones. '
      + 'Result: disconnected, spent, refundable, readyAt (unix s), signatures, pending, next (run `settle run --yes` after readyAt, '
      + 'then `settle withdraw --yes`). Signs transactions, so it runs only with yes:true; without it, a preview: what, session, perHour, perGb. '
      + 'Runs: devnet-dvpn agent down [--yes] --json',
    inputSchema: { type: 'object', properties: { yes: YES }, additionalProperties: false },
    args: (i) => ['agent', 'down', ...(i.yes === true ? ['--yes'] : [])],
  },
  {
    name: 'vpn_agent_status',
    agent: true,
    description: 'Read-only: wallet, device, service and session in one answer, with `next`, the exact next step (what to fund, or vpn_up). '
      + 'Result: address, sol, tdvpn, refundable (decimal strings or null), device, service, connected; when connected also '
      + 'session, node, protocol, spent, exitIp, socks. Runs: devnet-dvpn agent status --json',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    args: () => ['agent', 'status'],
  },
];

// ─── Input checks (the schema, enforced: clients do not all validate) ────────

class InputError extends Error {}

export const checkInput = (tool, input) => {
  if (input === undefined || input === null) input = {};
  if (typeof input !== 'object' || Array.isArray(input)) throw new InputError('arguments must be an object');
  const { properties, required = [] } = tool.inputSchema;
  for (const k of Object.keys(input)) {
    if (!properties[k]) throw new InputError(`${tool.name} has no argument "${k}" (allowed: ${Object.keys(properties).join(', ') || 'none'})`);
  }
  for (const k of required) {
    if (input[k] === undefined || input[k] === null || input[k] === '') throw new InputError(`${k} is required`);
  }
  for (const [k, v] of Object.entries(input)) {
    if (v === undefined || v === null) continue;
    const p = properties[k];
    if (p.type === 'integer') {
      const n = typeof v === 'string' && /^\d+$/.test(v) ? Number(v) : v;
      if (!Number.isInteger(n) || n < p.minimum || n > p.maximum) throw new InputError(`${k} must be a whole number from ${p.minimum} to ${p.maximum}`);
      input[k] = n;
      continue;
    }
    if (p.type === 'boolean') {
      if (typeof v !== 'boolean') throw new InputError(`${k} must be true or false`);
      continue;
    }
    if (typeof v !== 'string') throw new InputError(`${k} must be a string`);
    if (p.enum && !p.enum.includes(v)) throw new InputError(`${k} must be one of: ${p.enum.join(', ')}`);
    if (p.pattern && !new RegExp(p.pattern).test(v)) throw new InputError(`${k} is not valid: "${v.slice(0, 60)}"`);
  }
  const problem = tool.check?.(input);
  if (problem) throw new InputError(problem);
  return input;
};

// ─── Finding the installed CLI ───────────────────────────────────────────────

// The PATH of the env we were given (not always process.env). A plain object copy of the
// Windows environment keeps the key's real spelling, usually `Path`.
const pathOf = (env) => env.PATH ?? env.Path ?? Object.entries(env).find(([k]) => k.toUpperCase() === 'PATH')?.[1] ?? '';

const onPath = (names, env, exists = existsSync) => {
  for (const dir of pathOf(env).split(delimiter)) {
    if (!dir) continue;
    for (const n of names) {
      const p = join(dir.replace(/^"|"$/g, ''), n);
      if (exists(p)) return p;
    }
  }
  return null;
};

// macOS: before `daemon install` there is no /usr/local/bin/devnet-dvpn, and a client started as a
// GUI app gets launchd's short PATH (/usr/bin:/bin:/usr/sbin:/sbin). So look in the usual places.
const MAC_BUNDLE_CLI = 'Applications/Devnet dVPN.app/Contents/Resources/bin/devnet-dvpn';
const macFallback = (env, exists) => [
  '/usr/local/bin/devnet-dvpn',
  `/${MAC_BUNDLE_CLI}`,
  `${(env.HOME || homedir()).replace(/\/$/, '')}/${MAC_BUNDLE_CLI}`,
].find((p) => exists(p)) ?? null;

// Windows: a client started before the install still has the old PATH. Try the installer's
// default per-machine folder (`C:\Program Files\Devnet dVPN`, also on ARM64).
const winFallback = (env, exists) => {
  const p = win32.join(env.ProgramW6432 || env.ProgramFiles || 'C:\\Program Files', 'Devnet dVPN', 'bin', 'devnet-dvpn.cmd');
  return exists(p) ? p : null;
};

/**
 * The command to spawn, without a shell. On Windows the installer ships a .cmd shim
 * (`set ELECTRON_RUN_AS_NODE=1` + `"..\Devnet dVPN.exe" "..\resources\app.asar\out\cli\devnet-dvpn.cjs" %*`);
 * we run those two pieces directly so no argument ever passes through cmd.exe.
 */
export const resolveCli = (env = process.env, platform = process.platform, exists = existsSync) => {
  const given = env.DEVNET_DVPN_BIN;
  const found = given || onPath(platform === 'win32' ? ['devnet-dvpn.cmd', 'devnet-dvpn.exe'] : ['devnet-dvpn'], env, exists)
    || (platform === 'darwin' ? macFallback(env, exists) : platform === 'win32' ? winFallback(env, exists) : null);
  if (!found) return null;
  if (platform === 'win32' && /\.cmd$/i.test(found)) {
    // A Windows path (backslashes) keeps Windows path rules even when the tests run on Linux.
    const pp = found.includes('\\') ? win32 : { dirname, join, resolve };
    const root = pp.resolve(pp.dirname(found), '..');
    const exe = pp.join(root, 'Devnet dVPN.exe');
    const cjs = pp.join(root, 'resources', 'app.asar', 'out', 'cli', 'devnet-dvpn.cjs');
    if (!exists(exe)) return { error: `found ${found} but not ${exe}` };
    return { file: exe, pre: [cjs], env: { ELECTRON_RUN_AS_NODE: '1' }, shown: found };
  }
  if (platform === 'win32' && /\.(bat|ps1)$/i.test(found)) return { error: `${found}: point DEVNET_DVPN_BIN at devnet-dvpn.cmd or an .exe` };
  // A built CLI bundle (`out/cli/devnet-dvpn.cjs`) runs on this Node, as `npm run cli` does.
  if (/\.(c?js|mjs)$/i.test(found)) {
    if (!exists(found)) return { error: `DEVNET_DVPN_BIN=${found} does not exist` };
    return { file: process.execPath, pre: [found], env: {}, shown: found };
  }
  return { file: found, pre: [], env: {}, shown: found };
};

const INSTALL_FIX = 'Install Devnet dVPN v0.3.0-rc2 or newer for this OS — Windows (puts devnet-dvpn on PATH for new shells): https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-windows/releases, '
  + 'Linux (/usr/bin/devnet-dvpn): https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-linux/releases, '
  + 'macOS (copy the app from the .dmg to /Applications; this server then finds "/Applications/Devnet dVPN.app/Contents/Resources/bin/devnet-dvpn"; '
  + '/usr/local/bin/devnet-dvpn appears only after `daemon install --yes`): https://github.com/Sentinel-Bluebuilder/sentinel-solana-dvpn-macos/releases — '
  + 'or set DEVNET_DVPN_BIN to its path, then restart this MCP server.';

// ─── Running one CLI command ─────────────────────────────────────────────────

const lastJsonLine = (text) => {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    if (!lines[i].startsWith('{') && !lines[i].startsWith('[')) continue;
    try {
      return { line: lines[i], json: JSON.parse(lines[i]) };
    } catch (err) {
      process.stderr.write(`[mcp] CLI line ${i + 1} looked like JSON but did not parse: ${err.message}\n`);
    }
  }
  return null;
};

export const runCli = (argv, { timeoutMs = CLI_TIMEOUT_MS.default, env = process.env, platform = process.platform, spawnFn = spawn } = {}) => new Promise((done) => {
  const cli = resolveCli(env, platform);
  if (!cli || cli.error) {
    done({ exitCode: null, stdout: '', stderr: '', notFound: cli?.error ?? 'devnet-dvpn is not on PATH' });
    return;
  }
  const args = [...cli.pre, ...argv, '--json'];
  let child;
  try {
    // env is inherited as-is (DVPN_KEYFILE, DVPN_DATA_DIR, …): the key path travels by env, never argv.
    child = spawnFn(cli.file, args, { env: { ...env, ...cli.env }, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true, shell: false });
  } catch (err) {
    done({ exitCode: null, stdout: '', stderr: '', notFound: `could not start ${cli.shown}: ${err.message}` });
    return;
  }
  let stdout = '';
  let stderr = '';
  let timedOut = false;
  let truncated = false;
  const cap = (buf, chunk) => {
    if (buf.length + chunk.length <= MAX_OUTPUT_BYTES) return buf + chunk;
    truncated = true;
    return (buf + chunk).slice(0, MAX_OUTPUT_BYTES);
  };
  child.stdout.setEncoding('utf8').on('data', (c) => { stdout = cap(stdout, c); });
  child.stderr.setEncoding('utf8').on('data', (c) => { stderr = cap(stderr, c); });
  const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
  child.on('error', (err) => {
    clearTimeout(timer);
    done({ exitCode: null, stdout, stderr, notFound: `could not start ${cli.shown}: ${err.message}` });
  });
  child.on('close', (code, signal) => {
    clearTimeout(timer);
    done({ exitCode: code, signal, stdout, stderr, timedOut, truncated, cli: cli.shown, argv: [...argv, '--json'] });
  });
});

/** Call one tool. Never throws. The CLI's JSON and exit code come back as they are. */
export const callTool = async (name, input, opts = {}) => {
  const tool = TOOLS.find((t) => t.name === name);
  const fail = (text, extra = {}) => ({ content: [{ type: 'text', text }], structuredContent: { exitCode: null, ...extra }, isError: true });
  if (!tool) return fail(`unknown tool "${name}"; tools: ${TOOLS.map((t) => t.name).join(', ')}`, { error: 'unknown tool' });
  let checked;
  try {
    checked = checkInput(tool, structuredClone(input ?? {}));
  } catch (err) {
    if (!(err instanceof InputError)) throw err;
    return fail(`bad input: ${err.message}`, { error: err.message, fix: `see the input schema of ${name}` });
  }
  const r = await runCli(tool.args(checked), { timeoutMs: CLI_TIMEOUT_MS[name] ?? CLI_TIMEOUT_MS.default, ...opts });
  if (r.notFound) return fail(`${r.notFound}. ${INSTALL_FIX}`, { error: r.notFound, fix: INSTALL_FIX });
  if (tool.agent && r.exitCode === 3 && /unknown command:\s*agent\b/i.test(r.stderr)) {
    return fail(NO_AGENT_FIX, { exitCode: 3, command: `devnet-dvpn ${r.argv.join(' ')}`, error: 'no agent command in this CLI', fix: NO_AGENT_FIX });
  }
  const parsed = lastJsonLine(r.stdout);
  const content = [{ type: 'text', text: parsed ? parsed.line : r.stdout.trim() || '(no output)' }];
  if (r.exitCode !== 0 && r.stderr.trim()) content.push({ type: 'text', text: `stderr: ${r.stderr.trim().slice(-2000)}` });
  if (r.timedOut) {
    content.push({ type: 'text', text: `timed out after ${(opts.timeoutMs ?? CLI_TIMEOUT_MS[name] ?? CLI_TIMEOUT_MS.default) / 1000} s; check vpn_status before retrying` });
    if (name === 'vpn_connect' || name === 'vpn_up') {
      content.push({ type: 'text', text: 'a deposit may already be paid and open: vpn_agent_status (or vpn_status) shows it; vpn_disconnect then vpn_settle {"yes": true} (or vpn_down {"yes": true}) gets it back' });
    }
  }
  if (r.truncated) content.push({ type: 'text', text: `output passed ${MAX_OUTPUT_BYTES} bytes and was cut, so its JSON may be missing; narrow the request (e.g. vpn_nodes with country or protocol)` });
  // Exit 2 = "needs --yes": a preview, not a failure. Only tools with a `yes` input can get here.
  const preview = r.exitCode === 2 && 'yes' in tool.inputSchema.properties && checked.yes !== true;
  if (preview) content.push({ type: 'text', text: `preview only, nothing was spent; call ${name} again with "yes": true to do it` });
  return {
    content,
    structuredContent: { exitCode: r.exitCode, command: `devnet-dvpn ${r.argv.join(' ')}`, result: parsed ? parsed.json : null, ...(preview ? { preview: true } : {}) },
    isError: r.exitCode !== 0 && !preview,
  };
};

// ─── JSON-RPC over stdio ─────────────────────────────────────────────────────

const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });
const publicTool = ({ name, description, inputSchema }) => ({ name, description, inputSchema });

export const handleMessage = async (msg, opts = {}) => {
  if (!msg || typeof msg !== 'object') return rpcError(null, -32600, 'invalid request');
  if (!('method' in msg)) return null; // a response to us; we send no requests
  if (msg.jsonrpc !== '2.0' || typeof msg.method !== 'string') return rpcError(msg.id, -32600, 'invalid request');
  const isNotification = !('id' in msg);
  const { id, method, params = {} } = msg;
  switch (method) {
    case 'initialize': {
      const asked = params.protocolVersion;
      return {
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: SUPPORTED_VERSIONS.includes(asked) ? asked : SUPPORTED_VERSIONS[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
          instructions: 'Private internet through a Sentinel dVPN node on Solana devnet, via the installed devnet-dvpn CLI. '
            + 'Short path (CLI with `agent`): vpn_agent_status → vpn_up {yes:true} → vpn_down {yes:true}. '
            + 'Without yes:true, vpn_up / vpn_down / vpn_connect / vpn_settle only preview what they would spend or sign. '
            + 'Older CLI (no `agent`): vpn_status → vpn_wallet (a human funds the address with SOL + tDVPN) → vpn_nodes '
            + '→ vpn_connect {node, yes:true} → vpn_disconnect → vpn_settle {yes:true}. '
            + 'A `next` field that runs `… agent up`, `… agent down` or `… agent status` (any path to devnet-dvpn, maybe quoted) '
            + 'maps to vpn_up / vpn_down / vpn_agent_status; `--yes` in it means yes:true. '
            + 'Each result is the CLI\'s own JSON; exitCode 0 ok, 1 error, 2 needs yes (preview), 3 usage.',
        },
      };
    }
    case 'ping':
      return isNotification ? null : { jsonrpc: '2.0', id, result: {} };
    case 'tools/list':
      return { jsonrpc: '2.0', id, result: { tools: TOOLS.map(publicTool) } };
    case 'tools/call':
      // A notification has no id and gets no answer, so it must not run a tool (it could spend).
      if (isNotification) return null;
      return { jsonrpc: '2.0', id, result: await callTool(params.name, params.arguments, opts) };
    default:
      if (isNotification) return null; // notifications/initialized, notifications/cancelled, …
      return rpcError(id, -32601, `method not found: ${method}`);
  }
};

export const serve = ({ input = process.stdin, output = process.stdout, ...opts } = {}) => new Promise((done) => {
  const write = (obj) => { if (obj) output.write(`${JSON.stringify(obj)}\n`); };
  const rl = createInterface({ input, crlfDelay: Infinity });
  let pending = Promise.resolve();
  rl.on('line', (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch (err) {
      process.stderr.write(`[mcp] bad JSON from client: ${err.message}\n`);
      write(rpcError(null, -32700, 'parse error'));
      return;
    }
    // One CLI call at a time: one session per machine, and chain transactions must not race.
    pending = pending.then(() => handleMessage(msg, opts)).then(write, (err) => {
      process.stderr.write(`[mcp] ${msg?.method} crashed: ${err?.stack ?? err}\n`);
      write(rpcError(msg?.id, -32603, String(err?.message ?? err)));
    });
  });
  rl.on('close', () => { pending.then(done); });
});

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  serve().catch((err) => {
    process.stderr.write(`[mcp] server stopped: ${err?.stack ?? err}\n`);
    process.exitCode = 1;
  });
}
