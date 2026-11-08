#!/usr/bin/env python3
"""Run compare_source.py's comparison over a selection of a corpus build:
the largest own contract of each project (not lib/, node_modules/,
dependencies/), in every build of it (each compiler, EVM version, optimizer
and via-IR setting). It is resumable (a background job may be killed): it
stops after --minutes and goes on from OUT/results.jsonl when run again,
until it prints "== all done". Each artifact's result is a line of
OUT/results.jsonl, its decompiled functions OUT/texts/ARTIFACT.json, its
text and side information OUT/work/ARTIFACT/; --summary writes
OUT/summary.md from what is there.

    compare_largest.py --build BUILD --out OUT --bin DIR --sigdb DB
                       [--minutes 100] [--timeout 600] [--summary]

DIR has the release builds of pancxx, stagecheck and text_check.
"""
import argparse
import collections
import json
import os
import re
import sys
import time


def select(build):
    rows, seen = [], set()
    for line in open(os.path.join(build, 'index.jsonl')):
        r = json.loads(line)
        if r['artifact'] in seen:
            continue
        seen.add(r['artifact'])
        if re.match(r'(lib|node_modules|dependencies|\.deps)__', os.path.basename(r['artifact'])):
            continue
        rows.append(r)
    names = collections.defaultdict(dict)
    for r in rows:
        n = os.path.basename(r['artifact'])
        size = os.path.getsize(os.path.join(build, r['artifact'] + '.hex'))
        d = names[(r['program'], r['repo'], r['project'])]
        d[n] = max(d.get(n, 0), size)
    keep = {k: max(v, key=lambda n: (v[n], n)) for k, v in names.items()}
    rows = [r for r in rows if os.path.basename(r['artifact']) == keep[(r['program'], r['repo'], r['project'])]]
    rows.sort(key=lambda r: (r['program'], r['repo'], r['project'], r['build'], r['artifact']))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tools', default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument('--build', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--bin', required=True)
    ap.add_argument('--sigdb', required=True)
    ap.add_argument('--minutes', type=float, default=100)
    ap.add_argument('--timeout', type=int, default=600)
    ap.add_argument('--summary', action='store_true')
    a = ap.parse_args()
    sys.path.insert(0, a.tools)
    import compare_source as cs
    os.makedirs(os.path.join(a.out, 'texts'), exist_ok=True)
    rp = os.path.join(a.out, 'results.jsonl')
    done = set()
    if os.path.exists(rp):
        for line in open(rp):
            done.add(json.loads(line)['artifact'])
    rows = select(a.build)
    if a.summary:
        results, groups = [], collections.defaultdict(list)
        for line in open(rp):
            res = json.loads(line)
            results.append(res)
            tp = os.path.join(a.out, 'texts', res['artifact'].replace('/', '__') + '.json')
            if os.path.exists(tp):
                key = (res['program'], res['repo'], res['project'], res['source'], res['contract'],
                       res['compiler'], res.get('via_ir'))
                groups[key].append((res, json.load(open(tp))))
        cs.summary(results, cs.stability(groups), os.path.join(a.out, 'summary.md'))
        print('%d of %d artifacts -> %s' % (len(results), len(rows), os.path.join(a.out, 'summary.md')))
        return
    os.nice(19)
    args = argparse.Namespace(build=a.build, pancxx=os.path.join(a.bin, 'pancxx'),
                              stagecheck=os.path.join(a.bin, 'stagecheck'),
                              text_check=os.path.join(a.bin, 'text_check'), sigdb=a.sigdb, blind=False,
                              no_exec=False, timeout=a.timeout, out=a.out)
    todo = [r for r in rows if r['artifact'] not in done]
    print('%d artifacts, %d to do' % (len(rows), len(todo)), flush=True)
    t0, cache = time.time(), {}
    with open(rp, 'a') as fh:
        for r in todo:
            if time.time() - t0 > a.minutes * 60:
                print('== stopped (--minutes %g): run again to go on' % a.minutes, flush=True)
                return
            t = time.time()
            try:
                res, funcs = cs.one(args, r, cache)
            except Exception as e:
                res, funcs = dict(r, error='driver: %s' % str(e)[-300:]), None
            res['seconds'] = round(time.time() - t, 1)
            if funcs is not None:
                json.dump(funcs, open(os.path.join(a.out, 'texts', r['artifact'].replace('/', '__') + '.json'), 'w'))
            fh.write(json.dumps(res) + '\n')
            fh.flush()
            sc, tc = res.get('stagecheck') or {}, res.get('text_check') or {}
            tcd = {w: (v.get('different'), v.get('unparsed')) for w, v in tc.items() if isinstance(v, dict)}
            print('%s %.0fs %s sc diff %s bugs %s%s tc %s%s' % (
                r['artifact'], res['seconds'], res.get('error', ''), sc.get('different'), sc.get('bugs'),
                (' ERR ' + sc['error']) if 'error' in sc else '', tcd, (' ERR ' + tc['error']) if 'error' in tc else ''),
                flush=True)
    print('== all done', flush=True)


if __name__ == '__main__':
    main()
