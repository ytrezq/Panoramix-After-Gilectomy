#!/usr/bin/env python3
"""Copy one git repository's EVM sources into the corpus, with their tree.

    copy_repo.py --program SLUG --repo URL [--ref REF] [--scope PATH]...
                 [--root CORPUS_ROOT] [--work DIR] [--reference-only]

What is copied (DEST = ROOT/immunefi/SLUG/OWNER__NAME/, the repository's own
directory structure kept below it):
  - the sources of every EVM language: .sol .vy .vyi .yul .huff .fe .lll .se
    (tests and scripts written in them included: they exercise the contracts);
  - what building them needs: foundry.toml, remappings.txt, hardhat/truffle/
    brownie/ape/dapptools configs, package.json, .gitmodules, Makefile,
    foundry.lock, soldeer.lock;
  - LICENSE / COPYING / NOTICE / README files;
  - the dependencies, as the build sees them: the git submodules (recursively,
    each at the commit its parent pins, below its own path), and the npm
    packages the sources import (installed at the versions package.json asks,
    their EVM sources copied below node_modules/).
Never: .git, build outputs and caches (out, artifacts, cache, typechain,
coverage...), files over 2 MB.

A repository is copied only when its license allows redistribution (an open
license file at its root, or package.json's license, or open SPDX headers on
its own sources); otherwise it is recorded by URL and commit only (the corpus'
tools/fetch_reference.py fetches those). Either way ROOT/immunefi/SLUG/
manifest.json gets an entry: the repository, the commit, the submodules' and
npm packages' versions, the license found, the languages, the scope paths.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SRC_EXT = ('.sol', '.vy', '.vyi', '.yul', '.huff', '.fe', '.lll', '.se')
CONFIG_NAMES = {'foundry.toml', 'remappings.txt', 'package.json', '.gitmodules', 'Makefile', 'makefile',
                'foundry.lock', 'soldeer.lock', 'brownie-config.yaml', 'brownie-config.yml', 'ape-config.yaml',
                'ape-config.yml', 'truffle-config.js', 'truffle.js', 'dappfile', '.dapprc', 'vyper.toml',
                'pyproject.toml', 'setup.cfg', 'hardhat.config.js', 'hardhat.config.ts', 'hardhat.config.cjs',
                'hardhat.config.mjs', 'echidna.yaml', 'medusa.json', 'slither.config.json', 'tsconfig.json',
                'lerna.json', 'pnpm-workspace.yaml', 'nx.json', 'turbo.json', 'huff.toml', 'fe.toml', 'Scarb.toml'}
DOC_RE = re.compile(r'^(LICEN[CS]E|COPYING|NOTICE|README|AUTHORS|PATENTS)([._-].*)?$', re.I)
# build outputs and caches only (never a name a source directory may have:
# types/, build/, dist/, target/... are walked, only their EVM sources kept)
SKIP_DIRS = {'.git', 'node_modules', 'out', 'artifacts', 'cache', 'cache_forge', 'cache_hardhat', 'typechain',
             'typechain-types', 'coverage', 'crytic-export', '__pycache__', '.venv', 'venv', 'zkout',
             'artifacts-zk', 'cache-zk'}
MAX_BYTES = 2 * 1024 * 1024
OPEN_LICENSES = re.compile(
    r'MIT|Apache|GPL|LGPL|AGPL|BSD|MPL|ISC|Unlicense|CC0|BUSL|Business Source|WTFPL|Zlib|Artistic|EPL|0BSD|'
    r'BlueOak|PostgreSQL|Python|CC-BY', re.I)
PER_FILE = 'per-file headers'
LICENSE_TEXT_HINTS = [
    # a license file granting nothing "except as otherwise provided in the
    # header of a specific source code file": each file's header decides
    (PER_FILE, r'(?:except|unless)\s+(?:as\s+)?otherwise\s+(?:provided|stated|indicated|specified)\s+in\s+the\s+'
               r'header'),
    # (first of the others: its text names the open license it changes to)
    ('BUSL-1.1', r'Business Source License'),
    ('MIT', r'Permission is hereby granted, free of charge'),
    ('Apache-2.0', r'Apache License,?\s+V(?:ersion\s*)?2'),
    ('AGPL-3.0', r'GNU AFFERO GENERAL PUBLIC LICENSE'),
    ('LGPL-3.0', r'GNU LESSER GENERAL PUBLIC LICENSE'),
    # ("Version 3", and a file pointing at the text: "GNU General Public
    # License v3.0 (GPL-3.0), see LICENSES/GPL-3.0")
    ('GPL-3.0', r'GNU GENERAL PUBLIC LICENSE,?\s+V(?:ersion\s*)?3'),
    ('GPL-2.0', r'GNU GENERAL PUBLIC LICENSE,?\s+V(?:ersion\s*)?2'),
    ('MPL-2.0', r'Mozilla Public License'),
    ('BSD', r'Redistribution and use in source and binary forms'),
    ('Unlicense', r'This is free and unencumbered software released into the public domain'),
    ('CC0-1.0', r'CC0 1\.0|Creative Commons Zero'),
    ('ISC', r'Permission to use, copy, modify, and/or distribute this software'),
    ('WTFPL', r'DO WHAT THE FUCK YOU WANT'),
]
SHA_RE = re.compile(r'^[0-9a-f]{40}$')


def run(cmd, cwd=None, timeout=900, check=True, env=None):
    p = subprocess.run(cmd, cwd=cwd, timeout=timeout, capture_output=True, text=True,
                       env=dict(os.environ, GIT_TERMINAL_PROMPT='0', **(env or {})))
    if check and p.returncode != 0:
        raise RuntimeError(f'{" ".join(cmd)}: {p.returncode}: {p.stderr.strip()[-800:]}')
    return p


def clone(url, ref, dest):
    """a shallow checkout of url at ref (a branch, a tag, a commit, or the
    default branch); returns the commit"""
    os.makedirs(dest, exist_ok=True)
    run(['git', 'init', '-q'], cwd=dest)
    run(['git', 'remote', 'add', 'origin', url], cwd=dest)
    want = ref or 'HEAD'
    p = run(['git', 'fetch', '-q', '--depth', '1', 'origin', want], cwd=dest, timeout=1800, check=False)
    if p.returncode != 0 and ref and not SHA_RE.match(ref):
        # a short commit, or a ref the server won't hand out shallowly
        run(['git', 'fetch', '-q', '--filter=blob:none', 'origin'], cwd=dest, timeout=1800)
        r = run(['git', 'rev-parse', '--verify', ref + '^{commit}'], cwd=dest, check=False)
        if r.returncode != 0:
            r = run(['git', 'rev-parse', '--verify', 'origin/' + ref + '^{commit}'], cwd=dest)
        run(['git', 'checkout', '-q', r.stdout.strip()], cwd=dest, timeout=1800)
    else:
        if p.returncode != 0:
            raise RuntimeError(f'fetch {url} {want}: {p.stderr.strip()[-800:]}')
        run(['git', 'checkout', '-q', 'FETCH_HEAD'], cwd=dest, timeout=1800)
    return run(['git', 'rev-parse', 'HEAD'], cwd=dest).stdout.strip()


def submodules(repo_dir, depth=0, prefix=''):
    """checks out the submodules (recursively, shallow at their pinned
    commits); returns [{path, url, commit}]"""
    out = []
    if depth > 4 or not os.path.exists(os.path.join(repo_dir, '.gitmodules')):
        return out
    p = run(['git', 'config', '-f', '.gitmodules', '--get-regexp', r'^submodule\..*\.(path|url)$'], cwd=repo_dir,
            check=False)
    mods = {}
    for line in p.stdout.splitlines():
        key, _, val = line.partition(' ')
        m = re.match(r'submodule\.(.*)\.(path|url)$', key)
        if m:
            mods.setdefault(m.group(1), {})[m.group(2)] = val
    for name, mod in mods.items():
        path, url = mod.get('path'), mod.get('url')
        if not path or not url:
            continue
        ls = run(['git', 'ls-tree', 'HEAD', path], cwd=repo_dir, check=False).stdout.split()
        if len(ls) < 3 or ls[1] != 'commit':
            continue
        commit = ls[2]
        if url.startswith('../') or url.startswith('./'):
            base = run(['git', 'remote', 'get-url', 'origin'], cwd=repo_dir).stdout.strip()
            url = os.path.normpath(os.path.join(base.rstrip('/'), url)).replace(':/', '://')
        if url.startswith('git@github.com:'):
            url = 'https://github.com/' + url[len('git@github.com:'):]
        sub = os.path.join(repo_dir, path)
        if os.path.isdir(sub):
            shutil.rmtree(sub)
        entry = {'path': prefix + path, 'url': url, 'commit': commit}
        try:
            clone(url, commit, sub)
            out.append(entry)
            out += submodules(sub, depth + 1, prefix + path + '/')
        except Exception as e:  # a submodule that's gone: recorded, not fatal
            entry['error'] = str(e)[-300:]
            out.append(entry)
    return out


def soldeer(repo_dir, prefix=''):
    """the dependencies soldeer.lock files pin (foundry's soldeer: below each
    project's dependencies/<name>-<version>/, not in git): those from git
    cloned at their rev, those of soldeer's registry downloaded (its zip);
    returns [{path, url, rev|zip, error?}]"""
    import tomllib
    out = []
    for d, dirs, files in os.walk(repo_dir):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.git') and x != 'dependencies']
        if 'soldeer.lock' not in files:
            continue
        try:
            lock = tomllib.load(open(os.path.join(d, 'soldeer.lock'), 'rb'))
        except Exception as e:
            out.append({'path': os.path.relpath(d, repo_dir), 'error': 'soldeer.lock: ' + str(e)[:200]})
            continue
        for dep in lock.get('dependencies', []):
            name, version = dep.get('name'), dep.get('version')
            if not name or not version:
                continue
            target = os.path.join(d, 'dependencies', f'{name}-{version}')
            rel = prefix + os.path.relpath(target, repo_dir)
            entry = {'path': rel, 'name': name, 'version': version}
            try:
                if dep.get('git'):
                    entry.update({'url': dep['git'], 'rev': dep.get('rev')})
                    clone(dep['git'], dep.get('rev'), target)
                    entry['submodules'] = submodules(target, 1, rel + '/')
                elif dep.get('url'):
                    entry['zip'] = dep['url']
                    tmp = tempfile.mkdtemp(prefix='soldeer-', dir=os.path.dirname(repo_dir))
                    try:
                        z = os.path.join(tmp, 'dep.zip')
                        run(['curl', '-sSfL', '--max-time', '300', '-o', z, dep['url']], timeout=400)
                        os.makedirs(target, exist_ok=True)
                        run(['unzip', '-q', '-o', z, '-d', target], timeout=400)
                    finally:
                        shutil.rmtree(tmp, ignore_errors=True)
            except Exception as e:
                entry['error'] = str(e)[-300:]
            out.append(entry)
    return out


def wanted(name):
    return name.endswith(SRC_EXT) or name in CONFIG_NAMES or bool(DOC_RE.match(name))


def walk_sources(top):
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.git')]
        for f in files:
            if wanted(f):
                yield os.path.join(d, f)


IMPORT_RE = re.compile(r'''^\s*import\s+(?:[^'"]*from\s+)?["']([^"']+)["']''', re.M)


PROJECT_FILES = ('foundry.toml', 'remappings.txt', 'package.json', 'hardhat.config.js', 'hardhat.config.ts',
                 'truffle-config.js', 'brownie-config.yaml', 'ape-config.yaml')


def remappings(project_dir):
    """[(prefix, target)] of a project's remappings.txt and foundry.toml (a
    context prefix `ctx:` dropped), the longest prefix first"""
    out = []
    p = os.path.join(project_dir, 'remappings.txt')
    if os.path.exists(p):
        for line in open(p, errors='replace'):
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                k, v = line.split('=', 1)
                out.append((k.split(':', 1)[-1].strip(), v.strip()))
    ft = os.path.join(project_dir, 'foundry.toml')
    if os.path.exists(ft):
        for k, v in re.findall(r'["\']([^"\'=\s]+)=([^"\']*)["\']', open(ft, errors='replace').read()):
            out.append((k.split(':', 1)[-1].strip(), v.strip()))
    return sorted((x for x in out if x[0]), key=lambda kv: -len(kv[0]))


def npm_name(path):
    parts = path.split('/')
    return '/'.join(parts[:2]) if path.startswith('@') and len(parts) > 1 else parts[0]


def declared(pj_path):
    """a package.json's dependencies of every kind: {name: spec}"""
    try:
        pj = json.load(open(pj_path))
    except Exception:
        return {}
    out = {}
    for sec in ('dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'):
        for k, v in (pj.get(sec) or {}).items():
            # (a workspace's own packages are linked, not fetched: npm_needs)
            if isinstance(v, str) and not v.startswith(('workspace:', 'file:', 'link:')):
                out.setdefault(k, v)
    return out


