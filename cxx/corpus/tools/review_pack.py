#!/usr/bin/env python3
"""Review packs: for each contract of a tranche of review_select.py's list,
the decompiled text and, function by function, the source beside it.

    review_pack.py --build BUILD --sources IMMUNEFI --contracts contracts.jsonl --tranche N
                   --pancxx PANCXX --sigdb DB --out DIR [--jobs 2] [--timeout 900]
    review_pack.py ... --batches K     (DIR/batches/bNN.txt: K lists of ids, balanced by pack lines)

DIR/dec/ID.txt and ID.json: pancxx's text and JSON (made once; a later run
reuses them). DIR/packs/ID.md: the pack -
  - the artifact, its compiler and EVM, its other builds and duplicates;
  - the compiler's storage layout beside the text's `def storage:`;
  - each ABI function: its source (the function, with the modifiers and the
    internal functions it reaches listed), then its decompiled function with
    the text's line numbers;
  - the decompiled functions the ABI hasn't, the ABI functions not decompiled;
  - the internal functions and modifiers reached, each once.
IMMUNEFI is the corpus' immunefi/ directory (the sources at the paths the
build saw them: PROGRAM/REPO[/PROJECT]/ + the AST's absolutePath).
"""
import argparse
import collections
import concurrent.futures
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('compare_source', os.path.join(HERE, 'compare_source.py'))
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)
_spec = importlib.util.spec_from_file_location('review_select', os.path.join(HERE, 'review_select.py'))
rsel = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rsel)

ANSI = re.compile(r'\x1b\[[0-9;]*m')
MAX_REACHED = 400


# ---- sources -------------------------------------------------------------------------------

class Sources:
    """the source files of one project, by the AST's absolutePath"""

    def __init__(self, root, repo_root):
        self.root, self.repo_root = root, repo_root
        self.cache = {}
        self._walk = None

    def _suffix_index(self):
        if self._walk is None:
            self._walk = collections.defaultdict(list)
            for d, _, files in os.walk(self.repo_root):
                for f in files:
                    if f.endswith(('.sol', '.vy', '.vyi', '.yul')):
                        p = os.path.join(d, f)
                        self._walk[f].append(p)
        return self._walk

    def path(self, ap):
        for base in (self.root, os.path.join(self.root, 'node_modules'), self.repo_root,
                     os.path.join(self.repo_root, 'node_modules')):
            p = os.path.normpath(os.path.join(base, ap))
            if os.path.isfile(p):
                return p
        # a remapped import: the file whose path ends the same, the longest match
        parts = ap.split('/')
        best, score = None, 0
        for p in self._suffix_index().get(parts[-1], []):
            q = p.split('/')
            n = 0
            while n < min(len(q), len(parts)) and q[-1 - n] == parts[-1 - n]:
                n += 1
            if n > score:
                best, score = p, n
        return best

    def bytes(self, ap):
        if ap not in self.cache:
            p = self.path(ap)
            self.cache[ap] = (p, open(p, 'rb').read() if p else None)
        return self.cache[ap]


def node_text(srcs, files, node):
    """(path, first line, text) of an AST node's source"""
    try:
        s, l, f = (int(x) for x in node['src'].split(':'))
    except Exception:
        return None, 0, None
    ap = files.get(f)
    if ap is None:
        return None, 0, None
    p, b = srcs.bytes(ap)
    if b is None:
        return ap, 0, None
    line = b.count(b'\n', 0, s) + 1
    start = b.rfind(b'\n', 0, s) + 1  # from the line's start, for the indentation
    return p, line, b[start:s + l].decode('utf-8', 'replace')


def numbered(text, first):
    return '\n'.join('%5d  %s' % (first + i, t) for i, t in enumerate(text.split('\n')))


