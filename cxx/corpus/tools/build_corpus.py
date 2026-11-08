#!/usr/bin/env python3
"""Compile the corpus' EVM sources into runtime bytecode, for several EVM
versions, with each contract's ABI, storage layout and the source AST the
comparison tool (compare_source.py) reads.

    build_corpus.py [--program SLUG]... [--evm V,V...] [--optimizer auto|on|off|both]
                    [--out DIR] [--limit N] [--timeout S] [--solc-cache DIR]

Per project of a copied repository (immunefi/SLUG/OWNER__NAME/...: a
directory with foundry.toml, hardhat.config.*, truffle-config.js or
brownie-config.yaml, or a src/ or contracts/ of Solidity sources):
  - the sources: the Solidity files of its source directory (foundry.toml's
    `src`, else src/ or contracts/), tests and scripts left out (*.t.sol,
    *.s.sol, test/, tests/, script/, scripts/);
  - the remappings forge makes (its algorithm ported, forge_remaps): the
    project's remappings.txt and foundry.toml's, then - unless
    auto_detect_remappings is off - its libraries': those of each library
    with a foundry.toml (the same way, recursively) and the automatic ones
    (foundry-compilers' find_many), of one name the shortest path, none
    overlapping one already there; node_modules/ by solc's include paths;
  - the compiler: foundry.toml's solc / solc_version when set, else for each
    source the newest release its pragma (and its imports') allows: the
    sources are compiled in groups of one compiler;
  - optimizer: foundry.toml's optimizer / optimizer_runs / via_ir (auto), or
    on with 200 runs, or off, or both;
  - the EVM versions: each one asked that the compiler supports (default:
    byzantium petersburg istanbul london paris shanghai cancun prague) is a
    build of its own; with --fallback-evm, a compiler that knows none of
    them gets the newest of those it knows; and the project's own
    (foundry.toml's evm_version) when its code needs a newer one.
Vyper sources (.vy): compiled one by one by the Vyper their `# @version` /
`#pragma version` names (pip, a virtualenv per version under the cache), for
each EVM version that Vyper knows.

Output, OUT/SLUG/OWNER__NAME/PROJECT/:
  COMPILER-EVM[-noopt][-ir]/FILE:CONTRACT.hex   runtime bytecode (hex), the
                             contracts with code; libraries linked at made-up
                             addresses (0x11..., one per library)
  COMPILER-EVM[-noopt][-ir]/FILE:CONTRACT.json  abi, storageLayout, the
                             compiler and settings, the links, its AST's dir
  ast-COMPILER[-ir]/FILE.json  every source's AST (solc), once per compiler
and OUT/index.jsonl, one line per artifact. Errors are listed in
OUT/errors.jsonl; a build that fails doesn't stop the others. (FILE: the
source's path, / made __.)
"""
import argparse
import concurrent.futures
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

EVM_ORDER = ['homestead', 'tangerineWhistle', 'spuriousDragon', 'byzantium', 'constantinople', 'petersburg',
             'istanbul', 'berlin', 'london', 'paris', 'shanghai', 'cancun', 'prague', 'osaka']
# the first solc release that knows each EVM version
SOLC_EVM_SINCE = {'homestead': (0, 4, 21), 'tangerineWhistle': (0, 4, 21), 'spuriousDragon': (0, 4, 21),
                  'byzantium': (0, 4, 21), 'constantinople': (0, 4, 21), 'petersburg': (0, 5, 5),
                  'istanbul': (0, 5, 13), 'berlin': (0, 8, 5), 'london': (0, 8, 7), 'paris': (0, 8, 18),
                  'shanghai': (0, 8, 20), 'cancun': (0, 8, 24), 'prague': (0, 8, 27), 'osaka': (0, 8, 29)}
# and each Vyper release
# (vyper's: asked of each release, vyper_evms)
DEFAULT_EVM = 'byzantium,petersburg,istanbul,london,paris,shanghai,cancun,prague'
PROJECT_FILES = ('foundry.toml', 'hardhat.config.js', 'hardhat.config.ts', 'hardhat.config.cjs',
                 'truffle-config.js', 'truffle.js', 'brownie-config.yaml', 'ape-config.yaml')
SKIP_DIRS = {'node_modules', 'lib', 'out', 'cache', 'artifacts', '.git', 'dependencies', 'test', 'tests', 'script',
             'scripts', 'mocks', 'mock', 'certora', 'echidna', 'halmos', 'audit', 'audits'}


# ---- versions ------------------------------------------------------------------------------

def vt(s):
    m = re.match(r'^v?(\d+)\.(\d+)\.(\d+)', s.strip())
    return tuple(int(x) for x in m.groups()) if m else None


def satisfies(v, rng):
    """v (a tuple) satisfies a semver range of npm / solidity's pragma"""
    rng = rng.strip()
    if not rng or rng in ('*', 'x'):
        return True
    for alt in rng.split('||'):
        if all(_one(v, c) for c in _clauses(alt)):
            return True
    return False


def _clauses(alt):
    alt = re.sub(r'(>=|<=|>|<|=|\^|~)\s+', r'\1', alt.strip())
    m = re.match(r'^(\S+)\s+-\s+(\S+)$', alt)
    if m:
        return ['>=' + m.group(1), '<=' + m.group(2)]
    return alt.split()