def under(rel, prefixes):
    return any(rel == s or rel.startswith(s + '/') for s in prefixes)


def pnpm_catalogs(top):
    """pnpm-workspace.yaml's catalogs: {catalog name ('default' for
    `catalog:`): {package: spec}} (a small reader of the two mappings)"""
    p = os.path.join(top, 'pnpm-workspace.yaml')
    out = {}
    if not os.path.exists(p):
        return out
    section, name = None, None
    for raw in open(p, errors='replace'):
        line = raw.split(' #')[0].rstrip()
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        ind = len(line) - len(line.lstrip())
        key, sep, val = line.strip().partition(':')
        key, val = key.strip().strip('"\''), val.strip().strip('"\'')
        if ind == 0:
            section = key if key in ('catalog', 'catalogs') else None
            name = 'default' if section == 'catalog' else None
            continue
        if section == 'catalogs' and ind <= 2 and not val:
            name = key
            continue
        if section and name and sep and val:
            out.setdefault(name, {})[key] = val
    return out


def workspace_packages(top, skip=()):
    """{package name: its directory relative to top} of the package.json
    files in the tree (a monorepo's packages, which pnpm / yarn / npm
    workspaces link into node_modules/ by name)"""
    out = {}
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.git')]
        rel = os.path.relpath(d, top)
        rel = '' if rel == '.' else rel
        if under(rel, skip):
            dirs[:] = []
            continue
        if 'package.json' in files:
            try:
                n = json.load(open(os.path.join(d, 'package.json'))).get('name')
            except Exception:
                n = None
            if isinstance(n, str) and n:
                out.setdefault(n, rel)
    return out