class Contract:
    """a contract's AST: its ABI functions' definitions, what they reach"""

    def __init__(self, ast, contract):
        self.ast, self.c = ast, contract
        self.bases = [ast.by_id[i] for i in contract.get('linearizedBaseContracts', [contract['id']])
                      if i in ast.by_id]
        self.impl = {}  # (name, param types) -> the most derived definition
        for b in self.bases:
            for n in b.get('nodes', []):
                if n.get('nodeType') in ('FunctionDefinition', 'ModifierDefinition') and n.get('body'):
                    self.impl.setdefault((n.get('nodeType'), n.get('name'), self.sig(n)), n)

    @staticmethod
    def sig(n):
        return tuple((p.get('typeDescriptions') or {}).get('typeString', '')
                     for p in (n.get('parameters') or {}).get('parameters', []))

    def resolve(self, d, via_super=False):
        if d.get('nodeType') not in ('FunctionDefinition', 'ModifierDefinition'):
            return None
        if not via_super and d.get('virtual') is not False:
            m = self.impl.get((d.get('nodeType'), d.get('name'), self.sig(d)))
            if m is not None:
                return m
        return d if d.get('body') else None

    def reached(self, fn):
        """the functions and modifiers a function reaches (not itself), in order"""
        out, seen, todo = [], {fn['id']}, [fn]
        while todo and len(out) < MAX_REACHED:
            f = todo.pop(0)
            refs = []
            for m in f.get('modifiers') or []:
                ref = (m.get('modifierName') or {}).get('referencedDeclaration')
                if ref in self.ast.by_id:
                    refs.append((self.ast.by_id[ref], False))
            stack = [f.get('body')]
            while stack:
                x = stack.pop()
                if isinstance(x, list):
                    stack.extend(reversed(x))
                    continue
                if not isinstance(x, dict):
                    continue
                t = x.get('nodeType')
                if t in ('Identifier', 'MemberAccess') and x.get('referencedDeclaration') in self.ast.by_id:
                    d = self.ast.by_id[x['referencedDeclaration']]
                    sup = t == 'MemberAccess' and (x.get('expression') or {}).get('name') == 'super'
                    refs.append((d, sup))
                for k, v in x.items():
                    if isinstance(v, (dict, list)) and k != 'typeDescriptions':
                        stack.append(v)
            for d, sup in refs:
                r = self.resolve(d, sup)
                if r is not None and r['id'] not in seen:
                    seen.add(r['id'])
                    out.append(r)
                    todo.append(r)
        return out


def label(n):
    owner = n.get('_owner', '')
    kind = 'modifier' if n.get('nodeType') == 'ModifierDefinition' else (n.get('visibility') or '')
    return '%s%s (%s)' % (owner + '.' if owner else '', n.get('name') or n.get('kind'), kind)


# ---- the decompiled side -------------------------------------------------------------------

def dec_blocks(text):
    """the text's top-level blocks: [(first line number, block lines)]"""
    lines = text.split('\n')
    out, cur, start = [], [], 1
    for i, ln in enumerate(lines, 1):
        if ln.startswith('def ') and cur:
            out.append((start, cur))
            cur, start = [], i
        elif ln.startswith('#') and cur and cur[0].startswith('def '):
            out.append((start, cur))
            cur, start = [], i
        cur.append(ln)
    if cur:
        out.append((start, cur))
    return out


def trim(block):
    while block and not block[-1].strip():
        block = block[:-1]
    return block


def text_stats(text):
    s = collections.Counter()
    for ln in text.split('\n'):
        t = ln.strip()
        if t.startswith('while '):
            s['while'] += 1
        if t.startswith('for '):
            s['for'] += 1
        if 'Decompilation aborted' in t:
            s['aborted'] += 1
        if '????' in t:
            s['????'] += 1
        if ' len ' in t and '=' in t and '[' in t:
            s['copies'] += 1
    return s


# ---- one contract --------------------------------------------------------------------------

