#!/usr/bin/env python3
"""The readability of decompiled texts, measured and compared: the automatic
form of what the manual review's second round looked for (corpus/review/r2).

    tools/readability.py texts PANCXX SIGDB LIST OUT [-j N] [--timeout S]
    tools/readability.py measure DIR OUT.jsonl[.xz]
    tools/readability.py best OUT.jsonl[.xz] SET... 
    tools/readability.py compare OLD NEW [--allow FILE [--prune]] [--report FILE.md] [--list FILE.jsonl] [--top N]
    tools/readability.py selftest

`texts` decompiles the .hex files LIST names (a file of paths, a directory)
into OUT/NAME.txt. `best` writes the best each function has shown in the
SETs (oldest first; directories of texts or `measure` files): each count
its least, each string, call, event, error and form any of them showed -
the baseline a ratchet keeps (make readability-baseline). DIR holds such NAME.txt files (`pancxx decompile
--no-color`). OLD and NEW are such directories or `measure` files. `compare` exits with status 1 when NEW
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

A rule compares one function of OLD with the same function of NEW: the same
name, overloads paired by their parameters' types, then in the order printed.
A count's tolerance is there for the counts that follow the number of paths
printed. A line's nesting is its statement's: a line indented past a
statement that opens no block continues it (a wrapped revert's arguments,
aligned past `revert with`, are no deeper than the revert). The mean nesting
is compared when either side has 30 lines or more (below, a line or two more
moves it a lot), and is a regression only when the summed nesting grew too:
a mean that rose because shallow lines left the text (raw memory writes now
decoded) is none. A string, call, event or error a
function no longer shows isn't lost when the text shows it in a function
that didn't (a message moved to the call sites, a call into a helper's def),
or in the def of a helper the function calls (`SafeMath.add(x, y)`, its
message in `def SafeMath:`). A decoded form is a kind, not a thing with a
name: the `Array` another function gained is not the one a function lost.
The Error(string) reverts printed
word by word are counted with the raw reverts: a raw revert that became an
Error with its message decoded is no regression. The `while True` loops are
counted with the rotated loops (`while _x + 1 != N`, the first iteration
printed before the loop) and the labelled jumps (`continue loop1`): they are
the prints of a loop whose exit is no plain test at its head, and one that
was rotated or left by a labelled jump and is now `while True` is no
regression - a loop with a plain test that becomes `while True` is one, and
so is a loop that becomes rotated or labelled. A loop's label (`loop1:
while ...`) doesn't hide the loop.

The allow file (`compare --prune` rewrites it: the lines no regression needs
dropped, the counts lowered): lines `NAME FUNCTION RULE [MOST]  # why`, the first three
shell patterns (`*` for any, `ensdom122_*`), MOST the most the count may
reach (for a lost_ rule, the number of items lost); a regression a line
allows is reported as allowed and doesn't fail the comparison. A known
regression listed with its count can't grow unnoticed.
"""
import argparse
import collections
import concurrent.futures
import fnmatch
import subprocess
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
HELPER = re.compile(r'\b([A-Za-z_]\w*)\.[A-Za-z_]\w*\(')   # SafeMath.add(: a call into a def's helper
MEAN_DEPTH_LINES = 30
LOOP_LABEL = re.compile(r'^loop\d+:\s+')
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
# a rule whose count is the sum of these (raw_error: with the raw reverts;
# while_true: with the rotated loops and the labelled jumps - the three
# prints of a loop whose exit is no plain test at its head)
COMBINED = {'raw_error': ('raw_error', 'raw_revert'), 'while_true': ('while_true', 'rotated', 'labels')}
# the mean nesting and the summed nesting it is compared with
NESTING = ('mean_depth', 'depth_sum')
SETS = [('strings', 'revert strings'), ('calls', 'called functions'), ('events', 'events'),
        ('errors', 'custom errors'), ('forms', 'decoded forms (Array(len=...))')]
# the sets whose items are kinds, not things with a name: an `Array` another
# function gained is not the one this function lost
KINDS = ('forms',)


def opener(path, mode):
    return lzma.open(path, mode + 't') if path.endswith('.xz') else open(path, mode)


def bracket_end(s, i):
    """the index of the ']' that closes the '[' at s[i], or -1"""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '[':
            depth += 1
        elif s[j] == ']':
            depth -= 1
            if not depth:
                return j
    return -1