def npm_needs(top, skip=(), links=None):
    """The npm packages the EVM sources below top import, where the build will
    look for them: {(node_modules dir relative to top, package name): spec}.
    Each source is read in its project: the nearest directory above it with a
    foundry.toml, remappings.txt, package.json or another build config (its
    remappings first: one into node_modules/ names the package directory and
    where it goes; an import that isn't remapped and isn't in the tree is
    looked for in node_modules/ beside the project). The spec is what a
    package.json declares (the project's, then the tree's top one, then any
    other in the tree; pnpm's `catalog:` read in pnpm-workspace.yaml); a name
    no package.json declares is not fetched (an import the build resolves
    some other way). A package of the tree itself (a workspace's) isn't
    fetched: links[(nm, name)] = its directory, for a symbolic link as the
    workspace's install makes. Sources under skip (the submodules) resolve
    theirs themselves."""
    catalogs = pnpm_catalogs(top)
    ws = workspace_packages(top, skip)
    projects, pjs = [], {}
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.git')]
        rel = os.path.relpath(d, top)
        rel = '' if rel == '.' else rel
        if under(rel, skip):
            dirs[:] = []
            continue
        if any(f in files for f in PROJECT_FILES):
            projects.append(rel)
        if 'package.json' in files:
            pjs[rel] = declared(os.path.join(d, 'package.json'))
    projects.sort(key=len, reverse=True)
    anywhere = {}
    for rel in sorted(pjs, key=len):
        for k, v in pjs[rel].items():
            anywhere.setdefault(k, v)
    remap_cache = {}
    needs = {}
    for path in walk_sources(top):
        if not path.endswith('.sol'):
            continue
        rel = os.path.relpath(path, top)
        if under(rel, skip):
            continue
        proj = next((p for p in projects if p == '' or rel.startswith(p + '/')), '')
        if proj not in remap_cache:
            remap_cache[proj] = remappings(os.path.join(top, proj))
        try:
            text = open(path, errors='replace').read()
        except OSError:
            continue
        for imp in IMPORT_RE.findall(text):
            if imp.startswith('.') or '://' in imp or imp.startswith('/'):
                continue
            target = None
            for prefix, to in remap_cache[proj]:
                if imp.startswith(prefix):
                    target = to + imp[len(prefix):]
                    break
            if target is not None:
                t = target[2:] if target.startswith('./') else target
                i = t.find('node_modules/')
                if i < 0:
                    continue  # (into the tree: lib/, src/...)
                nm = os.path.normpath(os.path.join(proj, t[:i] + 'node_modules'))
                name = npm_name(t[i + len('node_modules/'):])
            else:
                if os.path.exists(os.path.join(top, proj, imp)) or os.path.exists(os.path.join(top, imp)):
                    continue
                nm = os.path.normpath(os.path.join(proj, 'node_modules'))
                name = npm_name(imp)
            if nm.startswith('..'):
                continue
            if name in ws:
                if links is not None and os.path.normpath(os.path.join(nm, name)) != ws[name]:
                    links.setdefault((nm, name), ws[name])
                continue
            spec = pjs.get(proj, {}).get(name) or pjs.get('', {}).get(name) or anywhere.get(name)
            if spec is not None and spec.startswith('catalog:'):
                spec = catalogs.get(spec[len('catalog:'):] or 'default', {}).get(name)
            if spec is None:
                continue
            needs.setdefault((nm, name), spec)
    return needs


