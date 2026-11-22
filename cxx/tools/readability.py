#!/usr/bin/env python3
"""The readability of decompiled texts, measured and compared: the automatic
form of what the manual review's second round looked for (corpus/review/r2).

    tools/readability.py measure DIR OUT.jsonl[.xz]
    tools/readability.py compare OLD NEW [--allow FILE] [--report FILE.md] [--list FILE.jsonl] [--top N]
    tools/readability.py selftest

DIR holds NAME.txt files (`pancxx decompile --no-color`). OLD and NEW are
such directories or `measure` files. `compare` exits with status 1 when NEW
has a regression that FILE doesn't allow.

What is measured, per function of a text:

- what the text shows decoded - the strings a revert gives, the names of the
  functions called, of the events logged, the custom errors (names or
  selectors). One that OLD has and NEW hasn't is a regression: the revert,
  call or event is still there, as raw memory;
- counts of the forms a reader can't follow, each of which must not grow
  (the rules are RULES below): reverts, returns, call arguments, call
  functions and event data printed as raw memory; differences of two reads
  of the free memory pointer left unfolded; storage keys hashed from raw
  memory; arguments split in byte slices; copies left as loops, `while
  True` loops, loop labels, rotated loops; aborted paths; GAS reads
  nothing uses, GAS read inside an expression; a loop variable carried as
  an offset of a hash; stores of the bytes after a selector; Error(string)
  reverts printed word by word; constants factored by a time unit, words of
  63 hex digits; lines over 240 characters or with four or more rounded
  lengths; raw memory writes; the nesting depth; the text's size.

A rule compares one function of OLD with the same function of NEW (same
name, same rank among the functions of that name); a count's tolerance is
there for the counts that follow the number of paths printed.

The allow file: lines `NAME FUNCTION RULE  # why` (`*` for any); a
regression it lists is reported as allowed and doesn't fail the comparison.
"""
import argparse
import collections
import json
import lzma
import os
import re
import sys

LONG = 240
STRING = re.compile(r"'((?:[^'\\]|\\.)*)'")
CALL = re.compile(r'^(?:static call|delegate|call) (.*?) with:')
FN = re.compile(r'\.([A-Za-z_]\w*)\(')
LOG_NAME = re.compile(r'^log ([A-Za-z_]\w*)\(')
LOG_TOPIC = re.compile(r'^log (0x[0-9a-f]{8})[0-9a-f]*')
ERR_NAME = re.compile(r'^revert with ([A-Za-z_]\w*)\(')
ERR_SEL = re.compile(r'^revert with (0x[0-9a-f]{8})\b')
PTR_DIFF = re.compile(r'- mem\[64\]|len [^\]]*?_\d+ - _\d+')
SPLIT = re.compile(r'Bytes\(28, .*?\), Bytes\(4, ')
GAS_VAR = re.compile(r'^(_\d+) = gas_remaining$')
OFFSET = re.compile(r'^\w+ = sha3\((.*)\) - (.+)$')
MEM_WRITE = re.compile(r'^mem\[.*\] = ')
PARTIAL = re.compile(r'^mem\[.* len 28\] = ')
TIME_CONST = re.compile(r'0x[0-9a-f]{9,} \* (60|3600|86400|604800|31536000)\b')
ROTATED = re.compile(r'^while _\w+ \+ 1 != \d+:')
ODD_HEX = re.compile(r'\b0x[0-9a-f]{63}\b')
GAS_LINE = re.compile(r'^(gas |_\d+ = gas_remaining$)')
COPY = re.compile(r'^mem\[.*\]\s*=\s*mem\[[^\[\]]*(\[[^\[\]]*\][^\[\]]*)*\]$')
ROUNDED = ('ceil32(', 'floor32(', 'Mask(250, 5')

