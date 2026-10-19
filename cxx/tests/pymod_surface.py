#!/usr/bin/env python3
"""The python module's surface: the asm's panoramix_asm module's functions
and objects (without _test), their arguments, results and exceptions -
against the core's stub (src/decompile_stub.cpp: placeholder text saying
what it was given), for both builds of the module (panoramix_cxx, and
compat/panoramix_asm). decompile_address against a node of our own.

    tests/pymod_surface.py BUILD_DIR
"""
import contextlib, http.server, importlib.util, io, json, os, signal, sys, threading, time

BUILD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build")
ASM_BUILD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build")
FUNCTIONS = {"decompile", "decompile_bytecode", "decompile_address", "disasm", "set_log_level", "build_signature_db"}

bad = 0


def check(name, ok, detail=""):
    global bad
    if not ok:
        bad += 1
        print("FAIL", name, str(detail)[:600], flush=True)
    else:
        print("ok  ", name, flush=True)


def raises(f, kind, text=""):
    try:
        f()
    except kind as e:
        return text in str(e)
    except Exception as e:
        print("   (raised %r)" % e)
        return False
    return False


def load(name, directory):
    for f in os.listdir(directory):
        if f.startswith(name + ".") and f.endswith(".so"):
            spec = importlib.util.spec_from_file_location(name, os.path.join(directory, f))
            m = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(m)
            return m
    return None


def fnv1a64(code):
    h = 0xcbf29ce484222325
    for b in code:
        h = ((h ^ b) * 0x100000001b3) & (2**64 - 1)
    return "%016x" % h


CODE = bytes.fromhex("6080604052348015600f57600080fd5b50")
# panasm's own disassembly of CODE
DISASM = ("0x0, push1, 0x80\n0x2, push1, 0x40\n0x4, mstore, \n0x5, callvalue, \n0x6, dup1, \n0x7, iszero, \n"
          "0x8, push1, 0xf\n0xa, jumpi, \n0xb, push1, 0x0\n0xd, dup1, \n0xe, revert, \n0xf, jumpdest, \n0x10, pop, \n")
FAIL = bytes.fromhex("deadbeef00")   # (the stub fails on it)

# a node: eth_getCode of two addresses, an error for a third
A1 = "0x00000000000000000000000000000000000000a1"
A2 = "0x00000000000000000000000000000000000000a2"
BOOM = "0x00000000000000000000000000000000000000e1"
ADDRS = {A1: CODE.hex(), A2: ""}