GIT_SPEC = re.compile(r'^(?:github:|git\+|git://|https?://(?:www\.)?github\.com/|https?://codeload\.github\.com/|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:#|$))')


def fetch_package(name, spec, nm, work):
    """one npm package's own files (not its dependencies: only its EVM
    sources are wanted) into nm/name; returns its version"""
    dest = os.path.join(nm, name)
    if os.path.isdir(dest):
        try:
            return json.load(open(os.path.join(dest, 'package.json'))).get('version')
        except Exception:
            return None
    real, ver = name, spec or 'latest'
    if ver.startswith('npm:'):  # an alias: npm:@scope/pkg@range
        rest = ver[4:]
        at = rest.rfind('@')
        real, ver = (rest[:at], rest[at + 1:]) if at > 0 else (rest, 'latest')
    tmp = tempfile.mkdtemp(prefix='pkg-', dir=work)
    try:
        if GIT_SPEC.match(ver):
            # a git dependency (the registry's tarballs of GitHub are not
            # reachable here; git is): cloned at its ref
            url, _, ref = ver.partition('#')
            url = re.sub(r'^(github:|git\+)', '', url)
            # a GitHub tarball or archive of a ref: the repository at that ref
            m = re.match(r'https?://(?:www\.)?github\.com/([^/]+)/([^/#]+?)/(?:tarball|archive|zipball)/(.+?)'
                         r'(?:\.tar\.gz|\.tgz|\.zip)?$', url) or \
                re.match(r'https?://codeload\.github\.com/([^/]+)/([^/]+)/(?:tar\.gz|zip|legacy\.tar\.gz)/(.+)$', url)
            if m:
                url, ref = 'https://github.com/%s/%s' % (m.group(1), m.group(2)), m.group(3)
            if not url.startswith(('http', 'git://', 'ssh')):
                url = 'https://github.com/' + url
            url = url.replace('git://', 'https://').replace('ssh://git@', 'https://').replace('git@github.com:', 'https://github.com/')
            clone(url, ref.replace('semver:', '') or None, os.path.join(tmp, 'package'))
        else:
            p = run(['npm', 'pack', f'{real}@{ver}', '--pack-destination', tmp, '--ignore-scripts', '--silent'],
                    cwd=tmp, timeout=600)
            tgz = os.path.join(tmp, p.stdout.strip().splitlines()[-1])
            os.makedirs(os.path.join(tmp, 'x'))
            run(['tar', 'xzf', tgz, '-C', os.path.join(tmp, 'x')], timeout=600)
            top = os.listdir(os.path.join(tmp, 'x'))
            os.rename(os.path.join(tmp, 'x', top[0] if len(top) == 1 else 'package'), os.path.join(tmp, 'package'))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(os.path.join(tmp, 'package'), dest)
        try:
            return json.load(open(os.path.join(dest, 'package.json'))).get('version')
        except Exception:
            return ref if GIT_SPEC.match(ver) else None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def install_npm(needs, work):
    """the packages (needs: {(nm dir, name): spec}) fetched one by one into
    work/<nm dir>/<name>, and the npm packages their own EVM sources import
    (declared by their package.json) beside them; returns ({"<nm dir>/<name>":
    version}, {"<nm dir>/<name>": error})"""
    os.makedirs(work, exist_ok=True)
    got, errors = {}, {}
    todo = list(needs.items())
    seen = set(needs)
    while todo:
        (nm, name), spec = todo.pop(0)
        key = f'{nm}/{name}'
        nm_abs = os.path.join(work, nm)
        try:
            got[key] = fetch_package(name, spec, nm_abs, work)
        except Exception as e:
            errors[key] = str(e)[-200:]
            continue
        pkg = os.path.join(nm_abs, name)
        for (sub_nm, dep), dep_spec in npm_needs(pkg).items():
            # (resolved where the package itself would look: beside it when
            # its project is the package)
            target_nm = nm if sub_nm == 'node_modules' else os.path.normpath(os.path.join(nm, name, sub_nm))
            k = (target_nm, dep)
            if k in seen or dep == name:
                continue
            seen.add(k)
            todo.append((k, dep_spec))
        if len(seen) > 80:
            break
    return got, errors


