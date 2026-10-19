#!/usr/bin/env python3
"""Lot 12: the asm's hostile-input suites (tests/robustness.sh and
tests/security.sh of the repository) against pancxx and the python module:
inputs no compiler makes must neither take the process down nor hang; the
limits (PANORAMIX_MAX_MEMORY, PANORAMIX_TIMEOUT) cut what they must, with the
asm's messages, and a function that fails is a problem in the text, the
others go on; the text is the same at any thread count.

    tests/driver_robustness.py BUILD_DIR [--full]

The command line's own surface (its inputs, the fetch, standard input) is
cli_surface.py's, the module's pymod_surface.py's, the signature database's
builder sigdb's tests'. --full (or PANORAMIX_TEST_FULL=1) adds the long cases
(the corpus' big contracts, 2400 selectors, 4500 nested ifs, address-space
limits, a fork during a decompilation).
"""
import importlib.util, os, resource, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
BUILD = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.join(HERE, "..", "build")
FULL = "--full" in sys.argv or os.environ.get("PANORAMIX_TEST_FULL") == "1"
PANCXX = os.path.join(BUILD, "pancxx")
# the repository's tests/ (its corpus): $PANORAMIX_TESTS_DIR, else beside cxx/
CORPUS = os.path.join(os.environ.get("PANORAMIX_TESTS_DIR") or os.path.join(REPO, "tests"), "corpus")

bad = 0


def check(name, ok, detail=""):
    global bad
    if not ok:
        bad += 1
        print("FAIL", name, str(detail)[:800], flush=True)
    else:
        print("ok  ", name, flush=True)


tmp = tempfile.mkdtemp()
EMPTY_HOME = os.path.join(tmp, "home")
os.makedirs(EMPTY_HOME)


def env(**kw):
    e = {k: v for k, v in os.environ.items() if not k.startswith(("WEB3_", "PANORAMIX_"))}
    e.update(HOME=EMPTY_HOME, PANORAMIX_LOG="error")
    e.update({k: str(v) for k, v in kw.items()})
    return e


def crashed(rc):
    """killed by a signal or by the timeout (as against a clean refusal)"""
    return rc is None or rc < 0 or rc >= 128


def pancxx(args, e=None, timeout=120, stdin=b""):
    """(rc, stdout, stderr, seconds); rc None when it was stopped at the timeout"""
    start = time.monotonic()
    try:
        p = subprocess.run([PANCXX] + args, input=stdin, capture_output=True, env=e or env(), timeout=timeout)
        rc, out, err = p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as x:
        rc, out, err = None, (x.stdout or b"").decode("utf-8", "replace"), (x.stderr or b"").decode("utf-8", "replace")
    return rc, out, err, time.monotonic() - start


def hexfile(name, code):
    path = os.path.join(tmp, name + ".hex")
    with open(path, "w") as f:
        f.write(code + "\n")
    return path


def decompiled(name, path, limit_s=60, e=None, args=()):
    """robustness.sh's run: rc 0, the header, in time"""
    rc, out, err, s = pancxx(["decompile", path, "--no-color"] + list(args), e, timeout=limit_s * 2)
    check("%s (%.1f s)" % (name, s), rc == 0 and "Palkeoramix decompiler" in out and s <= limit_s,
          (rc, err[-400:], round(s, 1)))
    return out, err


