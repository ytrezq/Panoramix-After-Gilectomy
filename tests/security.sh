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

# thread counts past what the arrays of a batch can be sized by: 8 times a
# count of 2^61 wrapped to a few bytes, and a negative one moved the arena's
# pointer back (it then zeroed 2^64 bytes). A huge count is capped (the
# text is the same at any count), a negative one is a usage error.
echo 6000356000556001600055 > "$tmp/threads.hex"
PANORAMIX_LOG=error timeout 60 "$PANASM" decompile "$tmp/threads.hex" --no-color \
    -j 4611686018427387904 > "$tmp/threads.out" 2>&1
rc=$?
if [ $rc -ne 0 ] || ! grep -q "Palkeoramix decompiler" "$tmp/threads.out"; then
    echo "FAIL threads_huge: rc=$rc"
    fail=1
else
    echo "ok   threads_huge"
fi
for j in -1 -4; do
    PANORAMIX_LOG=error timeout 60 "$PANASM" decompile "$tmp/threads.hex" --no-color \
        -j $j > /dev/null 2>&1
    rc=$?
    if [ $rc -ne 2 ]; then
        echo "FAIL threads_negative ($j): rc=$rc"
        fail=1
    else
        echo "ok   threads_negative ($j)"
    fi
done

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
    # a param's word at an offset of 4 + 32 * 2^32: get_param_name checked
    # the index on 32 bits and read 32 GiB past the params (a known
    # signature with inputs is all it takes - transfer(address,uint256))
    python3 - "$tmp" <<'EOF'
import lzma, sys
with lzma.open(sys.argv[1] + "/transfer.xz", "wt") as f:
    f.write('{"selector":"0xa9059cbb","abi":{"type":"function","name":"transfer",'
            '"inputs":[{"name":"recipient","type":"address"},'
            '{"name":"amount","type":"uint256"}]}}\n')
EOF
    PANORAMIX_LOG=error timeout 300 "$PANASM" build-db "$tmp/transfer.xz" "$tmp/transfer.bin" \
        > /dev/null 2>&1
    echo 60003560e01c8063a9059cbb146100165760006000fd5b6420000000043560005260206000f3 \
        > "$tmp/param_oob.hex"
    PANORAMIX_SIGDB="$tmp/transfer.bin" PANORAMIX_LOG=error timeout 60 \
        "$PANASM" decompile "$tmp/param_oob.hex" --no-color > "$tmp/param_oob.out" 2>&1
    rc=$?
    if crashed $rc || [ $rc -ne 0 ]; then
        echo "FAIL param_word_oob: rc=$rc"
        fail=1
    elif ! grep -q "def transfer(address recipient, uint256 amount)" "$tmp/param_oob.out"; then
        echo "FAIL param_word_oob: the signature was not used (the case tests nothing)"
        fail=1
    elif ! grep -q "return cd\[137438953476\]" "$tmp/param_oob.out"; then
        echo "FAIL param_word_oob: the word was not printed as python does"
        fail=1
    else
        echo "ok   param_word_oob"
    fi
else
    echo "skip dump cases (no xz or python3)"
fi

# the data of a return made of regions filled with zeroes: the printer
# concatenated the bytes of every term to test whether they are text,
# into builders that are malloc'd - outside the arena's limit, and the
# printing is past the watchdog. 170 bytes of contract took 153 MiB and
# 13 s (and the zeroes went in one sb_append_char each); the bytes it
# concatenates are capped now, and a data past the cap is printed term by
# term. Under 20 s and 192 MiB of RSS, with the limit set to 128.
for n in 8 32; do
    python3 - "$tmp" "$n" <<'EOF'