def license_of(repo_dir, own_files):
    info = {'file': None, 'spdx': None, 'package_json': None, 'headers': {}}
    for f in sorted(os.listdir(repo_dir)):
        if re.match(r'^(LICEN[CS]E|COPYING)', f, re.I) and os.path.isfile(os.path.join(repo_dir, f)):
            info['file'] = f
            info['spdx'] = license_text_spdx(open(os.path.join(repo_dir, f), errors='replace').read(200000))
            break
    pj = os.path.join(repo_dir, 'package.json')
    if os.path.exists(pj):
        try:
            lic = json.load(open(pj)).get('license')
            info['package_json'] = lic if isinstance(lic, str) else None
        except Exception:
            pass
    info['headers_main'] = {}
    for path in own_files:
        if not path.endswith(SRC_EXT):
            continue
        k = header_license(path)
        info['headers'][k] = info['headers'].get(k, 0) + 1
        if not is_aux(os.path.relpath(path, repo_dir)):
            info['headers_main'][k] = info['headers_main'].get(k, 0) + 1
    return info


def license_text_spdx(text):
    """the license a license file's text is: its title first (the first
    lines: a GPL's text mentions the Affero and Lesser ones further down),
    then anywhere; else its SPDX identifier; else 'unrecognized'"""
    for part in (text[:600], text):
        for spdx, pat in LICENSE_TEXT_HINTS:
            if re.search(pat, part, re.I):
                return spdx
    m = re.search(r'SPDX-License-Identifier:[ \t]*([^\r\n*]+)', text)
    return m.group(1).strip() if m else 'unrecognized'