def push(v):
    b = v.to_bytes(max(1, (v.bit_length() + 7) // 8), "big")
    return "%02x%s" % (0x5F + len(b), b.hex())


# --- robustness.sh ------------------------------------------------------------------


def nested_ifs(n):
    """require(!cd[4 + 32 i]) n times: a path n jumps deep"""
    code, size = "6080604052", 5
    for i in range(n):
        dest = size + 12
        code += "62%06x351562%06x57fe5b" % (4 + 32 * i, dest)
        size += 13
    return code + "00"


def cd_chain(n):
    """cd[cd[cd[...]]]: an expression n deep"""
    return "600435" + "35" * n + "60005500"


decompiled("nested_ifs_2000", hexfile("nested_ifs_2000", nested_ifs(2000)))
decompiled("cd_chain_20000", hexfile("cd_chain_20000", cd_chain(20000)))
decompiled("truncated_push", hexfile("truncated_push", "60"), 10)
decompiled("invalid", hexfile("invalid", "fe"), 10)
# a function whose memory limit is reached: a problem, the rest goes on
out, err = decompiled("nested_ifs_2000, PANORAMIX_MAX_MEMORY=64", os.path.join(tmp, "nested_ifs_2000.hex"),
                      e=env(PANORAMIX_MAX_MEMORY=64))
if FULL:
    decompiled("nested_ifs_4500", hexfile("nested_ifs_4500", nested_ifs(4500)))

# --- security.sh: contracts crafted to break the decompiler -------------------------

for name, code in [("codecopy_empty", "6000600060003900"),
                   ("codecopy_empty_stored", "600060006000393360005560005160015500"),
                   ("codecopy_1_0", "600060016000393360005500"),
                   ("codecopy_0_1", "600160006000393360005500"),
                   ("codecopy_end", "6001600160003933600055600051600155"),
                   ("codecopy_past", "60ff60ff60003900"),
                   ("calldatacopy_empty", "6000600060003700"),
                   ("returndatacopy_empty", "6000600060003e00"),
                   ("extcodecopy_empty", "60006000600060003c00")]:
    decompiled(name, hexfile(name, code), 60, env(PANORAMIX_MAX_MEMORY=2048))

# thread counts no machine has: capped (the text is the same at any count)
threads_hex = hexfile("threads", "6000356000556001600055")
rc, out, err, s = pancxx(["decompile", threads_hex, "--no-color", "-j", "4611686018427387904"])
rc1, out1, _, _ = pancxx(["decompile", threads_hex, "--no-color", "-j", "1"])
check("threads_huge", rc == 0 and "Palkeoramix decompiler" in out and out == out1, (rc, err[-300:]))

# a string constant with the bytes that end a line: the text stays one line per line
rc, out, err, s = pancxx(["decompile", hexfile("lines", "7f0a0a0a6465662070776e656428293a0a20207265766572740a0a0a0a0a600055"),
                          "--no-color"])
check("forged_lines", rc == 0 and not any(l.startswith("def pwned") for l in out.splitlines()), out[-300:])

# the data of a return made of regions of zeroes past the calldata: bounded in
# time and memory (PANORAMIX_MAX_MEMORY=128)
for n in (8, 32):
    sz, code, off = 1 << 24, "", 0
    for i in range(n):
        code += push(1) + push(off) + "52"
        off += 32
        code += push(sz) + "36" + push(off) + "37"
        off += sz
    code += push(1) + push(off) + "52"
    off += 32
    code += push(off) + push(0) + "f3"
    decompiled("printer_zeroes_%d" % n, hexfile("zeroes%d" % n, code), 20, env(PANORAMIX_MAX_MEMORY=128))

# --- the limits, the problems, the messages ------------------------------------------

weth = os.path.join(CORPUS, "WETH.hex")
if not os.path.exists(weth):
    print("(no corpus at %s: the cases of its contracts skipped)" % CORPUS)
else:
    # a function's limit below what an arena's chunk takes: every function
    # fails at it (the discovery too: the fallback alone), the text says so
    rc, out, err, s = pancxx(["decompile", weth, "--no-color"], env(PANORAMIX_MAX_MEMORY=1))
    check("PANORAMIX_MAX_MEMORY=1: the problems, the text, 0", rc == 0 and out.startswith("# Palkeoramix decompiler.")
          and "#  - _fallback(?)" in out and "Loader issue: out of memory" in err
          and "Problem with _fallback: out of memory: a function's memory limit was reached (PANORAMIX_MAX_MEMORY)" in err,
          (rc, out[:300], err[-400:]))
    # PANORAMIX_TIMEOUT=0: no time limit at all; a factor: the same text when nothing is cut
    rc0, out0, err0, _ = pancxx(["decompile", weth, "--no-color", "-j", "1"], env(PANORAMIX_TIMEOUT=0))
    rc1, out1, err1, _ = pancxx(["decompile", weth, "--no-color", "-j", "1"], env(PANORAMIX_TIMEOUT=10))
    check("PANORAMIX_TIMEOUT=0 / 10: the same text", rc0 == 0 and rc1 == 0 and out0 == out1, (rc0, rc1, err0[-200:]))
    # the log's lines of a decompilation (the asm's)
    rc, out, err, s = pancxx(["decompile", weth, "--no-color", "-j", "2"], env(PANORAMIX_LOG="info"))
    check("the log: the asm's lines", rc == 0 and "INFO Running light execution to find functions." in err
          and "INFO Decompiling 0xa9059cbb..." in err and "INFO  -> Interpreting EVM on function..." in err
          and "INFO Functions decompilation finished, now doing post-processing." in err, err[-600:])
    # --function: only those, the others not even decompiled
    rc, out, err, s = pancxx(["decompile", weth, "--no-color", "--function", "_fallback"], env(PANORAMIX_LOG="info"))
    # (the function headers: def name(...); def storage: and def SafeMath: are blocks)
    headers = [l for l in out.split("\n") if l.startswith("def ") and "(" in l.split(":")[0]]
    check("--function _fallback", rc == 0 and len(headers) == 1 and headers[0].startswith("def _fallback(")
          and "Decompiling 0xa9059cbb" not in err, (out[-300:], err[-300:]))

# the same text and JSON at any thread count
for f in ["WETH.hex", "Multicall3.hex", "USDC_proxy.hex", "AaveV3Pool_proxy.hex", "ENSRegistry.hex"]:
    path = os.path.join(CORPUS, f)
    if not os.path.exists(path):
        continue
    texts = {}
    for j in ("1", "2", "8"):
        rc, out, err, s = pancxx(["decompile", path, "--no-color", "-j", j])
        rc2, js, err2, s2 = pancxx(["decompile", path, "--no-color", "--json", "-j", j])
        texts[j] = (rc, out, rc2, js)
    check("the same text and JSON at -j 1, 2, 8: " + f,
          all(t == texts["1"] for t in texts.values()) and texts["1"][0] == 0 and texts["1"][2] == 0,
          [(j, t[0], t[2], len(t[1]), len(t[3])) for j, t in texts.items()])

# --- the long ones ----------------------------------------------------------------------

if FULL:
    one_inch = os.path.join(CORPUS, "OneInchV5.hex")
    if os.path.exists(one_inch):
        # a list of contracts: each decompiled within its own limits
        rc, out, err, s = pancxx(["decompile", ",".join([one_inch] * 9), "--no-color", "-j", "1"],
                                 env(PANORAMIX_MAX_MEMORY=64, PANORAMIX_LOG="critical"), timeout=1200)
        check("list_one_context: 9 texts", rc == 0 and out.count("Palkeoramix decompiler") == 9, (rc, err[-300:]))
        # a function's limit near what the contract takes (the asm's: a
        # contract that fit at 18 and 26 MiB came out with no text at 21 to
        # 24): its text whatever, each function there or a problem
        rc, out, err, s = pancxx(["decompile", one_inch, "--no-color", "-j", "1"], env(PANORAMIX_LOG="critical"),
                                 timeout=600)
        total = sum(1 for l in out.splitlines() if l.startswith("def ")) + out.count("\n#  - ")
        for mm in (18, 21, 22, 24, 26):
            rc, out, err, s = pancxx(["decompile", one_inch, "--no-color", "-j", "1"],
                                     env(PANORAMIX_MAX_MEMORY=mm, PANORAMIX_LOG="critical"), timeout=600)
            n = sum(1 for l in out.splitlines() if l.startswith("def "))
            fails = out.count("\n#  - ")
            check("limit_monotonic_%d: %d functions, %d problems (of %d)" % (mm, n, fails, total),
                  rc == 0 and n + fails == total and total >= 40, (rc, err[-300:]))
    ceth = os.path.join(CORPUS, "cETH.hex")
    if os.path.exists(ceth):
        rc, out, err, s = pancxx(["decompile", ceth, "--no-color", "-j", "1"],
                                 env(PANORAMIX_MAX_MEMORY=16, PANORAMIX_LOG="critical"), timeout=600)
        check("loader_fallback (PANORAMIX_MAX_MEMORY=16)", rc == 0 and "Palkeoramix decompiler" in out, (rc, err[-300:]))

    # a linear dispatcher of 2400 selectors under a tiny timeout factor: what
    # the discovery's VM found is kept (more than the fallback)
    k = 2400
    head = 6 + k * 12 + 4
    code = push(0) + "35" + "60e01c"
    for i in range(k):
        code += "8063%08x1462%06x57" % (0x10000000 + i, head + 2 * i)
    code += "600080fd"
    code += "5b00" * k
    chain = hexfile("chain", code)
    for attempt in range(3):
        rc, out, err, s = pancxx(["decompile", chain, "--no-color", "-j", "1"],
                                 env(PANORAMIX_TIMEOUT="0.004", PANORAMIX_LOG="critical"), timeout=300)
        n = sum(1 for l in out.splitlines() if l.startswith("def "))
        if n > 1:
            break
    check("discovery_deadline: %d functions" % n, rc == 0 and n > 1, (rc, err[-300:]))

    # one function whose walks blow up, six chains of 20000 CALLDATALOADs: the
    # six are there, the first a problem or a text that says why it has none
    n_steps, chain_len = 20, 20000

    def body_a():
        c = push(4) + "35" + push(36) + "3552"
        for i in range(n_steps):
            c += push(36) + "35"
            if i:
                c += push(32 * i) + "01"
            c += "5180" + push(1) + "0118"
            c += push(36) + "35" + push(32 * (i + 1)) + "0152"
        c += push(36) + "35" + push(32 * n_steps) + "0151" + push(0) + "5500"
        return c

    def body_b(kk):
        return push(4) + "35" * chain_len + push(kk) + "5500"

    bodies = [(0x11111111, body_a())] + [(0x22220000 + kk, body_b(kk + 1)) for kk in range(6)]
    head = 6 + len(bodies) * 12 + 4
    code = push(0) + "35" + "60e01c"
    off, dests = head, []
    for sel, b in bodies:
        dests.append(off)
        off += 1 + len(b) // 2
    for (sel, b), d in zip(bodies, dests):
        code += "8063%08x1462%06x57" % (sel, d)
    code += "600080fd"
    for sel, b in bodies:
        code += "5b" + b
    blowup = hexfile("blowup", code)
    for mm in (64, 256):
        rc, out, err, s = pancxx(["decompile", blowup, "--no-color", "-j", "2"],
                                 env(PANORAMIX_MAX_MEMORY=mm, PANORAMIX_LOG="critical"), timeout=600)
        n = sum(1 for l in out.splitlines() if l.startswith("def unknown2222"))
        check("function_blowup_%d: %d functions of 6" % (mm, n), rc == 0 and n == 6, (rc, err[-300:]))

    # --explain with a compaction at every round of the simplifier
    chainlink = os.path.join(CORPUS, "ChainlinkETHUSD.hex")
    if os.path.exists(chainlink):
        rc, out, err, s = pancxx(["decompile", chainlink, "--no-color", "--explain", "-j", "1"],
                                 env(PANORAMIX_COMPACT_MIB=1, PANORAMIX_TIMEOUT=0), timeout=1200)
        check("explain_compaction", rc == 0 and "Initial decompiled trace" in out, (rc, err[-300:]))

    # the system with no more memory (an address space limit): the contexts,
    # their chunks, the threads can't be had - the functions fail, the host
    # process lives on
    module_dir = BUILD
    if os.path.exists(weth) and any(f.startswith("panoramix_cxx.") for f in os.listdir(module_dir)):
        for lim in (60000, 90000, 160000, 400000):
            prog = ("import sys; sys.path.insert(0, %r)\nimport panoramix_cxx as A\n"
                    "t = A.decompile(open(%r).read().strip(), threads=2, color=False)\n"
                    "print('decompiled' if 'Palkeoramix' in t else 'no text')\n") % (module_dir, weth)

            def limit(lim=lim):
                resource.setrlimit(resource.RLIMIT_AS, (lim * 1024, lim * 1024))

            try:
                p = subprocess.run([sys.executable, "-I", "-c", prog], capture_output=True, env=env(),
                                   timeout=120, preexec_fn=limit)
                rc, last = p.returncode, (p.stdout.decode().strip().splitlines() or [""])[-1]
                err = p.stderr.decode()[-300:]
            except subprocess.TimeoutExpired:
                rc, last, err = None, "", "timeout"
            check("address space of %d KiB" % lim, rc == 0 and last == "decompiled", (rc, last, err))

        # a fork while a decompilation runs on another thread: the child decompiles
        prog = """
import os, sys, threading, time, signal
sys.path.insert(0, %r)
import panoramix_cxx as m
big = open(%r).read().strip()
small = open(%r).read().strip()
m.decompile(small, threads=1)
t = threading.Thread(target=lambda: m.decompile(big, threads=2))
t.start()
time.sleep(0.3)
pid = os.fork()
if pid == 0:
    signal.alarm(60)
    for i in range(3):
        m.decompile(small, threads=2)
    os._exit(0)
t.join()
_, st = os.waitpid(pid, 0)
print("child", os.WIFEXITED(st) and os.WEXITSTATUS(st) == 0)
""" % (module_dir, os.path.join(CORPUS, "UniV2Pair.hex"), weth)
        p = subprocess.run([sys.executable, "-I", "-c", prog], capture_output=True, env=env(PANORAMIX_LOG="critical"),
                           timeout=600)
        check("fork during a decompilation", p.returncode == 0 and b"child True" in p.stdout,
              (p.returncode, p.stdout[-200:], p.stderr[-300:]))

shutil.rmtree(tmp, True)
print("%d failures" % bad)
sys.exit(1 if bad else 0)
