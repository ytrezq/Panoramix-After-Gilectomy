#!/usr/bin/env python3
"""The contracts of the manual review, in the order it reviews them.

    review_select.py --build BUILD --compare RESULTS.jsonl --out contracts.jsonl [--tranche 600]

A contract is a project's own contract (not in lib/, node_modules/,
dependencies/, .deps/, vendor/; not a test, a mock, a script, a harness...)
whose ABI has a function, a fallback or a receive. Its builds (compilers, EVM
versions) are one contract; the build reviewed is the newest compiler's,
then the newest EVM's, the optimizer's before -noopt, the legacy code generator before via-IR. Contracts
whose reviewed bytecode is the same are reviewed once (the others are its
"duplicates").

The order: first the contracts of RESULTS.jsonl (compare_largest.py's
artifacts: each project's largest own contract in every build), then the
others, the largest bytecode first; tranches of --tranche contracts.

Each line: id, tranche, artifact (reviewed), bytes, builds (the contract's
other artifacts), duplicates (the other contracts' artifacts with the same
bytecode), compared (whether the contract was in RESULTS.jsonl).
"""
import argparse
import hashlib
import json
import os
import re

DEP = re.compile(r'(^|__)(lib|node_modules|dependencies|\.deps|vendor)__', re.I)
TEST_DIR = re.compile(r'(^|__)(tests?|testing|mocks?|scripts?|echidna|certora|fuzz|fuzzing|invariants?|harness(es)?|'
                      r'simulations?|examples?|forge-std)(__|$)', re.I)
TEST_NAME = re.compile(r'Mock|Test|Harness|Fuzz|Invariant|Echidna|Fake|Dummy|Stub|Script')
EVM_ORDER = ['homestead', 'tangerineWhistle', 'spuriousDragon', 'byzantium', 'constantinople', 'petersburg',
             'istanbul', 'berlin', 'london', 'paris', 'shanghai', 'cancun', 'prague', 'osaka']


def build_key(build):
    """solc-0.8.23-paris-ir -> a sort key: newest compiler, newest EVM, the optimizer's
    build before -noopt, legacy before IR"""
    parts = build.split('-')
    comp = parts[0]
    ver = tuple(int(x) for x in re.findall(r'\d+', parts[1])) if len(parts) > 1 else ()
    evm = EVM_ORDER.index(parts[2]) if len(parts) > 2 and parts[2] in EVM_ORDER else -1
    return (comp == 'solc', ver, evm, 'noopt' not in parts[3:], 'ir' not in parts[3:])


def split(artifact):
    """PROGRAM/REPO[/PROJECT...]/BUILD/SRC:NAME -> (project path, build, src, name)"""
    parts = artifact.split('/')
    bi = max(i for i, p in enumerate(parts) if re.match(r'(solc|vyper)-\d', p))
    src, name = parts[-1].rsplit(':', 1)
    return '/'.join(parts[:bi]), parts[bi], src, name


def own(src, name):
    if DEP.search(src) or TEST_DIR.search(src) or TEST_NAME.search(name):
        return False
    return not src.endswith(('.t.sol', '.s.sol'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--build', required=True)
    ap.add_argument('--compare', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--tranche', type=int, default=600)
    a = ap.parse_args()
    contracts = {}  # (project, src, name) -> [artifacts]
    for line in open(os.path.join(a.build, 'index.jsonl')):
        art = json.loads(line)['artifact']
        proj, build, src, name = split(art)
        if own(src, name):
            contracts.setdefault((proj, src, name), []).append(art)
    compared = set()
    for line in open(a.compare):
        proj, build, src, name = split(json.loads(line)['artifact'])
        compared.add((proj, src, name))
    rows = []
    for key, arts in contracts.items():
        arts.sort(key=lambda x: build_key(split(x)[1]), reverse=True)
        best = arts[0]
        meta = json.load(open(os.path.join(a.build, best + '.json')))
        if not any(e.get('type') in ('function', 'fallback', 'receive') for e in meta.get('abi') or []):
            continue
        code = open(os.path.join(a.build, best + '.hex')).read().strip()
        rows.append({'key': key, 'artifact': best, 'bytes': len(code) // 2, 'builds': arts[1:],
                     'hash': hashlib.sha256(code.encode()).hexdigest(), 'compared': key in compared})
    # the same reviewed bytecode: once
    first = {}
    kept = []
    for r in sorted(rows, key=lambda r: (not r['compared'], -r['bytes'], r['artifact'])):
        if r['hash'] in first:
            first[r['hash']]['duplicates'].append(r['artifact'])
            continue
        r['duplicates'] = []
        first[r['hash']] = r
        kept.append(r)
    with open(a.out, 'w') as f:
        for i, r in enumerate(kept):
            f.write(json.dumps({'id': 'c%05d' % (i + 1), 'tranche': i // a.tranche + 1, 'artifact': r['artifact'],
                                'bytes': r['bytes'], 'compared': r['compared'], 'builds': r['builds'],
                                'duplicates': r['duplicates']}) + '\n')
    print('%d own contracts with a function, %d reviewed (the others the same bytecode), %d compared, %d tranches'
          % (len(rows), len(kept), sum(r['compared'] for r in kept), (len(kept) + a.tranche - 1) // a.tranche))


if __name__ == '__main__':
    main()
