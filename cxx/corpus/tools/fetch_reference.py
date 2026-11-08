#!/usr/bin/env python3
"""Fetch the repositories the corpus records by reference only (their license
doesn't allow copying them here): each at its recorded commit, its EVM sources
and build files copied with their tree into OUT/SLUG/OWNER__NAME/, as
copy_repo.py lays out the copied ones.

    fetch_reference.py [OUT] [--program SLUG]...

OUT defaults to ./reference (not committed: .gitignore).
"""
import argparse
import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out', nargs='?', default=os.path.join(ROOT, 'reference'))
    ap.add_argument('--program', action='append', default=[])
    a = ap.parse_args()
    n = 0
    for mpath in sorted(glob.glob(os.path.join(ROOT, 'immunefi', '*', 'manifest.json'))):
        m = json.load(open(mpath))
        slug = m['program']
        if a.program and slug not in a.program:
            continue
        for r in m['repos']:
            if r.get('copied') or not r.get('commit') or 'no EVM source' in (r.get('why') or ''):
                continue
            n += 1
            cmd = [sys.executable, os.path.join(HERE, 'copy_repo.py'), '--program', slug, '--repo', r['repo'],
                   '--ref', r['commit'], '--root', a.out, '--force-copy']
            print(' '.join(cmd), flush=True)
            subprocess.run(cmd, check=False)
    print(n, 'repositories fetched into', a.out)


if __name__ == '__main__':
    main()