# the counts, and how much one may grow: (name, absolute slack, relative slack, what it is)
RULES = [
    ('raw_revert', 0, 0.0, 'reverts printed as raw memory'),
    ('raw_return', 0, 0.0, 'returns printed as raw memory'),
    ('raw_args', 0, 0.0, "calls' arguments holding raw memory"),
    ('raw_fn', 0, 0.0, 'calls whose function is a memory slice'),
    ('raw_log', 0, 0.0, 'events whose data hold raw memory'),
    ('ptr_diff', 0, 0.0, 'differences of free-pointer reads left unfolded'),
    ('raw_stor', 0, 0.0, 'storage keys or hashes of raw memory'),
    ('split_args', 0, 0.0, 'arguments split in byte slices'),
    ('copy_loops', 0, 0.0, 'memory copies left as loops'),
    ('while_true', 0, 0.0, '`while True` loops'),
    ('labels', 0, 0.0, 'loop labels (continue loopN)'),
    ('aborted', 0, 0.0, 'aborted paths'),
    ('unused_gas', 0, 0.0, 'GAS reads nothing uses'),
    ('offset_loop', 0, 0.0, 'loop variables carried as an offset of a hash'),
    ('partial_store', 0, 0.0, 'stores of the 28 bytes after a selector'),
    ('raw_error', 0, 0.0, 'Error(string) reverts printed word by word'),
    ('inline_gas', 0, 0.0, 'GAS read inside an expression'),
    ('time_const', 0, 0.0, 'big constants factored by a time unit'),
    ('rotated', 0, 0.0, 'rotated loops (while _x + 1 != N)'),
    ('identity', 0, 0.0, 'unused identity-precompile copies'),
    ('odd_hex', 0, 0.0, 'words printed with 63 hex digits'),
    ('long', 1, 0.10, 'lines over %d characters' % LONG),
    ('rounded', 1, 0.10, 'lines with four or more rounded lengths'),
    ('mem_writes', 2, 0.10, 'raw memory writes'),
    ('depth', 2, 0.0, 'the deepest nesting'),
    ('mean_depth', 50, 0.20, 'the mean nesting, in hundredths of a level'),
    ('chars', 2000, 0.25, "the function's size in characters"),
    ('structs', 0, 0.0, "`def storage` lines with a struct"),
]
SETS = [('strings', 'revert strings'), ('calls', 'called functions'), ('events', 'events'),
        ('errors', 'custom errors'), ('forms', 'decoded forms (Array(len=...))')]


def opener(path, mode):
    return lzma.open(path, mode + 't') if path.endswith('.xz') else open(path, mode)


def split_functions(text):
    """[(key, [lines])]: the text's `def` blocks, the same names ranked"""
    out, cur, seen = [], None, collections.Counter()
    for line in text.split('\n'):
        if line.startswith('def '):
            name = re.match(r'def (\w+)', line).group(1)
            seen[name] += 1
            cur = [name if seen[name] == 1 else '%s#%d' % (name, seen[name]), []]
            out.append(cur)
        if cur is not None:
            cur[1].append(line)
    return out


