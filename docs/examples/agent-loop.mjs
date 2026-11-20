#!/usr/bin/env node
// ─── agent-loop.mjs: drive Devnet dVPN (Path A) by its --json answers only ───
//
// One Node program, no dependencies. It runs the devnet-dvpn CLI and reads ONLY the one JSON line
// each command prints and its exit code (docs/AGENT-COMMANDS.md). It never parses text output.
//
//   node agent-loop.mjs                 dry run: reads, previews, pays nothing (exit 2 at the first spend)
//   node agent-loop.mjs --yes           connect, check the exit IP, disconnect (pays the deposit)
//   node agent-loop.mjs --yes --keep    connect and stay connected
//
// Options: --cli <path> (default $DVPN_CLI or devnet-dvpn; a .js/.mjs path runs with this node),
//          --up-args "<flags>" (extra agent up flags, e.g. "--country DE --units 1"),
//          --retry-wait <s> (exit 6 retry delay, default 60), --max-steps <n> (default 6).
//
// It prints progress on stderr and ONE JSON line on stdout: { ok, exit, steps, ... }.
// Its own exit code mirrors the CLI's classes: 0 done, 1 failed (read money), 2 needs --yes,
// 3 usage, 4 needs the operator, 5 refused for safety, 6 network (retried), 10 wrong network build.

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ─── Devnet constants (check before paying) ───
const PROGRAM_ID = 'J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs';
const MINT = 'Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa';

// Commands the loop may run when `next` names them. Anything else is reported, never run.
const RUNNABLE = ['agent status', 'agent up', 'agent down', 'daemon restore-network'];

// ─── Args ───
export function parseArgs(argv) {
  const opts = { yes: false, keep: false, cli: process.env.DVPN_CLI || 'devnet-dvpn', upArgs: [], retryWait: 60, maxSteps: 6 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--yes') opts.yes = true;
    else if (a === '--keep') opts.keep = true;
    else if (a === '--cli') opts.cli = argv[++i];
    else if (a === '--up-args') opts.upArgs = (argv[++i] || '').split(/\s+/).filter(Boolean);
    else if (a === '--retry-wait') opts.retryWait = Number(argv[++i]);
    else if (a === '--max-steps') opts.maxSteps = Number(argv[++i]);
    else throw new Error(`unknown option ${a}`);
  }
  if (opts.upArgs.includes('--yes')) throw new Error('put --yes on agent-loop itself, not in --up-args');
  return opts;
}

// ─── Run one CLI command; return { exit, json } ───
export function makeRunner(cli, log = () => {}) {
  const viaNode = /\.(m?js|cjs)$/.test(cli);
  return (args) => {
    const full = [...args, '--json'];
    log(`$ ${path.basename(cli)} ${full.join(' ')}`);
    const r = spawnSync(viaNode ? process.execPath : cli, viaNode ? [cli, ...full] : full, {
      encoding: 'utf8', timeout: 10 * 60 * 1000, shell: false,
    });
    if (r.error) return { exit: 127, json: null, error: `could not run ${cli}: ${r.error.message}` };
    const line = (r.stdout || '').trim().split('\n').filter(Boolean).pop() || '';
    let json = null;
    try { json = line ? JSON.parse(line) : null; } catch (err) {
      return { exit: r.status ?? 1, json: null, error: `not JSON (${err.message}): ${line.slice(0, 200)}` };
    }
    return { exit: r.status ?? 1, json, stderr: (r.stderr || '').trim() };
  };
}

