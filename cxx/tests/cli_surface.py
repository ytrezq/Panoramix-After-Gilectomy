#!/usr/bin/env python3
"""pancxx's command line against the core's stub (src/decompile_stub.cpp:
placeholder text saying what it was given - the code's size and FNV-1a, the
options): its inputs (hex, files, standard input, lists, addresses fetched
from a node of our own over HTTP - plain and chunked - and IPC, found as
web3 finds it), its options, messages and exit codes; the hostile inputs of
the asm's tests/security.sh; and, when the asm's panasm is there, the same
exit codes and messages as it for the same arguments.

    tests/cli_surface.py BUILD_DIR
"""
import atexit, http.server, json, os, shutil, socketserver, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "build")
PANCXX = os.path.join(BUILD, "pancxx")
PANASM = os.environ.get("PANASM") or os.path.join(HERE, "..", "..", "build", "panasm")

bad = 0


def check(name, ok, detail=""):
    global bad
    if not ok:
        bad += 1
        print("FAIL", name, str(detail)[:800], flush=True)
    else:
        print("ok  ", name, flush=True)


def fnv1a64(code):
    h = 0xcbf29ce484222325
    for b in code:
        h = ((h ^ b) * 0x100000001b3) & (2**64 - 1)
    return "%016x" % h


def stub_says(code):
    """what the stub's text says of the code"""
    return "# %d bytes of code, fnv1a64 %s\n" % (len(code), fnv1a64(code))


tmp = tempfile.mkdtemp()
atexit.register(shutil.rmtree, tmp, True)
EMPTY_HOME = os.path.join(tmp, "empty")
os.makedirs(EMPTY_HOME)


def env(**kw):
    e = {k: v for k, v in os.environ.items() if not k.startswith("WEB3_")}
    e.update(HOME=EMPTY_HOME, PANORAMIX_LOG="error")
    e.update(kw)
    return e


def run(args, e=None, stdin=b"", program=PANCXX, timeout=120):
    p = subprocess.run([program] + args, input=stdin, capture_output=True, env=e or env(), timeout=timeout)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


# --- a node of our own: eth_getCode over HTTP and over an IPC socket ---------

CODE1 = bytes.fromhex("6080604052348015600f57600080fd5b50")
CODE2 = bytes.fromhex("60016000556002600155")
ADDRS = {
    "0x00000000000000000000000000000000000000a1": CODE1.hex(),
    "0x00000000000000000000000000000000000000a2": CODE2.hex(),
    "0x00000000000000000000000000000000000000a3": "",
}
A1, A2, A3 = list(ADDRS)
BOOM = "0x00000000000000000000000000000000000000e1"
ESC = "0x00000000000000000000000000000000000000e2"   # an answer with terminal escapes


def answer(req):
    m, params, rid = req.get("method"), req.get("params") or [], req.get("id")
    if m == "eth_getCode":
        a = params[0].lower()
        if a == BOOM:
            return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32000, "message": "boom"}}
        return {"jsonrpc": "2.0", "id": rid, "result": "0x" + ADDRS.get(a, "")}
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "no such method"}}


class Http(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path.startswith("/404"):
            self.send_response(404, "Not Found")
            self.end_headers()
            return
        if req["params"][0].lower() == ESC:
            out = (b'{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":'
                   b'"\x1b]0;pwned\x07\x1b[2J\x1b[31mGOTCHA\x1b[0m\r\nfake"}}')
        else:
            out = json.dumps(answer(req)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if self.path.startswith("/chunked"):
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for i in range(0, len(out), 7):
                part = out[i:i + 7]
                self.wfile.write(b"%x\r\n%s\r\n" % (len(part), part))
            self.wfile.write(b"0\r\n\r\n")
        else:
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)

    def log_message(self, *a):
        pass


class Ipc(socketserver.StreamRequestHandler):
    def handle(self):
        # geth's way: the answers as the requests come, the connection kept;
        # the answer sent in pieces, a moment apart
        buf = b""
        dec = json.JSONDecoder()
        while True:
            data = self.request.recv(65536)
            if not data:
                return
            buf += data
            try:
                req, end = dec.raw_decode(buf.decode())
            except ValueError:
                continue
            buf = buf[end:].lstrip()
            out = json.dumps(answer(req)).encode()
            self.request.sendall(out[:5])
            time.sleep(0.05)
            self.request.sendall(out[5:])


class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Http)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d" % httpd.server_address[1]
HOME = os.path.join(tmp, "home")   # with geth's IPC socket
os.makedirs(os.path.join(HOME, ".ethereum"))
IPC = os.path.join(HOME, ".ethereum", "geth.ipc")
ipcd = UnixServer(IPC, Ipc)
threading.Thread(target=ipcd.serve_forever, daemon=True).start()