def _one(v, c):
    m = re.match(r'^(>=|<=|>|<|=|\^|~)?v?(\d+)(?:\.(\d+|x|\*))?(?:\.(\d+|x|\*))?', c)
    if not m:
        return True
    op = m.group(1) or '='
    parts = [m.group(2), m.group(3), m.group(4)]
    nums = []
    for p in parts:
        if p is None or p in ('x', '*'):
            break
        nums.append(int(p))
    base = tuple(nums + [0] * (3 - len(nums)))
    if op == '^':
        if base[0] > 0:
            upper = (base[0] + 1, 0, 0)
        elif base[1] > 0 or len(nums) < 3:
            upper = (0, base[1] + 1, 0)
        else:
            upper = (0, 0, base[2] + 1)
        return base <= v < upper
    if op == '~':
        upper = (base[0], base[1] + 1, 0) if len(nums) >= 2 else (base[0] + 1, 0, 0)
        return base <= v < upper
    if op == '=' and len(nums) < 3:  # 0.8 = 0.8.x
        upper = (base[0], base[1] + 1, 0) if len(nums) == 2 else (base[0] + 1, 0, 0)
        return base <= v < upper
    return {'>=': v >= base, '<=': v <= base, '>': v > base, '<': v < base, '=': v == base}[op]


# ---- solc ----------------------------------------------------------------------------------

def fetch(url, path):
    # (curl: the site refuses urllib's user agent)
    subprocess.run(['curl', '-fsSL', '--retry', '3', '-o', path, url], check=True, timeout=600)


class Solc:
    def __init__(self, cache):
        self.cache = cache
        os.makedirs(cache, exist_ok=True)
        lp = os.path.join(cache, 'list.json')
        if not os.path.exists(lp):
            fetch('https://binaries.soliditylang.org/linux-amd64/list.json', lp)
        self.builds = {b['version']: b for b in json.load(open(lp))['builds'] if 'prerelease' not in b}
        self.releases = sorted((vt(v) for v in self.builds), reverse=True)

    def newest(self, ranges):
        """the release for sources with these pragmas: the newest they allow;
        the oldest when none of them bounds the version from above (">=
        0.5.12": the code is 0.5.12's - a newer major release rejects it)"""
        ok = [v for v in self.releases if all(satisfies(v, r) for r in ranges)]
        if not ok:
            return None
        open_above = ranges and all(re.fullmatch(r'\s*(>=?\s*v?[\d.x*]+\s*)+', r) for r in ranges)
        return min(ok) if open_above else max(ok)

    def path(self, v):
        s = '%d.%d.%d' % v
        exe = os.path.join(self.cache, 'solc-' + s)
        if not os.path.exists(exe):
            b = self.builds[s]
            tmp = exe + '.part'
            fetch('https://binaries.soliditylang.org/linux-amd64/' + b['path'], tmp)
            data = open(tmp, 'rb').read()
            if b.get('sha256') and hashlib.sha256(data).hexdigest() != b['sha256'].removeprefix('0x'):
                os.unlink(tmp)
                raise RuntimeError('solc %s: a wrong sha256' % s)
            os.chmod(tmp, 0o755)
            os.rename(tmp, exe)
        return exe


# ---- projects -------------------------------------------------------------------------------

def toml_get(text, key):
    """a foundry.toml value (the first, [profile.default]'s in practice;
    key_name and key-name alike)"""
    k = re.escape(key).replace('_', '[_-]')
    m = re.search(r'^\s*' + k + r'\s*=\s*(.+?)\s*$', text, re.M)
    if not m:
        return None
    v = m.group(1).split('#')[0].strip()
    return v.strip('"\'')


def toml_array(text, key):
    """the strings of a foundry.toml array (remappings = [...], over lines)"""
    k = re.escape(key).replace('_', '[_-]')
    m = re.search(r'^\s*' + k + r'\s*=\s*\[(.*?)\]', text, re.M | re.S)
    if not m:
        return None
    body = re.sub(r'#[^\n]*', '', m.group(1))
    return re.findall(r'["\']([^"\']*)["\']', body)


def parse_remapping(line):
    """(context, name, path) of a remapping line as forge reads it (None if
    it isn't one); name and path given the trailing / forge gives them (not
    to a .sol file's)"""
    if '=' not in line:
        return None
    name, path = line.split('=', 1)
    ctx = ''
    if ':' in name:
        ctx, name = name.split(':', 1)
    name, path, ctx = name.strip(), path.strip(), ctx.strip()
    if not name or not path:
        return None
    if not name.endswith(('/', '.sol')):
        name += '/'
    if not path.endswith(('/', '.sol')):
        path += '/'
    if not os.path.isabs(path):
        tail = '/' if path.endswith('/') else ''
        path = os.path.normpath(path) + tail
        if path == './':
            path = ''
    return ctx, name, path