def is_copy(s):
    """a plain copy, `mem[...] = mem[...]`: the whole right-hand side one memory read"""
    if not s.startswith('mem['):
        return False
    e = bracket_end(s, 3)
    rest = s[e + 1:].lstrip() if e >= 0 else ''
    if not rest.startswith('= '):
        return False
    rhs = rest[2:].strip()
    return rhs.startswith('mem[') and bracket_end(rhs, 3) == len(rhs) - 1


def signature(defline):
    """the parameters' types of a `def` line, which tell overloads apart"""
    i = defline.find('(')
    if i < 0:
        return ''
    depth, cur, parts = 0, '', []
    for ch in defline[i + 1:]:
        if ch in '([':
            depth += 1
        elif ch in ')]':
            if not depth:
                break
            depth -= 1
        if ch == ',' and not depth:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    parts.append(cur)
    return ','.join(p.strip().rsplit(' ', 1)[0] for p in parts if p.strip())


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
    helpers = set()      # the defs whose helpers it calls (SafeMath)
    body = '\n'.join(lines)
    whiles = []          # [indent, has a plain copy]
    stmt = None          # (indent, level) of a statement that opens no block
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
        if stmt and ind > stmt[0]:
            # (a line past a statement that opens no block continues it)
            level = stmt[1]
        else:
            level = (ind - 2) // 4 if ind >= 2 else 0
            stmt = None if ind < 2 or s.endswith(':') else (ind, level)
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
        sets['strings'].update(STRING.findall(s))
        helpers.update(HELPER.findall(s))
        w = LOOP_LABEL.sub('', s, count=1)
        if w.startswith('while '):
            c['while'] += 1
            c['while_true'] += w.startswith('while True')
            whiles.append([ind, 0])
        elif whiles and is_copy(s):
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
        if ROTATED.match(w):
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
                c['depth_sum'] += level
                i += 1
            sets['strings'].update(STRING.findall(st))
            helpers.update(HELPER.findall(st))
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
    if c['lines']:
        c['mean_depth'] = 100 * c['depth_sum'] // c['lines']
    m = {'n': {k: v for k, v in c.items() if v}, 's': {k: sorted(v) for k, v in sets.items() if v}}
    if helpers:
        m['h'] = sorted(helpers)
    return m


def measure_text(text):
    out = {}
    for key, lines in split_functions(text):
        m = measure_function(key.split('#')[0], lines)
        sig = signature(lines[0]) if lines else ''
        if sig:
            m['sig'] = sig
        out[key] = m
    return out


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


def best(sets):
    """The best each function has shown in SETS (oldest first; the newest set
    holding a text names its functions, the older ones' paired with them as
    compare pairs them): each count its least, each kind of item all those
    shown. A later text compared with it may fall below none of them."""
    out = {}
    for name in set().union(*sets):
        have = [s[name] for s in sets if name in s]
        ref = have[-1]
        res = {}
        for fn, m in ref.items():
            res[fn] = dict(m, n=dict(m['n']), s={k: list(v) for k, v in m['s'].items()})
        for older in have[:-1]:
            for fo, fn in pairs(older, ref):
                o, r = older[fo], res[fn]
                rn, on = r['n'], o['n']
                # (a rule counting a sum: the least sum, its other parts their
                # own least - a raw revert in one text, an Error in another
                # are one revert)
                sums = {k: min(sum(rn.get(p, 0) for p in ps), sum(on.get(p, 0) for p in ps))
                        for k, ps in COMBINED.items()}
                # (the mean nesting and the sum it is compared with: one
                # text's, the one of the least mean)
                nest = min(tuple(x.get(k, 0) for k in NESTING) for x in (rn, on))
                for k in set(rn) | set(on):
                    rn[k] = min(rn.get(k, 0), on.get(k, 0))
                for k, ps in COMBINED.items():
                    rn[k] = sums[k] - sum(rn.get(p, 0) for p in ps if p != k)
                rn.update(zip(NESTING, nest))
                for k in [k for k, v in rn.items() if not v]:
                    del rn[k]
                for k, v in o['s'].items():
                    r['s'][k] = sorted(set(r['s'].get(k, ())) | set(v))
        out[name] = res
    return out


def parse_allow(lines):
    """[(name, function, rule, most)]: allow lines `NAME FUNCTION RULE [MOST]`
    (MOST None when not given)"""
    rules = []
    for line in lines:
        line = line.split('#', 1)[0].split()
        if len(line) >= 3:
            most = int(line[3]) if len(line) >= 4 and line[3].isdigit() else None
            rules.append((line[0], line[1], line[2], most))
    return rules


