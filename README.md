# panoramix-asm

The [panoramix](https://github.com/palkeo/panoramix) EVM decompiler, ported
to x86-64 assembly: a library that takes bytecode and gives back the
decompiled text, with a thin CPython wrapper and a command line tool. It
produces the same text as the python implementation (checked on a corpus
of 30 contracts against pypy's output, with the signature database), in
a small fraction of the time and the memory: the functions of a contract
are decompiled on threads sharing one address space (no GIL, no
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

From C: `build/libpanoramix_asm.so` and `include/panoramix_asm.h`
(`pan_decompile`, `pan_disasm`, `pan_build_sigdb`...; `make check` runs
an example).

The signature database goes to `$PANORAMIX_SIGDB`, or
`$XDG_CACHE_HOME/panoramix/abi_db.bin`, or `~/.cache/panoramix/abi_db.bin`.
`PANORAMIX_LOG=debug|warning|error` sets the log level (coloredlogs'
format), `PANORAMIX_ISA=scalar|avx2|avx512` forces the vector loops.

See `docs/DESIGN.md` for the layout, the conventions and the tests.