def measure_function(name, lines):
    c = collections.Counter()
    sets = {k: set() for k, _ in SETS}
    body = '\n'.join(lines)
    whiles = []          # [indent, has a plain copy]
    i = 0
    while i < len(lines):
        raw = lines[i]
        i += 1
        s = raw.strip()
        if not s:
            continue
        ind = len(raw) - len(raw.lstrip(' '))
        c['lines'] += 1
        c['chars'] += len(raw)
        level = (ind - 2) // 4 if ind >= 2 else 0
        c['depth'] = max(c['depth'], level)
        c['depth_sum'] += level
        if len(raw) > LONG:
            c['long'] += 1
        if sum(s.count(t) for t in ROUNDED) >= 4:
            c['rounded'] += 1
        while whiles and ind <= whiles[-1][0]:
            c['copy_loops'] += whiles.pop()[1]
        if name == 'storage':
            c['structs'] += 'struct' in s
            continue
        if s.startswith('while '):
            c['while'] += 1
            c['while_true'] += s.startswith('while True')
            whiles.append([ind, 0])
        elif whiles and COPY.match(s):
            whiles[-1][1] = 1
        if s.startswith(('continue loop', 'break loop')):
            c['labels'] += 1
        if MEM_WRITE.match(s):
            c['mem_writes'] += 1
            c['partial_store'] += bool(PARTIAL.match(s))
        if 'gas_remaining' in s and not GAS_LINE.match(s):
            c['inline_gas'] += 1
        if TIME_CONST.search(s):
            c['time_const'] += 1
        if ROTATED.match(s):
            c['rotated'] += 1
        if 'copied = identity(' in s:
            c['identity'] += 1
        if ODD_HEX.search(s):
            c['odd_hex'] += 1
        if 'Array(len=' in s:
            sets['forms'].add('Array')
        if 'Decompilation aborted' in s:
            c['aborted'] += 1
        if PTR_DIFF.search(s):
            c['ptr_diff'] += 1
        if 'sha3(mem[' in s or 'concat(mem[' in s:
            c['raw_stor'] += 1
        if SPLIT.search(s):
            c['split_args'] += 1
        m = GAS_VAR.match(s)
        if m and len(re.findall(r'\b%s\b' % m.group(1), body)) == 1:
            c['unused_gas'] += 1
        m = OFFSET.match(s)
        if m and m.group(2).strip() in m.group(1):
            c['offset_loop'] += 1
        if s.startswith('revert with'):
            if s.startswith(('revert with memory', 'revert with mem[')):
                c['raw_revert'] += 1
            if s.startswith('revert with Error('):
                c['raw_error'] += 1
            sets['strings'].update(STRING.findall(s))
            m = ERR_NAME.match(s)
            if m and m.group(1) not in ('Panic', 'Error', 'Bytes'):
                sets['errors'].add(m.group(1))
            m = ERR_SEL.match(s)
            if m:
                sets['errors'].add(m.group(1))
        elif s.startswith(('return memory', 'return mem[')):
            c['raw_return'] += 1
        elif s.startswith('args ') and 'mem[' in s:
            c['raw_args'] += 1
        elif s.startswith('log '):
            st = s
            while st.count('(') > st.count(')') and i < len(lines):   # its arguments' lines
                st += ' ' + lines[i].strip()
                c['lines'] += 1
                c['chars'] += len(lines[i])
                i += 1
            if 'mem[' in st:
                c['raw_log'] += 1
            m = LOG_NAME.match(st) or LOG_TOPIC.match(st)
            if m:
                sets['events'].add(m.group(1))
        else:
            m = CALL.match(s)
            if m:
                head = m.group(1)
                if '.mem[' in head:
                    c['raw_fn'] += 1
                names = FN.findall(head)
                if names:
                    sets['calls'].add(names[-1])
    c['copy_loops'] += sum(w[1] for w in whiles)
    if c['lines'] >= 30:
        c['mean_depth'] = 100 * c['depth_sum'] // c['lines']
    del c['depth_sum']
    return {'n': {k: v for k, v in c.items() if v}, 's': {k: sorted(v) for k, v in sets.items() if v}}


def measure_text(text):
    return {key: measure_function(key.split('#')[0], lines) for key, lines in split_functions(text)}


def measure_dir(d):
    out = {}
    for f in sorted(os.listdir(d)):
        if f.endswith('.txt'):
            out[f[:-4]] = measure_text(open(os.path.join(d, f), errors='replace').read())
    return out


def load(path):
    if os.path.isdir(path):
        return measure_dir(path)
    out = {}
    with opener(path, 'r') as f:
        for line in f:
            r = json.loads(line)
            out[r['name']] = r['functions']
    return out


def save(data, path):
    with opener(path, 'w') as f:
        for name in sorted(data):
            f.write(json.dumps({'name': name, 'functions': data[name]}, sort_keys=True, separators=(',', ':')) + '\n')


def read_allow(path):
    rules = []
    if path:
        for line in open(path):
            line = line.split('#', 1)[0].split()
            if len(line) >= 3:
                rules.append(tuple(line[:3]))
    return rules