def read_allow(path):
    if not path:
        return []
    with open(path) as f:
        return parse_allow(f)


def allowed(rules, name, fn, rule, value=None):
    """a line of rules allows the regression: its patterns match, and the new
    count (a lost_ rule: the number of items lost) is at most its MOST"""
    n = len(value) if isinstance(value, list) else value
    for r in rules:
        a, b, c = r[:3]
        most = r[3] if len(r) > 3 else None
        if fnmatch.fnmatchcase(name, a) and fnmatch.fnmatchcase(fn, b) and fnmatch.fnmatchcase(rule, c) and (
                most is None or (n is not None and n <= most)):
            return True
    return False


def prune_allow(lines, regs):
    """The allow file's lines with those no regression needs dropped and each
    MOST above what its regressions reach lowered to it - with the count in
    its comment (`# 5 -> 9`), or the items lost when it allows one regression.
    Returns (lines, dropped, lowered)."""
    out, dropped, lowered = [], 0, 0
    for line in lines:
        rule = parse_allow([line])
        if not rule:
            out.append(line)
            continue
        hits = [n for name, fn, r, o, n, ok in regs if allowed(rule, name, fn, r, n)]
        if not hits:
            dropped += 1
            continue
        top = max(len(n) if isinstance(n, list) else n for n in hits)
        if rule[0][3] is not None and top < rule[0][3]:
            lowered += 1
            head, sep, why = line.partition('#')
            head = re.sub(r'^(\s*\S+\s+\S+\s+\S+\s+)\d+', lambda m: m.group(1) + str(top), head)
            if len(hits) == 1 and isinstance(hits[0], list):
                why = ' ' + ', '.join(hits[0])
            elif len(hits) == 1:
                why = re.sub(r'^(\s*\d+ -> )\d+\s*$', lambda m: m.group(1) + str(top), why)
            line = head + sep + why
        out.append(line)
    return out, dropped, lowered


def anonymous(x):
    return x.startswith(('0x', 'unknown'))


def rank(key):
    return int(key.split('#')[1]) if '#' in key else 1