def decompile(a, row):
    dec = os.path.join(a.out, 'dec')
    hexp = os.path.join(a.build, row['artifact'] + '.hex')
    env = dict(os.environ, PANORAMIX_SIGDB=a.sigdb, PANORAMIX_LOG='error')
    for ext, extra in (('.txt', []), ('.json', ['--json'])):
        p = os.path.join(dec, row['id'] + ext)
        if os.path.exists(p):
            continue
        try:
            r = subprocess.run([a.pancxx, 'decompile', hexp, '--no-color', '-j', '1'] + extra, env=env,
                               capture_output=True, text=True, timeout=a.timeout)
            out = r.stdout if r.stdout else '# decompile: rc %d %s\n' % (r.returncode, r.stderr[-300:])
        except subprocess.TimeoutExpired:
            out = '# decompile: timeout after %d s\n' % a.timeout
        open(p + '.part', 'w').write(out)
        os.replace(p + '.part', p)


def pack(a, row, ast_cache):
    base = os.path.join(a.build, row['artifact'])
    meta = json.load(open(base + '.json'))
    proj, build, src, name = rsel.split(row['artifact'])
    text = open(os.path.join(a.out, 'dec', row['id'] + '.txt')).read()
    try:
        dj = json.loads(open(os.path.join(a.out, 'dec', row['id'] + '.json')).read())
        prints = {f.get('hash'): ANSI.sub('', f.get('print', '')) for f in dj.get('functions', [])}
    except Exception:
        prints = {}
    blocks = dec_blocks(text)
    first_line = {}
    for start, b in blocks:
        if b and b[0].startswith('def '):
            first_line.setdefault(b[0], (start, trim(b)))
    vyper = str(meta.get('compiler', '')).startswith('vyper')
    root = os.path.join(a.sources, proj)
    repo_root = os.path.join(a.sources, *proj.split('/')[:2])
    srcs = Sources(root, repo_root)
    astdir = os.path.normpath(os.path.join(os.path.dirname(base), meta['ast'])) if meta.get('ast') else None

    out = []
    w = out.append
    st = text_stats(text)
    w('# %s  %s : %s  (tranche %d)' % (row['id'], proj, name, row['tranche']))
    w('')
    w('- artifact: `%s`' % row['artifact'])
    w('- build: %s %s, EVM %s, via-IR %s, optimizer %s' % (
        'vyper' if vyper else 'solc', meta.get('compiler', '').split('-')[-1] if meta.get('compiler') else '?',
        meta.get('evm'), meta.get('via_ir'), meta.get('optimizer')))
    if row.get('builds'):
        w('- other builds of this contract: %d (%s)' % (
            len(row['builds']), ', '.join(sorted({rsel.split(x)[1] for x in row['builds']}))[:300]))
    if row.get('duplicates'):
        w('- the same bytecode in %d other contracts: %s' % (
            len(row['duplicates']), ', '.join(x.split('/')[-1] for x in row['duplicates'][:5])))
    w('- bytecode: %d bytes; decompiled text: `%s` (%d lines)' % (
        row['bytes'], os.path.join(a.out, 'dec', row['id'] + '.txt'), text.count('\n')))
    w('- the text has: %d `while`, %d `for`, %d copy-like lines, %d `Decompilation aborted`, %d `????`' % (
        st['while'], st['for'], st['copies'], st['aborted'], st['????']))
    w('- the build (ABI, storage layout, AST): `%s.json`' % base)

    # source file of the contract
    contract = fnodes = None
    files = {}
    if not vyper and astdir and os.path.isdir(astdir):
        if astdir not in ast_cache:
            ast_cache.clear()
            ast_cache[astdir] = cs.Ast(astdir)
            fm = {}
            for p in os.listdir(astdir):
                try:
                    root_node = json.load(open(os.path.join(astdir, p)))
                    fm[int(root_node['src'].split(':')[2])] = root_node.get('absolutePath', '')
                except Exception:
                    pass
            ast_cache[astdir + '#files'] = fm
            for cs_ in ast_cache[astdir].contracts.values():
                for c_ in cs_:
                    for n in c_.get('nodes', []):
                        n['_owner'] = c_.get('name', '')
        ast = ast_cache[astdir]
        files = ast_cache[astdir + '#files']
        cnode = ast.contract(meta['source'], meta['contract'])
        if cnode:
            contract = Contract(ast, cnode)
            fnodes = ast.external_functions(cnode)
    sp, _ = srcs.bytes(meta['source'])
    w('- source: `%s`' % (sp or '(not found: %s under %s)' % (meta['source'], root)))
    w('')

    # storage
    w('## Storage')
    w('')
    w("The compiler's layout (slot, byte offset, type, name):")
    w('')
    w('```')
    for e in (meta.get('storageLayout') or {}).get('storage', []) or []:
        t = ((meta['storageLayout'].get('types') or {}).get(e.get('type')) or {}).get('label', e.get('type'))
        w('slot %s +%s  %s  %s.%s' % (e.get('slot'), e.get('offset'), t, e.get('contract', '').split(':')[-1],
                                       e.get('label')))
    w('```')
    w('')
    w("The text's definitions:")
    w('')
    w('```')
    for start, b in blocks:
        if b and b[0].startswith('def storage:'):
            w(numbered('\n'.join(trim(b)), start))
    w('```')
    w('')

    # functions
    abi = cs.abi_functions(meta.get('abi'), bool(contract and contract.c.get('contractKind') == 'library'))
    by_name = {}
    for sel, f in abi.items():
        by_name.setdefault((f['name'], len(f['types'])), sel)
    sel_node = {}
    if fnodes:
        for key, n in fnodes.items():
            if isinstance(key, str):
                sel_node[key] = n
            elif key in by_name:
                sel_node[by_name[key]] = n
            else:
                for (nm, k), s in by_name.items():
                    if nm == key[0] and (key[1] is None or k == key[1]):
                        sel_node.setdefault(s, n)
    reached_all = {}
    w('## Functions: the source, then the decompiled function')
    w('')
    done_dec = set()
    for sel in sorted(abi, key=lambda s: (abi[s]['name'], s)):
        f = abi[sel]
        w('### %s(%s)  %s' % (f['name'], ','.join(f['types']), sel))
        w('')
        n = sel_node.get(sel)
        if n is not None and contract is not None:
            p, line, txt = node_text(srcs, files, n)
            r = contract.reached(n) if n.get('nodeType') == 'FunctionDefinition' else []
            for x in r:
                reached_all.setdefault(x['id'], x)
            if r:
                w('Reaches: ' + ', '.join(label(x) for x in r))
                w('')
            w('```solidity')
            w('// %s:%d' % (p, line) if p else '// (source not found)')
            if txt:
                w(numbered(txt, line))
            w('```')
        elif vyper:
            w('(Vyper: the function is in the source file named above.)')
        else:
            w('(no source definition found in the AST)')
        w('')
        pr = prints.get(sel)
        if pr:
            head = pr.split('\n', 1)[0]
            done_dec.add(head)
            if head in first_line:
                start, b = first_line[head]
                w('```decompiled')
                w(numbered('\n'.join(b), start))
                w('```')
            else:
                w('```decompiled')
                w(pr)
                w('```')
        else:
            w('**Not in the decompiled code.**')
        w('')
    # the fallback and what the ABI hasn't
    w('## Decompiled functions the ABI has no function for')
    w('')
    for start, b in blocks:
        if b and b[0].startswith('def ') and not b[0].startswith(('def storage:', 'def SafeMath:')) \
                and b[0] not in done_dec:
            w('```decompiled')
            w(numbered('\n'.join(trim(b)), start))
            w('```')
            w('')
    for e in meta.get('abi') or []:
        if e.get('type') in ('fallback', 'receive'):
            w('(the ABI has a %s%s)' % (e['type'], ', payable' if e.get('stateMutability') == 'payable' else ''))
            w('')
    if contract is not None:
        for b in contract.bases:
            for n in b.get('nodes', []):
                if n.get('nodeType') == 'FunctionDefinition' and n.get('kind') in ('fallback', 'receive') \
                        and n.get('body'):
                    p, line, txt = node_text(srcs, files, n)
                    w('Source of %s.%s:' % (b.get('name'), n.get('kind')))
                    w('')
                    w('```solidity')
                    w('// %s:%d' % (p, line))
                    if txt:
                        w(numbered(txt, line))
                    w('```')
                    w('')
                    for x in contract.reached(n):
                        reached_all.setdefault(x['id'], x)
    # helpers
    for start, b in blocks:
        if b and b[0].startswith('def SafeMath:'):
            w("## The text's `def SafeMath:` block")
            w('')
            w('```decompiled')
            w(numbered('\n'.join(trim(b)), start))
            w('```')
            w('')
    if reached_all:
        w('## Internal functions and modifiers reached (each once)')
        w('')
        for x in sorted(reached_all.values(), key=lambda x: (x.get('_owner', ''), x.get('name') or '')):
            p, line, txt = node_text(srcs, files, x)
            w('### %s' % label(x))
            w('')
            w('```solidity')
            w('// %s:%d' % (p, line) if p else '// (source not found)')
            if txt:
                w(numbered(txt, line))
            w('```')
            w('')
    if vyper and sp:
        w('## The Vyper source')
        w('')
        w('```python')
        w(numbered(open(sp, encoding='utf-8', errors='replace').read(), 1))
        w('```')
    data = '\n'.join(out) + '\n'
    open(os.path.join(a.out, 'packs', row['id'] + '.md'), 'w').write(data)
    return data.count('\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--build', required=True)
    ap.add_argument('--sources', required=True)
    ap.add_argument('--contracts', required=True)
    ap.add_argument('--tranche', type=int, required=True)
    ap.add_argument('--pancxx', required=True)
    ap.add_argument('--sigdb', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--jobs', type=int, default=2)
    ap.add_argument('--timeout', type=int, default=900)
    ap.add_argument('--batches', type=int, default=0)
    ap.add_argument('--only', default='', help='comma-separated ids')
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.contracts)]
    rows = [r for r in rows if r['tranche'] == a.tranche]
    if a.only:
        keep = set(a.only.split(','))
        rows = [r for r in rows if r['id'] in keep]
    for d in ('dec', 'packs', 'batches', 'results'):
        os.makedirs(os.path.join(a.out, d), exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        list(ex.map(lambda r: decompile(a, r), rows))
    sizes = {}
    ast_cache = {}
    # one build's ASTs at a time
    for r in sorted(rows, key=lambda r: os.path.dirname(r['artifact'])):
        try:
            sizes[r['id']] = pack(a, r, ast_cache)
        except Exception as e:
            open(os.path.join(a.out, 'packs', r['id'] + '.md'), 'w').write(
                '# %s\n\n(pack failed: %r)\n\ndecompiled text: %s\nartifact: %s\n' % (
                    r['id'], e, os.path.join(a.out, 'dec', r['id'] + '.txt'), r['artifact']))
            sizes[r['id']] = 0
            print('pack failed', r['id'], repr(e), file=sys.stderr)
    if a.batches:
        bins = [[0, []] for _ in range(a.batches)]
        for i in sorted(sizes, key=lambda i: -sizes[i]):
            b = min(bins, key=lambda x: x[0])
            b[0] += sizes[i] + 200
            b[1].append(i)
        for k, (n, ids) in enumerate(bins):
            ids.sort(key=lambda i: -sizes[i])
            open(os.path.join(a.out, 'batches', 'b%02d.txt' % (k + 1)), 'w').write(''.join(x + '\n' for x in ids))
            print('b%02d: %d contracts, %d pack lines' % (k + 1, len(ids), n))
    print('%d packs, %d lines' % (len(sizes), sum(sizes.values())))


if __name__ == '__main__':
    main()
