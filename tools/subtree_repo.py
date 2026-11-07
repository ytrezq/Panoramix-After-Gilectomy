#!/usr/bin/env python3
"""Add a GitHub repository to the corpus with git subtree, at
immunefi/SLUG/OWNER__REPO: the whole repository at its commit (git subtree
add --squash: one commit of its tree, its history left out), then each of
its submodules - recursively, those on GitHub - as a subtree at its own path
and commit in place of the submodule's link; then, as copy_repo.py does, the
npm packages its sources import (files, a commit of their own: they aren't
git repositories). The program's manifest.json gets the subtrees.

    subtree_repo.py --program SLUG --repo https://github.com/OWNER/REPO [--commit SHA] [--root DIR]

The corpus' work tree must be clean; every step is a commit (git subtree's
own two per subtree), so `git subtree pull --prefix=...` updates them later.
Nothing of the repository is run.
"""
import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('copy_repo', os.path.join(HERE, 'copy_repo.py'))
cr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cr)

IDENT = ['-c', 'user.name=Claude', '-c', 'user.email=noreply@anthropic.com']
TRAILER = ('\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n'
           'Claude-Session: https://claude.ai/code/session_011zM71XfnxEKjjJuZ81vSba\n')
GITHUB = re.compile(r'^(?:https?://(?:www\.)?github\.com/|git@github\.com:|git://github\.com/)([^/]+)/(.+?)(?:\.git)?/?$')