def header_license(path):
    """a source's SPDX-License-Identifier; '(none)' without one"""
    try:
        head = open(path, errors='replace').read(4000)
    except OSError:
        return '(none)'
    # (to the end of the line: "GNU AGPLv3" is one; a Vyper module says it
    # in its docstring's NatSpec, @license)
    m = re.search(r'SPDX-License-Identifier:[ \t]*([^\r\n]*)', head) or \
        (re.search(r'@license[ \t]+([^\r\n]*)', head) if path.endswith(('.vy', '.vyi')) else None)
    v = m.group(1).split('*/')[0].strip().rstrip('"\'') if m else ''
    return v or '(none)'


def is_open(spdx):
    if not spdx or re.match(r'^(UNLICEN[CS]ED|NONE|PROPRIETARY|SEE LICENSE)', spdx.strip(), re.I):
        return False  # (UNLICENSED: no license at all, not the Unlicense)
    return bool(OPEN_LICENSES.search(spdx))


AUX_DIR = re.compile(r'(^|/)(tests?|scripts?|mocks?|echidna|certora|halmos|fuzz|invariants?)(/|$)', re.I)


def is_aux(rel):
    """a test's, a script's or a mock's source, not one of the contracts"""
    return bool(AUX_DIR.search(os.path.dirname(rel))) or rel.endswith(('.t.sol', '.s.sol'))


