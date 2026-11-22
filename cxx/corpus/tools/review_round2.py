#!/usr/bin/env python3
"""A differential round of the manual review put together.

    review_round2.py --contracts contracts.jsonl --results DIR --out OUT [--tranche N] [--notes NOTES.md]

DIR holds the reviewers' ID.json files (review/r2/INSTRUCTIONS.md's schema;
a contract round 1 hadn't reviewed has round 1's schema with "round1": true).
OUT gets summary.md (the round-1 findings' statuses, the regressions by kind
and severity, every medium or high one, the new findings) and
regressions.jsonl / new_findings.jsonl (one finding a line, with its id and
artifact). NOTES.md, if given, is put after the totals (the causes, read
from the reports).
"""
import argparse
import collections
import json
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--contracts', required=True)
    ap.add_argument('--results', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--tranche', type=int, default=0)
    ap.add_argument('--notes', default='')
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.contracts)]
    rows = [r for r in rows if not a.tranche or r['tranche'] == a.tranche]
    art = {r['id']: r['artifact'] for r in rows}
    res, missing = {}, []
    for r in rows:
        p = os.path.join(a.results, r['id'] + '.json')
        if os.path.exists(p):
            res[r['id']] = json.load(open(p))
        else:
            missing.append(r['id'])
    status, regs, kinds, newk = collections.Counter(), [], collections.Counter(), collections.Counter()
    news, full, changed, with_reg = [], 0, 0, 0
    lines_old = lines_new = 0
    for i, r in sorted(res.items()):
        if r.get('round1'):
            full += 1
            for f in r.get('findings') or []:
                news.append(dict(f, id=i, artifact=art[i], round1=True))
                newk[(f.get('kind', '?'), f.get('severity', '?'))] += 1
            continue
        changed += bool(r.get('text_changed'))
        if isinstance(r.get('lines_old'), int) and isinstance(r.get('lines_new'), int):
            lines_old += r['lines_old']
            lines_new += r['lines_new']
        for o in r.get('old_findings') or []:
            status[o.get('status', '?')] += 1
        if r.get('regressions'):
            with_reg += 1
        for g in r.get('regressions') or []:
            regs.append(dict(g, id=i, artifact=art[i]))
            kinds[(g.get('kind', '?'), g.get('severity', '?'))] += 1
        for f in r.get('new_findings') or []:
            news.append(dict(f, id=i, artifact=art[i]))
            newk[(f.get('kind', '?'), f.get('severity', '?'))] += 1
    os.makedirs(a.out, exist_ok=True)
    for name, xs in (('regressions.jsonl', regs), ('new_findings.jsonl', news)):
        with open(os.path.join(a.out, name), 'w') as f:
            for x in xs:
                f.write(json.dumps(x) + '\n')
    sev = ['high', 'medium', 'low']

    def table(c):
        ks = sorted({k for k, _ in c})
        t = ['| kind | ' + ' | '.join(sev) + ' |', '|---|' + '---|' * len(sev)]
        return t + ['| %s | %s |' % (k, ' | '.join(str(c[(k, s)]) for s in sev)) for k in ks]

    out = ['# The manual review, round 2%s' % (' - tranche %d' % a.tranche if a.tranche else ''), '',
           'Contracts: %d of %d have a result%s.' % (len(res), len(rows),
                                                     ' (missing: %s)' % ', '.join(missing) if missing else ''),
           'Reviewed whole (round 1 hadn\'t): %d. Reviewed by their diff: %d, of which %d texts changed '
           '(%d lines before, %d after, for the texts whose counts were given).' % (
               full, len(res) - full, changed, lines_old, lines_new),
           '', '## Round 1\'s findings', '',
           ', '.join('%s %d' % kv for kv in sorted(status.items(), key=lambda kv: -kv[1])) + '.',
           '', '## Regressions', '',
           '%d regressions in %d contracts.' % (len(regs), with_reg), ''] + table(kinds)
    if a.notes:
        out += ['', open(a.notes).read().rstrip()]
    out += ['', '## The high and medium regressions', '']
    for g in regs:
        if g.get('severity') in ('high', 'medium'):
            out.append('- **%s** `%s` %s, %s (%s): %s' % (
                g['id'], g.get('function', '')[:80], g.get('kind', ''), g.get('severity', ''),
                g['artifact'].split('/')[-1], g.get('issue', '')))
    out += ['', '## New findings', ''] + table(newk) + ['']
    for f in news:
        if f.get('severity') in ('high',) or f.get('kind') == 'semantics':
            out.append('- **%s** `%s` %s, %s: %s *Verified:* %s' % (
                f['id'], f.get('function', '')[:80], f.get('kind', ''), f.get('severity', ''),
                f.get('issue', ''), f.get('verified', '')))
    open(os.path.join(a.out, 'summary.md'), 'w').write('\n'.join(out) + '\n')
    print('\n'.join(out[:16]))


if __name__ == '__main__':
    main()