def own_remaps(d):
    """a directory's own remappings, (context, name, path) with paths from
    it: remappings.txt's, then foundry.toml's (forge's order: the first of a
    name wins)"""
    lines = []
    rp = os.path.join(d, 'remappings.txt')
    if os.path.exists(rp):
        lines += [x.strip() for x in open(rp, errors='replace') if x.strip() and not x.strip().startswith('#')]
    ft = os.path.join(d, 'foundry.toml')
    if os.path.exists(ft):
        lines += toml_array(open(ft, errors='replace').read(), 'remappings') or []
    return [r for r in map(parse_remapping, lines) if r]


# forge's detection of remappings (foundry-compilers' Remapping::find_many),
# ported: the folder names it knows, its candidates and how it merges them

def _last(p):
    return os.path.basename(p.rstrip('/'))


def _ncomp(p):
    return len([c for c in p.split('/') if c]) + (1 if p.startswith('/') else 0)


def _is_source_dir(p):
    return _last(p) in ('src', 'contracts')


def _is_lib_dir(p):
    return _last(p) in ('lib', 'node_modules')


def _entries(d):
    try:
        return sorted((e for e in os.scandir(d) if not e.name.startswith('.')), key=lambda e: e.name)
    except OSError:
        return []


class _Candidate:
    __slots__ = ('window', 'source', 'level')

    def __init__(self, window, source, level):
        self.window, self.source, self.level = window, source, level


def _next_window(root, cur):
    if not _is_lib_dir(root) or root == cur:
        return root
    if cur.startswith(root + '/'):
        p = root
        for c in os.path.relpath(cur, root).split('/'):
            nxt = os.path.join(p, c)
            if not _is_lib_dir(nxt) or _last(nxt) != 'contracts':
                return nxt
            p = nxt
    return root


def _distance(root, cur):
    if root == cur or not cur.startswith(root + '/'):
        return 0
    return _ncomp(os.path.relpath(cur, root))


def _last_source_dir(root, d):
    if _is_source_dir(d):
        return d
    p = d
    while os.path.dirname(p) != p:
        parent = os.path.dirname(p)
        if parent == root:
            return root
        if _is_source_dir(parent):
            return parent
        p = parent
    return root


def _merge(cands, cur, level, window, in_nm):
    n, pos = 0, None
    for i, c in enumerate(cands):
        if _last(c.source) == 'src':
            n += 1
            pos = i if n == 1 else None
    if pos is not None:
        cands[:] = [cands[pos]]
        return
    cands[:] = [c for c in cands if c.level != level]
    source = window if in_nm else cur
    if level > 0 and source == window and (_is_source_dir(source) or _is_lib_dir(source)):
        return
    cands.append(_Candidate(window, source, level))


def _candidates(cur, open_, level, in_nm, visited):
    is_cand, cands = False, []
    for e in _entries(cur):
        try:
            is_file, is_dir = e.is_file(), e.is_dir()
        except OSError:
            continue
        if not is_cand and is_file and e.name.endswith('.sol'):
            is_cand = True
        elif is_dir:
            if e.is_symlink():
                target = os.path.realpath(e.path)
                if target in visited:
                    return []
                visited.add(target)
                if _ncomp(open_) > _ncomp(target):
                    return []
            if e.name in ('tests', 'test', 'demo'):
                continue
            if _is_lib_dir(e.path):
                for s in _entries(e.path):
                    if s.is_dir():
                        cands += _candidates(s.path, s.path, level + 1, in_nm, visited)
            else:
                cands += _candidates(e.path, open_, level, in_nm, visited)
    window = _next_window(open_, cur)
    if is_cand or sum(1 for c in cands if c.level == level and c.window == window) > 1:
        _merge(cands, cur, level, window, in_nm)
    else:
        c = next((c for c in cands if c.level == level), None)
        if c:
            if _distance(c.window, c.source) > 1 and (
                    _last(c.source) == 'contracts' or c.source.rstrip('/').endswith('/contracts/src')):
                c.source = window
            elif not _is_source_dir(c.source) and c.source != c.window:
                c.source = _last_source_dir(open_, c.source)
    return cands


def find_many(d):
    """forge's automatic remappings of a library folder: {name/: path}
    (absolute paths)"""
    d = os.path.abspath(d)
    in_nm = _last(d) == 'node_modules'
    found, visited = {}, set()
    for e in _entries(d):
        if not e.is_dir():
            continue
        for c in _candidates(e.path, e.path, 0, in_nm, visited):
            name = _last(c.window)
            if not name:
                continue
            k = name + '/'
            old = found.get(k)
            if old is None or _ncomp(old) > _ncomp(c.source) or (_last(c.source) == 'src' and _last(old) != 'src'):
                found[k] = c.source
    return found


def _conflicts(existing, r):
    ctx, name, path = r
    if name.endswith('.sol') and not path.endswith('.sol'):
        return True
    for c, k, v in existing:
        if c != ctx:
            continue
        if name.endswith('.sol'):
            if k == name and v == path:
                return True
            continue
        kk = k if k.endswith('/') else k + '/'
        if name.startswith(kk) or k.startswith(name):
            return True
    return False


_FORGE_CACHE = {}


