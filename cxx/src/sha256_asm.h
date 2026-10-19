/* The portability of the SHA-256 assembly (sha256_*.S): ELF (Linux, the BSDs)
 * or PE/COFF (the MinGW port). The functions follow the System V calling
 * convention on every platform: sha256.cpp declares them sysv_abi, so that
 * on Windows the compiler saves what the Microsoft convention would have them
 * save (xmm6-xmm15, rsi, rdi). Their symbols are hidden: not exported by the
 * python module's shared object. */
#ifndef PAN_SHA256_ASM_H
#define PAN_SHA256_ASM_H

/* _CET_ENDBR, and the note that marks the object compatible with CET's
 * indirect branch tracking and shadow stack (when the compiler targets it:
 * __CET__) - otherwise the linker would drop the marking of the whole
 * program for want of it in these objects. */
#include <cet.h>

#ifdef __ELF__
# define SHA256_FUNCTION(name) \
        .globl name; .hidden name; .type name, @function; .p2align 5; name: _CET_ENDBR
# define SHA256_END(name) .size name, . - name
# define SHA256_RODATA .section .rodata
        .section .note.GNU-stack, "", @progbits
#else
# define SHA256_FUNCTION(name) .globl name; .p2align 5; name: _CET_ENDBR
# define SHA256_END(name)
# define SHA256_RODATA .section .rdata, "dr"
#endif

#endif
