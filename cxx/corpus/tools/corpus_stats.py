#!/usr/bin/env python3
"""The corpus' status from its manifests: immunefi/STATUS.md.

    corpus_stats.py [--root DIR]

Per program: the repositories found, copied, recorded by reference only
(their license doesn't allow a copy) and failed; their languages, files and
bytes; then the totals.
"""
import argparse
import collections
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=ROOT)
    a = ap.parse_args()
    programs = {p['slug']: p for p in json.load(open(os.path.join(a.root, 'immunefi', 'programs.json')))}
    # (the programs looked at as EVM ones: those assigned to a search, the
    # scrape's flag checked by hand; the others are listed in not_evm.txt)
    ne = os.path.join(a.root, 'immunefi', 'assign', 'not_evm.txt')
    not_evm = {l.split()[0] for l in open(ne) if l.strip()} if os.path.exists(ne) else \
        {s for s, p in programs.items() if not p.get('evm')}
    rows, tot = [], collections.Counter()
    langs = collections.Counter()
    licenses = collections.Counter()
    for slug in sorted(programs):
        p = programs[slug]
        mp = os.path.join(a.root, 'immunefi', slug, 'manifest.json')
        if slug in not_evm:
            tot['not_evm'] += 1
            continue
        if not os.path.exists(mp):
            notes = os.path.join(a.root, 'immunefi', slug, 'notes.md')
            if os.path.exists(notes):
                # (searched: no repository to copy - not EVM after all, or
                # nothing public; notes.md says which)
                rows.append((slug, p.get('project', slug), 0, 0, 0, 0, 0, 'nothing copied: see notes.md'))
                tot['programs_searched_empty'] += 1
            else:
                rows.append((slug, p.get('project', slug), 0, 0, 0, 0, 0, 'not searched yet'))
                tot['programs_pending'] += 1
            continue
        m = json.load(open(mp))
        c = collections.Counter()
        for r in m.get('repos', []):
            c['repos'] += 1
            if r.get('copied'):
                c['copied'] += 1
                c['files'] += r.get('files', 0)
                c['bytes'] += r.get('bytes', 0)
                for ext, n in (r.get('languages') or {}).items():
                    langs[ext] += n
            elif r.get('error'):
                c['failed'] += 1
            elif 'reference only' in (r.get('why') or ''):
                c['reference'] += 1
            else:
                c['other'] += 1
            lic = r.get('license') or {}
            licenses[lic.get('spdx') or lic.get('package_json') or 'headers'] += 1
        note = '' if c['repos'] else (m.get('note') or 'no public repository found')
        rows.append((slug, p.get('project', slug), c['repos'], c['copied'], c['reference'], c['failed'],
                     c['bytes'], note))
        tot.update(c)
        tot['programs'] += 1
    L = ['# Corpus status', '',
         '%d programs with repositories, %d searched without one to copy (not EVM after all, or no public '
         'source: their notes.md), %d not searched yet, %d not EVM; %d repositories: %d copied (%d files, %.1f MB '
         'of sources), %d by reference only, %d failed.' % (
             tot['programs'], tot['programs_searched_empty'], tot['programs_pending'], tot['not_evm'], tot['repos'],
             tot['copied'], tot['files'], tot['bytes'] / 1e6, tot['reference'], tot['failed']), '',
         'Languages of the copied repositories\' own sources: ' + ', '.join(
             '%s %d' % kv for kv in langs.most_common()) + '.', '',
         '| program | project | repositories | copied | reference only | failed | MB | note |',
         '|---|---|---|---|---|---|---|---|']
    for slug, name, n, cp, ref, fail, size, note in rows:
        L.append('| [%s](%s/) | %s | %d | %d | %d | %d | %.1f | %s |' % (slug, slug, name, n, cp, ref, fail, size / 1e6,
                                                                         note))
    open(os.path.join(a.root, 'immunefi', 'STATUS.md'), 'w').write('\n'.join(L) + '\n')
    print(L[2])


if __name__ == '__main__':
    main()