def forge_remaps(root, depth=0):
    """the remappings forge gives a project root (foundry-config's
    RemappingsProvider), (context, name, path) with paths from the root: its
    own; then, unless auto_detect_remappings is off, those of its libraries:
    the remappings of each library with a foundry.toml (its own and its
    libraries', the same way), the libraries' src/ when they name another
    one, and the automatic ones (find_many) - of one name the shortest path
    - each left out when its name overlaps one already there"""
    root = os.path.realpath(root)
    if root in _FORGE_CACHE:
        return _FORGE_CACHE[root]
    ft = os.path.join(root, 'foundry.toml')
    text = open(ft, errors='replace').read() if os.path.exists(ft) else ''
    out, seen = [], set()
    for r in own_remaps(root):
        if r[0] + r[1] not in seen:
            seen.add(r[0] + r[1])
            out.append(r)
    if (toml_get(text, 'auto_detect_remappings') or '').lower() != 'false' and depth < 6:
        libs = toml_array(text, 'libs')
        if libs is None:
            libs = ['lib'] if os.path.isdir(os.path.join(root, 'lib')) or not text else \
                ['node_modules'] if os.path.isdir(os.path.join(root, 'node_modules')) else ['lib']
        closest = {}

        def put(ctx, name, path):
            k = (ctx, name)
            if k not in closest or _ncomp(closest[k]) > _ncomp(path):
                closest[k] = path

        for l in libs:
            ld = os.path.join(root, l)
            if not os.path.isdir(ld):
                continue
            dirs = [ld] + [e.path for e in _entries(ld) if e.is_dir()]
            for sub in dirs:
                sub = os.path.realpath(sub)
                if sub == root or not os.path.exists(os.path.join(sub, 'foundry.toml')):
                    continue
                for c, k, v in forge_remaps(sub, depth + 1):
                    put(c, k, v if os.path.isabs(v) else os.path.join(sub, v))
                src = toml_get(open(os.path.join(sub, 'foundry.toml'), errors='replace').read(), 'src') or 'src'
                if src.strip('/') not in ('src', 'contracts', 'lib'):
                    put('', os.path.basename(sub) + '/', os.path.join(sub, src))
        for l in libs:
            ld = os.path.join(root, l)
            if os.path.isdir(ld):
                for k, v in find_many(ld).items():
                    if k not in ('lib/', 'src/', 'contracts/'):
                        put('', k, v)
        project_dirs = {(toml_get(text, k) or k).strip('/').lower() + '/' for k in ('src', 'test', 'script')}
        for (ctx, name), path in sorted(closest.items()):
            if not name.endswith('.sol'):
                rel = os.path.relpath(path, root) if os.path.isabs(path) else path
                path = os.path.normpath(rel) + '/'
            r = (ctx, name, path)
            if _conflicts(out, r) or name.lower() in project_dirs:
                continue
            out.append(r)
    _FORGE_CACHE[root] = out
    return out


def foundry_remaps(project):
    """the remappings as forge makes them (forge_remaps), in solc's terms"""
    return forge_remaps(project)


def projects_of(repo):
    """the project directories of a copied repository"""
    found = []
    for d, dirs, files in os.walk(repo):
        dirs[:] = [x for x in dirs if x not in ('node_modules', 'lib', 'out', 'cache', '.git', 'dependencies')]
        if any(f in files for f in PROJECT_FILES):
            found.append(d)
    if not found:
        for sub in ('src', 'contracts'):
            if os.path.isdir(os.path.join(repo, sub)):
                found.append(repo)
                break
    if not found and has_sources(repo):
        found.append(repo)  # (sources and nothing else: the repository is the project)
    return found


def has_sources(top):
    """whether there's a Solidity or Vyper source under top (its tests,
    libraries and the like left out)"""
    for d, dirs, fs in os.walk(top):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.')]
        if any(f.endswith(('.sol', '.vy')) for f in fs):
            return True
    return False


