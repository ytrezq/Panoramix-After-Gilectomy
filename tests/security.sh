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

# --- the third review: the seams between components (an input that one
# part takes as valid and another one breaks on) ---

# --explain prints the traces between the rounds of the simplification:
# its names record, made in the arena, was read after the round's
# compaction gave the arena back (a SIGSEGV)
PANORAMIX_LOG=error PANORAMIX_COMPACT_MIB=1 PANORAMIX_TIMEOUT=0 timeout 60 "$PANASM" \
    decompile tests/corpus/ChainlinkETHUSD.hex --no-color --explain -j 1 > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FAIL explain_compaction: rc=$rc"
    fail=1
else
    echo "ok   explain_compaction"
fi

# a list of contracts on the command line: each was limited after what the
# ones before it had taken (one context for them all, whose arena gives
# nothing back) - the same contract nine times, three texts
L=tests/corpus/OneInchV5.hex; for i in 1 2 3 4 5 6 7 8; do L="$L,tests/corpus/OneInchV5.hex"; done
PANORAMIX_LOG=critical PANORAMIX_MAX_MEMORY=64 timeout 120 "$PANASM" decompile "$L" \
    --no-color -j 1 > "$tmp/list.out" 2> /dev/null
n=$(grep -c "Palkeoramix decompiler" "$tmp/list.out")
if [ "$n" != 9 ]; then
    echo "FAIL list_one_context: $n texts of 9"
    fail=1
else
    echo "ok   list_one_context"
fi

# the limit of the contract phase: one limit shared by the imports, the
# post-processing and the text - a contract fit at 18 and 26 MiB and came
# out with no text at all at 21 to 24; and the fallback of a discovery that
# ran out (the half of it) threw for its 48 bytes
for mm in 21 22 24; do
    PANORAMIX_LOG=critical PANORAMIX_MAX_MEMORY=$mm timeout 60 "$PANASM" decompile \
        tests/corpus/OneInchV5.hex --no-color -j 1 > "$tmp/mono$mm.out" 2> /dev/null
    rc=$?
    if [ $rc -ne 0 ] || [ "$(grep -c '^def ' "$tmp/mono$mm.out")" -lt 50 ]; then
        echo "FAIL limit_monotonic_$mm: rc=$rc"
        fail=1
    else
        echo "ok   limit_monotonic_$mm"
    fi
done
PANORAMIX_LOG=critical PANORAMIX_MAX_MEMORY=16 timeout 60 "$PANASM" decompile \
    tests/corpus/cETH.hex --no-color -j 1 > "$tmp/fallback.out" 2> /dev/null
rc=$?
if [ $rc -ne 0 ] || ! grep -q "Palkeoramix decompiler" "$tmp/fallback.out"; then
    echo "FAIL loader_fallback: rc=$rc"
    fail=1
else
    echo "ok   loader_fallback"
fi

