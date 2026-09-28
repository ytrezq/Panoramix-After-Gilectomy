#!/usr/bin/env python3
"""python's decompile_address: the code of an address, fetched from a node
(web3's automatic provider), then decompiled - against a node of our own
answering eth_getCode with contracts of the corpus, over HTTP (plain and
chunked) and over an IPC socket (found by $WEB3_PROVIDER_URI, by the
default places, by $WEB3_HTTP_PROVIDER_URI). `panasm decompile ADDRESS`
must give the text of the contract's file, the module's
decompile_address its decompile_bytecode, and `python -m panoramix
ADDRESS` (when the python implementation is there) the same text; the
node's errors, a provider that can't be reached, TLS, come back as
messages.

    tests/test_fetch.py
"""
import http.server, json, os, re, socketserver, subprocess, sys, tempfile, threading, time
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BUILD = os.environ.get("PANASM_BUILD") or os.path.join(ROOT, "build")
sys.path.insert(0, BUILD)
import panoramix_asm as A
A.set_log_level("error")

PANASM = os.path.join(BUILD, "panasm")
CORPUS = os.path.join(HERE, "corpus")
PY_REPO = os.environ.get("PANORAMIX_PY") or os.path.join(ROOT, "..", "panoramix")
PY = os.path.join(PY_REPO, ".venv", "bin", "python")

def code_of(name):
    return open(os.path.join(CORPUS, name + ".hex")).read().strip().removeprefix("0x")

ADDRS = {
    "0x00000000000000000000000000000000000000a1": code_of("WETH"),
    "0x00000000000000000000000000000000000000a2": code_of("Multicall3"),
    "0x00000000000000000000000000000000000000a3": "",           # no code
}
BOOM = "0x00000000000000000000000000000000000000e1"                # an error

def answer(req):
    m, params, rid = req.get("method"), req.get("params") or [], req.get("id")
    if m == "web3_clientVersion":
        return {"jsonrpc": "2.0", "id": rid, "result": "mock/1.0"}
    if m == "eth_getCode":
        a = params[0].lower()
        if a == BOOM:
            return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32000, "message": "boom"}}
        return {"jsonrpc": "2.0", "id": rid, "result": "0x" + ADDRS.get(a, "")}
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "no such method"}}

class Http(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.startswith("/404"):
            self.send_response(404, "Not Found")
            self.end_headers()
            return
        out = json.dumps(answer(json.loads(body))).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if self.path.startswith("/chunked"):
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for i in range(0, len(out), 1000):
                part = out[i:i + 1000]
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
        # geth's way: the answers as the requests come, the connection kept
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
            self.request.sendall(json.dumps(answer(req)).encode())

class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

tmp = tempfile.mkdtemp()
httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Http)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
PORT = httpd.server_address[1]
HOME = os.path.join(tmp, "home")                 # with geth's IPC socket
os.makedirs(os.path.join(HOME, ".ethereum"))
IPC = os.path.join(HOME, ".ethereum", "geth.ipc")
ipcd = UnixServer(IPC, Ipc)
threading.Thread(target=ipcd.serve_forever, daemon=True).start()
EMPTY_HOME = os.path.join(tmp, "empty")
os.makedirs(EMPTY_HOME)

CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")

def env(**kw):
    # (HOME elsewhere, without IPC socket unless asked; the signature
    # databases where they are)
    e = {k: v for k, v in os.environ.items() if not k.startswith("WEB3_")}
    e.update(HOME=EMPTY_HOME, XDG_CACHE_HOME=CACHE, PANORAMIX_LOG="error")
    e.update(kw)
    return e

def panasm(arg, e, *opts):
    p = subprocess.run([PANASM, "decompile", arg, "--no-color", "-j", "2"] + list(opts),
                       capture_output=True, env=e, timeout=600)
    return p.returncode, p.stdout.decode(), p.stderr.decode()

expected = {}
def text_of(addr):
    if addr not in expected:
        p = subprocess.run([PANASM, "decompile", ADDRS[addr] or "-", "--no-color", "-j", "2"],
                           capture_output=True, input=b"", env=env(), timeout=600)
        expected[addr] = p.stdout.decode()
    return expected[addr]

bad = 0
def check(name, ok, detail=""):
    global bad
    if ok:
        print("ok  ", name, flush=True)
    else:
        bad += 1
        print("FAIL", name, detail[:600], flush=True)