def sources_of(project):
    cfg = {}
    ft = os.path.join(project, 'foundry.toml')
    text = open(ft, errors='replace').read() if os.path.exists(ft) else ''
    for k in ('src', 'solc', 'solc_version', 'optimizer', 'optimizer_runs', 'via_ir', 'evm_version'):
        v = toml_get(text, k)
        if v is not None:
            cfg[k] = v
    # the compilers a hardhat or truffle configuration names (read, never
    # run): each source gets the newest of them its pragmas allow
    vs = set()
    for name in ('hardhat.config.js', 'hardhat.config.ts', 'hardhat.config.cjs', 'truffle-config.js', 'truffle.js'):
        hp = os.path.join(project, name)
        if os.path.exists(hp):
            vs |= {vt(x) for x in re.findall(r'version\s*:\s*["\'](\d+\.\d+\.\d+)', open(hp, errors='replace').read())}
    # dapptools: .dapprc's DAPP_SOLC_VERSION
    dr = os.path.join(project, '.dapprc')
    if os.path.exists(dr):
        m = re.search(r'DAPP_SOLC_VERSION\s*=\s*["\']?(\d+\.\d+\.\d+)', open(dr, errors='replace').read())
        if m:
            vs.add(vt(m.group(1)))
    cfg['config_versions'] = sorted(v for v in vs if v)
    for name in ('hardhat.config.js', 'hardhat.config.ts', 'hardhat.config.cjs'):
        hp = os.path.join(project, name)
        if os.path.exists(hp) and re.search(r'viaIR\s*:\s*true', open(hp, errors='replace').read()):
            cfg.setdefault('via_ir', 'true')
    remaps = foundry_remaps(project)
    # the source directories: foundry.toml's src, a hardhat configuration's
    # paths.sources (read, never run), src/ and contracts/ - every one there,
    # none inside another; else the project's own directory
    hh = []
    for name in ('hardhat.config.js', 'hardhat.config.ts', 'hardhat.config.cjs'):
        hp = os.path.join(project, name)
        if os.path.exists(hp):
            hh += re.findall(r'\bsources\s*:\s*["\']([^"\']+)["\']', open(hp, errors='replace').read())
    src_dirs = []
    for sd in ([cfg['src']] if 'src' in cfg else []) + hh + ['src', 'contracts']:
        sd = os.path.normpath(sd.strip())
        if sd not in src_dirs and not sd.startswith('..') and os.path.isdir(os.path.join(project, sd)):
            src_dirs.append(sd)
    src_dirs = [d for d in src_dirs if d == '.' or not any(e != d and (e == '.' or (d + '/').startswith(e + '/'))
                                                         for e in src_dirs)]
    if not src_dirs:
        src_dirs = ['.']
    files = []
    for sd in src_dirs:
        top = os.path.join(project, sd)
        for d, dirs, fs in os.walk(top):
            dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.')]
            for f in fs:
                if (f.endswith('.sol') and not f.endswith(('.t.sol', '.s.sol'))) or f.endswith('.vy'):
                    files.append(os.path.relpath(os.path.join(d, f), project))
    return sorted(files), remaps, cfg


PRAGMA_RE = re.compile(r'^\s*pragma\s+solidity\s+([^;]+);', re.M)
IMPORT_RE = re.compile(r'''^\s*import\s+(?:[^'"]*from\s+)?["']([^"']+)["']''', re.M)


def resolve(imp, src_file, project, remaps, repo):
    if imp.startswith('.'):
        return os.path.normpath(os.path.join(os.path.dirname(src_file), imp))
    # (solc's choice: the longest context, then the longest prefix)
    best = None
    for c, k, v in remaps:
        if (not c or src_file.startswith(c)) and imp.startswith(k):
            if best is None or (len(c), len(k)) > (len(best[0]), len(best[1])):
                best = (c, k, v)
    if best:
        return os.path.normpath(best[2] + imp[len(best[1]):])
    return os.path.normpath(imp)


def find(path, project, repo):
    for base in (project, os.path.join(project, 'node_modules'), repo, os.path.join(repo, 'node_modules')):
        p = os.path.join(base, path)
        if os.path.exists(p):
            return p
    return None


def pragmas(entry, project, remaps, repo, cache):
    """the pragma ranges of a source and everything it imports"""
    out, todo, seen = [], [entry], set()
    while todo and len(seen) < 5000:
        f = todo.pop()
        if f in seen:
            continue
        seen.add(f)
        if f not in cache:
            p = find(f, project, repo)
            try:
                text = open(p, errors='replace').read() if p else ''
            except OSError:
                text = ''
            cache[f] = (PRAGMA_RE.findall(text), [resolve(i, f, project, remaps, repo) for i in IMPORT_RE.findall(text)])
        prs, imps = cache[f]
        out += prs
        todo += imps
    return out


# ---- builds --------------------------------------------------------------------------------

LINK_RE = re.compile(r'__[$A-Za-z0-9_:./-]{36}__')


def link(code):
    """the code with each library's placeholder (__$hash$__, solc >= 0.5;
    __path:Name___, before) replaced by an address of its own (0x11 then
    its hash's first bytes: never a precompile, one per library); returns
    (code, {placeholder: address})"""
    linked = {}

    def addr(m):
        ph = m.group(0)
        if ph not in linked:
            linked[ph] = '11' + hashlib.sha256(ph.encode()).hexdigest()[:38]
        return linked[ph]

    return LINK_RE.sub(addr, code), linked