def pairs(olds, news):
    """[(old key, new key)]: the functions compared - the same name; overloads
    by their parameters' types first, then in the order printed"""
    def groups(fns):
        g = collections.defaultdict(list)
        for key in sorted(fns, key=rank):
            g[key.split('#')[0]].append(key)
        return g
    gn = groups(news)
    out = []
    for base, ks in groups(olds).items():
        cand = list(gn.get(base, ()))
        if len(ks) == 1 and len(cand) == 1:
            out.append((ks[0], cand[0]))
            continue
        left = []
        for k in ks:
            sig = olds[k].get('sig')
            m = next((c for c in cand if sig and news[c].get('sig') == sig), None)
            if m is None:
                left.append(k)
            else:
                cand.remove(m)
                out.append((k, m))
        out.extend(zip(left, cand))
    return out


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
        pr = pairs(old[name], new[name])
        # what NEW shows in a function whose OLD didn't (or that OLD hasn't):
        # moved there, not lost from the text
        was = {fn: old[name][fo] for fo, fn in pr}
        gained = collections.Counter()
        for fn, n in new[name].items():
            o = was.get(fn)
            for key, _ in SETS:
                if key in KINDS:
                    continue
                for x in n['s'].get(key, ()):
                    if o is None or x not in o['s'].get(key, ()):
                        gained[key, x] += 1
        # what each def of NEW shows (a helper's def: `def SafeMath:`)
        shown = {}
        for fn, n in new[name].items():
            d = shown.setdefault(fn.split('#')[0], {})
            for key, _ in SETS:
                d.setdefault(key, set()).update(n['s'].get(key, ()))
        for fo, fn in pr:
            o, n = old[name][fo], new[name][fn]
            for key, _ in SETS:
                # (what the def of a helper it calls shows isn't lost)
                reach = set()
                for h in n.get('h', ()):
                    reach |= shown.get(h, {}).get(key, set())
                lost = sorted(set(o['s'].get(key, ())) - set(n['s'].get(key, ())) - reach)
                # a selector or topic that NEW shows by its name isn't lost
                named = [x for x in set(n['s'].get(key, ())) - set(o['s'].get(key, ())) if not anonymous(x)]
                for x in [x for x in lost if anonymous(x)][:len(named)]:
                    lost.remove(x)
                for x in list(lost):
                    if gained[key, x] > 0:
                        gained[key, x] -= 1
                        lost.remove(x)
                if lost:
                    regs.append((name, fo, 'lost_' + key, len(o['s'].get(key, ())), lost,
                                 allowed(allow, name, fo, 'lost_' + key, lost)))
            for key, slack, rel, _ in RULES:
                if key == 'mean_depth' and (
                        max(o['n'].get('lines', 0), n['n'].get('lines', 0)) < MEAN_DEPTH_LINES
                        # (the mean up, the sum not: shallow lines left)
                        or n['n'].get('depth_sum', 0) <= o['n'].get('depth_sum', 0)):
                    continue
                parts = COMBINED.get(key, (key,))
                a, b = sum(o['n'].get(p, 0) for p in parts), sum(n['n'].get(p, 0) for p in parts)
                if b > a + max(slack, rel * a):
                    regs.append((name, fo, key, a, b, allowed(allow, name, fo, key, b)))
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
    # MOST: the most the count may reach (a lost_ rule: the items lost)
    regs = compare(good, bad, parse_allow(['x execute ptr_diff 2  # 0 -> 2']))[0]
    assert [r[5] for r in regs if r[2] == 'ptr_diff'] == [True], regs
    regs = compare(good, bad, parse_allow(['x execute ptr_diff 1']))[0]
    assert [r[5] for r in regs if r[2] == 'ptr_diff'] == [False], regs
    regs = compare(good, bad, parse_allow(['x execute lost_strings 1', 'x execute lost_calls 0']))[0]
    assert {r[2]: r[5] for r in regs if r[2] in ('lost_strings', 'lost_calls')} == {
        'lost_strings': True, 'lost_calls': False}, regs
    # labels don't hide loops; a copy whose address reads memory twice over is a copy
    m = measure_text('def f(): # not payable\n  loop1: while True:\n      if idx > 3:\n          break\n'
                     '      mem[idx + 192] = mem[mem[mem[64] + 32] + idx]\n      idx = idx + 32\n')['f']['n']
    assert m.get('while') == 1 and m.get('while_true') == 1 and m.get('copy_loops') == 1, m
    # strings anywhere; overloads paired by their types; moved strings not lost
    o = {'x': measure_text("def f(uint256 _a): # not payable\n  return 1\n\n"
                           "def f(address _b): # not payable\n  while True:\n      stop\n\n"
                           "def g(): # not payable\n  revert with 'X'\n")}
    n = {'x': measure_text("def f(address _b): # not payable\n  while True:\n      stop\n\n"
                           "def f(uint256 _a): # not payable\n  return 1\n\n"
                           "def g(): # not payable\n  return SafeMath.mul(1, 2, 'Y')\n\n"
                           "def h(): # not payable\n  revert with 'X'\n")}
    assert n['x']['g']['s'] == {'strings': ['Y']}, n['x']['g']
    assert not compare(o, n, [])[0], compare(o, n, [])[0]
    del n['x']['h']
    assert [r[2] for r in compare(o, n, [])[0]] == ['lost_strings']
    # a form is a kind, not a thing that moves: the `Array` another function
    # gained is not the one this function lost
    o = {'x': measure_text("def f(): # not payable\n  return Array(len=x, data=mem[128 len x])\n\n"
                           "def g(): # not payable\n  return mem[128 len 64]\n")}
    n = {'x': measure_text("def f(): # not payable\n  return mem[128 len 64]\n\n"
                           "def g(): # not payable\n  return Array(len=y, data=mem[128 len y])\n")}
    assert [(r[1], r[2]) for r in compare(o, n, [])[0] if r[2] == 'lost_forms'] == [('f', 'lost_forms')]
    # the allow file pruned: a line no regression needs dropped, a count
    # lowered with its comment, the items lost named again; the rest as it is
    regs = [('x', 'f', 'rounded', 3, 5, True), ('x', 'g', 'lost_errors', 3, ['A', 'B'], True)]
    kept, dropped, lowered = prune_allow(['# why', 'x f rounded 9  # 3 -> 9', 'x h long 4  # 1 -> 4', '',
                                          'x g lost_errors 3  # A, B, C', 'x * lost_*  # any'], regs)
    assert (kept, dropped, lowered) == (['# why', 'x f rounded 5  # 3 -> 5', '', 'x g lost_errors 2  # A, B',
                                         'x * lost_*  # any'], 1, 2), (kept, dropped, lowered)
    # a rotated loop, or one left by labelled jumps, now `while True`: no
    # regression; a loop with a plain test now `while True`, or `while True`
    # now rotated or labelled: one
    def loops(*heads):
        t = "def f(): # not payable\n"
        for h in heads:
            t += "  %s\n      x = x + 1\n%s" % (h, "      continue loop1\n" if h.startswith('loop1') else '')
        return {'x': measure_text(t)}
    plain, true, rot, lab = (loops(h) for h in ('while x < 3:', 'while True:', 'while _5 + 1 != 3:',
                                                 'loop1: while x < 3:'))
    assert (rot['x']['f']['n'].get('rotated'), lab['x']['f']['n'].get('labels')) == (1, 1), (rot, lab)
    assert not compare(rot, true, [])[0] and not compare(lab, true, [])[0], (compare(rot, true, [])[0],
                                                                             compare(lab, true, [])[0])
    assert [r[2] for r in compare(plain, true, [])[0]] == ['while_true']
    assert [r[2] for r in compare(true, rot, [])[0]] == ['rotated'], compare(true, rot, [])[0]
    assert [r[2] for r in compare(true, lab, [])[0]] == ['labels'], compare(true, lab, [])[0]
    # (the best of a rotated text and a `while True` one: either is no regression against it)
    for a, b in ((rot, true), (true, rot)):
        assert not compare(best([a, b]), true, [])[0], compare(best([a, b]), true, [])[0]
    # a raw revert become an Error is no regression; a decoded one become an Error is
    raw, err, dec = ({'x': {'f': measure_function('f', ['def f():', '  revert with ' + r])}}
                     for r in ('memory from mem[64] len 100', "Error(32, 3, 'abc', mem[_5 + 100 len 29])", "'abc'"))
    assert not compare(raw, err, [])[0] and [r[2] for r in compare(dec, err, [])[0]] == ['raw_error']

    # the mean nesting from 30 lines on either side, the old side's real value
    # (26 lines at 0.61 -> 33 at 0.69: within the slack, not 0 -> 0.69)
    def nest(n_lines, deep):
        return ['def f():'] + ['      x = 1'] * deep + ['  y = 2'] * (n_lines - 1 - deep)
    o, n = ({'x': {'f': measure_function('f', nest(k, d))}} for k, d in ((26, 16), (33, 23)))
    assert (o['x']['f']['n'].get('mean_depth'), n['x']['f']['n'].get('mean_depth')) == (61, 69)
    assert not compare(o, n, [])[0], compare(o, n, [])[0]
    o, n = ({'x': {'f': measure_function('f', nest(40, d))}} for d in (0, 39))
    assert [r[2] for r in compare(o, n, [])[0]] == ['mean_depth'], compare(o, n, [])[0]
    # the mean up because shallow lines left (60 raw writes decoded away),
    # the nested lines the same: the summed nesting didn't grow, no regression;
    # one nested line more, and it is one
    def shallow(top, deep):
        return ['def f():'] + ['  mem[x] = 1'] * top + ['  if a:', '      if b:'] + ['          y = 2'] * deep
    o, n, m = ({'x': {'f': measure_function('f', shallow(t, d))}} for t, d in ((80, 20), (20, 20), (20, 21)))
    assert (o['x']['f']['n']['mean_depth'], n['x']['f']['n']['mean_depth']) == (39, 95)
    assert not [r for r in compare(o, n, [])[0] if r[2] == 'mean_depth'], compare(o, n, [])[0]
    assert [r[2] for r in compare(o, m, [])[0] if r[2] == 'mean_depth'] == ['mean_depth'], compare(o, m, [])[0]
    # the best of two texts keeps the mean and the sum of one text: either
    # text compared with it is no regression
    assert best([o, n])['x']['f']['n']['depth_sum'] == best([n, o])['x']['f']['n']['depth_sum'] == 41
    assert not [r for r in compare(best([o, n]), n, [])[0] + compare(best([n, o]), o, [])[0] if r[2] == 'mean_depth']
    # a wrapped statement's lines are no deeper than the statement: a revert's
    # arguments aligned past `revert with`, a raw revert's `from` and `len`
    def wrapped(args):
        return ['def f():', '  if a:', '      if b:', '          revert with 0x12345678, '] + \
               ['                      %s' % x for x in args] + ['  stop']
    o, n = ({'x': {'f': measure_function('f', t)}} for t in (
        ['def f():', '  if a:', '      if b:', '          revert with memory', '            from _1 + 32',
         '             len mem[_1]', '  stop'], wrapped(['0,', 'x * y,', 'z - 1'])))
    assert (o['x']['f']['n']['depth'], n['x']['f']['n']['depth']) == (2, 2), (o, n)
    assert n['x']['f']['n']['depth_sum'] == 1 + 2 * 4, n
    assert not [r for r in compare(o, n, [])[0] if r[2] in ('depth', 'mean_depth')], compare(o, n, [])[0]
    # (a block's lines are not its opener's continuation; a log's arguments are)
    t = measure_function('f', ['def f(): # not payable', '  while a:', '      if b:', '          x = 1',
                               '      log Transfer(', '            address from=x,', '            uint256 value=y)'])
    assert (t['n']['depth'], t['n']['depth_sum'], t['n']['lines']) == (2, 0 + 1 + 2 + 3 * 1, 7), t
    # a message now in the def of a helper the function calls isn't lost
    lib = ("def SafeMath:\n  def add(a, b):\n      if a + b < a:\n          revert with 'addition overflow'\n"
           "      return a + b\n\n")
    o = {'x': measure_text(lib + "def f(): # not payable\n  if x + y < y:\n      revert with 'addition overflow'\n"
                           "  return x + y\n")}
    n = {'x': measure_text(lib + "def f(): # not payable\n  return SafeMath.add(x, y)\n")}
    assert n['x']['f'].get('h') == ['SafeMath'] and not compare(o, n, [])[0], compare(o, n, [])[0]
    n = {'x': measure_text(lib + "def f(): # not payable\n  return x + y\n")}
    assert [r[2] for r in compare(o, n, [])[0]] == ['lost_strings'], compare(o, n, [])[0]
    # the best of several texts: each count its least, the items of all
    a = {'x': {'f': measure_function('f', ['def f():', "  revert with 'a'"] + ['  ' + 'x' * 250] * 3)}}
    b = {'x': {'f': measure_function('f', ['def f():', "  revert with 'b'"] + ['  ' + 'x' * 250] * 5)}}
    m = best([a, b])['x']['f']
    assert m['n']['long'] == 3 and m['s']['strings'] == ['a', 'b'], m
    assert sorted(r[2] for r in compare(best([a, b]), b, [])[0]) == ['long', 'lost_strings']
    assert not compare(best([a, b]), best([a, b]), [])[0]
    # (a raw revert in one, an Error with its message in the next: one revert, the message gained)
    raw1, err1 = ({'x': {'f': measure_function('f', ['def f():', '  revert with ' + x])}}
                  for x in ('memory from mem[64] len 100', "Error(32, 3, 'abc', mem[_5 + 100 len 29])"))
    assert not compare(best([raw1, err1]), err1, [])[0], compare(best([raw1, err1]), err1, [])[0]
    assert sorted(r[2] for r in compare(best([err1, raw1]), raw1, [])[0]) == ['lost_strings', 'raw_revert']
    print('readability selftest: ok')
    return 0