A1, A2, A3 = list(ADDRS)
URL = f"http://127.0.0.1:{PORT}"
for name, e in [("http", env(WEB3_PROVIDER_URI=URL)),
                ("http, a path", env(WEB3_PROVIDER_URI=URL + "/some/path?x=1")),
                ("http, chunked", env(WEB3_PROVIDER_URI=URL + "/chunked")),
                ("http, userinfo and the host by name", env(WEB3_PROVIDER_URI=f"http://u:p@localhost:{PORT}/")),
                ("ipc, file://", env(WEB3_PROVIDER_URI="file://" + IPC)),
                ("ipc, the default place", env(HOME=HOME)),
                ("ipc, the provider of the environment unreachable", env(HOME=HOME, WEB3_PROVIDER_URI="http://127.0.0.1:1")),
                ("http, WEB3_HTTP_PROVIDER_URI", env(WEB3_HTTP_PROVIDER_URI=URL))]:
    rc, out, err = panasm(A1, e)
    check(name, rc == 0 and out == text_of(A1), err + out[:300])
rc, out, err = panasm(f"{A1},{A2},{A3}", env(WEB3_PROVIDER_URI=URL))
check("a list", rc == 0 and out == text_of(A1) + text_of(A2) + text_of(A3), err)
rc, out, err = panasm(A1.upper().replace("0X", "0x"), env(WEB3_PROVIDER_URI=URL))
check("an address in capitals", rc == 0 and out == text_of(A1), err)
p = subprocess.run([PANASM, "decompile", "-", "--no-color", "-j", "2"], input=f"  {A2}\n".encode(),
                   capture_output=True, env=env(WEB3_PROVIDER_URI=URL), timeout=600)
check("an address on stdin", p.returncode == 0 and p.stdout.decode() == text_of(A2), p.stderr.decode())
rc, out, err = panasm(A1, env(WEB3_PROVIDER_URI=URL, PANORAMIX_LOG="info"))
check("the log line", f"panoramix.loader[" in err and f"INFO Fetching code for {A1}..." in err, err)
rc, out, err = panasm(BOOM, env(WEB3_PROVIDER_URI=URL))
check("the node's error", rc == 1 and "boom" in err and not out, err)
rc, out, err = panasm(A1, env(WEB3_PROVIDER_URI=URL + "/404"))
check("an HTTP error", rc == 1 and f"404 Client Error: Not Found for url: {URL}/404" in err, err)
rc, out, err = panasm(A1, env(WEB3_HTTP_PROVIDER_URI="http://127.0.0.1:1"))
check("no provider", rc == 1 and err.startswith("Could not discover provider while making request: method:eth_getCode\n"), err)
rc, out, err = panasm(A1, env(WEB3_PROVIDER_URI="https://example.com"))
check("https", rc == 1 and "no TLS" in err, err)
rc, out, err = panasm(A1, env(WEB3_PROVIDER_URI="gopher://x"))
check("an unknown scheme", rc == 1 and "Web3 does not know how to connect to scheme 'gopher' in 'gopher://x'" in err, err)
rc, out, err = panasm("0x" + "g" * 40, env(WEB3_PROVIDER_URI=URL))
check("not an address", rc == 1 and "not an address" in err, err)
rc, out, err = panasm(f"{A1},nothing,{A2}", env(WEB3_PROVIDER_URI=URL))
check("a list with a bad input", rc == 1 and out == text_of(A1) + text_of(A2) and "can't read the file: nothing" in err, err)

# the module
os.environ["WEB3_PROVIDER_URI"] = URL
d = A.decompile_address(A2, threads=2, color=False)
ref = A.decompile_bytecode(ADDRS[A2], threads=2, color=False)
check("decompile_address", d.text == ref.text and d.asm == ref.asm and d.json == ref.json)
try:
    A.decompile_address(BOOM)
    check("decompile_address, the node's error", False, "no exception")
except Exception as ex:
    check("decompile_address, the node's error", "boom" in str(ex), repr(ex))
del os.environ["WEB3_PROVIDER_URI"]

# python's, through the same node
if os.path.exists(PY):
    for addr in (A1, A2):
        for attempt in range(10):       # (the database's lock, taken by another python)
            p = subprocess.run([PY, "-m", "panoramix", addr, "-v", "ERROR"], capture_output=True,
                               env=env(WEB3_PROVIDER_URI=URL), cwd=PY_REPO, timeout=1800)
            if b"Resource temporarily unavailable" not in p.stderr:
                break
            time.sleep(3)
        out = re.sub(r"\x1b\[[0-9;]*m", "", p.stdout.decode())
        check("python -m panoramix " + addr, p.returncode == 0 and out == text_of(addr), p.stderr.decode()[-600:])
else:
    print("(no python implementation at", PY_REPO + ": skipped)")
print(f"{bad} failures")
sys.exit(1 if bad else 0)