# --- the command line -----------------------------------------------------------

USAGE = ("usage: pancxx disasm <file.hex|->\n"
         "       pancxx decode <file.hex|-|address|bytecode>\n"
         "       pancxx decompile <file.hex|-|address|bytecode>[,...] [-j threads] [--function name]\n"
         "                        [--no-color] [--json] [-v level] [--verbose] [--explain] [--repr] [--returns]\n"
         "       pancxx build-db <abi_dump.xz> [out.bin]\n"
         "       pancxx --version\n")
LEVEL = "Logging should be DEBUG/INFO/WARNING/ERROR.\n"

for args in ([], ["decompile"], ["build-db"], ["foo", "x"], ["decompile", "6000", "--bad"],
             ["decompile", "6000", "-j"], ["decompile", "6000", "-j", "-1"], ["decompile", "6000", "--function"]):
    rc, out, err = run(args)
    check("usage: %s" % args, rc == 2 and err == USAGE and not out, (rc, err))
for args in (["decompile", "6000", "-v", "bogus"], ["foo", "x", "-v", "bogus"], ["decompile", "6000", "-v", ""]):
    rc, out, err = run(args)
    check("bad level: %s" % args, rc == 1 and err == LEVEL and not out, (rc, err))
rc, out, err = run(["--version"])
check("--version", rc == 0 and out.startswith("pancxx ") and len(out.splitlines()) == 2, out)

H = CODE1.hex()
rc, out, err = run(["decompile", H, "--no-color", "-j", "2"])
check("decompile HEX", rc == 0 and stub_says(CODE1) in out and "threads=2" in out and out.endswith("\n")
      and "\x1b" not in out, (rc, out, err))
rc, out2, err = run(["decompile", "0x" + H.upper(), "--no-color", "-j", "2"])
check("decompile 0xHEX", out2 == out, out2)
rc, out, err = run(["decompile", H])
check("decompile: colors by default", rc == 0 and "\x1b[" in out and "threads=0 function='' color=1" in out, out)
rc, out, err = run(["decompile", H, "--no-color", "--function", "trans", "-j", "0", "--verbose", "--repr", "--returns"])
check("decompile: the options reach the core",
      "threads=1 function='trans' color=0 verbose=1 explain=0 repr=1 returns=1 json=0" in out, out)
rc, out, err = run(["decompile", H, "--json"])
check("--json", rc == 0 and json.loads(out)["bytes"] == len(CODE1) and out.endswith("}\n"), out)
rc, out, err = run(["decompile", H, "--explain", "--no-color"])
check("--explain: its text first", rc == 0 and out.startswith("(stub) what --explain prints")
      and stub_says(CODE1) in out and "verbose=1 explain=1" in out, out)
rc, out, err = run(["decompile", "deadbeef", "--explain", "--no-color"])
check("a failure: --explain's text, the message, 1", rc == 1 and out.startswith("(stub) what --explain")
      and err == "decompilation failed: (stub) the code asked for a failure\n", (rc, out, err))

