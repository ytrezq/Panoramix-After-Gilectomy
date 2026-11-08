#!/usr/bin/env python3
"""The corpus' repositories as git subtrees of their EVM sources: for each
repository a program's manifest names (and each of its submodules and
Soldeer dependencies from git, at their pinned commits), the commit is
fetched shallowly into a scratch repository, its tree filtered without a
checkout - kept: the EVM sources, the build configurations, the license
files, the symbolic links; gone: the documentation, the server-side code,
the JavaScript and TypeScript, the tests' data, the submodule links (each
submodule is a subtree of its own) - and the filtered commit added with
`git subtree add --squash` at cxx/corpus/immunefi/SLUG/OWNER__REPO[/PATH].
The npm packages and the Soldeer zips (not git repositories) are copied
as files from an earlier copy (--from). The program's manifest says what
was added, from where.

    subtree_corpus.py --from OLD_CORPUS [--program SLUG]... [--jobs N] [--limit N]

Run in the branch's work tree, clean; resumable (a prefix already in HEAD
is skipped). Nothing of the repositories is run.
"""
import argparse
import concurrent.futures
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.dirname(HERE)                      # cxx/corpus
TOP = subprocess.run(['git', '-C', CORPUS, 'rev-parse', '--show-toplevel'], capture_output=True, text=True,
                     check=True).stdout.strip()
IDENT = ['-c', 'user.name=Claude', '-c', 'user.email=noreply@anthropic.com']
TRAILER = ('\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n'
           'Claude-Session: https://claude.ai/code/session_011zM71XfnxEKjjJuZ81vSba\n')

SRC_EXT = ('.sol', '.vy', '.vyi', '.yul', '.huff', '.fe', '.lll', '.se')
BUILD_FILES = {'foundry.toml', 'remappings.txt', 'package.json', '.gitmodules', 'Makefile', 'makefile',
               'foundry.lock', 'soldeer.lock', 'brownie-config.yaml', 'brownie-config.yml', 'ape-config.yaml',
               'ape-config.yml', 'truffle-config.js', 'truffle.js', 'dappfile', '.dapprc', 'vyper.toml',
               'pyproject.toml', 'hardhat.config.js', 'hardhat.config.ts', 'hardhat.config.cjs',
               'hardhat.config.mjs', 'pnpm-workspace.yaml', 'lerna.json', 'huff.toml', 'fe.toml'}
LICENSE_RE = re.compile(r'^(LICEN[CS]E|COPYING|NOTICE|UNLICENSE)([._-].*)?$', re.I)
MAX_BYTES = 2 * 1024 * 1024
FILTER = ('EVM sources (%s), build files, license files and symbolic links; the rest (documentation, '
          'server-side code, JavaScript / TypeScript, data, submodule links) left out' % ' '.join(SRC_EXT))


def run(args, cwd=None, check=True, timeout=3600, env=None, input=None):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env, input=input)
    if check and p.returncode != 0:
        raise RuntimeError('%s: %s' % (' '.join(args[:4]), (p.stderr or p.stdout).strip()[-600:]))
    return p.stdout


def git(*args, **kw):
    return run(['git', '-C', TOP] + IDENT + list(args), **kw)


def keep(path, mode, size):
    if mode == '120000':                     # a link (a project's lib/ pointing at the repository's)
        return True
    if mode not in ('100644', '100755'):     # submodule links: subtrees of their own
        return False
    name = path.rsplit('/', 1)[-1]
    if name.endswith(SRC_EXT):
        return size <= MAX_BYTES
    return name in BUILD_FILES or bool(LICENSE_RE.match(name)) or '/LICENSES/' in '/' + path


def github(url):
    m = re.match(r'^(?:https?://(?:www\.)?github\.com/|git@github\.com:|git://github\.com/)([^/]+)/(.+?)(?:\.git)?/?$',
                 url.strip())
    return 'https://github.com/%s/%s' % (m.group(1), m.group(2)) if m else None


