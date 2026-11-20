# ─── direct/schema/validate.py: check one direct/*.sh last line against its JSON Schema ───
#
#   python3 -I direct/schema/validate.py '<json line>'      # prints "ok" or the first problem; exit 0 / 1
#
# Picks the schema by shape: step faults/build without a code -> faults.json/build.json (report lines),
# needsConfirm -> preview.json, ok false -> failure.json,
# ok true -> <step>.json. Standard library only; supports the keywords the schemas use:
# type, const, enum, required, properties, additionalProperties (false), items, pattern, minLength, minimum.
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# faults.sh and build.sh end with a report, not a step result: ok false there (a failed case, a hash
# MISMATCH) has no code, so the line is checked against faults.json / build.json, not failure.json.
REPORT_STEPS = ('faults', 'build')
TYPES = {'object': dict, 'string': str, 'boolean': bool, 'array': list, 'null': type(None)}


def type_ok(v, t):
    if t == 'integer':
        return isinstance(v, int) and not isinstance(v, bool)
    if t == 'number':
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    return isinstance(v, TYPES[t])


def check(v, s, path):
    if 'const' in s and v != s['const']:
        return '%s: %r is not %r' % (path, v, s['const'])
    if 'enum' in s and v not in s['enum']:
        return '%s: %r not in %r' % (path, v, s['enum'])
    if 'type' in s:
        ts = s['type'] if isinstance(s['type'], list) else [s['type']]
        if not any(type_ok(v, t) for t in ts):
            return '%s: %r is not %s' % (path, v, '/'.join(ts))
    if isinstance(v, str):
        if len(v) < s.get('minLength', 0):
            return '%s: empty' % path
        if 'pattern' in s and not re.search(s['pattern'], v):
            return '%s: %r does not match %s' % (path, v, s['pattern'])
    if isinstance(v, (int, float)) and not isinstance(v, bool) and 'minimum' in s and v < s['minimum']:
        return '%s: %r below %r' % (path, v, s['minimum'])
    if isinstance(v, list) and 'items' in s:
        for i, item in enumerate(v):
            err = check(item, s['items'], '%s[%d]' % (path, i))
            if err:
                return err
    if isinstance(v, dict):
        for k in s.get('required', []):
            if k not in v:
                return '%s: missing %s' % (path, k)
        props = s.get('properties', {})
        for k, sub in v.items():
            if k in props:
                err = check(sub, props[k], path + '.' + k)
                if err:
                    return err
            elif s.get('additionalProperties') is False:
                return '%s: unexpected field %s' % (path, k)
    return None


def main():
    try:
        line = json.loads(sys.argv[1])
    except (IndexError, ValueError) as e:
        print('not JSON: %s' % e)
        return 1
    if not isinstance(line, dict):
        print('not a JSON object')
        return 1
    if line.get('step') in REPORT_STEPS and 'code' not in line:
        name = line['step']  # a report line: its own schema whether ok is true or false
    elif line.get('needsConfirm'):
        name = 'preview'
    elif line.get('ok') is False:
        name = 'failure'
    else:
        name = str(line.get('step', ''))
    path = os.path.join(HERE, name + '.json')
    if not re.match(r'^[a-z-]+$', name) or not os.path.exists(path):
        print('no schema for step %r' % name)
        return 1
    with open(path) as f:
        schema = json.load(f)
    err = check(line, schema, name)
    print(err or 'ok')
    return 1 if err else 0


if __name__ == '__main__':
    sys.exit(main())