def build_solc(solc, version, group, project, repo, remaps, cfg, evm, opt, via_ir, outdir, timeout):
    sources = {f: {'urls': [f]} for f in group}
    settings = {
        'remappings': [('%s:%s=%s' if c else '%s%s=%s') % (c, k, v) for c, k, v in remaps],
        'optimizer': {'enabled': opt, 'runs': int(cfg.get('optimizer_runs', 200) or 200)},
        'outputSelection': {'*': {'*': ['abi', 'evm.deployedBytecode.object', 'storageLayout'], '': ['ast']}},
        'metadata': {'bytecodeHash': 'none'} if version >= (0, 6, 0) else {},
    }
    if version >= (0, 4, 21):
        settings['evmVersion'] = evm
    if via_ir:
        settings['viaIR'] = True
    if version < (0, 5, 13):  # (no storage layout before)
        settings['outputSelection']['*']['*'].remove('storageLayout')
    if not settings['metadata']:
        del settings['metadata']
    inp = {'language': 'Solidity', 'sources': sources, 'settings': settings}
    astname = 'ast-solc-%d.%d.%d' % version + ('-ir' if via_ir else '')
    args = [solc, '--standard-json', '--allow-paths', repo]
    if version < (0, 8, 8):
        # (no include paths before 0.8.8: the packages under node_modules/
        # remapped by name, as a node resolver finds them)
        taken = {k for c, k, v in remaps if not c}
        for nm in ('node_modules', os.path.relpath(os.path.join(repo, 'node_modules'), project)):
            top = os.path.join(project, nm)
            if not os.path.isdir(top):
                continue
            for name in sorted(os.listdir(top)):
                pkgs = [name + '/' + x for x in sorted(os.listdir(os.path.join(top, name)))] \
                    if name.startswith('@') and os.path.isdir(os.path.join(top, name)) else [name]
                for pkg in pkgs:
                    if pkg + '/' not in taken and os.path.isdir(os.path.join(top, pkg)):
                        taken.add(pkg + '/')
                        settings['remappings'].append('%s/=%s/' % (pkg, os.path.normpath(os.path.join(nm, pkg))))
    if version >= (0, 8, 8):
        args += ['--base-path', project]
        # (each directory once, and never the base path: a file found twice
        # is an ambiguous import)
        seen = {os.path.realpath(project)}
        for inc in (os.path.join(project, 'node_modules'), os.path.join(repo, 'node_modules'), repo):
            if os.path.isdir(inc) and os.path.realpath(inc) not in seen:
                seen.add(os.path.realpath(inc))
                args += ['--include-path', inc]
    p = subprocess.run(args, input=json.dumps(inp), capture_output=True, text=True, cwd=project, timeout=timeout)
    try:
        out = json.loads(p.stdout)
    except Exception:
        return [], ['solc output: ' + (p.stderr or p.stdout)[-500:]]
    errors = [e.get('formattedMessage', e.get('message', ''))[-400:] for e in out.get('errors', [])
              if e.get('severity') == 'error']
    arts = []
    os.makedirs(outdir, exist_ok=True)
    for f, contracts in (out.get('contracts') or {}).items():
        for name, c in contracts.items():
            code = (c.get('evm', {}).get('deployedBytecode', {}) or {}).get('object', '')
            if not code:
                continue
            code, linked = link(code)
            base = os.path.join(outdir, f.replace('/', '__') + ':' + name)
            open(base + '.hex', 'w').write(code + '\n')
            json.dump({'abi': c.get('abi'), 'storageLayout': c.get('storageLayout'), 'source': f, 'contract': name,
                       'compiler': 'solc-%d.%d.%d' % version, 'evm': evm, 'optimizer': opt, 'via_ir': via_ir,
                       'ast': '../' + astname, 'linked': linked},
                      open(base + '.json', 'w'))
            arts.append(base)
    # every source's AST (the imported ones too: a contract's bases), once
    # per compiler: the same for every EVM version
    astdir = os.path.join(os.path.dirname(outdir), astname)
    for f, s in (out.get('sources') or {}).items():
        p = os.path.join(astdir, f.replace('/', '__') + '.json')
        if s.get('ast') and not os.path.exists(p):
            os.makedirs(astdir, exist_ok=True)
            json.dump(s['ast'], open(p, 'w'))
    return arts, errors


def vyper_exe(version, cache):
    """the vyper of a release, in a virtualenv of its own under the cache
    (the releases before 0.3.8 ask for a python below 3.11: the oldest one
    here, their constraint ignored)"""
    venv = os.path.join(cache, 'vyper-' + version)
    exe = os.path.join(venv, 'bin', 'vyper')
    if not os.path.exists(exe):
        old = vt(version) < (0, 3, 8)
        py = next((p for p in ('/usr/bin/python3.10', '/usr/bin/python3.11') if os.path.exists(p)),
                  sys.executable) if old else sys.executable
        shutil.rmtree(venv, ignore_errors=True)
        subprocess.run([py, '-m', 'venv', venv], check=True, timeout=600)
        subprocess.run([os.path.join(venv, 'bin', 'pip'), 'install', '-q'] +
                       (['--ignore-requires-python'] if old else []) + ['vyper==' + version],
                       check=True, timeout=1200)
    return exe


_VYPER_EVMS = {}


def vyper_evms(exe):
    """the EVM versions a vyper knows (from its own --evm-version choices)"""
    if exe not in _VYPER_EVMS:
        p = subprocess.run([exe, '--evm-version', 'none-such', 'x.vy'], capture_output=True, text=True, timeout=120)
        m = re.search(r'choose from ([^)]*)\)', p.stderr)
        _VYPER_EVMS[exe] = set(re.findall(r"'([A-Za-z]+)'", m.group(1))) if m else set()
    return _VYPER_EVMS[exe]


def vyper_layout(layout):
    """vyper's storage layout as solc's (storage: label, slot, offset, type;
    types: the encoding), modules' variables with their path"""
    storage, types = [], {}

    def kind(t):
        if t.startswith('HashMap'):
            return 'mapping'
        if t.startswith('DynArray'):
            return 'dynamic_array'
        if t.startswith(('String', 'Bytes[')):
            return 'bytes'
        return 'inplace'

    def walk(d, prefix):
        for name, v in (d or {}).items():
            if isinstance(v, dict) and 'slot' in v and 'type' in v:
                t = str(v['type'])
                types.setdefault(t, {'encoding': kind(t), 'label': t})
                storage.append({'label': prefix + name, 'slot': str(v['slot']), 'offset': 0, 'type': t})
            elif isinstance(v, dict):
                walk(v, prefix + name + '.')

    walk((layout or {}).get('storage_layout', layout or {}), '')
    return {'storage': storage, 'types': types}


