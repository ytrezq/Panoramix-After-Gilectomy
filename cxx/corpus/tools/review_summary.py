#!/usr/bin/env python3
"""The manual review's results put together.

    review_summary.py --contracts contracts.jsonl --results DIR --out OUT [--tranche N]

DIR holds the reviewers' ID.json files (INSTRUCTIONS.md's schema). OUT gets
summary.md (the totals, the findings by kind and severity, every high one)
and findings.jsonl (every finding, with its contract's id and artifact).
"""
import argparse
import collections
import glob
import json
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--contracts', required=True)
    ap.add_argument('--results', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--tranche', type=int, default=0)
    a = ap.parse_args()
    rows = {}
    for line in open(a.contracts):
        r = json.loads(line)
        if not a.tranche or r['tranche'] == a.tranche:
            rows[r['id']] = r
    res, bad = {}, []
    for p in sorted(glob.glob(os.path.join(a.results, 'c*.json'))):
        i = os.path.basename(p)[:-5]
        try:
            res[i] = json.load(open(p))
        except Exception as e:
            bad.append((i, repr(e)))
    os.makedirs(a.out, exist_ok=True)
    tot = collections.Counter()
    loops = collections.Counter()
    kinds = collections.Counter()
    flat = []
    for i, r in sorted(res.items()):
        tot['contracts'] += 1
        for k in ('abi_functions', 'reviewed', 'source_loops', 'spurious_while'):
            v = r.get(k)
            tot[k] += v if isinstance(v, int) else 0
        for k, v in (r.get('loops_shown') or {}).items():
            loops[k] += v if isinstance(v, int) else 0
        for f in r.get('findings') or []:
            kinds[(f.get('kind', '?'), f.get('severity', '?'))] += 1
            flat.append(dict(f, id=i, artifact=rows.get(i, {}).get('artifact', '')))
    with open(os.path.join(a.out, 'findings.jsonl'), 'w') as f:
        for x in flat:
            f.write(json.dumps(x) + '\n')
    sev = ['high', 'medium', 'low']
    ks = sorted({k for k, _ in kinds})
    out = ['# The manual review%s' % (' - tranche %d' % a.tranche if a.tranche else ''), '',
           'Contracts reviewed: %d of %d.%s' % (tot['contracts'], len(rows),
                                                ' Unreadable results: %s.' % ', '.join(b[0] for b in bad) if bad
                                                else ''),
           'ABI functions: %d, reviewed: %d.' % (tot['abi_functions'], tot['reviewed']),
           'Source loops: %d; shown as %s; spurious `while`: %d.' % (
               tot['source_loops'], ', '.join('%s %d' % kv for kv in sorted(loops.items())), tot['spurious_while']),
           '', '| kind | ' + ' | '.join(sev) + ' |', '|---|' + '---|' * len(sev)]
    for k in ks:
        out.append('| %s | %s |' % (k, ' | '.join(str(kinds[(k, s)]) for s in sev)))
    out += ['', '## The high findings', '']
    for x in flat:
        if x.get('severity') == 'high':
            out.append('- **%s** `%s` %s (%s): %s *Rule:* %s *Verified:* %s' % (
                x['id'], x.get('function', ''), x.get('kind', ''), x['artifact'].split('/')[-1],
                x.get('issue', ''), x.get('rule', ''), x.get('verified', '')))
    open(os.path.join(a.out, 'summary.md'), 'w').write('\n'.join(out) + '\n')
    print('\n'.join(out[:12]))


if __name__ == '__main__':
    main()