def git(root, *args, check=True, timeout=3600):
    p = subprocess.run(['git', '-C', root] + IDENT + list(args), capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError('git %s: %s' % (' '.join(args[:3]), (p.stderr or p.stdout).strip()[-600:]))
    return p.stdout


def github_url(url):
    m = GITHUB.match(url.strip())
    return 'https://github.com/%s/%s' % (m.group(1), m.group(2)) if m else None


def gitlinks(root, prefix):
    """the submodule links (mode 160000) below prefix in HEAD: {path: commit}"""
    out = {}
    for rec in git(root, 'ls-tree', '-r', '-z', 'HEAD', '--', prefix + '/').split('\0'):
        if rec.startswith('160000 commit '):
            meta, path = rec.split('\t', 1)
            out[path] = meta.split()[2]
    return out


def module_urls(root, repo_dir):
    """{path relative to repo_dir: url} of repo_dir/.gitmodules"""
    gm = os.path.join(root, repo_dir, '.gitmodules')
    if not os.path.exists(gm):
        return {}
    p = subprocess.run(['git', 'config', '-f', gm, '--get-regexp', r'^submodule\..*\.(path|url)$'],
                       capture_output=True, text=True)
    mods = {}
    for line in p.stdout.splitlines():
        key, _, val = line.partition(' ')
        m = re.match(r'submodule\.(.*)\.(path|url)$', key)
        if m:
            mods.setdefault(m.group(1), {})[m.group(2)] = val.strip()
    return {os.path.normpath(m['path']): m['url'] for m in mods.values() if m.get('path') and m.get('url')}


def resolve(url, parent):
    if url.startswith(('../', './')):
        return re.sub(r'(?<!:)//+', '/', os.path.normpath(os.path.join(parent.rstrip('/'), url))).replace(':/', '://', 1)
    return url


def subtree_add(root, prefix, url, commit, what):
    git(root, 'subtree', 'add', '--prefix=' + prefix, url, commit, '--squash',
        '-m', 'corpus: %s at %s, as a subtree (%s)%s' % (url.split('github.com/')[-1], commit[:12], what, TRAILER),
        timeout=7200)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--program', required=True)
    ap.add_argument('--repo', required=True)
    ap.add_argument('--commit')
    ap.add_argument('--root', default=os.path.dirname(HERE))
    ap.add_argument('--why', default='its license does not allow redistribution: added as git subtrees at the '
                                       "user's request, its license files kept in the tree")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    url = github_url(a.repo)
    if not url:
        sys.exit('not a GitHub repository: ' + a.repo)
    owner, name = url.split('/')[-2:]
    prog_dir = os.path.join('immunefi', a.program)
    mp = os.path.join(root, prog_dir, 'manifest.json')
    manifest = json.load(open(mp))
    entry = next((r for r in manifest['repos'] if github_url(r['repo']) == url), None)
    commit = a.commit or (entry or {}).get('commit')
    if not commit:
        sys.exit('no commit for %s (--commit)' % url)
    if git(root, 'status', '--porcelain').strip():
        sys.exit('the work tree is not clean')
    prefix = os.path.join(prog_dir, '%s__%s' % (owner, name))
    if os.path.lexists(os.path.join(root, prefix)):
        sys.exit(prefix + ' exists')

    subtree_add(root, prefix, url, commit, 'its license kept')
    subtrees = [{'prefix': os.path.relpath(prefix, prog_dir), 'url': url, 'commit': commit}]
    roots = {prefix: url}
    kept, done = [], set()
    # the submodules, level by level: a link replaced by the subtree of its
    # commit when its repository is on GitHub
    for _ in range(12):
        todo = []
        for path, sha in sorted(gitlinks(root, prefix).items()):
            if path in done:
                continue
            done.add(path)
            owner_dir = max((r for r in roots if path.startswith(r + '/')), key=len)
            sub_url = module_urls(root, owner_dir).get(os.path.relpath(path, owner_dir))
            gh = github_url(resolve(sub_url, roots[owner_dir])) if sub_url else None
            if gh:
                todo.append((path, gh, sha))
            else:
                kept.append({'path': os.path.relpath(path, prog_dir), 'url': sub_url, 'commit': sha})
        if not todo:
            break
        for path, gh, sha in todo:
            git(root, 'rm', '-q', '--cached', path)
            full = os.path.join(root, path)
            if os.path.isdir(full) and not os.listdir(full):
                os.rmdir(full)
        git(root, 'commit', '-q', '-m', 'corpus: %s - the submodule links below %s, to be subtrees%s' % (
            name, os.path.relpath(prefix, prog_dir), TRAILER))
        for path, gh, sha in todo:
            subtree_add(root, path, gh, sha, 'a submodule of %s/%s' % (owner, name))
            roots[path] = gh
            subtrees.append({'prefix': os.path.relpath(path, prog_dir), 'url': gh, 'commit': sha})

    # the npm packages its sources import (files), where a build finds them
    dest = os.path.join(root, prefix)
    skip = [os.path.relpath(r, prefix) for r in roots if r != prefix]
    links = {}
    needs = cr.npm_needs(dest, skip, links)
    got, errors = {}, {}
    if needs or links:
        work = tempfile.mkdtemp(prefix='subtree-npm-')
        try:
            if needs:
                got, errors = cr.install_npm(needs, work)
            added = []
            for key in got:
                for path in cr.walk_sources(os.path.join(work, key)):
                    if os.path.getsize(path) > cr.MAX_BYTES:
                        continue
                    out = os.path.join(dest, os.path.relpath(path, work))
                    if os.path.exists(out):
                        continue
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    shutil.copyfile(path, out)
                    added.append(out)
            for (nm, pkg), pkg_dir in sorted(links.items()):
                out = os.path.join(dest, nm, pkg)
                if not os.path.lexists(out):
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    os.symlink(os.path.relpath(os.path.join(dest, pkg_dir), os.path.dirname(out)), out)
                    added.append(out)
            if added:
                # (-f: the repository's own .gitignore names node_modules/)
                for i in range(0, len(added), 500):
                    git(root, 'add', '-f', '--', *added[i:i + 500])
                git(root, 'commit', '-q', '-m', 'corpus: %s/%s - the npm packages its sources import%s' % (
                    owner, name, TRAILER))
        finally:
            shutil.rmtree(work, ignore_errors=True)

    n = len(git(root, 'ls-files', '--', prefix).splitlines())
    new = dict(entry or {'repo': url, 'commit': commit})
    new.update({'copied': True, 'via': 'git subtree', 'dest': os.path.relpath(prefix, prog_dir), 'files': n,
                'subtrees': subtrees, 'npm': got, 'why': a.why})
    if kept:
        new['links_kept'] = kept
    if errors:
        new['npm_errors'] = errors
    else:
        new.pop('npm_errors', None)
    manifest['repos'] = [r for r in manifest['repos'] if github_url(r['repo']) != url] + [new]
    json.dump(manifest, open(mp, 'w'), indent=1)
    git(root, 'add', '--', os.path.relpath(mp, root))
    git(root, 'commit', '-q', '-m', 'corpus: %s - %s/%s in the manifest, as git subtrees%s' % (
        a.program, owner, name, TRAILER))
    print(json.dumps({'repo': url, 'commit': commit, 'subtrees': len(subtrees), 'links_kept': len(kept),
                      'files': n, 'npm': len(got), 'npm_errors': len(errors)}))


if __name__ == '__main__':
    main()
