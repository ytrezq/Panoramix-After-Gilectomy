#!/usr/bin/env python3
"""Immunefi programs -> programs.json: per program, its assets in scope (the
scope page's RSC payload), the git repositories they point to (with the refs
and files named), the contract addresses on EVM explorers, and whether the
program is EVM-compatible (an EVM explorer address, an EVM language file, or
an EVM ecosystem / language tag).

    extract_assets.py BOUNTIES_RAW.json PAGES_DIR OUT.json
"""
import json
import re
import sys
from collections import OrderedDict

raw, pages, out = sys.argv[1:4]
bounties = json.load(open(raw))

NON_EVM_ECO = {'Solana', 'Bitcoin', 'Stacks', 'Starknet', 'Aptos', 'SUI', 'TON', 'Injective', 'Polkadot',
               'Cosmos', 'Centrifuge', 'Algorand', 'Obyte', 'Celestia', 'Tezos', 'Lightning'}
EVM_LANG = {'Solidity', 'Vyper', 'Yul'}
EVM_EXT = ('.sol', '.vy', '.vyi', '.yul', '.huff', '.fe')
# block explorers of EVM chains: host -> chain
EXPLORERS = [
    (r'(^|\.)etherscan\.io$', 'ethereum'), (r'^sepolia\.etherscan\.io$', 'sepolia'),
    (r'^holesky\.etherscan\.io$', 'holesky'), (r'^goerli\.etherscan\.io$', 'goerli'),
    (r'^optimistic\.etherscan\.io$', 'optimism'), (r'arbiscan\.io$', 'arbitrum'), (r'polygonscan\.com$', 'polygon'),
    (r'bscscan\.com$', 'bsc'), (r'basescan\.org$', 'base'), (r'snowtrace\.io$', 'avalanche'),
    (r'snowscan\.xyz$', 'avalanche'), (r'ftmscan\.com$', 'fantom'), (r'gnosisscan\.io$', 'gnosis'),
    (r'lineascan\.build$', 'linea'), (r'scrollscan\.com$', 'scroll'), (r'era\.zksync\.network$', 'zksync'),
    (r'explorer\.zksync\.io$', 'zksync'), (r'celoscan\.io$', 'celo'), (r'moonscan\.io$', 'moonbeam'),
    (r'blastscan\.io$', 'blast'), (r'mantlescan\.xyz$', 'mantle'), (r'explorer\.mantle\.xyz$', 'mantle'),
    (r'sonicscan\.org$', 'sonic'), (r'fraxscan\.com$', 'fraxtal'), (r'cronoscan\.com$', 'cronos'),
    (r'kavascan\.com$', 'kava'), (r'explorer\.kava\.io$', 'kava'), (r'seistream\.app$', 'sei'), (r'seitrace\.com$', 'sei'),
    (r'routescan\.io$', 'routescan'), (r'blockscout\.com$', 'blockscout'), (r'explorer\.', 'other-evm'),
    (r'tronscan\.org$', 'tron'), (r'opbnbscan\.com$', 'opbnb'), (r'berascan\.com$', 'berachain'),
    (r'unichain', 'unichain'), (r'katanascan', 'katana'), (r'hyperevmscan|hyperliquid', 'hyperevm'),
    (r'abscan\.org$', 'abstract'), (r'worldscan\.org$', 'worldchain'), (r'inkonchain|explorer\.inkonchain', 'ink'),
]
ADDR = re.compile(r'0x[0-9a-fA-F]{40}')
GIT = re.compile(r'https?://(github\.com|gitlab\.com|bitbucket\.org)/([A-Za-z0-9_.\-]+)/([A-Za-z0-9_.\-]+)((?:/[^\s"\'<>)\]\\]*)?)')


def payload(path):
    try:
        html = open(path, encoding='utf-8').read()
    except FileNotFoundError:
        return None
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', html, re.S)
    text = ''
    for c in chunks:
        try:
            text += json.loads('"' + c + '"')
        except Exception:
            pass
    return text or html