def hex_list(spec):
    if os.path.isdir(spec):
        return sorted(os.path.join(spec, f) for f in os.listdir(spec) if f.endswith('.hex'))
    if spec.endswith('.hex'):
        return [spec]
    return [l.strip() for l in open(spec) if l.strip() and not l.startswith('#')]


def texts(pancxx, sigdb, spec, out, jobs, timeout):
    os.makedirs(out, exist_ok=True)
    env = dict(os.environ, PANORAMIX_SIGDB=os.path.abspath(sigdb), PANORAMIX_LOG='error')
    paths = hex_list(spec)

    def one(hexp):
        name = os.path.basename(hexp)[:-4]
        try:
            r = subprocess.run([pancxx, 'decompile', hexp, '--no-color', '-j', '1'], env=env, capture_output=True,
                               text=True, timeout=timeout)
            text = r.stdout if r.stdout else '# decompile: rc %d %s\n' % (r.returncode, r.stderr[-300:])
        except subprocess.TimeoutExpired:
            text = '# decompile: timeout\n'
        with open(os.path.join(out, name + '.txt'), 'w') as f:
            f.write(text)
        return text.startswith('# decompile:')

    with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
        failed = sum(ex.map(one, paths))
    print('%d texts in %s%s' % (len(paths), out, ', %d failed' % failed if failed else ''))
    return 2 if failed else 0