f = os.path.join(tmp, "c.hex")
open(f, "w").write("0x" + H[:10] + "\n" + H[10:] + "\n")
rc, out, err = run(["decompile", f, "--no-color"])
check("a file", rc == 0 and stub_says(CODE1) in out, (rc, out, err))
rc, out, err = run(["decompile", "-", "--no-color"], stdin=("  0x%s \n" % H).encode())
check("standard input", rc == 0 and stub_says(CODE1) in out, (rc, out, err))
rc, out, err = run(["decompile", "-", "--no-color"])
check("standard input, empty", rc == 0 and stub_says(b"") in out, (rc, out, err))
rc, out, err = run(["disasm", f])
check("disasm", rc == 0 and out.startswith("0x0, push1, 0x80\n") and "0xf, jumpdest, \n" in out, (rc, out, err))
rc, out, err = run(["decode", "0x" + H])
check("decode", rc == 0 and "%d bytes of code" % len(CODE1) in out, (rc, out, err))
rc, out, err = run(["decompile", "%s,nothing,0x%s" % (H, CODE2.hex()), "--no-color"])
check("a list with a bad input", rc == 1 and out.count("Palkeoramix") == 2 and stub_says(CODE1) in out
      and stub_says(CODE2) in out and err == "can't read the file: nothing\n", (rc, out, err))
fc = os.path.join(tmp, "a,b.hex")
open(fc, "w").write(H)
rc, out, err = run(["decompile", fc, "--no-color"])
check("a file named with a comma", rc == 0 and out.count("Palkeoramix") == 1 and stub_says(CODE1) in out, (rc, err))
fb = os.path.join(tmp, "bad.hex")
open(fb, "w").write("60zz")
rc, out, err = run(["decompile", fb])
check("not a valid hex file", rc == 1 and err == "not a valid hex file: %s\n" % fb, err)
rc, out, err = run(["disasm", "600"])
check("odd hex", rc == 1 and err == "not a valid hex file: 600\n", err)
rc, out, err = run(["decompile", "nothing"])
check("can't read the file", rc == 1 and err == "can't read the file: nothing\n", err)
rc, out, err = run(["decompile", "6000,/dev/zero"], timeout=30)
check("/dev/zero isn't read", rc == 1 and "can't read the file: /dev/zero" in err, err)
fifo = os.path.join(tmp, "fifo")
os.mkfifo(fifo)
rc, out, err = run(["decompile", fifo], timeout=20)
check("a fifo isn't waited for", rc == 1 and "can't read the file" in err, err)

# what comes in is escaped and cut to an excerpt before it goes to stderr
rc, out, err = run(["decompile", "-", "--no-color"], stdin=b"6001\x1b]0;pwned\x07\x1b[2J\x1b[31mFORGED\x1b[0m")
check("stdin's escapes", rc == 1 and "\x1b" not in err and len(err) < 400 and err.startswith("not a valid hex file: 6001\\x1b"),
      err)
rc, out, err = run(["decompile", "-", "--no-color"], stdin=b"zz" * 20000000)
check("stdin's excerpt", rc == 1 and len(err) < 400, len(err))
long_dir = os.path.join(tmp, "d" * 150, "e" * 150)
os.makedirs(long_dir)
open(os.path.join(long_dir, "bad.hex"), "w").write("60zz")
rc, out, err = run(["decompile", os.path.join(long_dir, "bad.hex")])
check("a long path whole in the message", os.path.join(long_dir, "bad.hex") in err, err)

# standard input that is O_NONBLOCK: a pipe that runs dry isn't the end
r, w = os.pipe()
os.write(w, H[:12].encode())
os.set_blocking(r, False)
p = subprocess.Popen([PANCXX, "disasm", "-"], stdin=r, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env())
os.close(r)
time.sleep(0.5)
os.write(w, H[12:].encode())
os.close(w)
check("stdin non-blocking", p.communicate(timeout=60)[0].decode() == run(["disasm", H])[1])

