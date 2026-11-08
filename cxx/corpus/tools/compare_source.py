#!/usr/bin/env python3
"""Compare the decompiled code of the corpus' builds (build_corpus.py) with
their sources.

    compare_source.py BUILD [--pancxx BIN] [--sigdb DB] [--stagecheck BIN]
                      [--text-check BIN] [-j N] [--limit N] [--program SLUG]...
                      [--no-exec] [--blind] [--out DIR] [--timeout S]

Per artifact of BUILD/index.jsonl:
  interface  the ABI's functions (selectors: keccak of the canonical
             signature) found in the decompiled dispatcher, extra selectors;
             their names and parameter types as decompiled, payable as the ABI
             says; --blind decompiles a second time without the signature
             database: the parameters' types as inferred from the code alone
  storage    the compiler's storage layout (slot, offset, kind: a value of n
             bits, a mapping, an array, bytes / string, a struct's members)
             against the decompiled storage definitions: places found, kinds
             and names that agree
  semantics  stagecheck (every stage's trace against evmone, the same calls)
             and text_check (the printed text parsed again and run against
             evmone): the calls the same, different, inconclusive
  size       each function's decompiled lines against its source statements
             (solc's AST: the body, its modifiers', the internal functions it
             calls, each once), and the loops, conditions, reverts each side
Across EVM versions and optimizer settings, the same contract's decompiled
functions are compared: identical, lines changed.
Output: OUT/results.jsonl (a line per artifact) and OUT/summary.md.
The decompiler's own trust in the source is nil: the comparisons only read
the compiler's outputs (ABI, layout, AST) beside the decompiled ones.
"""
import argparse
import collections
import concurrent.futures
import difflib
import glob
import json
import os
import re
import subprocess
import sys

# ---- keccak-256 (the selectors; no dependency) -------------------------------------------

_RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000, 0x000000000000808B,
       0x0000000080000001, 0x8000000080008081, 0x8000000000008009, 0x000000000000008A, 0x0000000000000088,
       0x0000000080008009, 0x000000008000000A, 0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
       0x8000000000008003, 0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
       0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M = (1 << 64) - 1


def _rol(x, n):
    return ((x << n) | (x >> (64 - n))) & _M if n else x