def main():
    if sys.argv[1:] == ['selftest']:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    t = sub.add_parser('texts')
    t.add_argument('pancxx')
    t.add_argument('sigdb')
    t.add_argument('list')
    t.add_argument('out')
    t.add_argument('-j', type=int, default=2)
    t.add_argument('--timeout', type=int, default=900)
    m = sub.add_parser('measure')
    m.add_argument('dir')
    m.add_argument('out')
    b = sub.add_parser('best')
    b.add_argument('out')
    b.add_argument('sets', nargs='+')
    c = sub.add_parser('compare')
    c.add_argument('old')
    c.add_argument('new')
    c.add_argument('--allow', default='')
    c.add_argument('--report', default='')
    c.add_argument('--list', default='')
    c.add_argument('--top', type=int, default=30)
    c.add_argument('--prune', action='store_true',
                   help='rewrite the allow file: its useless lines dropped, its counts lowered')
    a = ap.parse_args()
    if a.cmd == 'texts':
        return texts(a.pancxx, a.sigdb, a.list, a.out, a.j, a.timeout)
    if a.cmd == 'measure':
        data = measure_dir(a.dir)
        save(data, a.out)
        print('%d texts measured' % len(data))
        return 0
    if a.cmd == 'best':
        data = best([load(x) for x in a.sets])
        save(data, a.out)
        print('%d texts: the best of %d sets' % (len(data), len(a.sets)))
        return 0
    old, new = load(a.old), load(a.new)
    rules = read_allow(a.allow)
    regs, tot_old, tot_new = compare(old, new, rules)
    bad = [r for r in regs if not r[5]]
    # the allow lines no regression needs, and those whose MOST is above what they allow now
    top = collections.defaultdict(int)
    for name, fn, rule, o, n, ok in regs:
        if ok:
            for i, r in enumerate(rules):
                if allowed([r], name, fn, rule, n):
                    top[i] = max(top[i], len(n) if isinstance(n, list) else n)
    stale = [' '.join(r[:3]) for i, r in enumerate(rules) if i not in top]
    lower = ['%s %d -> %d' % (' '.join(r[:3]), r[3], top[i]) for i, r in enumerate(rules)
             if i in top and r[3] is not None and top[i] < r[3]]
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
        # (a sum of means is no total)
        summed = not key.startswith('lost_') and key != 'mean_depth'
        out.append('| %s (%s) | %d | %d | %s | %s |' % (
            key, what[key], by_rule[key], len({r[0] for r in bad if r[2] == key}),
            tot_old[base] if summed else '', tot_new[base] if summed else ''))
    out += ['', '| also | total before | total after |', '|---|---|---|']
    for key in ('lines', 'while'):
        out.append('| %s | %d | %d |' % (key, tot_old[key], tot_new[key]))
    per_text = collections.Counter(r[0] for r in bad)
    out += ['', '## The texts with the most regressions', '']
    for name, k in per_text.most_common(a.top):
        rules = collections.Counter(r[2] for r in bad if r[0] == name)
        out.append('- %s: %d (%s)' % (name, k, ', '.join('%s %d' % kv for kv in rules.most_common())))
    if stale:
        out += ['', '## Allow lines no regression needs (delete them)', ''] + ['- ' + x for x in stale]
    if lower:
        out += ['', '## Allow lines whose count can go down', ''] + ['- ' + x for x in lower]
    out.insert(4, '%d allow lines no regression needs, %d whose count can go down.' % (len(stale), len(lower)))
    text = '\n'.join(out) + '\n'
    if a.report:
        open(a.report, 'w').write(text)
    if a.list:
        with open(a.list, 'w') as f:
            for name, fn, rule, o, n, ok in regs:
                f.write(json.dumps({'name': name, 'function': fn, 'rule': rule, 'old': o, 'new': n,
                                    'allowed': ok}) + '\n')
    print(text if not a.report else '\n'.join(out[:5]))
    if a.prune and a.allow and not bad and (stale or lower):
        with open(a.allow) as f:
            kept, dropped, lowered = prune_allow(f.read().split('\n'), regs)
        with open(a.allow, 'w') as f:
            f.write('\n'.join(kept))
        print('%s: %d lines dropped, %d counts lowered' % (a.allow, dropped, lowered))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