def allowed(rules, name, fn, rule):
    return any(a in ('*', name) and b in ('*', fn) and c in ('*', rule) for a, b, c in rules)


def anonymous(x):
    return x.startswith(('0x', 'unknown'))


def compare(old, new, allow):
    """the regressions [(name, function, rule, old, new, allowed)] and the totals"""
    regs = []
    tot_old, tot_new = collections.Counter(), collections.Counter()
    for name in sorted(new):
        if name not in old:
            continue
        for fn, m in new[name].items():
            for k, v in m['n'].items():
                tot_new[k] += v
        for fn, m in old[name].items():
            for k, v in m['n'].items():
                tot_old[k] += v
        for fn, o in old[name].items():
            n = new[name].get(fn)
            if n is None:
                continue        # a function OLD has and NEW hasn't: the checks by execution's matter
            for key, _ in SETS:
                lost = sorted(set(o['s'].get(key, ())) - set(n['s'].get(key, ())))
                # a selector or topic that NEW shows by its name isn't lost
                named = [x for x in set(n['s'].get(key, ())) - set(o['s'].get(key, ())) if not anonymous(x)]
                for x in [x for x in lost if anonymous(x)][:len(named)]:
                    lost.remove(x)
                if lost:
                    regs.append((name, fn, 'lost_' + key, len(o['s'].get(key, ())), lost,
                                 allowed(allow, name, fn, 'lost_' + key)))
            for key, slack, rel, _ in RULES:
                a, b = o['n'].get(key, 0), n['n'].get(key, 0)
                if b > a + max(slack, rel * a):
                    regs.append((name, fn, key, a, b, allowed(allow, name, fn, key)))
    return regs, tot_old, tot_new


GOOD = '''def storage:
  owner is address at storage 0

def execute(uint256 _param1): # not payable
  require calldata.size - 4 >=′ 32
  if not stor1[_param1]:
      revert with 'Governor: unknown proposal id'
  idx = 0
  while idx < stor2.length:
      mem[idx + 192] = stor[idx + sha3(2)]
      idx = idx + 32
  call timelock.queueTransaction(address target, uint256 value) with:
       gas gas_remaining
      args owner, _param1
  if not ext_call.success:
      revert with ext_call.return_data[0 len return_data.size]
  log ProposalExecuted(
        uint256 proposalId=_param1)
  return Array(len=stor2.length, data=mem[192 len stor2.length])
'''
BAD = '''def storage:
  owner is address at storage 0

def execute(uint256 _param1): # not payable
  require calldata.size - 4 >=′ 32
  _3 = gas_remaining
  _5 = mem[64]
  if not stor1[_param1]:
      mem[mem[64]] = 0x08c379a000000000000000000000000000000000000000000000000000000000
      revert with memory from mem[64] len _5 - mem[64] + 100
  idx = 0
  while True:
      if idx >= stor2.length:
          break
      mem[idx + 192] = mem[idx + 320]
      idx = idx + 32
  mem[_5 + 36 len 28] = owner >> 32
  call timelock.mem[_5 len 4] with:
       gas gas_remaining
      args Bytes(28, owner >> 32), Bytes(4, uint32(owner)), mem[_5 + 36 len 32]
  if not ext_call.success:
      revert with ext_call.return_data[0 len return_data.size]
  log 0x712ae1383f79ac853f8d882153778e0260ef8f03b504e2866e0593e04d2b291f: mem[mem[64] len 32]
  return memory from mem[64] len _5 - mem[64] + 64
'''


