# panoramix-asm

The [panoramix](https://github.com/palkeo/panoramix) EVM decompiler, ported
to x86-64 assembly: a library that takes bytecode and gives back the
decompiled text, with a thin CPython wrapper and a command line tool. It
produces the same text as the python implementation (checked on two
corpora - 30 mainnet contracts and 407 bytecodes of npm packages -
against pypy's output, with the signature database), in about a
fiftieth of pypy's time (70 s of CPU for the 407 where pypy takes 57
minutes) and a fraction of its memory: the functions of a contract are
decompiled on threads sharing one address space (no GIL, no
processes), integers are GMP's, the expressions are hash-consed.

    make                         # needs as, cc, libgmp, liblzma, python3-dev
    build/panasm build-db /path/to/panoramix/data/abi_dump.xz   # once: the signature database
    build/panasm decompile contract.hex [-j threads] [--function name] [--no-color]
    build/panasm disasm contract.hex

From python (the module in `build/`):

    import panoramix_asm
    text = panoramix_asm.decompile(open("contract.hex").read())          # a str with colors
    text = panoramix_asm.decompile(code, threads=4, function="transfer", color=False)
    panoramix_asm.build_signature_db("abi_dump.xz")                       # once
    panoramix_asm.set_log_level("info")     # warnings and errors only by default

`code` is the bytecode as bytes, or as a hex str (`0x` optional).
`decompile` releases the GIL: several python threads can decompile
contracts at once, in one process, each call using `threads` threads
for the functions of its contract (by default as many as the machine
has cores). A function that fails is reported in the text, as python
does ("I failed with these"); an error where python would have printed
a traceback raises `RuntimeError`.

From C: `build/libpanoramix_asm.so` and `include/panoramix_asm.h`
(`pan_decompile`, `pan_disasm`, `pan_build_sigdb`...; `make check` runs
an example).

The signature database goes to `$PANORAMIX_SIGDB`, or
`$XDG_CACHE_HOME/panoramix/abi_db.bin`, or `~/.cache/panoramix/abi_db.bin`.
`PANORAMIX_LOG=debug|warning|error` sets the log level (coloredlogs'
format), `PANORAMIX_ISA=scalar|avx2|avx512` forces the vector loops,
`PANORAMIX_MAX_MEMORY` caps what one function may take (MiB; by default
the machine's memory shared by the threads): a function past it is
reported as a problem, as python does with the ones that fail.
`PANORAMIX_TIMEOUT` scales python's time limits (60 s a step, 3 minutes
a function) as it does in python (10 on a slow machine, 0 for none: to
compare runs under valgrind).

Inputs no compiler would make (thousands of nested ifs, expressions
thousands deep) don't take the process down: the recursions stop at
python's `RecursionError` instead of running off the stack, the folder
gives up past 1 GiB, and an error where python would print a traceback
(in the postprocessing) comes back as one (`pan_decompile` returns -1,
the module raises `RuntimeError`).

See `docs/DESIGN.md` for the layout, the conventions and the tests.
