/* panoramix_asm: the EVM decompiler panoramix, in x86-64 assembly.
 *
 * Link with -lpanoramix_asm (build/libpanoramix_asm.so), which needs
 * libgmp, liblzma and libpthread. Every function may be called from any
 * thread, several at once. */
#ifndef PANORAMIX_ASM_H
#define PANORAMIX_ASM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Initializes the library (the other functions call it; idempotent). */
int pan_init(void);

/* The decompilation of `code` (raw bytecode, not hex) as
 * `python -m panoramix` prints it, in *out (a NUL-terminated, malloc'ed
 * string of *outlen bytes, released with pan_free). threads: the number
 * of functions decompiled at once (1 or more). only_func: NULL, or only
 * the functions whose name starts with it. Returns 0, or -1 when the
 * decompilation failed where python would have raised (a function that
 * fails is reported in the text instead, as python does); *out is the
 * message then. PANORAMIX_MAX_MEMORY (MiB) caps the memory one function
 * may take (by default the machine's, shared by the threads). */
int pan_decompile(const uint8_t *code, size_t len, size_t threads,
                  const char *only_func, char **out, size_t *outlen);

#define PAN_NO_COLOR 1   /* the text without the terminal color codes */
int pan_decompile_ex(const uint8_t *code, size_t len, size_t threads,
                     const char *only_func, char **out, size_t *outlen,
                     long flags);

/* The disassembly, one instruction per line, as panoramix's
 * Loader.disasm(). */
int pan_disasm(const uint8_t *code, size_t len, char **out, size_t *outlen);

void pan_free(void *p);

/* The signature database (function names), made once from panoramix's
 * data/abi_dump.xz. out_path: NULL for $PANORAMIX_SIGDB, or
 * $XDG_CACHE_HOME/panoramix/abi_db.bin, or ~/.cache/panoramix/abi_db.bin
 * (where pan_decompile looks for it). Returns 0 on success. */
int pan_build_sigdb(const char *xz_path, const char *out_path);

/* The messages on stderr: python's logging levels (10 DEBUG, 20 INFO,
 * 30 WARNING, 40 ERROR). The default is INFO, or PANORAMIX_LOG. */
void pan_set_log_level(long level);
long pan_log_level_from_name(const char *name);  /* -1 if unknown */

#ifdef __cplusplus
}
#endif

#endif