def selftest():
    good, bad = {'x': measure_text(GOOD)}, {'x': measure_text(BAD)}
    g, b = good['x']['execute'], bad['x']['execute']
    assert g['s'] == {'strings': ['Governor: unknown proposal id'], 'calls': ['queueTransaction'],
                      'events': ['ProposalExecuted'], 'forms': ['Array']}, g['s']
    assert g['n'].get('while') == 1 and 'copy_loops' not in g['n'] and 'raw_revert' not in g['n'], g['n']
    for key, want in (('raw_revert', 1), ('raw_return', 1), ('raw_args', 1), ('raw_fn', 1), ('raw_log', 1),
                      ('ptr_diff', 2), ('split_args', 1), ('copy_loops', 1), ('while_true', 1),
                      ('unused_gas', 1), ('partial_store', 1), ('mem_writes', 3)):
        assert b['n'].get(key) == want, (key, b['n'].get(key))
    regs, _, _ = compare(good, bad, [])
    rules = {r[2] for r in regs}
    for want in ('lost_strings', 'lost_calls', 'lost_events', 'lost_forms', 'raw_revert', 'raw_fn', 'raw_log',
                 'raw_return', 'raw_args', 'ptr_diff', 'split_args', 'copy_loops', 'while_true', 'unused_gas',
                 'partial_store'):
        assert want in rules, want
    assert not compare(good, good, [])[0] and not compare(bad, good, [])[0]
    assert all(r[5] for r in compare(good, bad, [('x', '*', '*')])[0])
    print('readability selftest: ok')
    return 0


def main():
    if sys.argv[1:] == ['selftest']:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    m = sub.add_parser('measure')
    m.add_argument('dir')
    m.add_argument('out')
    c = sub.add_parser('compare')
    c.add_argument('old')
    c.add_argument('new')
    c.add_argument('--allow', default='')
    c.add_argument('--report', default='')
    c.add_argument('--list', default='')
    c.add_argument('--top', type=int, default=30)
    a = ap.parse_args()
    if a.cmd == 'measure':
        data = measure_dir(a.dir)
        save(data, a.out)
        print('%d texts measured' % len(data))
        return 0
    old, new = load(a.old), load(a.new)
    regs, tot_old, tot_new = compare(old, new, read_allow(a.allow))
    bad = [r for r in regs if not r[5]]
    names = {r[0] for r in bad}
    what = dict((k, w) for k, _, _, w in RULES)
    what.update(('lost_' + k, w + ' no longer shown') for k, w in SETS)
    by_rule = collections.Counter(r[2] for r in bad)
    out = ['# Readability: %s -> %s' % (a.old, a.new), '',
           '%d texts compared (%d only in the old set, %d only in the new).' % (
               len(set(old) & set(new)), len(set(old) - set(new)), len(set(new) - set(old))),
           '%d regressions in %d texts%s.' % (len(bad), len(names),
                                              '; %d more allowed' % (len(regs) - len(bad)) if len(regs) > len(bad)
                                              else ''),
           '', '| rule | regressions | texts | total before | total after |', '|---|---|---|---|---|']
    for key in [k for k, _, _, _ in RULES] + ['lost_' + k for k, _ in SETS]:
        base = key[5:] if key.startswith('lost_') else key
        out.append('| %s (%s) | %d | %d | %s | %s |' % (
            key, what[key], by_rule[key], len({r[0] for r in bad if r[2] == key}),
            tot_old[base] if not key.startswith('lost_') else '', tot_new[base] if not key.startswith('lost_') else ''))
    out += ['', '| also | total before | total after |', '|---|---|---|']
    for key in ('lines', 'while'):
        out.append('| %s | %d | %d |' % (key, tot_old[key], tot_new[key]))
    per_text = collections.Counter(r[0] for r in bad)
    out += ['', '## The texts with the most regressions', '']
    for name, k in per_text.most_common(a.top):
        rules = collections.Counter(r[2] for r in bad if r[0] == name)
        out.append('- %s: %d (%s)' % (name, k, ', '.join('%s %d' % kv for kv in rules.most_common())))
    text = '\n'.join(out) + '\n'
    if a.report:
        open(a.report, 'w').write(text)
    if a.list:
        with open(a.list, 'w') as f:
            for name, fn, rule, o, n, ok in regs:
                f.write(json.dumps({'name': name, 'function': fn, 'rule': rule, 'old': o, 'new': n,
                                    'allowed': ok}) + '\n')
    print(text if not a.report else '\n'.join(out[:4]))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