# standard input past 256 MiB: refused, not cut
p = subprocess.Popen([PANCXX, "disasm", "-"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                     stderr=subprocess.PIPE, env=env())
chunk = b"0" * (1 << 20)
try:
    for i in range(258):
        p.stdin.write(chunk)
    p.stdin.close()
except BrokenPipeError:
    pass
err = p.stderr.read().decode()
p.wait(timeout=120)
check("stdin too long", p.returncode == 1 and err == "the standard input is longer than 256 MiB\n", err)

# --- the fetch --------------------------------------------------------------------

text_of = {a: run(["decompile", c or "-", "--no-color", "-j", "2"])[1] for a, c in ADDRS.items()}
for name, e in [("http", env(WEB3_PROVIDER_URI=URL)),
                ("http, a path", env(WEB3_PROVIDER_URI=URL + "/some/path?x=1")),
                ("http, chunked", env(WEB3_PROVIDER_URI=URL + "/chunked")),
                ("http, userinfo and the host by name",
                 env(WEB3_PROVIDER_URI="http://u:p@localhost:%d/" % httpd.server_address[1])),
                ("ipc, file://", env(WEB3_PROVIDER_URI="file://" + IPC)),
                ("ipc, the default place", env(HOME=HOME)),
                ("ipc, the provider of the environment unreachable", env(HOME=HOME, WEB3_PROVIDER_URI="http://127.0.0.1:1")),
                ("http, WEB3_HTTP_PROVIDER_URI", env(WEB3_HTTP_PROVIDER_URI=URL))]:
    rc, out, err = run(["decompile", A1, "--no-color", "-j", "2"], e)
    check("fetch: " + name, rc == 0 and out == text_of[A1] and stub_says(CODE1) in out, (rc, err, out))
rc, out, err = run(["decompile", "%s,%s,%s" % (A1, A2, A3), "--no-color", "-j", "2"], env(WEB3_PROVIDER_URI=URL))
check("fetch: a list", rc == 0 and out == text_of[A1] + text_of[A2] + text_of[A3], err)
rc, out, err = run(["decompile", A1.upper().replace("0X", "0x"), "--no-color", "-j", "2"], env(WEB3_PROVIDER_URI=URL))
check("fetch: an address in capitals", rc == 0 and out == text_of[A1], err)
rc, out, err = run(["decompile", "-", "--no-color", "-j", "2"], env(WEB3_PROVIDER_URI=URL), stdin=("  %s\n" % A2).encode())
check("fetch: an address on stdin", rc == 0 and out == text_of[A2], err)
rc, out, err = run(["decompile", A1, "--no-color"], env(WEB3_PROVIDER_URI=URL, PANORAMIX_LOG="info"))
check("fetch: the log line", "panoramix.loader[" in err and "INFO Fetching code for %s..." % A1 in err, err)
rc, out, err = run(["decompile", A1, "--no-color", "-v", "debug"], env(WEB3_PROVIDER_URI=URL))
check("fetch: -v debug, the code logged", "DEBUG Code: 0x%s" % CODE1.hex() in err, err)
rc, out, err = run(["disasm", A2], env(WEB3_PROVIDER_URI=URL))
check("fetch: disasm ADDRESS", rc == 0 and out.startswith("0x0, push1, 0x1\n0x2, push1, 0x0\n0x4, sstore, \n"), (rc, out, err))
rc, out, err = run(["decompile", BOOM], env(WEB3_PROVIDER_URI=URL))
check("fetch: the node's error", rc == 1 and not out
      and err == 'the node answered an error: {"code": -32000, "message": "boom"}\n', err)
rc, out, err = run(["decompile", A1], env(WEB3_PROVIDER_URI=URL + "/404"))
check("fetch: an HTTP error", rc == 1 and err == "404 Client Error: Not Found for url: %s/404\n" % URL, err)
rc, out, err = run(["decompile", A1], env(WEB3_PROVIDER_URI="http://127.0.0.1:1", WEB3_HTTP_PROVIDER_URI="http://127.0.0.1:1"))
check("fetch: no provider", rc == 1 and err == "Could not discover provider while making request: method:eth_getCode\n"
      "params:('%s', 'latest')\n" % A1, err)
rc, out, err = run(["decompile", A1], env(WEB3_PROVIDER_URI="https://example.com"))
check("fetch: https", rc == 1 and "no TLS" in err, err)
rc, out, err = run(["decompile", A1], env(WEB3_PROVIDER_URI="gopher://x"))
check("fetch: an unknown scheme", rc == 1 and err == "Web3 does not know how to connect to scheme 'gopher' in 'gopher://x'\n",
      err)
rc, out, err = run(["decompile", "0x" + "g" * 40], env(WEB3_PROVIDER_URI=URL))
check("fetch: not an address", rc == 1 and err == "not an address (0x and 40 hex digits): 0x%s\n" % ("g" * 40), err)
rc, out, err = run(["decompile", "%s,nothing,%s" % (A1, A2), "--no-color", "-j", "2"], env(WEB3_PROVIDER_URI=URL))
check("fetch: a list with a bad input", rc == 1 and out == text_of[A1] + text_of[A2]
      and "can't read the file: nothing" in err, err)
rc, out, err = run(["decompile", ESC], env(WEB3_PROVIDER_URI=URL))
check("fetch: a node's escapes", rc == 1 and "\x1b" not in out + err and "GOTCHA" in err, err)

# --- the same as the asm's panasm ---------------------------------------------------

if os.access(PANASM, os.X_OK):
    def same(name, args, e=None, stdin=b""):
        a = run(args, e, stdin, program=PANASM)
        c = run(args, e, stdin)
        asm_err = a[2].replace("panasm", "pancxx")
        check("as panasm: " + name, a[0] == c[0] and asm_err == c[2], "\n   asm:  %r\n   cxx:  %r" % ((a[0], asm_err),
                                                                                                    (c[0], c[2])))

    for args in ([], ["decompile"], ["build-db"], ["foo", "x"], ["foo", "x", "--bad", "-v", "bogus"],
                 ["decompile", "6000", "-j", "-1"], ["decompile", "6000", "-j"], ["decompile", "6000", "--function"],
                 ["decompile", "6000", "--threads", "-4"]):
        a = run(args, program=PANASM)
        check("as panasm: usage %s" % args, a[0] == 2 == run(args)[0], a)
    for args in (["decompile", "nothing"], ["decompile", "60zz"], ["decompile", "0x"], ["disasm", "600"],
                 ["decompile", "6000", "-v", "bogus"], ["foo", "x", "-v", "bogus"], ["decompile", "6000", "-v", " 1"],
                 ["decompile", "6000,nothing"], ["decompile", ","], ["decompile", fb], ["decode", fb],
                 ["decompile", "0x" + "g" * 40], ["decompile", os.path.join(long_dir, "bad.hex")]):
        same(" ".join(args)[:60], args)
    same("stdin's escapes", ["decompile", "-"], stdin=b"6001\x1b]0;pwned\x07\x1b[2J\x1b[31mFORGED\x1b[0m")
    same("stdin, not an address", ["decompile", "-"], stdin=("  0x%s\n" % ("g" * 40)).encode())
    for name, e, args in [
            ("no provider", env(WEB3_PROVIDER_URI="http://127.0.0.1:1", WEB3_HTTP_PROVIDER_URI="http://127.0.0.1:1"), [A1]),
            ("https", env(WEB3_PROVIDER_URI="https://example.com"), [A1]),
            ("wss", env(WEB3_HTTP_PROVIDER_URI="wss://example.com"), [A1]),
            ("gopher", env(WEB3_PROVIDER_URI="gopher://x"), [A1]),
            ("a scheme without ':'", env(WEB3_PROVIDER_URI="nothing"), [A1]),
            ("404", env(WEB3_PROVIDER_URI=URL + "/404"), [A1]),
            ("the node's error", env(WEB3_PROVIDER_URI=URL), [BOOM]),
            ("the node's escapes", env(WEB3_PROVIDER_URI=URL), [ESC]),
            ("a list of addresses, one bad", env(WEB3_PROVIDER_URI=URL), ["%s,nothing,%s" % (A1, BOOM)])]:
        same("fetch, " + name, ["decompile"] + args + ["--no-color"], e)
    for args in (["decompile", H, "-j", "abc"], ["decompile", H, "-v", "20x"], ["decompile", H, "--function", "--json"],
                 ["decode", "-"], ["decompile", "-"]):
        check("as panasm: rc of %s" % args, run(args, program=PANASM)[0] == run(args)[0] == 0)
else:
    print("(no asm's panasm at %s: not compared)" % PANASM)

print("%d failures" % bad)
sys.exit(1 if bad else 0)