def build_vyper(f, project, evm, outdir, cache, timeout):
    text = open(os.path.join(project, f), errors='replace').read()
    m = re.search(r'^#\s*(?:@version|pragma\s+version)\s+[\^~=>]*\s*(\d+\.\d+\.\d+)', text, re.M)
    if not m:
        return [], ['%s: no version pragma' % f]
    version = m.group(1)
    exe = vyper_exe(version, cache)
    if evm not in vyper_evms(exe):
        return [], []
    # a source that pins its EVM version (#pragma evm-version) is compiled
    # for another one from a copy without that line, beside it (imports
    # resolve the same), removed after
    src, tmp = f, None
    pm = re.search(r'^#\s*pragma\s+evm-version\s+(\w+)\s*$', text, re.M)
    if pm and pm.group(1) != evm:
        d, b = os.path.split(f)
        tmp = os.path.join(d, '.%s.%s.vy' % (os.path.splitext(b)[0], evm))
        open(os.path.join(project, tmp), 'w').write(text[:pm.start()] + '\n' + text[pm.end():])
        src = tmp
    try:
        p = subprocess.run([exe, '-f', 'bytecode_runtime,abi,layout', '--evm-version', evm, src], capture_output=True,
                           text=True, cwd=project, timeout=timeout)
    finally:
        if tmp:
            os.unlink(os.path.join(project, tmp))
    if p.returncode != 0:
        err = [l for l in p.stderr.strip().split('\n') if 'Warning' not in l and 'python_ast' not in l]
        return [], ['%s: %s' % (f, '\n'.join(err)[-400:])]
    lines = p.stdout.strip().split('\n')
    code = lines[0].strip().removeprefix('0x')
    try:
        abi = json.loads(lines[1]) if len(lines) > 1 else None
        layout = vyper_layout(json.loads(lines[2])) if len(lines) > 2 else None
    except Exception:
        abi, layout = None, None
    if not code:
        return [], []
    os.makedirs(outdir, exist_ok=True)
    base = os.path.join(outdir, f.replace('/', '__') + ':' + os.path.splitext(os.path.basename(f))[0])
    open(base + '.hex', 'w').write(code + '\n')
    # its AST (vyper's -f ast), once per compiler
    astname = 'ast-vyper-' + version
    ap = os.path.join(os.path.dirname(outdir), astname, f.replace('/', '__') + '.json')
    if not os.path.exists(ap):
        q = subprocess.run([exe, '-f', 'ast', f], capture_output=True, text=True, cwd=project, timeout=timeout)
        if q.returncode == 0 and q.stdout.strip():
            os.makedirs(os.path.dirname(ap), exist_ok=True)
            open(ap, 'w').write(q.stdout)
    json.dump({'abi': abi, 'storageLayout': layout, 'source': f, 'contract': os.path.basename(f),
               'compiler': 'vyper-' + version, 'evm': evm, 'optimizer': True, 'via_ir': False,
               'ast': '../' + astname}, open(base + '.json', 'w'))
    return [base], []


