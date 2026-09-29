#!/bin/bash
# The inputs of the security review (docs/DESIGN.md, "Hostile input"):
# contracts and databases crafted to break the port, that must not
# corrupt memory, take the process down, or hang.
#
#   tests/security.sh [panasm]
#
# A line per case; exits 1 when one of them failed. The cases that used
# to crash are marked with what they were.
cd "$(dirname "$0")/.."
PANASM=${1:-build/panasm}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# crashed RC: killed by a signal (128 + the signal) or stopped by the
# timeout - as against a clean refusal, which returns -1 (255)
crashed() { [ "$1" = 124 ] || { [ "$1" -ge 128 ] && [ "$1" -le 160 ]; }; }

# case NAME HEX: decompiled without a crash (rc 0 and the header), in 60 s
case_hex() {
    local name=$1 hex=$2 rc
    echo "$hex" > "$tmp/$name.hex"
    PANORAMIX_LOG=error PANORAMIX_MAX_MEMORY=2048 \
        timeout 60 "$PANASM" decompile "$tmp/$name.hex" --no-color \
        > "$tmp/$name.out" 2> "$tmp/$name.err"
    rc=$?
    if [ $rc -ne 0 ] || ! grep -q "Palkeoramix decompiler" "$tmp/$name.out"; then
        echo "FAIL $name: rc=$rc"
        head -3 "$tmp/$name.err"
        fail=1
    else
        echo "ok   $name"
    fi
}

# CODECOPY of no bytes: code_bytes_value copied the whole code into one
# byte (the length 0 - 1, python's negative index of an empty range)
case_hex codecopy_empty 6000600060003900
case_hex codecopy_empty_stored 600060006000393360005560005160015500
# the same with the offset and the length in the other orders
case_hex codecopy_1_0 600060016000393360005500
case_hex codecopy_0_1 600160006000393360005500
# CODECOPY of the last byte, and past the end (the range is refused)
case_hex codecopy_end 6001600160003933600055600051600155
case_hex codecopy_past 60ff60ff60003900
# the other copies with no bytes
case_hex calldatacopy_empty 6000600060003700
case_hex returndatacopy_empty 6000600060003e00
case_hex extcodecopy_empty 60006000600060003c00

# a string constant with the bytes that end a line: the text stays one
# line per line of the trace (the quotes are python's)
printf '7f0a0a0a6465662070776e656428293a0a20207265766572740a0a0a0a0a600055\n' > "$tmp/lines.hex"
n=$(PANORAMIX_LOG=error timeout 60 "$PANASM" decompile "$tmp/lines.hex" --no-color 2>/dev/null \
    | grep -c "^def pwned")
if [ "$n" != 0 ]; then
    echo "FAIL forged_lines: $n line(s) forged by a constant"
    fail=1
else
    echo "ok   forged_lines"
fi

# an address the fetcher formats (43 bytes in its frame: it wrote three
# past it); no provider, so it fails to reach one and says so
out=$(WEB3_PROVIDER_URI=http://127.0.0.1:1 PANORAMIX_LOG=error timeout 60 \
    "$PANASM" decompile 0xdAC17F958D2ee523a2206206994597C13D831ec7 2>&1)
rc=$?
if crashed $rc; then
    echo "FAIL fetch_address: rc=$rc"
    echo "$out" | tail -2
    fail=1
else
    echo "ok   fetch_address"
fi

# a node that answers with terminal escape sequences: its text ends up on
# a terminal, so it is escaped (the contract's own constants can't hold
# ESC - pretty_bignum takes only printable bytes - but a node's answer is
# bytes from the network)
if command -v python3 > /dev/null; then
    python3 - "$tmp" <<'EOF' &
import http.server, sys, threading, time
RAW = (b'{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":'
       b'"\x1b]0;pwned\x07\x1b[2J\x1b[31mGOTCHA\x1b[0m\r\nfake"}}')
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(200)
        self.send_header('Content-Length', str(len(RAW)))
        self.end_headers()
        self.wfile.write(RAW)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(('127.0.0.1', 8601), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
time.sleep(30)
EOF
    node=$!
    sleep 2
    WEB3_PROVIDER_URI=http://127.0.0.1:8601 PANORAMIX_LOG=error timeout 30 \
        "$PANASM" decompile 0xdAC17F958D2ee523a2206206994597C13D831ec7 \
        > "$tmp/node.out" 2>&1
    rc=$?
    kill $node 2> /dev/null
    if crashed $rc; then
        echo "FAIL node_escapes: rc=$rc"
        fail=1
    elif grep -q $'\x1b' "$tmp/node.out"; then
        echo "FAIL node_escapes: an escape sequence of the node's reached the output"
        fail=1
    else
        echo "ok   node_escapes"
    fi
fi

# the signature dump: a string bigger than the blob it is put in (it was
# grown once, not until the string fits), and values nested deeper than
# the stack (js_skip recurses)
if command -v xz > /dev/null && command -v python3 > /dev/null; then
    python3 - "$tmp" <<'EOF'
import lzma, sys
tmp = sys.argv[1]
big = '{"selector":"0x12345678","abi":{"name":"%s","inputs":[]}}\n' % ("A" * (34 << 20))
with lzma.open(tmp + "/big.xz", "wt") as f:
    f.write(big)
deep = '{"selector":"0x12345678","abi":{"name":"a","inputs":[],"x":%s%s}}\n' % (
    "[" * 400000, "]" * 400000)
with lzma.open(tmp + "/deep.xz", "wt") as f:
    f.write(deep)
EOF
    for d in big deep; do
        PANORAMIX_LOG=error timeout 300 "$PANASM" build-db "$tmp/$d.xz" "$tmp/$d.bin" \
            > "$tmp/$d.out" 2>&1
        rc=$?
        # (either built, or refused with a message: never killed by a
        # signal - a crash - nor stuck until the timeout)
        if crashed $rc; then
            echo "FAIL dump_$d: rc=$rc"
            tail -2 "$tmp/$d.out"
            fail=1
        else
            echo "ok   dump_$d (rc=$rc)"
        fi
    done
    # the database written where a link was planted: it is not followed
    ln -s "$tmp/planted" "$tmp/db.bin.$$.tmp" 2> /dev/null
    PANORAMIX_LOG=error timeout 300 "$PANASM" build-db "$tmp/deep.xz" "$tmp/db.bin" \
        > "$tmp/link.out" 2>&1
    if [ -e "$tmp/planted" ]; then
        echo "FAIL tmp_symlink: the planted file was written"
        fail=1
    else
        echo "ok   tmp_symlink"
    fi
else
    echo "skip dump cases (no xz or python3)"
fi

exit $fail
