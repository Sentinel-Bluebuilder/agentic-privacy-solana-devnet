// ─── check-agent-answers.mjs: docs/agent-answers.schema.json against fixtures/agent-answers.jsonl ───
// Each fixture line is {"def": "<a $defs name>", "from": "<where it came from>", "answer": {…}}: one real-shape
// answer of `devnet-dvpn agent status|up|down --json`. Every line must pass its own def AND the top-level schema.
// Then a set of broken answers (one per def) must each FAIL: a validator that passes everything is caught.
//
// Needs Ajv 8 (draft 2020-12): run from a folder where `npm i ajv@8.17.1` was done, or set NODE_PATH.
// Usage: node tools/check-agent-answers.mjs [schema] [fixtures]
// Exit: 0 all pass and every control is caught · 1 otherwise.
// strictRequired is off: it is Ajv's own lint and rejects `required` inside if/then, which 2020-12 allows.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(`${process.cwd()}/`);
const Ajv2020 = require('ajv/dist/2020.js');
const AjvClass = Ajv2020.default ?? Ajv2020;

const here = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const [schemaPath = `${here}docs/agent-answers.schema.json`, fixturesPath = `${here}fixtures/agent-answers.jsonl`] = process.argv.slice(2);

const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
const ajv = new AjvClass({ allErrors: true, strict: true, strictRequired: false });
ajv.addSchema(schema, 's');
const def = (name) => {
  const fn = ajv.getSchema(`s#/$defs/${name}`);
  if (!fn) throw new Error(`no $defs/${name} in ${schemaPath}`);
  return fn;
};
const top = ajv.getSchema('s');

// ─── Fixtures: every line passes ───
const lines = readFileSync(fixturesPath, 'utf8').split('\n').filter((l) => l.trim());
let bad = 0;
const perDef = {};
for (const [i, l] of lines.entries()) {
  const row = JSON.parse(l);
  const fn = def(row.def);
  const ok = fn(row.answer) && top(row.answer);
  perDef[row.def] = (perDef[row.def] ?? 0) + 1;
  if (!ok) {
    bad += 1;
    console.log(`FAIL line ${i + 1} (${row.def}, ${row.from}): ${JSON.stringify(fn.errors ?? top.errors)}`);
  }
}
console.log(`fixtures: ${lines.length} lines, ${bad} failed, per def ${JSON.stringify(perDef)}`);

// ─── Negative controls: each must fail ───
const neg = [
  ['statusAnswer', { ok: true, address: null, sol: null, tdvpn: null, device: null, service: true, connected: false, next: 'x' }, 'no held'],
  ['upAnswer', { ok: true, connected: true, session: 'S', node: 'N', protocol: 'wireguard', exitIp: null, socks: null, wholeDevice: true, deposit: null, next: 'x', limitRaised: { from: '1', to: '2', fromBase: '1', toBase: '2' } }, 'limitRaised without limitNote'],
  ['upConfirm', { needsConfirm: true, what: 'x', node: 'N', switchFrom: null }, 'no deposit'],
  ['downAnswer', { ok: true, disconnected: null, spent: null, refundable: 'abc', readyAt: null, signatures: [], pending: [], next: 'x' }, 'amount not a number'],
  ['downConfirm', { needsConfirm: true, what: 'x', session: null, perHour: -1, perGb: 0 }, 'negative count'],
  ['errorAnswer', { ok: false, error: 'x', action: null }, 'no code'],
];
let caught = 0;
for (const [name, obj, why] of neg) {
  if (!def(name)(obj)) caught += 1;
  else console.log(`CONTROL NOT CAUGHT: ${name} (${why})`);
}
console.log(`negative controls: ${caught} of ${neg.length} caught`);

const pass = lines.length > 0 && bad === 0 && caught === neg.length;
console.log(pass ? 'PASS' : 'FAIL');
process.exit(pass ? 0 : 1);
