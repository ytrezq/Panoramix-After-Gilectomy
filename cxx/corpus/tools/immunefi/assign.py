#!/usr/bin/env python3
"""Split the programs to search among N agents: the EVM ones and those whose
EVM-ness the tags don't tell (no tag, or repos of unknown language), balanced
by an estimate of the work (in-scope repositories, explorer addresses).

    assign.py PROGRAMS.json OUTDIR N
"""
import json
import os
import sys

programs, outdir, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
ps = json.load(open(programs))
NON_EVM_ECO = {'Solana', 'Stacks', 'Aptos', 'SUI', 'TON', 'Polkadot', 'Cosmos', 'Algorand', 'Obyte', 'Celestia',
               'Tezos', 'Lightning', 'Bitcoin', 'Starknet', 'Injective', 'Centrifuge'}
todo, skipped = [], []
for p in ps:
    eco = set(p['ecosystems'])
    clearly_not = eco and eco <= NON_EVM_ECO and not p['evm'] and not set(p['languages']) & {'Solidity', 'Vyper', 'Yul'}
    (skipped if clearly_not else todo).append(p)


def work(p):
    return 1 + 2 * sum(1 for r in p['repos'] if r['in_scope']) + len(p['repos']) / 4 + len(p['addresses']) / 40


todo.sort(key=work, reverse=True)
bins = [[] for _ in range(n)]
loads = [0.0] * n
for p in todo:
    i = loads.index(min(loads))
    bins[i].append(p['slug'])
    loads[i] += work(p)
os.makedirs(outdir, exist_ok=True)
for i, b in enumerate(bins, 1):
    with open(os.path.join(outdir, f'agent{i}.txt'), 'w') as f:
        f.write('\n'.join(b) + '\n')
with open(os.path.join(outdir, 'not_evm.txt'), 'w') as f:
    f.write('\n'.join(f"{p['slug']}\t{','.join(p['ecosystems'])}" for p in skipped) + '\n')
print(len(todo), 'programs to search,', len(skipped), 'clearly not EVM;', [len(b) for b in bins], [round(x) for x in loads])