class Node(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        a = req["params"][0].lower()
        if a == BOOM:
            out = {"jsonrpc": "2.0", "id": req["id"], "error": {"code": -32000, "message": "boom"}}
        else:
            out = {"jsonrpc": "2.0", "id": req["id"], "result": "0x" + ADDRS.get(a, "")}
        body = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class SlowNode(Node):
    def do_POST(self):
        time.sleep(1.5)
        super().do_POST()


node = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Node)
threading.Thread(target=node.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d" % node.server_address[1]
slow = http.server.ThreadingHTTPServer(("127.0.0.1", 0), SlowNode)
threading.Thread(target=slow.serve_forever, daemon=True).start()
SLOW_URL = "http://127.0.0.1:%d" % slow.server_address[1]


def ctrl_c(m, p):
    """a CTRL+C during a call: held until it returns (the node's answer
    not cut short), then python's KeyboardInterrupt"""
    previous = signal.signal(signal.SIGINT, signal.default_int_handler)
    os.environ["WEB3_PROVIDER_URI"] = SLOW_URL
    threading.Timer(0.5, lambda: os.kill(os.getpid(), signal.SIGINT)).start()
    start = time.time()
    try:
        m.decompile_address(A1)
        time.sleep(0.5)
        check(p + "ctrl-c: lost", False)
    except KeyboardInterrupt:
        check(p + "ctrl-c: held until the call returned, then KeyboardInterrupt", time.time() - start >= 1.4,
              time.time() - start)
    finally:
        os.environ.pop("WEB3_PROVIDER_URI", None)
        signal.signal(signal.SIGINT, previous)


def surface(m, name):
    p = name + ": "
    public = {n for n in dir(m) if not n.startswith("_")}
    check(p + "the functions and Decompilation", public == FUNCTIONS | {"Decompilation"}, sorted(public))
    check(p + "no _test", not hasattr(m, "_test"))
    check(p + "__version__", isinstance(getattr(m, "__version__", None), str) and m.__version__.count(".") == 2,
          getattr(m, "__version__", None))
    D = m.Decompilation
    check(p + "Decompilation's name", D.__name__ == "Decompilation" and D.__module__ == name, (D.__module__, D.__name__))
    check(p + "Decompilation: a struct sequence (text, asm, json) and .explain",
          issubclass(D, tuple) and D.n_sequence_fields == 3 and D.n_fields == 4
          and D.__match_args__ == ("text", "asm", "json"), (D.n_sequence_fields, D.n_fields))
    for f in FUNCTIONS:
        check(p + f + "'s doc", (getattr(m, f).__doc__ or "").startswith(f + "("), getattr(m, f).__doc__)

    # decompile: the code as bytes, bytes-like, hex
    m.set_log_level("error")
    t = m.decompile(CODE, threads=2, color=False)
    check(p + "decompile(bytes)", "# %d bytes of code, fnv1a64 %s" % (len(CODE), fnv1a64(CODE)) in t
          and "threads=2" in t and "color=0" in t and "\x1b" not in t and not t.endswith("\n"), t)
    for what, arg in [("bytearray", bytearray(CODE)), ("memoryview", memoryview(CODE)),
                      ("str", CODE.hex()), ("str 0x", "0x" + CODE.hex()), ("str 0X, blanks", " 0X" + CODE.hex().upper() + "\n"),
                      ("a buffer of 0x60 80... in an array", __import__("array").array("B", CODE))]:
        check(p + "decompile(%s)" % what, m.decompile(arg, threads=2, color=False) == t)
    check(p + "decompile: color", "\x1b[" in m.decompile(CODE))
    t = m.decompile(CODE, 3, "trans", False, True, False)
    check(p + "decompile: positional options", "threads=3 function='trans' color=0 verbose=1 explain=0" in t, t)
    t = m.decompile(CODE, threads=0, function=None)
    check(p + "decompile: threads=0 (one per CPU), no function", "threads=0 function=''" in t, t)
    t = m.decompile(CODE, threads=-5)
    check(p + "decompile: threads<0 (one per CPU)", "threads=0" in t, t)
    t = m.decompile(CODE, explain=True, color=False)
    check(p + "decompile: --explain's text first", t.startswith("(stub) what --explain prints")
          and "verbose=1 explain=1" in t, t)
    check(p + "decompile: odd hex", raises(lambda: m.decompile("608"), ValueError, "odd"))
    check(p + "decompile: not hex", raises(lambda: m.decompile("60zz"), ValueError, "position 2"))
    check(p + "decompile: not code", raises(lambda: m.decompile(12), TypeError, "expected bytes"))
    check(p + "decompile: a failure", raises(lambda: m.decompile(FAIL), RuntimeError, "decompilation failed: (stub)"))
    check(p + "decompile: a bad keyword", raises(lambda: m.decompile(CODE, colour=False), TypeError))
    check(p + "decompile: empty code", "# 0 bytes of code" in m.decompile(b""))

    # decompile_bytecode: Decompilation(text, asm, json), explain
    saved = sys.argv
    sys.argv = ["x"]
    d = m.decompile_bytecode(CODE, threads=2, color=False)
    check(p + "decompile_bytecode", isinstance(d, D) and len(d) == 3 and d.text == d[0] and d.asm == d[1]
          and d.json == d[2] and d.explain is None, repr(d)[:300])
    check(p + "decompile_bytecode: the text", "json=1 asm_lines=1" in d.text and fnv1a64(CODE) in d.text, d.text)
    check(p + "decompile_bytecode: asm, a list of str", isinstance(d.asm, list) and all(isinstance(x, str) for x in d.asm)
          and d.asm, d.asm)
    check(p + "decompile_bytecode: json, a dict", isinstance(d.json, dict) and d.json.get("bytes") == len(CODE), d.json)
    text, asm, js = d
    check(p + "decompile_bytecode: unpacked", text == d.text and asm == d.asm and js == d.json)
    match d:
        case D(text=tx, asm=a, json=j):
            check(p + "decompile_bytecode: match", tx == d.text and a == d.asm and j == d.json)
    d = m.decompile_bytecode(CODE.hex(), "trans", 4, False)
    check(p + "decompile_bytecode: positional", "threads=4 function='trans' color=0" in d.text, d.text)
    # python's flags of sys.argv, or the arguments
    sys.argv = ["x", "--verbose", "--repr", "--returns"]
    d = m.decompile_bytecode(CODE, color=False)
    check(p + "decompile_bytecode: sys.argv's flags", "verbose=1 explain=0 repr=1 returns=1" in d.text, d.text)
    d = m.decompile_bytecode(CODE, color=False, verbose=False)
    check(p + "decompile_bytecode: verbose=False over sys.argv", "verbose=0" in d.text, d.text)
    sys.argv = ["x", "--explain"]
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        d = m.decompile_bytecode(CODE, color=False)
    check(p + "decompile_bytecode: --explain printed and kept", out.getvalue().startswith("(stub) what --explain")
          and d.explain == out.getvalue() and "explain=1" in d.text, (out.getvalue(), d.explain))
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        d = m.decompile_bytecode(CODE, color=False, explain=0)
    check(p + "decompile_bytecode: explain=0 over sys.argv", out.getvalue() == "" and d.explain is None)
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        ok = raises(lambda: m.decompile_bytecode(FAIL, explain=True), RuntimeError, "decompilation failed")
    check(p + "decompile_bytecode: a failure, --explain printed first", ok and out.getvalue().startswith("(stub)"),
          out.getvalue())
    sys.argv = saved
    check(p + "decompile_bytecode: not code", raises(lambda: m.decompile_bytecode(None), TypeError))

    # decompile_address: from the node
    os.environ["WEB3_PROVIDER_URI"] = URL
    try:
        d = m.decompile_address(A1, threads=2, color=False)
        ref = m.decompile_bytecode(CODE, threads=2, color=False)
        check(p + "decompile_address", isinstance(d, D) and d.text == ref.text and d.asm == ref.asm and d.json == ref.json)
        check(p + "decompile_address: in capitals", m.decompile_address(A1.upper().replace("0X", "0x"),
              threads=2, color=False).text == ref.text)
        check(p + "decompile_address: no code", "# 0 bytes of code" in m.decompile_address(A2).text)
        check(p + "decompile_address: the node's error", raises(lambda: m.decompile_address(BOOM), ConnectionError, "boom"))
        check(p + "decompile_address: not an address", raises(lambda: m.decompile_address("0x12"), ConnectionError,
                                                              "not an address"))
        os.environ["WEB3_PROVIDER_URI"] = "https://example.com"
        check(p + "decompile_address: no TLS", raises(lambda: m.decompile_address(A1), ConnectionError, "no TLS"))
        os.environ["WEB3_PROVIDER_URI"] = "http://127.0.0.1:1"
        os.environ["WEB3_HTTP_PROVIDER_URI"] = "http://127.0.0.1:1"
        home = os.environ.get("HOME")
        os.environ["HOME"] = "/nonexistent"
        check(p + "decompile_address: no provider", raises(lambda: m.decompile_address(A1), ConnectionError,
              "Could not discover provider while making request: method:eth_getCode\nparams:('%s', 'latest')" % A1))
        if home is not None:
            os.environ["HOME"] = home
        check(p + "decompile_address: not a str", raises(lambda: m.decompile_address(5), TypeError))
    finally:
        os.environ.pop("WEB3_PROVIDER_URI", None)
        os.environ.pop("WEB3_HTTP_PROVIDER_URI", None)

    # disasm
    t = m.disasm(CODE)
    check(p + "disasm", t == DISASM and t == m.disasm(CODE.hex()), t)
    check(p + "disasm: not code", raises(lambda: m.disasm(1.5), TypeError))
    check(p + "disasm: two arguments", raises(lambda: m.disasm(CODE, CODE), TypeError))

    # set_log_level
    for level in (10, 20, 30, 40, 50, 0, 1000, True, "debug", "INFO", "Warning", "warn", "error", "critical", "fatal"):
        check(p + "set_log_level(%r)" % (level,), m.set_log_level(level) is None)
    check(p + "set_log_level: an unknown name", raises(lambda: m.set_log_level("verbose"), ValueError,
                                                        "unknown log level: verbose"))
    check(p + "set_log_level: not a level", raises(lambda: m.set_log_level(1.5), TypeError, "expected an int"))
    check(p + "set_log_level: too big", raises(lambda: m.set_log_level(2**80), OverflowError))
    m.set_log_level("error")

    # build_signature_db: a dump that isn't there
    check(p + "build_signature_db: no dump", raises(lambda: m.build_signature_db("/nonexistent/abi_dump.xz",
          os.path.join(BUILD, "never.bin")), RuntimeError, "building the signature database failed"))
    check(p + "build_signature_db: not a path", raises(lambda: m.build_signature_db(None), TypeError))

    # calls at once from threads (the GIL let go of)
    texts = []
    ts = [threading.Thread(target=lambda: texts.append(m.decompile(CODE, threads=1, color=False))) for _ in range(4)]
    for th in ts:
        th.start()
    for th in ts:
        th.join()
    check(p + "calls from threads", len(texts) == 4 and len(set(texts)) == 1)


cxx = load("panoramix_cxx", BUILD)
check("panoramix_cxx is built", cxx is not None, BUILD)
if cxx:
    surface(cxx, "panoramix_cxx")
    ctrl_c(cxx, "panoramix_cxx: ")
compat = load("panoramix_asm", os.path.join(BUILD, "compat")) if os.path.isdir(os.path.join(BUILD, "compat")) else None
check("compat/panoramix_asm is built", compat is not None)
if compat:
    surface(compat, "panoramix_asm")

# the asm's module, when it is there: the same functions (but its _test)
asm_dir = os.environ.get("PANASM_BUILD") or ASM_BUILD
asm = load("panoramix_asm", asm_dir) if os.path.isdir(asm_dir) else None
if asm and cxx:
    names = {n for n in dir(asm) if not n.startswith("_")}
    check("the asm's module's functions", names == {n for n in dir(cxx) if not n.startswith("_")}, sorted(names))
    for f in FUNCTIONS:
        check("the asm's %s's doc" % f, getattr(asm, f).__doc__ == getattr(cxx, f).__doc__)
    check("the asm's Decompilation's fields", [asm.Decompilation.n_sequence_fields, asm.Decompilation.n_fields,
          asm.Decompilation.__match_args__] == [cxx.Decompilation.n_sequence_fields, cxx.Decompilation.n_fields,
          cxx.Decompilation.__match_args__])
else:
    print("(no asm module at %s: not compared)" % asm_dir)

print("%d failures" % bad)
sys.exit(1 if bad else 0)