def keccak256(data):
    rate = 136
    p = bytearray(data) + b'\x01'
    while len(p) % rate:
        p += b'\x00'
    p[-1] |= 0x80
    a = [[0] * 5 for _ in range(5)]
    for off in range(0, len(p), rate):
        for i in range(rate // 8):
            a[i % 5][i // 5] ^= int.from_bytes(p[off + 8 * i:off + 8 * i + 8], 'little')
        for rc in _RC:
            c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
            d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
            b = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    b[y][(2 * x + 3 * y) % 5] = _rol(a[x][y] ^ d[x], _ROT[x][y])
            a = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
            a[0][0] ^= rc
    return b''.join(a[i % 5][i // 5].to_bytes(8, 'little') for i in range(4))


def canonical(inp):
    t = inp['type']
    if t.startswith('tuple'):
        return '(' + ','.join(canonical(c) for c in inp.get('components', [])) + ')' + t[len('tuple'):]
    return t


def abi_functions(abi):
    """{selector: {'sig', 'types', 'payable', 'mutability'}} of an ABI"""
    out = {}
    for e in abi or []:
        if e.get('type', 'function') != 'function' or 'name' not in e:
            continue
        types = [canonical(i) for i in e.get('inputs', [])]
        sig = '%s(%s)' % (e['name'], ','.join(types))
        sel = '0x' + keccak256(sig.encode()).hex()[:8]
        mut = e.get('stateMutability') or ('payable' if e.get('payable') else 'view' if e.get('constant') else
                                           'nonpayable')
        out[sel] = {'sig': sig, 'name': e['name'], 'types': types, 'payable': mut == 'payable', 'mutability': mut}
    return out


# ---- the source side: solc's AST -----------------------------------------------------------

STMTS = {'ExpressionStatement', 'VariableDeclarationStatement', 'IfStatement', 'ForStatement', 'WhileStatement',
         'DoWhileStatement', 'Return', 'EmitStatement', 'RevertStatement', 'Break', 'Continue', 'Throw',
         'TryStatement',
         'YulExpressionStatement', 'YulAssignment', 'YulVariableDeclaration', 'YulIf', 'YulForLoop', 'YulSwitch',
         'YulBreak', 'YulContinue', 'YulLeave'}
LOOPS = {'ForStatement', 'WhileStatement', 'DoWhileStatement', 'YulForLoop'}
CONDS = {'IfStatement', 'Conditional', 'YulIf', 'YulSwitch'}


class Ast:
    """the nodes of every AST of a build (one compiler run: shared ids)"""

    def __init__(self, astdir):
        self.by_id = {}
        self.contracts = collections.defaultdict(list)  # (source unit, name) -> node
        for p in glob.glob(os.path.join(astdir, '*.json')):
            try:
                root = json.load(open(p))
            except Exception:
                continue
            self._index(root, root.get('absolutePath', ''))

    def _index(self, n, unit):
        stack = [n]
        while stack:
            x = stack.pop()
            if isinstance(x, dict):
                if 'id' in x and 'nodeType' in x:
                    self.by_id[x['id']] = x
                    if x['nodeType'] == 'ContractDefinition':
                        self.contracts[(unit, x.get('name'))].append(x)
                stack.extend(v for v in x.values() if isinstance(v, (dict, list)))
            elif isinstance(x, list):
                stack.extend(v for v in x if isinstance(v, (dict, list)))

    def contract(self, unit, name):
        c = self.contracts.get((unit, name))
        return c[0] if c else None

    def external_functions(self, contract):
        """{selector or (name, nparams): node} of the functions and public
        variables a contract exposes, the most derived first"""
        out = {}
        for cid in contract.get('linearizedBaseContracts', [contract['id']]):
            c = self.by_id.get(cid)
            if not c:
                continue
            for n in c.get('nodes', []):
                t = n.get('nodeType')
                pub = n.get('visibility') in ('public', 'external')
                if t == 'FunctionDefinition' and pub and n.get('kind', 'function') == 'function' and n.get('body'):
                    key = '0x' + n['functionSelector'] if n.get('functionSelector') else \
                        (n.get('name'), len(n.get('parameters', {}).get('parameters', [])))
                    out.setdefault(key, n)
                elif t == 'VariableDeclaration' and pub and n.get('stateVariable'):
                    key = '0x' + n['functionSelector'] if n.get('functionSelector') else (n.get('name'), None)
                    out.setdefault(key, n)
        return out

    def size(self, fn):
        """the statements, loops, conditions, reverts of a function with its
        modifiers and the internal functions it calls (each once)"""
        m = {'statements': 0, 'loops': 0, 'conditions': 0, 'reverts': 0, 'functions': 0}
        seen = set()
        todo = [fn]
        for mod in fn.get('modifiers', []) or []:
            ref = (mod.get('modifierName') or {}).get('referencedDeclaration')
            if ref in self.by_id:
                todo.append(self.by_id[ref])
        while todo and len(seen) < 500:
            f = todo.pop()
            if f.get('id') in seen:
                continue
            seen.add(f.get('id'))
            m['functions'] += 1
            stack = [f.get('body')] if f.get('nodeType') != 'VariableDeclaration' else []
            while stack:
                x = stack.pop()
                if isinstance(x, list):
                    stack.extend(x)
                    continue
                if not isinstance(x, dict):
                    continue
                t = x.get('nodeType', '')
                if t in STMTS:
                    m['statements'] += 1
                if t in LOOPS:
                    m['loops'] += 1
                if t in CONDS:
                    m['conditions'] += 1
                if t == 'RevertStatement':
                    m['reverts'] += 1
                if t == 'FunctionCall':
                    e = x.get('expression') or {}
                    if e.get('nodeType') == 'Identifier' and e.get('name') in ('require', 'revert', 'assert'):
                        m['reverts'] += 1
                    ref = e.get('referencedDeclaration')
                    d = self.by_id.get(ref)
                    if d and d.get('nodeType') == 'FunctionDefinition' and d.get('visibility') in ('internal',
                                                                                                    'private'):
                        todo.append(d)
                for k, v in x.items():
                    if isinstance(v, (dict, list)) and k not in ('typeDescriptions',):
                        stack.append(v)
        return m


class VyperAst:
    """a Vyper module's AST (vyper -f ast): its external functions and public
    variables, sized as Ast.size does (statements of the function and of the
    internal functions it calls, each once)"""
    STMTS = {'Assign', 'AugAssign', 'AnnAssign', 'If', 'For', 'Return', 'Log', 'Raise', 'Assert', 'Expr', 'Pass',
             'Break', 'Continue'}

    def __init__(self, path):
        d = json.load(open(path))
        self.module = d.get('ast', d)
        self.fns = {n.get('name'): n for n in self.module.get('body', []) if n.get('ast_type') == 'FunctionDef'}

    def external_functions(self):
        out = {}
        for name, n in self.fns.items():
            decs = {x.get('id') for x in n.get('decorator_list', []) if isinstance(x, dict)}
            if 'external' in decs:
                out[(name, len((n.get('args') or {}).get('args', [])))] = n
        for n in self.module.get('body', []):
            if n.get('ast_type') == 'VariableDecl' and n.get('is_public'):
                t = n.get('target') or {}
                out[(t.get('id'), None)] = n
        return out

    def size(self, fn):
        m = {'statements': 0, 'loops': 0, 'conditions': 0, 'reverts': 0, 'functions': 0}
        seen, todo = set(), [fn]
        while todo and len(seen) < 500:
            f = todo.pop()
            if id(f) in seen:
                continue
            seen.add(id(f))
            m['functions'] += 1
            stack = list(f.get('body') or []) if f.get('ast_type') == 'FunctionDef' else []
            while stack:
                x = stack.pop()
                if isinstance(x, list):
                    stack.extend(x)
                    continue
                if not isinstance(x, dict):
                    continue
                t = x.get('ast_type', '')
                if t in self.STMTS:
                    m['statements'] += 1
                if t == 'For':
                    m['loops'] += 1
                if t in ('If', 'IfExp'):
                    m['conditions'] += 1
                if t in ('Raise', 'Assert'):
                    m['reverts'] += 1
                if t == 'Call':
                    fu = x.get('func') or {}
                    if fu.get('ast_type') == 'Attribute' and (fu.get('value') or {}).get('id') == 'self' and \
                            fu.get('attr') in self.fns:
                        todo.append(self.fns[fu['attr']])
                for k, v in x.items():
                    if isinstance(v, (dict, list)):
                        stack.append(v)
        return m


# ---- the decompiled side -------------------------------------------------------------------

def run(args, env=None, timeout=900):
    try:
        p = subprocess.run(args, capture_output=True, text=True, env=env, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return -1, '', 'timeout'


ANSI = re.compile(r'\x1b\[[0-9;]*m')


def dec_size(text):
    # (the JSON's print keeps its colors, as the other implementations')
    text = ANSI.sub('', text or '')
    m = {'lines': 0, 'loops': 0, 'conditions': 0, 'reverts': 0}
    for line in (text or '').split('\n')[1:]:
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        m['lines'] += 1
        if s.startswith(('while ', 'for ')):
            m['loops'] += 1
        if s.startswith(('if ', 'elif ')):
            m['conditions'] += 1
        if s.startswith(('revert', 'require ')) or ' revert ' in s:
            m['reverts'] += 1
    return m


def layout_entries(layout):
    """the compiler's storage layout: [(slot, byte offset, kind, bits, label)],
    an in-place struct's members one by one"""
    out = []
    if not layout:
        return out
    types = layout.get('types') or {}

    def add(slot, off, t, label, depth=0):
        ty = types.get(t, {})
        enc = ty.get('encoding', 'inplace')
        if enc == 'mapping':
            out.append((slot, off, 'mapping', None, label))
        elif enc == 'dynamic_array':
            out.append((slot, off, 'array', None, label))
        elif enc == 'bytes':
            out.append((slot, off, 'bytes', None, label))
        elif ty.get('members') and depth < 3:
            for mb in ty['members']:
                add(slot + int(mb['slot']), int(mb['offset']), mb['type'], label + '.' + mb['label'], depth + 1)
        elif t.startswith('t_array'):
            out.append((slot, off, 'static array', None, label))
        else:
            out.append((slot, off, 'value', int(ty.get('numberOfBytes', 32)) * 8, label))

    for e in layout.get('storage') or []:
        add(int(e['slot']), int(e['offset']), e['type'], e['label'])
    return out


def dec_storage(stor_defs):
    out = {}
    for d in stor_defs or []:
        if not (isinstance(d, list) and len(d) >= 5 and d[0] == 'sdef'):
            continue
        _, name, slot, off, ty = d[:5]
        if not isinstance(slot, int):
            continue
        kind = ty[0] if isinstance(ty, list) and ty else str(ty)
        bits = ty[1] if isinstance(ty, list) and len(ty) > 1 and isinstance(ty[1], int) else None
        out.setdefault((slot, off), (name, kind, bits))
    return out


GENERIC_NAME = re.compile(r'^(stor|unknown|_?[0-9a-f]{8}$)', re.I)


def compare_storage(layout, defs):
    want = layout_entries(layout)
    got = dec_storage(defs)
    r = {'layout': len(want), 'found': 0, 'kind_same': 0, 'named': 0, 'name_same': 0}
    for slot, off, kind, bits, label in want:
        d = got.get((slot, off * 8)) or got.get((slot, off))
        if not d:
            continue
        r['found'] += 1
        name, dkind, dbits = d
        same = (kind == dkind) or (kind == 'value' and dkind == 'value') or \
               (kind in ('array', 'static array') and dkind in ('array', 'list')) or \
               (kind == 'bytes' and dkind in ('bytes', 'string'))
        if same and kind == 'value' and bits and dbits and bits != dbits:
            same = False
        r['kind_same'] += bool(same)
        if name and not GENERIC_NAME.match(str(name)):
            r['named'] += 1
            base = label.split('.')[-1].lstrip('_')
            r['name_same'] += str(name).lstrip('_').lower() == base.lower()
    return r


STATIC = re.compile(r'^(address|bool|u?int\d*|bytes\d+)$')


def compare_interface(abi_fns, dec, blind):
    r = {'abi': len(abi_fns), 'found': 0, 'missing': [], 'extra': 0, 'name_same': 0, 'payable_same': 0,
         'params_static': 0, 'params_static_same': 0, 'blind_params_static': 0, 'blind_params_static_same': 0}
    dfs = {f.get('hash'): f for f in dec.get('functions', []) if isinstance(f.get('hash'), str)}
    for sel, a in abi_fns.items():
        f = dfs.get(sel)
        if not f:
            r['missing'].append(a['sig'])
            continue
        r['found'] += 1
        r['name_same'] += f.get('abi_name') == a['sig']
        r['payable_same'] += bool(f.get('payable')) == a['payable']
        for key, src in (('params_static', f), ('blind_params_static', (blind or {}).get(sel))):
            if not src:
                continue
            ps = src.get('params') or {}
            dtypes = [ps[k][0] for k in sorted(ps, key=lambda o: int(o)) if isinstance(ps[k], list) and ps[k]]
            if all(STATIC.match(t) for t in a['types']) and a['types']:
                r[key] += len(a['types'])
                r[key + '_same'] += sum(1 for x, y in zip(a['types'], dtypes) if x == y)
    r['extra'] = sum(1 for h in dfs if h not in abi_fns and h.startswith('0x'))
    r['missing'] = r['missing'][:20]
    return r


def parse_stagecheck(out):
    line = next((l for l in out.split('\n') if ' | ' in l and 'folded:' in l), '')
    seg = line.split('folded:')[-1].split('|')[0] if line else ''
    num = lambda k: int(m.group(1)) if (m := re.search(r'\b' + k + r' (\d+)', seg)) else 0
    if not line:
        return {'error': (out.strip().split('\n') or [''])[-1][-200:]}
    return {'same': num('same'), 'different': num('different'), 'bugs': num('bugs'),
            'inconclusive': num('inconclusive')}


def parse_text_check(out):
    r = {}
    for world in ('empty', 'random'):
        m = re.search(world + r' world:.*?calls (\d+): same (\d+).*?different (\d+), unsupported (\d+), '
                              r'exhausted (\d+), evm inconclusive (\d+)', out)
        if m:
            c, s, d, u, e, i = map(int, m.groups())
            r[world] = {'calls': c, 'same': s, 'different': d, 'unsupported': u, 'exhausted': e, 'inconclusive': i}
        m = re.search(world + r' world: \d+ contracts \((\d+) with unparsed lines', out)
        if m:
            r.setdefault(world, {})['unparsed'] = int(m.group(1))
    return r or {'error': out.strip()[-200:]}


# ---- one artifact --------------------------------------------------------------------------

def sideinfo(dec):
    lines = []
    for f in dec.get('functions', []):
        params = f.get('params') or {}
        h = f.get('hash')
        key = '_fallback' if str(f.get('name', '')).startswith('_fallback') else (
            h if isinstance(h, str) else '0x%08x' % h)
        items = []
        for off in sorted(params, key=lambda o: int(o)):
            t = params[off][0] if isinstance(params[off], list) and params[off] else ''
            items.append('%s:%s' % (off, t) if t else str(off))
        lines.append(' '.join([key] + items))
    return '\n'.join(lines) + ('\n' if lines else '')


def one(args, row, ast_cache):
    base = os.path.join(args.build, row['artifact'])
    hexp, meta = base + '.hex', json.load(open(base + '.json'))
    res = dict(row, compiler=meta.get('compiler'), evm=meta.get('evm'), optimizer=meta.get('optimizer'),
               via_ir=meta.get('via_ir'), source=meta.get('source'), contract=meta.get('contract'))
    res['code_bytes'] = len(open(hexp).read().strip().removeprefix('0x')) // 2
    env = dict(os.environ, PANORAMIX_SIGDB=args.sigdb, PANORAMIX_LOG='error')
    rc, out, err = run([args.pancxx, 'decompile', hexp, '--json', '--no-color', '-j', '1'], env, args.timeout)
    try:
        dec = json.loads(out)
    except Exception:
        res['error'] = 'decompile: rc %d %s' % (rc, err.strip()[-200:])
        return res, None
    blind = None
    if args.blind:
        benv = dict(env, PANORAMIX_SIGDB=os.path.join(args.out, 'no-such-sigdb'))
        rc2, out2, _ = run([args.pancxx, 'decompile', hexp, '--json', '--no-color', '-j', '1'], benv, args.timeout)
        try:
            blind = {f.get('hash'): f for f in json.loads(out2).get('functions', [])}
        except Exception:
            blind = None
    res['lang'] = dec.get('lang')
    res['problems'] = len(dec.get('problems') or [])
    res['interface'] = compare_interface(abi_functions(meta.get('abi')), dec, blind)
    if meta.get('storageLayout'):
        res['storage'] = compare_storage(meta['storageLayout'], dec.get('stor_defs'))
    # size: per function found on both sides
    texts = {f.get('hash'): ANSI.sub('', f.get('print', '')) for f in dec.get('functions', [])}
    astdir = os.path.normpath(os.path.join(os.path.dirname(base), meta['ast'])) if meta.get('ast') else None
    sizes = []
    vy_ast = os.path.join(astdir, meta['source'].replace('/', '__') + '.json') if astdir else None
    if str(meta.get('compiler', '')).startswith('vyper') and vy_ast and os.path.exists(vy_ast):
        try:
            ast = VyperAst(vy_ast)
        except Exception:
            ast = None
        if ast:
            abi_fns = abi_functions(meta.get('abi'))
            by_name = {}
            for sel, a in abi_fns.items():
                by_name.setdefault((a['name'], len(a['types'])), sel)
                by_name.setdefault((a['name'], None), sel)
            for key, node in ast.external_functions().items():
                sel = by_name.get(key) or by_name.get((key[0], None))
                if sel in texts:
                    sizes.append({'sel': sel, 'src': ast.size(node), 'dec': dec_size(texts[sel])})
    elif astdir and os.path.isdir(astdir):
        if astdir not in ast_cache:
            ast_cache.clear()  # (one build's ASTs at a time: they're large)
            ast_cache[astdir] = Ast(astdir)
        ast = ast_cache[astdir]
        c = ast.contract(meta['source'], meta['contract'])
        if c:
            abi_fns = abi_functions(meta.get('abi'))
            by_name = {}
            for sel, a in abi_fns.items():
                by_name.setdefault((a['name'], len(a['types'])), sel)
                by_name.setdefault((a['name'], None), sel)
            for key, node in ast.external_functions(c).items():
                sel = key if isinstance(key, str) else by_name.get(key)
                if sel not in texts:
                    continue
                s = ast.size(node)
                d = dec_size(texts[sel])
                sizes.append({'sel': sel, 'src': s, 'dec': d})
    res['size'] = {
        'functions': len(sizes),
        'src_statements': sum(x['src']['statements'] for x in sizes),
        'dec_lines': sum(x['dec']['lines'] for x in sizes),
        'src_loops': sum(x['src']['loops'] for x in sizes), 'dec_loops': sum(x['dec']['loops'] for x in sizes),
        'src_conditions': sum(x['src']['conditions'] for x in sizes),
        'dec_conditions': sum(x['dec']['conditions'] for x in sizes),
        'src_reverts': sum(x['src']['reverts'] for x in sizes), 'dec_reverts': sum(x['dec']['reverts'] for x in sizes),
        'per_function': [(x['sel'], x['src']['statements'], x['dec']['lines']) for x in sizes],
    }
    if not args.no_exec:
        rc, out, err = run([args.stagecheck, hexp, '--stage', 'folded', '--quiet', '--sigdb', args.sigdb,
                            '--timeout', str(args.timeout)], env, args.timeout + 60)
        res['stagecheck'] = parse_stagecheck(out + err)
        work = os.path.join(args.out, 'work', row['artifact'].replace('/', '__'))
        os.makedirs(os.path.join(work, 'params'), exist_ok=True)
        rc, txt, err = run([args.pancxx, 'decompile', hexp, '--no-color', '-j', '1'], env, args.timeout)
        name = os.path.splitext(os.path.basename(hexp))[0]
        open(os.path.join(work, name + '.txt'), 'w').write(txt)
        open(os.path.join(work, 'params', name + '.txt'), 'w').write(sideinfo(dec))
        rc, out, err = run([args.text_check, 'run', hexp, os.path.join(work, name + '.txt'), '--params',
                            os.path.join(work, 'params'), '--sigdb', args.sigdb, '--quiet'], env, args.timeout + 60)
        res['text_check'] = parse_text_check(out + err)
    return res, texts


# ---- the whole run -------------------------------------------------------------------------

def stability(groups):
    """the same contract across EVM versions / optimizer settings: per pair of
    builds, the functions identical and the lines changed"""
    out = collections.defaultdict(lambda: {'pairs': 0, 'functions': 0, 'identical': 0, 'lines': 0, 'changed': 0})
    for key, builds in groups.items():
        builds = sorted(builds, key=lambda b: (b[0]['optimizer'] is False, EVM_ORDER.index(b[0]['evm'])
                                               if b[0]['evm'] in EVM_ORDER else 99))
        for (ra, fa), (rb, fb) in zip(builds, builds[1:]):
            if ra['optimizer'] != rb['optimizer']:
                continue
            k = '%s -> %s' % (ra['evm'], rb['evm'])
            s = out[k]
            s['pairs'] += 1
            for sel in set(fa) & set(fb):
                s['functions'] += 1
                if fa[sel] == fb[sel]:
                    s['identical'] += 1
                a, b = fa[sel].split('\n'), fb[sel].split('\n')
                s['lines'] += max(len(a), len(b))
                s['changed'] += sum(1 for t in difflib.ndiff(a, b) if t.startswith(('+ ', '- ')))
    return out


EVM_ORDER = ['homestead', 'tangerineWhistle', 'spuriousDragon', 'byzantium', 'constantinople', 'petersburg',
             'istanbul', 'berlin', 'london', 'paris', 'shanghai', 'cancun', 'prague', 'osaka']


def pct(a, b):
    return '%.1f%%' % (100.0 * a / b) if b else '-'


def summary(results, stab, path):
    ok = [r for r in results if 'error' not in r]
    tot = collections.Counter()
    for r in ok:
        i = r['interface']
        for k in ('abi', 'found', 'extra', 'name_same', 'payable_same', 'params_static', 'params_static_same',
                  'blind_params_static', 'blind_params_static_same'):
            tot['i_' + k] += i[k]
        for k, v in (r.get('storage') or {}).items():
            tot['s_' + k] += v
        for k, v in r['size'].items():
            if isinstance(v, int):
                tot['z_' + k] += v
        sc = r.get('stagecheck') or {}
        for k in ('same', 'different', 'bugs', 'inconclusive'):
            tot['sc_' + k] += sc.get(k, 0)
        tot['sc_contracts_diff'] += bool(sc.get('different') or sc.get('bugs'))
        tot['sc_errors'] += 'error' in sc
        for w in ('empty', 'random'):
            t = (r.get('text_check') or {}).get(w) or {}
            for k in ('calls', 'same', 'different', 'unsupported', 'inconclusive', 'unparsed'):
                tot['tc_%s_%s' % (w, k)] += t.get(k, 0)
    L = ['# Decompiled code against the sources', '',
         '%d artifacts, %d decompiled, %d failed.' % (len(results), len(ok), len(results) - len(ok)), '',
         '## Interface', '',
         '| | |', '|---|---|',
         '| ABI functions found in the dispatcher | %d / %d (%s) |' % (tot['i_found'], tot['i_abi'],
                                                                     pct(tot['i_found'], tot['i_abi'])),
         '| selectors not in the ABI | %d |' % tot['i_extra'],
         '| names and types as the ABI (signature database) | %s |' % pct(tot['i_name_same'], tot['i_found']),
         '| payable as the ABI | %s |' % pct(tot['i_payable_same'], tot['i_found']),
         '| static parameter types (with the database) | %s of %d |' % (
             pct(tot['i_params_static_same'], tot['i_params_static']), tot['i_params_static']),
         '| static parameter types (inferred, --blind) | %s of %d |' % (
             pct(tot['i_blind_params_static_same'], tot['i_blind_params_static']), tot['i_blind_params_static']),
         '', '## Storage', '',
         '| | |', '|---|---|',
         '| layout places found | %d / %d (%s) |' % (tot['s_found'], tot['s_layout'], pct(tot['s_found'], tot['s_layout'])),
         '| their kind as the compiler\'s | %s |' % pct(tot['s_kind_same'], tot['s_found']),
         '| named (from a getter) | %d, the source\'s name %s |' % (tot['s_named'], pct(tot['s_name_same'], tot['s_named'])),
         '', '## Semantics (execution against evmone)', '',
         '| | same | different | inconclusive |', '|---|---|---|---|',
         '| stagecheck, every stage (calls) | %d | %d (%d contracts; bugs %d) | %d |' % (
             tot['sc_same'], tot['sc_different'], tot['sc_contracts_diff'], tot['sc_bugs'], tot['sc_inconclusive']),
         '| text_check, empty world (calls) | %d | %d | %d (+ %d unsupported) |' % (
             tot['tc_empty_same'], tot['tc_empty_different'], tot['tc_empty_inconclusive'],
             tot['tc_empty_unsupported']),
         '| text_check, random world (calls) | %d | %d | %d (+ %d unsupported) |' % (
             tot['tc_random_same'], tot['tc_random_different'], tot['tc_random_inconclusive'],
             tot['tc_random_unsupported']),
         '', 'Texts with lines not parsed: %d (empty world).' % tot['tc_empty_unparsed'],
         '', '## Size (functions matched on both sides: %d)' % tot['z_functions'], '',
         '| | source | decompiled |', '|---|---|---|',
         '| statements / lines | %d | %d (x%.2f) |' % (tot['z_src_statements'], tot['z_dec_lines'],
                                                     tot['z_dec_lines'] / max(1, tot['z_src_statements'])),
         '| loops | %d | %d |' % (tot['z_src_loops'], tot['z_dec_loops']),
         '| conditions | %d | %d |' % (tot['z_src_conditions'], tot['z_dec_conditions']),
         '| reverts and requires | %d | %d |' % (tot['z_src_reverts'], tot['z_dec_reverts']),
         '', '(Source statements: the function, its modifiers and the internal functions it calls, each once;',
         'decompiled lines: the function\'s, comments aside.)', '',
         '## Across EVM versions (the same source and settings)', '',
         '| builds | pairs | functions | identical | lines changed |', '|---|---|---|---|---|']
    for k, s in sorted(stab.items()):
        L.append('| %s | %d | %d | %s | %s |' % (k, s['pairs'], s['functions'], pct(s['identical'], s['functions']),
                                                pct(s['changed'], s['lines'])))
    by_build = collections.defaultdict(lambda: [0, 0])
    for r in ok:
        k = '%s %s%s' % (r['compiler'], r['evm'], '' if r.get('optimizer', True) else ' noopt')
        by_build[k][0] += 1
        by_build[k][1] += bool((r.get('stagecheck') or {}).get('different'))
    L += ['', '## Builds', '', '| compiler, EVM | artifacts | with a difference |', '|---|---|---|']
    for k, (n, d) in sorted(by_build.items()):
        L.append('| %s | %d | %d |' % (k, n, d))
    fails = [r for r in results if 'error' in r][:30]
    if fails:
        L += ['', '## Failures', ''] + ['- %s: %s' % (r['artifact'], r['error']) for r in fails]
    open(path, 'w').write('\n'.join(L) + '\n')


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('build')
    ap.add_argument('--pancxx', default='pancxx')
    ap.add_argument('--stagecheck', default='stagecheck')
    ap.add_argument('--text-check', default='text_check')
    ap.add_argument('--sigdb', default=os.environ.get('PANORAMIX_SIGDB',
                                                      os.path.expanduser('~/.cache/panoramix/sigdb2.bin')))
    ap.add_argument('-j', '--jobs', type=int, default=2)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--program', action='append', default=[])
    ap.add_argument('--evm', default='', help='only these EVM versions (comma separated)')
    ap.add_argument('--match', default='', help='only the artifacts whose path matches this regex')
    ap.add_argument('--own', action='store_true', help="only the projects' own contracts (not lib/, node_modules/...)")
    ap.add_argument('--per-project', type=int, default=0, help='at most N contracts per project and build')
    ap.add_argument('--no-exec', action='store_true')
    ap.add_argument('--blind', action='store_true')
    ap.add_argument('--timeout', type=int, default=600)
    ap.add_argument('--out', default=None)
    args = ap.parse_args()
    args.out = os.path.abspath(args.out or os.path.join(args.build, 'compare'))
    os.makedirs(args.out, exist_ok=True)
    rows, seen = [], set()
    for line in open(os.path.join(args.build, 'index.jsonl')):
        r = json.loads(line)
        if r['artifact'] in seen or (args.program and r['program'] not in args.program):
            continue
        if args.evm and r['build'].split('-')[2] not in args.evm.split(','):
            continue
        if args.match and not re.search(args.match, r['artifact']):
            continue
        if args.own and re.match(r'(lib|node_modules|dependencies|\.deps)__', os.path.basename(r['artifact'])):
            continue
        seen.add(r['artifact'])
        rows.append(r)
    # (an AST's build at a time: the rows of a build together)
    rows.sort(key=lambda r: (r['program'], r['repo'], r['project'], r['build'], r['artifact']))
    if args.per_project:
        # (the same contracts in every build of a project: its N largest)
        names = collections.defaultdict(dict)
        for r in rows:
            n = os.path.basename(r['artifact'])
            size = os.path.getsize(os.path.join(args.build, r['artifact'] + '.hex'))
            d = names[(r['program'], r['repo'], r['project'])]
            d[n] = max(d.get(n, 0), size)
        keep = {k: set(sorted(v, key=lambda n: -v[n])[:args.per_project]) for k, v in names.items()}
        rows = [r for r in rows if os.path.basename(r['artifact']) in keep[(r['program'], r['repo'], r['project'])]]
    if args.limit:
        rows = rows[:args.limit]
    results, groups = [], collections.defaultdict(list)
    caches = collections.defaultdict(dict)
    import threading
    with open(os.path.join(args.out, 'results.jsonl'), 'w') as fh, \
            concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
        futs = [ex.submit(lambda r: one(args, r, caches[threading.get_ident()]), r) for r in rows]
        for fut in futs:
            res, funcs = fut.result()
            results.append(res)
            fh.write(json.dumps(res) + '\n')
            fh.flush()
            if funcs is not None:
                key = (res['program'], res['repo'], res['project'], res['source'], res['contract'],
                       res['compiler'], res.get('via_ir'))
                groups[key].append((res, funcs))
            print('.', end='', flush=True)
    summary(results, stability(groups), os.path.join(args.out, 'summary.md'))
    print('\n%d artifacts -> %s' % (len(results), os.path.join(args.out, 'summary.md')))


if __name__ == '__main__':
    main()