python3 - "$tmp" <<'EOF'
import sys
tmp = sys.argv[1]
def push(v):
    b = v.to_bytes(max(1, (v.bit_length() + 7) // 8), "big")
    return bytes([0x5f + len(b)]) + b
# a linear dispatcher of 2400 selectors, each function a STOP
k = 2400
head_len = 6 + k * 12 + 4
code = push(0) + bytes([0x35, 0x60, 0xe0, 0x1c])
for i in range(k):
    code += bytes([0x80, 0x63]) + (0x10000000 + i).to_bytes(4, "big") + bytes([0x14, 0x62]) \
        + (head_len + 2 * i).to_bytes(3, "big") + bytes([0x57])
code += bytes([0x60, 0x00, 0x80, 0xfd])
assert len(code) == head_len
code += bytes([0x5b, 0x00]) * k
open(tmp + "/chain.hex", "w").write(code.hex() + "\n")
# a dispatcher of 7 functions: the first doubles its expression at each of
# 20 steps (cheap to run, a function whose walks blow up when it is made
# and printed), the others a chain of 20000 CALLDATALOADs
n, nb, chain = 20, 6, 20000
CDL, MLOAD, MSTORE, SSTORE, ADD, XOR, DUP1, STOP, JUMPDEST = 0x35, 0x51, 0x52, 0x55, 0x01, 0x18, 0x80, 0x00, 0x5b
def body_a():
    c = push(4) + bytes([CDL]) + push(36) + bytes([CDL, MSTORE])
    for i in range(n):
        c += push(36) + bytes([CDL])
        if i: c += push(32 * i) + bytes([ADD])
        c += bytes([MLOAD, DUP1]) + push(1) + bytes([ADD, XOR])
        c += push(36) + bytes([CDL]) + push(32 * (i + 1)) + bytes([ADD, MSTORE])
    c += push(36) + bytes([CDL]) + push(32 * n) + bytes([ADD, MLOAD]) + push(0) + bytes([SSTORE, STOP])
    return c
def body_b(k):
    return push(4) + bytes([CDL]) * chain + push(k) + bytes([SSTORE, STOP])
bodies = [(0x11111111, body_a())] + [(0x22220000 + k, body_b(k + 1)) for k in range(nb)]
head_len = 6 + len(bodies) * 12 + 4
code = push(0) + bytes([CDL]) + bytes([0x60, 0xe0, 0x1c])
off = head_len
dests = []
for sel, b in bodies:
    dests.append(off); off += 1 + len(b)
for (sel, b), d in zip(bodies, dests):
    code += bytes([DUP1, 0x63]) + sel.to_bytes(4, "big") + bytes([0x14, 0x62]) + d.to_bytes(3, "big") + bytes([0x57])
code += bytes([0x60, 0x00, DUP1, 0xfd])
for sel, b in bodies:
    code += bytes([JUMPDEST]) + b
open(tmp + "/blowup.hex", "w").write(code.hex() + "\n")
# the doubling function alone: made in a fraction of a second, its text
# (16 MiB) in seconds
a = body_a()
code = push(0) + bytes([CDL, 0x60, 0xe0, 0x1c, DUP1, 0x63]) + (0x11111111).to_bytes(4, "big") \
    + bytes([0x14, 0x62]) + (22).to_bytes(3, "big") + bytes([0x57, 0x60, 0x00, DUP1, 0xfd, JUMPDEST]) + a
open(tmp + "/slowtext.hex", "w").write(code.hex() + "\n")
EOF

# the discovery's watchdog had the deadline of its VM: the walks after a
# VM stopped at its limit were cut by it, and what the VM had found was
# thrown away (the contract a fallback alone, every time). The walks have
# 3 times the VM's limit now, which a machine busy with other things can
# still run past (they're quadratic in the selectors, as python's): three
# tries, and anything more than the fallback is what the VM found, kept.
for try in 1 2 3; do
    PANORAMIX_LOG=critical PANORAMIX_TIMEOUT=0.004 timeout 60 "$PANASM" decompile "$tmp/chain.hex" \
        --no-color -j 1 > "$tmp/chain.out" 2> /dev/null
    n=$(grep -c '^def ' "$tmp/chain.out")
    [ "$n" -gt 1 ] && break
done
if [ "$n" -le 1 ]; then
    echo "FAIL discovery_deadline: $n functions"
    fail=1
else
    echo "ok   discovery_deadline"
fi

# one function that blows up when it is made (function_new, on the main
# context): the whole contract's limit gone with it, every function a
# problem or no text at all; and when it is printed: the decompilation
# failed. Now the others are there, that one a problem or a text that says
# why it has none.
for mm in 64 256; do
    PANORAMIX_LOG=critical PANORAMIX_MAX_MEMORY=$mm timeout 120 "$PANASM" decompile \
        "$tmp/blowup.hex" --no-color -j 2 > "$tmp/blowup$mm.out" 2> /dev/null
    rc=$?
    n=$(grep -c '^def unknown2222' "$tmp/blowup$mm.out")
    if [ $rc -ne 0 ] || [ "$n" != 6 ]; then
        echo "FAIL function_blowup_$mm: rc=$rc, $n functions of 6"
        fail=1
    else
        echo "ok   function_blowup_$mm"
    fi
done

# the folds and the functions' texts are made on contexts of their own,
# which had no deadline: the post-processing's didn't reach them, and a
# text that took seconds past it held the call (and a CTRL+C) as long -
# made to its end (4 s here, for a deadline of 1 s), then the decompilation
# failed. Now it's cut at the deadline, which the message names. (The
# function is made in 0.9 s of its 1 s: a machine busy with other things
# makes it a problem, the text never printed - three tries.)
for try in 1 2 3; do
    s=$(date +%s%N)
    PANORAMIX_LOG=critical PANORAMIX_TIMEOUT=0.0056 PANORAMIX_MAX_MEMORY=4096 timeout 120 "$PANASM" \
        decompile "$tmp/slowtext.hex" --no-color -j 1 > /dev/null 2> "$tmp/slowtext.err"
    rc=$?
    ms=$(( ($(date +%s%N) - s) / 1000000 ))
    crashed $rc && break
    grep -q "the post-processing and the text took more than" "$tmp/slowtext.err" \
        && [ $ms -le 3000 ] && break
done
if crashed $rc || ! grep -q "the post-processing and the text took more than" "$tmp/slowtext.err" \
        || [ $ms -gt 3000 ]; then
    echo "FAIL text_deadline: rc=$rc, $ms ms"
    fail=1
else
    echo "ok   text_deadline"
fi
# the same with --json: its handler (python's except Exception) took the
# deadline for a failure of the json - {}, code 0, and then the text made
# with no deadline at all
for try in 1 2 3; do
    PANORAMIX_LOG=critical PANORAMIX_TIMEOUT=0.0056 PANORAMIX_MAX_MEMORY=4096 timeout 120 "$PANASM" \
        decompile "$tmp/slowtext.hex" --no-color --json -j 1 > "$tmp/slowjson.out" 2> "$tmp/slowjson.err"
    rc=$?
    crashed $rc && break
    grep -q "the post-processing and the text took more than" "$tmp/slowjson.err" && break
done
if crashed $rc || [ $rc -eq 0 ] \
        || ! grep -q "the post-processing and the text took more than" "$tmp/slowjson.err"; then
    echo "FAIL text_deadline_json: rc=$rc"
    fail=1
else
    echo "ok   text_deadline_json"
fi

# a hostile signature database: a parameter's name (not in the hash a
# signature is checked with) with an escape that sets the terminal's
# title, a bell, newlines and a forged definition - all of it reached the
# text as it was, --no-color or not
if command -v xz > /dev/null && command -v python3 > /dev/null; then
    python3 - "$tmp" <<'EOF'
import lzma, sys
with lzma.open(sys.argv[1] + "/forge.xz", "wt") as f:
    f.write('{"selector":"0xa9059cbb","abi":{"type":"function","name":"transfer",'
            '"inputs":[{"name":"to","type":"address"},{"name":"amount\\u001b]0;PWNED\\u0007'
            '\\n\\n    def withdraw_all_funds(): # forged\\n\\u001b[31mowned","type":"uint256"}]}}\n')
EOF
    PANORAMIX_LOG=error timeout 300 "$PANASM" build-db "$tmp/forge.xz" "$tmp/forge.bin" \
        > /dev/null 2>&1
    PANORAMIX_SIGDB="$tmp/forge.bin" PANORAMIX_LOG=error timeout 60 \
        "$PANASM" decompile "$tmp/param_oob.hex" --no-color > "$tmp/forge.out" 2>&1
    if grep -q $'\033' "$tmp/forge.out" || grep -q $'\a' "$tmp/forge.out"; then
        echo "FAIL sigdb_escapes: a control character reached the text"
        fail=1
    elif grep -q '^ *def withdraw_all_funds' "$tmp/forge.out"; then
        echo "FAIL sigdb_escapes: a forged line"
        fail=1
    elif ! grep -q 'def transfer(address to, uint256 amount' "$tmp/forge.out"; then
        echo "FAIL sigdb_escapes: the signature was not used (the case tests nothing)"
        fail=1
    else
        echo "ok   sigdb_escapes"
    fi
    # a database names the dump it was built from, read again at every load
    # to see if it changed - the database may be anybody's, and a fifo
    # there (or /dev/zero) hung every decompilation (or took all the memory)
    cp "$tmp/forge.xz" "$tmp/dumpf.xz"
    PANORAMIX_LOG=error timeout 300 "$PANASM" build-db "$tmp/dumpf.xz" "$tmp/dumpf.bin" \
        > /dev/null 2>&1
    rm -f "$tmp/dumpf.xz"
    mkfifo "$tmp/dumpf.xz"
    PANORAMIX_SIGDB="$tmp/dumpf.bin" PANORAMIX_LOG=error timeout 20 \
        "$PANASM" decompile "$tmp/param_oob.hex" --no-color > "$tmp/dumpf.out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || ! grep -q 'def transfer(address to' "$tmp/dumpf.out"; then
        echo "FAIL sigdb_dump_fifo: rc=$rc"
        fail=1
    else
        echo "ok   sigdb_dump_fifo"
    fi
    # and build-db reads its dump from a pipe (the guard against a path the
    # command line's argument may be had refused it): what the operator
    # names is the operator's, and a pipe's path isn't recorded
    cat "$tmp/forge.xz" | PANORAMIX_LOG=error timeout 300 "$PANASM" build-db /dev/stdin \
        "$tmp/piped.bin" > /dev/null 2>&1
    rc=$?
    PANORAMIX_SIGDB="$tmp/piped.bin" PANORAMIX_LOG=error timeout 20 \
        "$PANASM" decompile "$tmp/param_oob.hex" --no-color > "$tmp/piped.out" 2>&1
    if [ $rc -ne 0 ] || ! grep -q 'def transfer(address to' "$tmp/piped.out"; then
        echo "FAIL build_db_pipe: rc=$rc"
        fail=1
    else
        echo "ok   build_db_pipe"
    fi
fi

# a file whose hex isn't: its path in the message was cut at 200 bytes, as
# an excerpt of a text is
long="$tmp/$(printf 'd%.0s' $(seq 150))/$(printf 'e%.0s' $(seq 150))"
mkdir -p "$long"
echo "60zz" > "$long/bad.hex"
PANORAMIX_LOG=critical "$PANASM" decompile "$long/bad.hex" --no-color > /dev/null 2> "$tmp/longpath.err"
if ! grep -qF "$long/bad.hex" "$tmp/longpath.err"; then
    echo "FAIL long_path_message: $(head -c 120 "$tmp/longpath.err")"
    fail=1
else
    echo "ok   long_path_message"
fi

# standard input that is O_NONBLOCK (a program's own pipe): EAGAIN was the
# end, the code cut where the pipe had run dry, and decompiled as the whole
# contract
out=$(timeout 120 python3 -I - "$PANASM" <<'EOF' 2>&1
import os, sys, subprocess, time
code = open('tests/corpus/WETH.hex').read().strip()
r, w = os.pipe()
os.write(w, code[:len(code) // 2].encode())
os.set_blocking(r, False)
p = subprocess.Popen([sys.argv[1], 'disasm', '-'], stdin=r, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL)
os.close(r)
time.sleep(0.5)
try:
    os.write(w, code[len(code) // 2:].encode())
except BrokenPipeError:
    pass
os.close(w)
out = p.communicate(timeout=60)[0]
full = subprocess.run([sys.argv[1], 'disasm', 'tests/corpus/WETH.hex'], capture_output=True).stdout
print('same' if out == full else 'cut: %d lines of %d' % (out.count(b'\n'), full.count(b'\n')))
EOF
)
if [ "$out" != "same" ]; then
    echo "FAIL stdin_nonblocking: $out"
    fail=1
else
    echo "ok   stdin_nonblocking"
fi

# standard input past the 256 MiB a file may have: cut there and the rest
# decompiled as if it were the contract (now refused)
head -c 270000000 /dev/zero | tr '\0' '0' | timeout 120 "$PANASM" disasm - \
    > /dev/null 2> "$tmp/stdin_long.err"
rc=$?
if [ $rc -eq 0 ] || ! grep -q "longer than 256 MiB" "$tmp/stdin_long.err"; then
    echo "FAIL stdin_too_long: rc=$rc"
    fail=1
else
    echo "ok   stdin_too_long"
fi

if [ -f build/panoramix_asm.cpython-311-x86_64-linux-gnu.so ]; then
    # the python module, as a program that runs many calls: memory that
    # grew with each (the loader of a code that failed to load, the signature
    # builder's 72 MiB, the strings interned), GMP's memory functions (the
    # library's, process-wide: a GMP of the program's own on another thread
    # read a context there is none of), signals delivered to the library's
    # threads and its system calls cut short by them
    out=$(PANORAMIX_LOG=critical PANORAMIX_PURGE_MIB=1 timeout 300 python3 -I - "$tmp" <<'EOF' 2>&1
import sys, os, ctypes, ctypes.util, threading, signal, time, lzma
tmp = sys.argv[1]
sys.path.insert(0, 'build')
import panoramix_asm as m
def vsz():
    return int(open('/proc/self/statm').read().split()[0]) * 4096 >> 20
class MI(ctypes.Structure):
    _fields_ = [(n, ctypes.c_size_t) for n in ("arena", "ordblks", "smblks", "hblks", "hblkhd",
                "usmblks", "fsmblks", "uordblks", "fordblks", "keepcost")]
libc = ctypes.CDLL(None)
libc.mallinfo2.restype = MI
def heap():
    mi = libc.mallinfo2()
    return (mi.uordblks + mi.hblkhd) >> 20
bad = []
# a code whose loader can't be had (16 bytes of tables a byte): -1, and
# nothing kept
import resource
code = bytes(40 << 20)
v0 = vsz()
resource.setrlimit(resource.RLIMIT_AS, (v0 + (512 << 20), resource.RLIM_INFINITY))
for i in range(4):
    try:
        m.disasm(code)
    except Exception:
        pass
if vsz() - v0 > 64:
    bad.append("disasm_oom_leak: +%d MiB" % (vsz() - v0))
resource.setrlimit(resource.RLIMIT_AS, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))
del code
# the signature database built again and again
with lzma.open(tmp + "/one.xz", "wt") as f:
    f.write('{"selector":"0x12345678","abi":{"type":"function","name":"f","inputs":[]}}\n')
m.build_signature_db(tmp + "/one.xz", tmp + "/one.bin")    # (what malloc keeps
v0 = vsz()                                                  # of the first: once)
for i in range(4):
    m.build_signature_db(tmp + "/one.xz", tmp + "/one.bin")
if vsz() - v0 > 40:
    bad.append("sigdb_build_leak: +%d MiB" % (vsz() - v0))
# the strings a decompilation interns: purged once no call is in progress
h = []
for i in range(30):
    c = b'\x7f' + os.urandom(32) + b'\x80' * 300 + b'\x00'
    m.decompile(c, threads=1, color=False, verbose=True)
    h.append(heap())
if h[-1] > h[4] + 16:
    bad.append("strings_purge: %s MiB" % h[::5])
# a GMP of the program's, on a thread of its own
gmp = ctypes.CDLL(ctypes.util.find_library('gmp') or 'libgmp.so.10')
def use_gmp():
    z = ctypes.create_string_buffer(64)
    gmp.__gmpz_init(z)
    gmp.__gmpz_ui_pow_ui(z, 3, 100000)
    gmp.__gmpz_clear(z)
t = threading.Thread(target=use_gmp); t.start(); t.join()
use_gmp()
# a CTRL+C during a call: held until it returns, then python's exception
signal.signal(signal.SIGINT, signal.default_int_handler)
slow = '6000' + '35' * 120000 + '600055' + '00'
threading.Timer(0.5, lambda: os.kill(os.getpid(), signal.SIGINT)).start()
try:
    m.decompile(slow, threads=2, color=False)
    time.sleep(0.3)
    bad.append("ctrl_c: lost")
except KeyboardInterrupt:
    pass
print("bad:", bad)
print("survived")
EOF
)
    rc=$?
    if crashed $rc || [ "$(echo "$out" | tail -1)" != "survived" ] || ! echo "$out" | grep -q '^bad: \[\]$'; then
        echo "FAIL module_calls: rc=$rc"
        echo "$out" | tail -3
        fail=1
    else
        echo "ok   module_calls"
    fi
    # the GMP shifts of the storage's recomposition of packed numbers: a
    # field 2^32 bits wide was a shift of as many (an abort), 2^40 GMP's
    # own overflow (a SIGFPE); and a data of 32 terms of 16 MiB each made
    # one text of all of them, outside the arena (512 MiB at a limit of 32)
    out=$(PANORAMIX_LOG=critical PANORAMIX_MAX_MEMORY=32 timeout 120 python3 -I -c "
import sys, resource; sys.path.insert(0, 'build')
import panoramix_asm as m
for big in (1 << 32, 1 << 40):
    fn1 = ('h1', 'f1', [('store', big, 0, ('loc', 0), ('cd', 1))], None, None, True)
    fn2 = ('h2', 'f2', [('store', big - 8, 0, ('loc', 0), 7), ('store', 8, big - 8, ('loc', 0), 9)],
           None, None, True)
    m._test('storage', repr(('regroup', (fn1, fn2), 'solidity')))
SZ = 1 << 24
terms = ','.join(\"('bytes', %d, 0)\" % SZ for _ in range(32))
m._test('pretty_memory_l', \"(('data', ('arr', %d, %s)), 16)\" % (32 * SZ, terms))
print(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss >> 10)
print('survived')
" 2>&1)
    rc=$?
    if crashed $rc || [ "$(echo "$out" | tail -1)" != "survived" ]; then
        echo "FAIL gmp_shift_and_arr: rc=$rc"
        echo "$out" | tail -2
        fail=1
    elif [ "$(echo "$out" | tail -2 | head -1)" -gt 256 ]; then
        echo "FAIL gmp_shift_and_arr: $(echo "$out" | tail -2 | head -1) MiB"
        fail=1
    else
        echo "ok   gmp_shift_and_arr"
    fi
    # a fork while a call is in progress on another thread (multiprocessing
    # forks, and the module lets go of the GIL during its calls): the child
    # had the count of the calls in progress, never back to 0 - with a purge
    # after every call, its second call waited for good; and the locks the
    # others held stayed held there. Then a dump whose line ends early, built
    # after two good ones: read on past its end, into the text the buffer
    # still held, and accepted, completed with the other dump's bytes.
    out=$(PANORAMIX_LOG=critical PANORAMIX_PURGE_MIB=0 timeout 300 python3 -I - "$tmp" <<'EOF' 2>&1
import sys, os, threading, time, signal, lzma
tmp = sys.argv[1]
sys.path.insert(0, 'build')
import panoramix_asm as m
big = open('tests/corpus/Seaport15.hex').read().strip()
small = open('tests/corpus/WETH.hex').read().strip()
bad = []
m.decompile(small, threads=1)
t = threading.Thread(target=lambda: m.decompile(big, threads=1))
t.start()
time.sleep(0.3)
pid = os.fork()
if pid == 0:
    signal.alarm(30)
    for i in range(3):
        m.decompile(small, threads=1)
    os._exit(0)
t.join()
_, st = os.waitpid(pid, 0)
if not os.WIFEXITED(st) or os.WEXITSTATUS(st) != 0:
    bad.append("fork_in_call: the child %s" % ("hung" if os.WIFSIGNALED(st) else "failed"))
ok = ('{"selector":"0xa9059cbb","abi":{"type":"function","name":"transfer","inputs":'
      '[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}]}}\n')
with lzma.open(tmp + "/ok.xz", "wt") as f:
    f.write(ok)
with lzma.open(tmp + "/cut.xz", "wt") as f:
    f.write(ok[:ok.index('},{') + 1] + '\n')
for i in range(2):
    m.build_signature_db(tmp + "/ok.xz", tmp + "/ok.bin")
try:
    m.build_signature_db(tmp + "/cut.xz", tmp + "/cut.bin")
    bad.append("sigdb_line_end: a dump cut short accepted")
except Exception:
    pass
print("bad:", bad)
print("survived")
EOF
)
    rc=$?
    if crashed $rc || [ "$(echo "$out" | tail -1)" != "survived" ] || ! echo "$out" | grep -q '^bad: \[\]$'; then
        echo "FAIL fork_and_dump: rc=$rc"
        echo "$out" | tail -3
        fail=1
    else
        echo "ok   fork_and_dump"
    fi
fi

exit $fail
