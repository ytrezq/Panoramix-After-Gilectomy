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
/* python's `--verbose`: the instructions the symbolic execution ran, and
 * the stack before each, as comments of the text */
#define PAN_VERBOSE 8
/* python's `--explain`: the trace at every stage of each function's
 * decompilation, and the traits found of the function, as python prints
 * them along the way - put before the text by pan_decompile_ex */
#define PAN_EXPLAIN 16
/* python's hidden `--repr` and `--returns` (read from sys.argv, which its
 * command line refuses): after each function, its trace as
 * prettify.pprint_repr prints it, and its returns */
#define PAN_REPR 32
#define PAN_RETURNS 64
int pan_decompile_ex(const uint8_t *code, size_t len, size_t threads,
                     const char *only_func, char **out, size_t *outlen,
                     long flags);

/* The text as pan_decompile_ex gives it, and python's
 * decompilation.json - the problems, the storage definitions, and for
 * each function its hash, names, length, getter, constant, payable,
 * printed text, trace and parameters. flags: PAN_NO_COLOR (the text's),
 * and PAN_JSON for the data as the JSON text json.dumps makes of it;
 * without it, the data is a binary form of python's objects (tuples
 * apart from lists, the keys' types), which the python module reads:
 *     'N' None, 'T' True, 'F' False, 'i' int64 (little-endian),
 *     'I' u32 n + n ASCII (any other integer: [-]0x + its hex digits),
 *     's' u32 n + n bytes of UTF-8, 'f' u32 n + n ASCII (a float),
 *     '(' tuple, '[' list, '{' dict: u32 n + n elements (n keys and
 *     values for a dict).
 * The text and the data are malloc'ed (released with pan_free; the
 * data is NULL on failure). Returns 0, or -1 with the message as the
 * text. */
#define PAN_JSON 4
typedef struct {
    char *text;
    size_t textlen;
    char *data;
    size_t datalen;
    char *explain;       /* with PAN_EXPLAIN only (the fields are left alone */
    size_t explainlen;   /* otherwise): what python's --explain printed */
} pan_output;
int pan_decompile_data(const uint8_t *code, size_t len, size_t threads,
                       const char *only_func, long flags, pan_output *out);

/* The code deployed at an address ("0x" and 40 hex digits), as python's
 * decompile_address fetches it: eth_getCode from the node web3's
 * automatic provider finds - $WEB3_PROVIDER_URI (http://..., or
 * file://PATH for the node's IPC socket), else the first of the default
 * IPC sockets that exists (~/.ethereum/geth.ipc, parity's, trinity's),
 * else $WEB3_HTTP_PROVIDER_URI or http://localhost:8545; each tried when
 * the one before can't be reached (10 s at most each). No TLS (https://)
 * nor websockets. Returns 0 with the raw bytecode in *code (malloc'ed,
 * *len bytes: none for an address without code), or -1 with the reason
 * in *err (malloc'ed; err may be NULL). */
int pan_fetch_code(const char *address, uint8_t **code, size_t *len, char **err);

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