class Prepared:
    def __init__(self, prefix, url, commit, scratch=None, filtered=None, files=0, error=None):
        self.prefix, self.url, self.commit = prefix, url, commit
        self.scratch, self.filtered, self.files, self.error = scratch, filtered, files, error


def prepare(prefix, url, commit, scratch_root):
    """url's commit fetched shallowly, filtered into a parentless commit of
    a scratch repository"""
    scratch = tempfile.mkdtemp(prefix='st-', dir=scratch_root)
    try:
        run(['git', 'init', '-q', '--bare', scratch])
        u = github(url) or url
        run(['git', '-C', scratch, 'fetch', '-q', '--depth', '1', u, commit], check=False, timeout=3600)
        rev = run(['git', '-C', scratch, 'rev-parse', '--verify', '-q', commit + '^{commit}'], check=False).strip()
        if not rev:
            # (a server that won't hand out a commit by its id: the history, then the commit)
            run(['git', '-C', scratch, 'fetch', '-q', '--filter=blob:none', u, '+refs/heads/*:refs/remotes/o/*',
                 '+refs/tags/*:refs/tags/*'], timeout=3600)
            rev = run(['git', '-C', scratch, 'rev-parse', '--verify', commit + '^{commit}']).strip()
        entries = []
        for rec in run(['git', '-C', scratch, 'ls-tree', '-r', '-l', '-z', '--full-tree', rev]).split('\0'):
            if not rec:
                continue
            meta, path = rec.split('\t', 1)
            mode, typ, sha, size = meta.split()
            size = int(size) if size.isdigit() else 0
            if keep(path, mode, size):
                entries.append('%s %s\t%s' % (mode, sha, path))
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(scratch, 'filter.index'))
        run(['git', '-C', scratch, 'update-index', '--index-info'], env=env, input='\n'.join(entries) + '\n')
        tree = run(['git', '-C', scratch, 'write-tree'], env=env).strip()
        msg = 'the EVM sources and build files of %s at %s\n\nfilter: %s\n' % (u, rev, FILTER)
        # (dated as the commit it filters: the same repository and commit
        # give the same filtered commit, wherever and whenever)
        date = run(['git', '-C', scratch, 'log', '-1', '--format=%cI', rev]).strip()
        denv = dict(os.environ, GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
        filtered = run(['git', '-C', scratch] + IDENT + ['commit-tree', tree, '-m', msg], env=denv).strip()
        return Prepared(prefix, u, rev, scratch, filtered, len(entries))
    except Exception as e:
        shutil.rmtree(scratch, ignore_errors=True)
        return Prepared(prefix, url, commit, error=str(e)[-500:])


def in_head(prefix):
    return bool(git('ls-tree', '--name-only', 'HEAD', '--', prefix, check=False).strip())


CACHE = {}   # (url, commit) -> the filtered commit, in the branch's repository (refs/corpus/filtered/*)


def integrate(p, what):
    """git subtree add of the filtered commit at its prefix (from its scratch
    repository, or the repository's own copy of it)"""
    try:
        if p.files == 0:
            return 'nothing kept'
        msg = 'corpus: %s at %s, its EVM sources (%s)%s' % (p.url.split('github.com/')[-1], p.commit[:12], what,
                                                             TRAILER)
        if p.scratch:
            git('subtree', 'add', '--prefix=' + p.prefix, p.scratch, p.filtered, '--squash', '-m', msg, timeout=7200)
            # (kept, for the same repository and commit elsewhere: no fetch again)
            git('update-ref', 'refs/corpus/filtered/' + p.filtered, p.filtered)
        else:
            git('subtree', 'add', '--prefix=' + p.prefix, p.filtered, '--squash', '-m', msg, timeout=7200)
        CACHE[(p.url, p.commit)] = (p.filtered, p.files)
        return None
    finally:
        if p.scratch:
            shutil.rmtree(p.scratch, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--from', dest='old', required=True, help='the earlier corpus (its immunefi/: manifests, copies)')
    ap.add_argument('--program', action='append', default=[])
    ap.add_argument('--jobs', type=int, default=4)
    ap.add_argument('--limit', type=int, default=0, help='programs at most')
    ap.add_argument('--scratch', default=None)
    a = ap.parse_args()
    if git('status', '--porcelain', '--untracked-files=no').strip():
        sys.exit('the work tree is not clean')
    scratch_root = a.scratch or tempfile.mkdtemp(prefix='subtree-corpus-')
    os.makedirs(scratch_root, exist_ok=True)
    manifests = sorted(glob.glob(os.path.join(a.old, 'immunefi', '*', 'manifest.json')))
    if a.program:
        manifests = [m for m in manifests if os.path.basename(os.path.dirname(m)) in a.program]
    if a.limit:
        manifests = manifests[:a.limit]
    cache_file = os.path.join(scratch_root, 'filtered.json')
    if os.path.exists(cache_file):
        for k, v in json.load(open(cache_file)).items():
            url, commit = k.split(' ')
            if subprocess.run(['git', '-C', TOP, 'cat-file', '-e', v[0] + '^{commit}']).returncode == 0:
                CACHE[(url, commit)] = tuple(v)
    t0 = time.time()
    for mp in manifests:
        slug = os.path.basename(os.path.dirname(mp))
        old = json.load(open(mp))
        prog = os.path.join('cxx', 'corpus', 'immunefi', slug)
        jobs = []      # (prefix, url, commit, what, repo entry)
        for r in old['repos']:
            if not r.get('commit') or (not r.get('copied') and not r.get('subtrees')):
                continue
            url = github(r['repo']) or r['repo']
            owner, name = url.rstrip('/').split('/')[-2:]
            base = os.path.join(prog, '%s__%s' % (owner, name))
            jobs.append((base, url, r['commit'], 'the repository', r))
            subs = r.get('submodules') or []
            for s in sorted(subs, key=lambda s: s['path'].count('/')):
                if s.get('url') and s.get('commit'):
                    jobs.append((os.path.join(base, s['path']), s['url'], s['commit'],
                                 'a submodule of %s/%s' % (owner, name), r))
            for s in r.get('soldeer') or []:
                if s.get('url') and s.get('rev') and not s.get('error'):
                    jobs.append((os.path.join(base, s['path']), s['url'], s['rev'],
                                 'a Soldeer dependency of %s/%s' % (owner, name), r))
                    for ss in s.get('submodules') or []:
                        if ss.get('url') and ss.get('commit'):
                            jobs.append((os.path.join(base, ss['path']), ss['url'], ss['commit'],
                                         'a submodule of a Soldeer dependency of %s/%s' % (owner, name), r))
        todo = [j for j in jobs if not in_head(j[0])]
        results = {}
        key = lambda j: (github(j[1]) or j[1], j[2])
        with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
            futs, seen = {}, set()
            for j in todo:
                k = key(j)
                if k in CACHE or k in seen:
                    continue
                seen.add(k)
                futs[k] = ex.submit(prepare, j[0], j[1], j[2], scratch_root)
            for j in todo:                       # (in order: a repository before its submodules)
                k = key(j)
                if k in CACHE:
                    f, n = CACHE[k]
                    p = Prepared(j[0], k[0], k[1], None, f, n)
                else:
                    p = futs.pop(k).result()
                    p.prefix = j[0]
                err = p.error or integrate(p, j[3])
                results[j[0]] = (p, err)
                print('%s %s %s' % (j[0], p.files, err or 'ok'), flush=True)
        json.dump({'%s %s' % k: list(v) for k, v in CACHE.items()}, open(cache_file, 'w'))
        # the files that aren't git repositories (npm packages, Soldeer zips,
        # a workspace's links), from the earlier copy, and the manifest
        added = []
        new_repos = []
        for r in old['repos']:
            if not r.get('commit') or (not r.get('copied') and not r.get('subtrees')):
                new_repos.append(r)
                continue
            url = github(r['repo']) or r['repo']
            owner, name = url.rstrip('/').split('/')[-2:]
            base = os.path.join(prog, '%s__%s' % (owner, name))
            src = os.path.join(a.old, 'immunefi', slug, r.get('dest') or '%s__%s' % (owner, name))
            extra = [k for k in (r.get('npm') or {})] + \
                    [s['path'] for s in (r.get('soldeer') or []) if s.get('zip') and not s.get('error')]
            for key in extra:
                top = os.path.join(src, key)
                for d, dirs, files in os.walk(top):
                    for f in files:
                        sp = os.path.join(d, f)
                        rel = os.path.relpath(sp, src)
                        if not (f.endswith(SRC_EXT) or f in BUILD_FILES or LICENSE_RE.match(f)):
                            continue
                        dp = os.path.join(TOP, base, rel)
                        if os.path.lexists(dp):
                            continue
                        os.makedirs(os.path.dirname(dp), exist_ok=True)
                        shutil.copyfile(sp, dp)
                        added.append(dp)
            for key, pkg_dir in (r.get('workspace_links') or {}).items():
                dp = os.path.join(TOP, base, key)
                if not os.path.lexists(dp):
                    os.makedirs(os.path.dirname(dp), exist_ok=True)
                    os.symlink(os.path.relpath(os.path.join(TOP, base, pkg_dir), os.path.dirname(dp)), dp)
                    added.append(dp)
            subtrees, failed = [], []
            for j in jobs:
                if j[4] is not r:
                    continue
                p, err = results.get(j[0], (None, None))
                if err and err != 'nothing kept':
                    # (not fetched: its files from the earlier copy, as files)
                    top = os.path.join(src, os.path.relpath(j[0], base))
                    for d, dirs, files in os.walk(top):
                        for f in files:
                            sp = os.path.join(d, f)
                            dp = os.path.join(TOP, base, os.path.relpath(sp, src))
                            if not os.path.lexists(dp) and (f.endswith(SRC_EXT) or f in BUILD_FILES or
                                                            LICENSE_RE.match(f)):
                                os.makedirs(os.path.dirname(dp), exist_ok=True)
                                shutil.copyfile(sp, dp)
                                added.append(dp)
                entry = {'prefix': os.path.relpath(j[0], prog), 'url': github(j[1]) or j[1], 'commit': j[2]}
                if p is not None and p.files:
                    entry['files'] = p.files
                if err and err != 'nothing kept':
                    entry['error'] = err
                    failed.append(entry)
                else:
                    subtrees.append(entry)
            n = r.copy()
            for k in ('dest', 'bytes', 'skipped_large', 'skipped_unlicensed', 'symlinks', 'why'):
                n.pop(k, None)
            n.update({'via': 'git subtree', 'filter': FILTER, 'dest': '%s__%s' % (owner, name),
                      'subtrees': subtrees})
            if failed:
                n['subtrees_failed'] = failed
            if not r.get('redistributable', True) or r.get('why'):
                n['license_note'] = ('its license does not allow redistribution: added at the owner\'s request, '
                                     'its license files kept')
            new_repos.append(n)
        for i in range(0, len(added), 500):
            git('add', '-f', '--', *[os.path.relpath(x, TOP) for x in added[i:i + 500]])
        man = dict(old, repos=new_repos)
        os.makedirs(os.path.join(TOP, prog), exist_ok=True)
        json.dump(man, open(os.path.join(TOP, prog, 'manifest.json'), 'w'), indent=1)
        git('add', '--', os.path.join(prog, 'manifest.json'))
        if git('diff', '--cached', '--name-only').strip():
            git('commit', '-q', '-m', 'corpus: %s - its manifest%s%s' % (
                slug, ', the npm packages and Soldeer zips its sources import' if added else '', TRAILER))
        print('== %s done (%.0f s)' % (slug, time.time() - t0), flush=True)
    shutil.rmtree(scratch_root, ignore_errors=True)


if __name__ == '__main__':
    main()