def build_project(args, solc, slug, repo, project):
    files, remaps, cfg = sources_of(project)
    sol = [f for f in files if f.endswith('.sol')]
    vys = [f for f in files if f.endswith('.vy')]
    rel = os.path.relpath(project, repo)
    rel = '' if rel == '.' else rel
    base_out = os.path.join(args.out, slug, os.path.basename(repo), rel)
    index, errors = [], []
    opts = {'auto': [cfg.get('optimizer', 'true') != 'false'], 'on': [True], 'off': [False],
            'both': [True, False]}[args.optimizer]
    via_ir = cfg.get('via_ir', 'false') == 'true'
    evms = args.evm.split(',')
    # the compiler of each Solidity source: foundry's, else the newest every pragma allows
    groups = {}
    fixed = vt(cfg.get('solc_version') or cfg.get('solc') or '')
    cache = {}
    for f in sol:
        prs = pragmas(f, project, remaps, repo, cache)
        conf = [x for x in cfg.get('config_versions', []) if all(satisfies(x, r) for r in prs)]
        v = fixed or (max(conf) if conf else solc.newest(prs))
        if v is None:
            errors.append({'project': project, 'file': f, 'error': 'no solc release fits its pragmas'})
            continue
        groups.setdefault(v, []).append(f)
    for v, group in sorted(groups.items()):
        try:
            exe = solc.path(v)
        except Exception as e:
            errors.append({'project': project, 'solc': '%d.%d.%d' % v, 'error': str(e)})
            continue
        known = [e for e in evms if v >= SOLC_EVM_SINCE.get(e, (9, 9, 9))]
        if not known and args.fallback_evm:
            fb = [e for e in args.fallback_evm.split(',') if v >= SOLC_EVM_SINCE.get(e, (9, 9, 9))]
            known = fb[-1:]
        # the project's own EVM version too when the code needs a newer one
        # than those asked (an instruction "only available for" it)
        own = cfg.get('evm_version', '')
        extra = [own] if own in SOLC_EVM_SINCE and own not in known and v >= SOLC_EVM_SINCE[own] and \
            (not known or EVM_ORDER.index(own) > EVM_ORDER.index(known[-1])) else []
        for evm in known + extra:
            if evm in extra and not any(re.search(r'only available for', str(x.get('error', ''))) for x in errors
                                        if x.get('build', '').startswith('solc-%d.%d.%d-' % v)):
                continue
            for opt in opts:
                tag = 'solc-%d.%d.%d-%s%s%s' % (v + (evm, '' if opt else '-noopt', '-ir' if via_ir else ''))
                outdir = os.path.join(base_out, tag)
                try:
                    arts, errs = build_solc(exe, v, group, project, repo, remaps, cfg, evm, opt, via_ir, outdir,
                                            args.timeout)
                except subprocess.TimeoutExpired:
                    arts, errs = [], ['timeout']
                # one source's error fails its whole group: each source alone
                # then (not when the EVM version is what the code can't
                # target: an error says so, the others follow from it)
                if errs and not arts and len(group) > 1 and len(group) <= args.retry_max and \
                        not any(re.search(r'VMs?\b|only available for|not supported by the', e) for e in errs):
                    errs = ['group failed, each source alone: ' + errs[0][-200:]]
                    for f in group:
                        try:
                            a1, e1 = build_solc(exe, v, [f], project, repo, remaps, cfg, evm, opt, via_ir, outdir,
                                                args.timeout)
                        except subprocess.TimeoutExpired:
                            a1, e1 = [], ['timeout']
                        arts += [a for a in a1 if a not in arts]
                        errs += ['%s: %s' % (f, x) for x in e1[:2]]
                index += [{'program': slug, 'repo': os.path.basename(repo), 'project': rel, 'build': tag,
                           'artifact': os.path.relpath(a, args.out)} for a in arts]
                errors += [{'project': project, 'build': tag, 'error': e} for e in errs[:20]]
    for f in vys:
        m = re.search(r'^#\s*(?:@version|pragma\s+version)\s+[\^~=>]*\s*(\d+\.\d+\.\d+)',
                      open(os.path.join(project, f), errors='replace').read(), re.M)
        if not m:
            continue  # (an interface or a module without a version: compiled through its users)
        for evm in evms:
            tag = 'vyper-%s-%s' % (m.group(1), evm)
            try:
                arts, errs = build_vyper(f, project, evm, os.path.join(base_out, tag), args.solc_cache, args.timeout)
            except Exception as e:
                arts, errs = [], [str(e)[-300:]]
            index += [{'program': slug, 'repo': os.path.basename(repo), 'project': rel, 'build': tag,
                       'artifact': os.path.relpath(a, args.out)} for a in arts]
            errors += [{'project': project, 'file': f, 'evm': evm, 'error': e} for e in errs]
    return index, errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--program', action='append', default=[])
    ap.add_argument('--repo', action='append', default=[], help='OWNER__NAME, only those')
    ap.add_argument('--evm', default=DEFAULT_EVM)
    ap.add_argument('--fallback-evm', default='',
                    help='for a compiler that knows none of --evm: the newest of these it knows (comma separated)')
    ap.add_argument('--optimizer', default='auto', choices=['auto', 'on', 'off', 'both'])
    ap.add_argument('--out', default=os.path.join(ROOT, 'build'))
    ap.add_argument('--limit', type=int, default=0, help='projects at most')
    ap.add_argument('--timeout', type=int, default=900)
    ap.add_argument('--jobs', type=int, default=1)
    ap.add_argument('--retry-max', type=int, default=150, help='a failed group of at most N sources: each alone')
    ap.add_argument('--solc-cache', default=os.path.expanduser('~/.cache/panoramix-corpus'))
    args = ap.parse_args()
    solc = Solc(args.solc_cache)
    work = []
    for prog in sorted(glob.glob(os.path.join(ROOT, 'immunefi', '*', 'manifest.json'))):
        slug = os.path.basename(os.path.dirname(prog))
        if args.program and slug not in args.program:
            continue
        for repo in sorted(glob.glob(os.path.join(os.path.dirname(prog), '*__*'))):
            if args.repo and os.path.basename(repo) not in args.repo:
                continue
            for project in projects_of(repo):
                work.append((slug, repo, project))
    if args.limit:
        work = work[:args.limit]
    os.makedirs(args.out, exist_ok=True)
    n_art = n_err = 0
    with open(os.path.join(args.out, 'index.jsonl'), 'a') as idx, \
            open(os.path.join(args.out, 'errors.jsonl'), 'a') as err, \
            concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
        for index, errors in ex.map(lambda w: build_project(args, solc, *w), work):
            for x in index:
                idx.write(json.dumps(x) + '\n')
            for x in errors:
                err.write(json.dumps(x) + '\n')
            n_art += len(index)
            n_err += len(errors)
            print('.', end='', flush=True)
    print('\n%d projects, %d artifacts, %d errors (%s)' % (len(work), n_art, n_err, args.out))


if __name__ == '__main__':
    main()