import sys
tmp, n = sys.argv[1], int(sys.argv[2])
# n regions of 2^24 zero bytes in memory, a marker between them, all
# returned: the data has a term per region, each Bytes(2^24, 0) - the
# bytes copied from past the calldata are known zeroes
SZ = 1 << 24
def push(v):
    b = v.to_bytes(max(1, (v.bit_length() + 7) // 8), "big")
    return "%02x%s" % (0x5f + len(b), b.hex())
code, off = "", 0
for i in range(n):
    code += push(1) + push(off) + "52"          # mstore(off, 1)
    off += 32
    code += push(SZ) + "36" + push(off) + "37"  # calldatacopy(off, size, SZ)
    off += SZ
code += push(1) + push(off) + "52"
off += 32
code += push(off) + push(0) + "f3"              # return(0, off)
open("%s/zeroes%d.hex" % (tmp, n), "w").write(code + "\n")
EOF
    s=$(date +%s)
    PANORAMIX_LOG=error PANORAMIX_MAX_MEMORY=128 timeout 40 "$PANASM" decompile \
        "$tmp/zeroes$n.hex" --no-color > "$tmp/zeroes$n.out" 2> "$tmp/zeroes$n.err"
    rc=$?
    e=$(date +%s)
    if crashed $rc || [ $rc -ne 0 ]; then
        echo "FAIL printer_zeroes_$n: rc=$rc"
        head -2 "$tmp/zeroes$n.err"
        fail=1
    elif [ $((e - s)) -gt 20 ]; then
        echo "FAIL printer_zeroes_$n: $((e - s)) s"
        fail=1
    else
        echo "ok   printer_zeroes_$n ($((e - s)) s)"
    fi
done

# the argument of the command line is the bytecode or an address before it
# is a path: a server running `panasm decompile <what it was sent>` opened
# whatever path it was given - a character device or a fifo read without
# end (/dev/zero aborted the process when malloc failed), and any local
# file of hex printed by `disasm`
PANORAMIX_LOG=error timeout 30 "$PANASM" decompile 6000,/dev/zero --no-color \
    > /dev/null 2> "$tmp/devzero.err"
rc=$?
if crashed $rc || ! grep -q "can't read the file" "$tmp/devzero.err"; then
    echo "FAIL arg_device: rc=$rc"
    head -2 "$tmp/devzero.err"
    fail=1
else
    echo "ok   arg_device"
fi
mkfifo "$tmp/fifo" 2> /dev/null
PANORAMIX_LOG=error timeout 20 "$PANASM" decompile "$tmp/fifo" --no-color \
    > /dev/null 2> "$tmp/fifo.err"
rc=$?
if [ $rc -eq 124 ]; then
    echo "FAIL arg_fifo: it waited for a writer"
    fail=1
else
    echo "ok   arg_fifo"
fi

# what came in is escaped and cut to an excerpt before it goes to stderr:
# bytecode on standard input starting with an escape drove the terminal
# (its title, its screen, forged lines), and 50 MB of it made 50 MB of
# stderr
printf '6001\033]0;pwned\007\033[2J\033[31mFORGED\033[0m' \
    | timeout 30 "$PANASM" decompile - --no-color > /dev/null 2> "$tmp/esc.err"
if grep -q $'\033' "$tmp/esc.err"; then
    echo "FAIL stdin_escapes: an escape sequence reached stderr"
    fail=1
elif [ "$(wc -c < "$tmp/esc.err")" -gt 400 ]; then
    echo "FAIL stdin_escapes: $(wc -c < "$tmp/esc.err") bytes of stderr"
    fail=1
else
    echo "ok   stdin_escapes"
fi
python3 -c "import sys; sys.stdout.write('zz' * 20000000)" \
    | timeout 60 "$PANASM" decompile - --no-color > /dev/null 2> "$tmp/long.err"
if [ "$(wc -c < "$tmp/long.err")" -gt 400 ]; then
    echo "FAIL stdin_excerpt: $(wc -c < "$tmp/long.err") bytes of stderr"
    fail=1
else
    echo "ok   stdin_excerpt"
fi

# the test interface: a literal nested past the stack's margin threw where
# nothing caught it (the context had no stack bounds, so every STACK_CHECK
# passed), and the hooks that take machine values read with them
if [ -f build/panoramix_asm.cpython-311-x86_64-linux-gnu.so ]; then
    out=$(PANORAMIX_LOG=error timeout 60 python3 -I -c "
import sys; sys.path.insert(0, 'build')
import panoramix_asm as m
for name, arg in (('roundtrip', '(' * 100000 + ')' * 100000),
                  ('dfa_step', '(100000000, 0)'), ('decode', '1'),
                  ('min_ifs', \"[('while',1,5,'jd',[])]\"),
                  ('cleanup_vars', \"[('setvar',)]\")):
    m._test(name, arg)
print('survived')
" 2>&1)
    rc=$?
    if crashed $rc || [ "$(echo "$out" | tail -1)" != "survived" ]; then
        echo "FAIL test_api: rc=$rc"
        echo "$out" | tail -2
        fail=1
    else
        echo "ok   test_api"
    fi
fi

exit $fail
