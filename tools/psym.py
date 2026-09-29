#!/usr/bin/env python3
"""The report of tools/psamp.c's samples.

    tools/psym.py OUT [N]                 the functions the samples fall in (self)
    tools/psym.py OUT N --incl M          and the M first by samples below them
    tools/psym.py OUT N --callers F,G     the samples in F or G by the caller: the
                  [--skip W,V]            first frame up that isn't F, G or one of
                                          the wrappers W, V (a leaf function has no
                                          frame: its caller is the word at [rsp])
    tools/psym.py OUT N --below F         the samples under F by F's callee
    tools/psym.py OUT N --annotate F      the samples in F by instruction (objdump)

The symbols come from nm (the objects of the maps), so the functions of a
library without its symbol table are the dynamic symbol before them.
"""
import bisect, collections, re, subprocess, sys

args = sys.argv[1:]
path = args[0]
n = int(args[1]) if len(args) > 1 and args[1].isdigit() else 40
opt = lambda name: args[args.index(name) + 1] if name in args else None

maps, samples = [], []
for line in open(path):
    if line.startswith('S '):
        f = line.split()
        samples.append([int(x, 16) if i > 1 else int(x) for i, x in enumerate(f[1:], 1)])
    elif line.startswith('M '):
        f = line[2:].split()
        if len(f) >= 6 and 'x' in f[1]:
            lo, hi = (int(x, 16) for x in f[0].split('-'))
            maps.append((lo, hi, int(f[2], 16), f[5]))
maps.sort()

objs = {}
def symbols(obj):
    """(load segments, symbol addresses, names) of an object"""
    if obj not in objs:
        segs = []
        r = subprocess.run(['readelf', '-lW', obj], capture_output=True, text=True)
        for l in r.stdout.splitlines():
            m = re.match(r'\s*LOAD\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x[0-9a-f]+\s+0x([0-9a-f]+)', l)
            if m:
                segs.append((int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16)))
        syms = []
        for cmd in (['nm', '-n', '--defined-only', obj], ['nm', '-D', '-n', '--defined-only', obj]):
            for l in subprocess.run(cmd, capture_output=True, text=True).stdout.splitlines():
                p = l.split()
                if len(p) >= 3 and p[1] in 'tTwWiI':
                    syms.append((int(p[0], 16), p[2]))
            if syms:
                break
        syms.sort()
        objs[obj] = (segs, [a for a, _ in syms], [s for _, s in syms])
    return objs[obj]

def locate(ip):
    """(object, its virtual address) of an address"""
    i = bisect.bisect_right(maps, (ip, float('inf'))) - 1
    if i < 0 or not (maps[i][0] <= ip < maps[i][1]):
        return None, None
    lo, hi, off, obj = maps[i]
    foff = ip - lo + off
    for so, sv, sz in symbols(obj)[0]:
        if so <= foff < so + sz:
            return obj, foff - so + sv
    return obj, foff

names = {}
def name(ip):
    r = names.get(ip)
    if r is None:
        obj, va = locate(ip)
        if obj is None:
            r = '?'
        else:
            _, addrs, syms = symbols(obj)
            j = bisect.bisect_right(addrs, va) - 1
            r = syms[j] if j >= 0 else '?'
            base = obj.rsplit('/', 1)[-1]
            if 'panasm' not in base and 'panoramix_asm' not in base:
                r += ' [' + base + ']'
        names[ip] = r
    return r

tot = len(samples)
print('%d samples, %d threads' % (tot, len({s[0] for s in samples})))
self_ = collections.Counter(name(s[1]) for s in samples)
for f, k in self_.most_common(n):
    print('%7d %6.2f%% %s' % (k, 100.0 * k / tot, f))

def frames(s):
    return [name(s[1])] + [name(a) for a in s[4:]]

if '--incl' in args:
    inc = collections.Counter()
    for s in samples:
        for f in set(frames(s)):
            inc[f] += 1
    print('--- below them')
    for f, k in inc.most_common(int(opt('--incl'))):
        print('%7d %6.2f%% %s' % (k, 100.0 * k / tot, f))

if '--callers' in args:
    fs = set(opt('--callers').split(','))
    skip = set((opt('--skip') or '').split(','))
    cc = collections.Counter()
    for s in samples:
        fr = frames(s)
        if fr[0] not in fs:
            continue
        who = None
        for f in [name(s[2])] + fr[1:]:
            if f not in fs and f not in skip:
                who = f
                break
        cc[who] += 1
    t = sum(cc.values())
    print('--- %d samples in %s, by the caller' % (t, ','.join(sorted(fs))))
    for f, k in cc.most_common(n):
        print('%7d %6.2f%% %s' % (k, 100.0 * k / max(t, 1), f))

if '--below' in args:
    fn = opt('--below')
    cc = collections.Counter()
    for s in samples:
        fr = frames(s)
        if fn in fr:
            i = fr.index(fn)
            cc[fr[i - 1] if i > 0 else '(itself)'] += 1
    t = sum(cc.values())
    print('--- %d samples under %s, by its callee' % (t, fn))
    for f, k in cc.most_common(n):
        print('%7d %6.2f%% %s' % (k, 100.0 * k / max(t, 1), f))

if '--annotate' in args:
    fn = opt('--annotate')
    ips = collections.Counter(s[1] for s in samples if name(s[1]).split(' ')[0] == fn)
    if ips:
        obj, _ = locate(next(iter(ips)))
        base = {ip: locate(ip)[1] for ip in ips}
        _, addrs, syms = symbols(obj)
        start = addrs[syms.index(fn)]
        end = next((a for a in addrs if a > start), start + 4096)
        dis = subprocess.run(['objdump', '-d', '-M', 'intel', '--no-show-raw-insn',
                              '--start-address=%#x' % start, '--stop-address=%#x' % end, obj],
                             capture_output=True, text=True).stdout
        at = collections.Counter()
        for ip, k in ips.items():
            at[base[ip]] += k
        print('--- %d samples in %s' % (sum(ips.values()), fn))
        for l in dis.splitlines():
            m = re.match(r'\s*([0-9a-f]+):\s*(.*)', l)
            if m:
                k = at.get(int(m.group(1), 16), 0)
                print('%6s %s' % (k or '', l.strip()[:100]))