// ─── Turn a `next` / `action` string into argv, or null when it is not one plain runnable command ───
export function commandFrom(text) {
  if (typeof text !== 'string') return null;
  const t = text.trim();
  // Several steps, a wait, a choice or prose: report it, do not run it.
  if (/,| then | after | or |\(|;/.test(t)) return null;
  const words = t.split(/\s+/);
  if (!/devnet-dvpn$|^<cli>$/.test(words[0]) && words[0] !== process.env.DVPN_CLI_NAME) return null;
  const args = words.slice(1);
  if (!RUNNABLE.some((c) => args.join(' ').startsWith(c))) return null;
  return args.filter((a) => a !== '--json');
}

const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

// ─── The loop ───
export async function runLoop(opts, run, log = () => {}) {
  const steps = [];
  const done = (exit, extra = {}) => ({ ok: exit === 0, exit, steps, ...extra });
  const step = async (args) => {
    let r = run(args);
    for (let attempt = 1; r.exit === 6 && attempt <= 2; attempt++) {
      log(`network (exit 6, ${r.json?.code}): nothing changed; retry ${attempt} in ${opts.retryWait}s`);
      await sleep(opts.retryWait);
      r = run(args);
    }
    steps.push({ cmd: args.join(' '), exit: r.exit, code: r.json?.code ?? null });
    return r;
  };
  // A failure answer: stop, carry error/action/money, and close a deposit that may be open (only with --yes).
  const fail = async (r, where) => {
    const j = r.json || {};
    const out = { where, code: j.code ?? null, error: j.error ?? r.error ?? null, action: j.action ?? null, money: j.money ?? null };
    if (r.exit === 1 && opts.yes && typeof j.money === 'string' && /deposit may be open/i.test(j.money)) {
      log('money says a deposit may be open: closing it with agent down --yes');
      const d = await step(['agent', 'down', '--yes']);
      out.cleanup = { exit: d.exit, next: d.json?.next ?? null, money: d.json?.money ?? null };
    }
    return done(r.exit === 127 ? 1 : r.exit, out);
  };

  // 1. Is this the build we think it is?
  const v = await step(['version']);
  if (v.exit !== 0 || !v.json) return fail(v, 'version');
  if (v.json.programId === undefined || v.json.mint === undefined) {
    return done(10, { where: 'version', error: `version --json of ${v.json.app} has no programId/mint (0.3.0-rc.6 and later report them): update the app before paying`, money: 'Nothing was paid.' });
  }
  if (v.json.programId !== PROGRAM_ID || v.json.mint !== MINT) {
    return done(10, { where: 'version', error: `wrong build: programId ${v.json.programId}, mint ${v.json.mint}`, money: 'Nothing was paid.' });
  }

  // 2. agent status, then follow `next` until it says agent up (or there is nothing runnable).
  let status = await step(['agent', 'status']);
  for (let n = 0; n < opts.maxSteps; n++) {
    if (status.exit !== 0 || !status.json) return fail(status, 'agent status');
    const next = status.json.next;
    const cmd = commandFrom(next);
    log(`next: ${next}`);
    const wait = typeof next === 'string' && next.match(/ after (\d{4}-\d\d-\d\dT[\d:.]+Z)/);
    if (!cmd && wait) return done(0, { where: 'agent status', waitUntil: wait[1], next, why: 'a deposit is closing: run again after waitUntil' });
    if (!cmd) return done(4, { where: 'agent status', next, alsoNext: status.json.alsoNext ?? null, why: 'next is not one plain command: do it yourself (fund, create a wallet, or wait), then run again' });
    if (cmd[0] === 'agent' && cmd[1] === 'up') break; // ready to connect
    if (cmd[0] === 'agent' && cmd[1] === 'down' && status.json.connected && opts.keep) {
      return done(0, { where: 'agent status', connected: true, node: status.json.node, exitIp: status.json.exitIp ?? null, next });
    }
    // agent down / daemon restore-network: these change things, so they obey --yes too.
    const args = cmd.filter((a) => a !== '--yes');
    if (opts.yes && cmd.includes('--yes')) args.push('--yes');
    const r = await step(args);
    if (r.exit === 2) return done(2, { where: args.join(' '), what: r.json?.what ?? null, money: 'Nothing was paid.' });
    if (r.exit !== 0) return fail(r, args.join(' '));
    status = await step(['agent', 'status']);
  }

  // 3. agent up: without --yes it is a preview (exit 2, nothing signed).
  const upArgs = ['agent', 'up', ...opts.upArgs, ...(opts.yes ? ['--yes'] : [])];
  const up = await step(upArgs);
  if (up.exit === 2) return done(2, { where: 'agent up', what: up.json?.what ?? null, node: up.json?.node ?? null, deposit: up.json?.deposit ?? null, money: 'Nothing was paid.' });
  if (up.exit !== 0 || !up.json?.ok) return fail(up, 'agent up');

  // 4. Exit-IP check: traffic must leave by the node, not by this computer.
  let exitIp = up.json.exitIp ?? null;
  const directIp = up.json.directIp ?? null;
  if (exitIp === null) {
    const s = await step(['agent', 'status']);
    exitIp = s.json?.exitIp ?? null;
  }
  const tunnelled = exitIp !== null && exitIp !== directIp;
  log(`exit IP ${exitIp} (direct ${directIp}): ${tunnelled ? 'through the node' : 'NOT through the node'}`);
  const session = { node: up.json.node, protocol: up.json.protocol, exitIp, directIp, tunnelled, deposit: up.json.deposit ?? null, reused: !!up.json.reused };

  if (opts.keep && tunnelled) return done(0, { where: 'agent up', connected: true, ...session, next: up.json.next });

  // 5. agent down (also when the tunnel check failed: do not keep paying for a session that does not carry traffic).
  const down = await step(['agent', 'down', '--yes']);
  if (down.exit !== 0) return fail(down, 'agent down');
  const result = { where: 'agent down', ...session, spent: down.json.spent ?? null, refundable: down.json.refundable ?? null, readyAt: down.json.readyAt ?? null, next: down.json.next ?? null };
  return tunnelled ? done(0, result) : done(1, { ...result, code: 'not-tunnelled', error: 'the exit IP was not the node\'s', money: 'The deposit is closed or closing: the unused part comes back.' });
}

// ─── Main ───
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  let opts;
  try { opts = parseArgs(process.argv.slice(2)); } catch (err) {
    process.stderr.write(`agent-loop: ${err.message}\n`);
    process.exit(3);
  }
  const log = (m) => process.stderr.write(`agent-loop: ${m}\n`);
  const out = await runLoop(opts, makeRunner(opts.cli, log), log);
  process.stdout.write(`${JSON.stringify(out)}\n`);
  process.exit(out.exit);
}