def redistributable(lic):
    # the license file at the root is the repository's own statement: when it
    # isn't one of the open licenses (a proprietary text, "all rights
    # reserved", a licence for non-commercial use...), neither package.json's
    # field (often npm's default, ISC) nor the files' headers override it
    if lic['file'] and lic['spdx'] != PER_FILE:
        return lic['spdx'] not in (None, 'unrecognized') and is_open(lic['spdx'])
    if not lic['file'] and lic['package_json'] and lic['package_json'].upper() != 'UNLICENSED':
        return is_open(lic['package_json'])
    # no license for the repository: each file's own (per_file); worth a copy
    # when the contracts' headers (tests, scripts, mocks aside) are mostly open
    heads = lic.get('headers_main') or lic['headers']
    total = sum(heads.values())
    open_n = sum(n for k, n in heads.items() if is_open(k))
    return total > 0 and open_n >= 0.8 * total


def per_file(lic):
    """the files' own headers decide (no license for the repository, or one
    that defers to them): only the sources whose header is an open license
    are copied"""
    if lic['file']:
        return lic['spdx'] == PER_FILE
    return not (lic['package_json'] and lic['package_json'].upper() != 'UNLICENSED')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--program', required=True)
    ap.add_argument('--repo', required=True)
    ap.add_argument('--ref')
    ap.add_argument('--scope', action='append', default=[])
    ap.add_argument('--root', default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument('--work', default=None)
    ap.add_argument('--reference-only', action='store_true', help='record, never copy')
    ap.add_argument('--force-copy', action='store_true',
                    help='copy whatever the license (a local copy, tools/fetch_reference.py: never committed)')
    ap.add_argument('--note', default=None)
    a = ap.parse_args()

    m = re.match(r'https?://([^/]+)/([^/]+)/([^/]+?)(?:\.git)?/?$', a.repo)
    if not m:
        sys.exit(f'not a repository URL: {a.repo}')
    host, owner, name = m.groups()
    url = f'https://{host}/{owner}/{name}'
    prog_dir = os.path.join(a.root, 'immunefi', a.program)
    dest = os.path.join(prog_dir, f'{owner}__{name}')
    manifest_path = os.path.join(prog_dir, 'manifest.json')
    os.makedirs(prog_dir, exist_ok=True)
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {'program': a.program, 'repos': []}

    work = tempfile.mkdtemp(prefix='corpus-', dir=a.work)
    entry = {'repo': url, 'ref': a.ref, 'scope_paths': a.scope, 'fetched': datetime.date.today().isoformat()}
    if a.note:
        entry['note'] = a.note
    try:
        co = os.path.join(work, 'repo')
        entry['commit'] = clone(url, a.ref, co)
        entry['submodules'] = submodules(co)
        sold = soldeer(co)
        if sold:
            entry['soldeer'] = sold
        own = []
        subpaths = [s['path'] for s in entry['submodules']] + [x['path'] for x in entry.get('soldeer', [])]
        for path in walk_sources(co):
            rel = os.path.relpath(path, co)
            if not any(rel == s or rel.startswith(s + '/') for s in subpaths):
                own.append(path)
        lic = license_of(co, own)
        entry['license'] = lic
        entry['redistributable'] = redistributable(lic) and not a.reference_only
        langs = {}
        for path in own:
            ext = os.path.splitext(path)[1]
            if ext in SRC_EXT:
                langs[ext] = langs.get(ext, 0) + 1
        entry['languages'] = langs
        if not langs or (not entry['redistributable'] and not a.force_copy):
            entry['copied'] = False
            entry['why'] = ('no EVM source in the repository' if not langs else
                            'reference only: no license allowing redistribution found')
            # (a copy an earlier run made goes: it mustn't be committed)
            if os.path.isdir(dest):
                shutil.rmtree(dest)
        else:
            ws_links = {}
            needs = npm_needs(co, subpaths, ws_links)
            entry['npm'] = {}
            if needs:
                got, errors = install_npm(needs, os.path.join(work, 'npm'))
                entry['npm'] = got
                if errors:
                    entry['npm_errors'] = errors
            if os.path.isdir(dest):
                shutil.rmtree(dest)
            n = size = skipped = unlicensed = 0
            own_set = set(own)
            only_open = per_file(lic) and not a.force_copy
            for path in walk_sources(co):
                st = os.stat(path)
                if st.st_size > MAX_BYTES:
                    skipped += 1
                    continue
                if only_open and path in own_set and path.endswith(SRC_EXT) and not is_open(header_license(path)):
                    unlicensed += 1
                    continue
                rel = os.path.relpath(path, co)
                out = os.path.join(dest, rel)
                os.makedirs(os.path.dirname(out), exist_ok=True)
                shutil.copyfile(path, out)
                n += 1
                size += st.st_size
            for key in entry.get('npm', {}):
                top = os.path.join(work, 'npm', key)
                for path in walk_sources(top):
                    st = os.stat(path)
                    if st.st_size > MAX_BYTES:
                        skipped += 1
                        continue
                    rel = os.path.relpath(path, os.path.join(work, 'npm'))
                    out = os.path.join(dest, rel)
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    shutil.copyfile(path, out)
                    n += 1
                    size += st.st_size
            # the tree's symbolic links that stay inside it (a project's lib/
            # linked to the repository's), as they are
            links = 0
            for d, dirs, files in os.walk(co):
                dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith('.git')]
                for name in dirs + files:
                    src = os.path.join(d, name)
                    if not os.path.islink(src):
                        continue
                    target = os.readlink(src)
                    resolved = os.path.normpath(os.path.join(d, target))
                    if os.path.isabs(target) or not (resolved == co or resolved.startswith(co + os.sep)):
                        continue
                    out = os.path.join(dest, os.path.relpath(src, co))
                    if os.path.lexists(out):
                        continue
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    os.symlink(target, out)
                    links += 1
            if links:
                entry['symlinks'] = links
            # a workspace's packages, linked by name where its sources import
            # them (as pnpm / yarn / npm workspaces install them)
            for (nm, pkg), pkg_dir in sorted(ws_links.items()):
                out = os.path.join(dest, nm, pkg)
                if os.path.lexists(out):
                    continue
                os.makedirs(os.path.dirname(out), exist_ok=True)
                os.symlink(os.path.relpath(os.path.join(dest, pkg_dir), os.path.dirname(out)), out)
                entry.setdefault('workspace_links', {})[f'{nm}/{pkg}'] = pkg_dir
            if unlicensed:
                entry['skipped_unlicensed'] = unlicensed
            entry.update({'copied': True, 'dest': os.path.relpath(dest, prog_dir), 'files': n, 'bytes': size,
                          'skipped_large': skipped})
    except Exception as e:
        entry['copied'] = False
        entry['error'] = str(e)[-600:]
    finally:
        shutil.rmtree(work, ignore_errors=True)
    manifest['repos'] = [r for r in manifest['repos'] if r['repo'] != url] + [entry]
    json.dump(manifest, open(manifest_path, 'w'), indent=1)
    print(json.dumps({k: entry.get(k) for k in ('repo', 'commit', 'copied', 'files', 'bytes', 'languages', 'why', 'error')}))


if __name__ == '__main__':
    main()