def assets_of(text):
    """the first JSON array after "assets": in the payload"""
    found = []
    for m in re.finditer(r'"assets":\[', text):
        start = m.end() - 1
        depth = 0
        for i in range(start, min(len(text), start + 2_000_000)):
            ch = text[i]
            if ch in '[{':
                depth += 1
            elif ch in ']}':
                depth -= 1
                if depth == 0:
                    try:
                        arr = json.loads(text[start:i + 1])
                        if isinstance(arr, list):
                            found.extend(a for a in arr if isinstance(a, dict) and 'url' in a)
                    except Exception:
                        pass
                    break
    seen, out = set(), []
    for a in found:
        k = (a.get('url'), a.get('type'))
        if k not in seen:
            seen.add(k)
            out.append(a)
    return out


def chain_of(host):
    for pat, chain in EXPLORERS:
        if re.search(pat, host):
            return chain
    return None


def git_ref(url):
    m = GIT.match(url)
    if not m:
        return None
    host, owner, repo, rest = m.groups()
    repo = re.sub(r'\.git$', '', repo)
    ref, path = None, None
    rm = re.match(r'/(?:-/)?(?:blob|tree|commit|src)/([^/]+)(/.*)?', rest or '')
    if rm:
        ref, path = rm.group(1), (rm.group(2) or '').lstrip('/') or None
    return {'host': host, 'repo': f'https://{host}/{owner}/{repo}', 'owner': owner, 'name': repo, 'ref': ref, 'path': path}


programs = []
for b in bounties:
    slug = b['slug']
    tags = b.get('tags') or {}
    scope = payload(f'{pages}/{slug}_scope.html')
    info = payload(f'{pages}/{slug}_information.html')
    assets = assets_of(scope) if scope else []
    repos = OrderedDict()
    addresses = []
    evm_reasons = set()
    for a in assets:
        url = a.get('url') or ''
        g = git_ref(url)
        if g:
            r = repos.setdefault(g['repo'], {'repo': g['repo'], 'refs': [], 'paths': [], 'in_scope': True})
            if g['ref'] and g['ref'] not in r['refs']:
                r['refs'].append(g['ref'])
            if g['path']:
                r['paths'].append(g['path'])
                if g['path'].endswith(EVM_EXT):
                    evm_reasons.add('evm-source-file')
            continue
        hm = re.match(r'https?://([^/]+)', url)
        host = hm.group(1).lower() if hm else ''
        chain = chain_of(host)
        am = ADDR.search(url)
        if am and chain and chain != 'tron':
            addresses.append({'chain': chain, 'address': am.group(0), 'url': url, 'type': a.get('type'),
                              'description': a.get('description')})
            evm_reasons.add('evm-explorer-address')
    # repos mentioned elsewhere on the pages (documentation, resources)
    for text in (info or '', scope or ''):
        for m in GIT.finditer(text):
            g = git_ref(m.group(0))
            if g and g['repo'] not in repos and g['owner'] not in ('immunefi-team', 'Immunefi'):
                repos[g['repo']] = {'repo': g['repo'], 'refs': [g['ref']] if g['ref'] else [], 'paths': [g['path']] if g['path'] else [], 'in_scope': False}
    eco = set(tags.get('ecosystem') or [])
    langs = set(tags.get('language') or [])
    if eco - NON_EVM_ECO:
        evm_reasons.add('ecosystem-tag')
    if langs & EVM_LANG:
        evm_reasons.add('language-tag')
    programs.append({
        'slug': slug, 'project': b.get('project'), 'page': f'https://immunefi.com/bug-bounty/{slug}/',
        'max_bounty': b.get('maxBounty'), 'ecosystems': sorted(eco), 'languages': sorted(langs),
        'program_types': tags.get('programType') or [], 'evm': bool(evm_reasons), 'evm_reasons': sorted(evm_reasons),
        'scope_fetched': scope is not None, 'assets': [{k: a.get(k) for k in ('url', 'type', 'description')} for a in assets],
        'repos': list(repos.values()), 'addresses': addresses,
    })

json.dump(programs, open(out, 'w'), indent=1)
evm = [p for p in programs if p['evm']]
print(len(programs), 'programs;', len(evm), 'EVM-compatible;',
      sum(1 for p in programs if not p['scope_fetched']), 'scope pages missing')
print('EVM programs with an in-scope repo:', sum(1 for p in evm if any(r['in_scope'] for r in p['repos'])),
      '; with only other repo links:', sum(1 for p in evm if p['repos'] and not any(r['in_scope'] for r in p['repos'])),
      '; with no repo link:', sum(1 for p in evm if not p['repos']))
print('EVM explorer addresses:', sum(len(p['addresses']) for p in evm))
