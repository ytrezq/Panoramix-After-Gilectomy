# Panoramix after Gilectomy

The [panoramix](https://github.com/palkeo/panoramix) EVM decompiler, ported
to x86-64 assembly: a library that takes bytecode and gives back the
decompiled text, with a thin CPython wrapper and a command line tool.

The name says why: the [Gilectomy](https://github.com/larryhastings/gilectomy)
set out to take the GIL out of CPython, and python still can't run
threads in parallel on objects they all read and write. Here the
functions of a contract are decompiled on threads sharing one address
space and one read-only loader - no GIL, no processes, no copies -, the
integers are GMP's and the expressions are deduplicated.

It produces the same text as the python implementation (pypy's output,
with the signature database, on 30 mainnet contracts, the 407 runtime
bytecodes npm packages ship, 491 more recent ones - OpenZeppelin 5,
Uniswap v4, ENS, Safe, ERC-4337, compiled for Shanghai and Cancun - and
179 vyper contracts; see `docs/DESIGN.md` for the few intended
differences) in a hundredth to a three hundredth of pypy's time - 21 s
of CPU for the 407 where pypy takes about an hour, 32 s for the 491
where it takes two and a half hours - and a fraction of its memory.

    make                         # needs as, cc, libgmp, liblzma, python3-dev
    make install PREFIX=/usr/local   # panasm, libpanoramix_asm.so, the header
    pip install .                # the python module (built by make, for that python)
    build/panasm build-db /path/to/panoramix/data/abi_dump.xz   # once: the signature database
    build/panasm decompile contract.hex [-j threads] [--function name] [--no-color] [--json] [-v level]
                                        [--verbose] [--explain] [--repr] [--returns]
    build/panasm decompile 0x6080...       # (the bytecode itself, as python -m panoramix takes it)
    build/panasm decompile 0xdAC17F958D2ee523a2206206994597C13D831ec7   # an address: its code from a node
    build/panasm decompile a.hex,b.hex,0x6080...   # each in turn
    build/panasm disasm contract.hex

From python (the module in `build/`):

    import panoramix_asm
    text = panoramix_asm.decompile(open("contract.hex").read())          # a str with colors
    text = panoramix_asm.decompile(code, threads=4, function="transfer", color=False)
    d = panoramix_asm.decompile_bytecode(code)      # as panoramix.decompiler's:
    d.text, d.asm, d.json                           # the text, the disassembly, python's json
    d = panoramix_asm.decompile_bytecode(code, verbose=True)   # or explain=True: python's options
    d = panoramix_asm.decompile_address("0xdAC17F958D2ee523a2206206994597C13D831ec7")
    panoramix_asm.build_signature_db("abi_dump.xz")                       # once
    panoramix_asm.set_log_level("info")     # warnings and errors only by default

`code` is the bytecode as bytes (or any bytes-like object: bytearray,
memoryview...), or as a hex str (`0x` optional).
`decompile` releases the GIL: several python threads can decompile
contracts at once, in one process, each call using `threads` threads
for the functions of its contract (by default as many as the machine
has cores). A function that fails is reported in the text, as python
does ("I failed with these"); an error where python would have printed
a traceback raises `RuntimeError`.

`decompile_bytecode` gives what panoramix's function of that name gives:
`json` is python's `decompilation.json` - the problems, the storage
definitions, and each function's names, length, getter, constant,
payable, printed text, trace and parameters - as the same python objects
(tuples, numbers as keys); `panasm decompile --json` prints it as
`json.dumps` does.

`--verbose` and `--explain` are python's: the first puts the
instructions the symbolic execution ran, with the stack before each, in
the text (as comments); the second prints, before the text, each
function's trace at every stage of its decompilation and the traits its
analysis found (and gives the text without the instructions). As python
reads them from `sys.argv`, so does `decompile_bytecode` when its
`verbose`/`explain` aren't given; what `--explain` prints goes to
`sys.stdout`, as python prints it, and to `d.explain`. So do `--repr`
and `--returns`, which python's library reads there too (its command
line refuses them): each function's trace, and its returns, after it.

An address (`0x` and 40 hex digits) is decompiled as python's
`decompile_address` does it: its code comes from a node, through
`eth_getCode`, found where web3's automatic provider looks -
`$WEB3_PROVIDER_URI` (`http://...`, or `file://PATH` for the node's IPC
socket), the default IPC sockets (`~/.ethereum/geth.ipc`, parity's,
trinity's), then `$WEB3_HTTP_PROVIDER_URI` or `http://localhost:8545`.
Plain HTTP and IPC only: no TLS nor websockets (a local node, or a
proxy, for a provider in `https://`).

From C: `build/libpanoramix_asm.so` and `include/panoramix_asm.h`
(`pan_decompile`, `pan_decompile_data` for the json, `pan_disasm`,
`pan_fetch_code`, `pan_build_sigdb`...; `make check` runs an example).

The signature database goes to `$PANORAMIX_SIGDB`, or
`$XDG_CACHE_HOME/panoramix/abi_db.bin`, or `~/.cache/panoramix/abi_db.bin`.
As python's, it is built again when the dump it was made from changes
(`$PANORAMIX_ABI_DUMP`, or the dump `build-db` was given), and built
from `$PANORAMIX_ABI_DUMP` when there is none.
`PANORAMIX_LOG=debug|warning|error` sets the log level (coloredlogs'
format), `PANORAMIX_ISA=scalar|sse2|avx2|avx512` forces the vector loops,
`PANORAMIX_MAX_MEMORY` caps what one function may take (MiB; by default
the machine's memory shared by the threads): a function past it is
reported as a problem, as python does with the ones that fail.
`PANORAMIX_TIMEOUT` scales python's time limits (60 s a step, 3 minutes
a function) as it does in python (10 on a slow machine, 0 for none: to
compare runs under valgrind).

The bytecode is whoever wrote it's, so it is treated as hostile: see
"Hostile input" in `docs/DESIGN.md` for the review of the sources
against that, what it found and what bounds a contract's memory and
time. `tests/security.sh` keeps the inputs that used to break it.

Inputs no compiler would make (thousands of nested ifs, expressions
thousands deep) don't take the process down: the recursions stop at
python's `RecursionError` instead of running off the stack, the folder
gives up past 1 GiB, and an error where python would print a traceback
(in the postprocessing) comes back as one (`pan_decompile` returns -1,
the module raises `RuntimeError`).

See `docs/DESIGN.md` for the layout, the conventions and the tests.
