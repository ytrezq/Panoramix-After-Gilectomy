/* bbfreq: a DynamoRIO client counting how many times every instruction of
 * the main executable runs - natively, AVX-512 included (no valgrind has
 * it: cachegrind and callgrind run the AVX2 paths, PANORAMIX_ISA=avx2). A
 * counter per basic block (DynamoRIO's: a block may start inside another,
 * its instructions counted in both), incremented with a locked add (the
 * decompiler's threads run the same blocks); at the exit, every block's
 * offset in the executable, its count and the offsets of its
 * instructions, written to OUTDIR/bbfreq.PID (the client's argument; one
 * line per block: "B start count n off1 off2 ...", in hex), for
 * tools/bbf_agg.py.
 *
 *     cmake -DDynamoRIO_DIR=$DR/cmake tools/bbfreq && make   (libbbfreq.so)
 *     $DR/bin64/drrun -c libbbfreq.so OUTDIR -- build/panasm decompile ...
 */
#include "dr_api.h"
#include "drmgr.h"
#include "drx.h"
#include "drreg.h"
#include "hashtable.h"

typedef struct {
    app_pc start;
    uint64 count;
    uint n;
    ushort *offs;
} bb_t;

static hashtable_t table;
static void *lock;
static app_pc mod_start, mod_end;
static char out_dir[512];

static void
bb_free(void *p)
{
    bb_t *b = (bb_t *)p;
    dr_global_free(b->offs, sizeof(ushort) * b->n);
    dr_global_free(b, sizeof(*b));
}

static bb_t *
bb_get(app_pc start, instrlist_t *ilist)
{
    bb_t *b;
    dr_mutex_lock(lock);
    b = (bb_t *)hashtable_lookup(&table, start);
    if (b == NULL) {
        uint n = 0;
        instr_t *in;
        for (in = instrlist_first_app(ilist); in != NULL; in = instr_get_next_app(in))
            n++;
        b = (bb_t *)dr_global_alloc(sizeof(*b));
        b->start = start;
        b->count = 0;
        b->n = n;
        b->offs = (ushort *)dr_global_alloc(sizeof(ushort) * (n ? n : 1));
        n = 0;
        for (in = instrlist_first_app(ilist); in != NULL; in = instr_get_next_app(in))
            b->offs[n++] = (ushort)(instr_get_app_pc(in) - start);
        hashtable_add(&table, start, b);
    }
    dr_mutex_unlock(lock);
    return b;
}

static dr_emit_flags_t
event_insert(void *drcontext, void *tag, instrlist_t *bb, instr_t *instr, bool for_trace,
             bool translating, void *user_data)
{
    app_pc start;
    bb_t *b;
    if (!drmgr_is_first_instr(drcontext, instr))
        return DR_EMIT_DEFAULT;
    start = instr_get_app_pc(instr);
    if (start == NULL || start < mod_start || start >= mod_end)
        return DR_EMIT_DEFAULT;
    b = bb_get(start, bb);
    /* (with drmgr, drx spills through drreg: the slot SPILL_SLOT_MAX + 1) */
    if (!drx_insert_counter_update(drcontext, bb, instr, SPILL_SLOT_MAX + 1, &b->count, 1,
                                   DRX_COUNTER_64BIT | DRX_COUNTER_LOCK))
        DR_ASSERT(false);
    return DR_EMIT_DEFAULT;
}

static void
event_exit(void)
{
    char path[600];
    file_t f;
    uint i;
    dr_snprintf(path, sizeof(path), "%s/bbfreq.%d", out_dir, (int)dr_get_process_id());
    path[sizeof(path) - 1] = 0;
    f = dr_open_file(path, DR_FILE_WRITE_OVERWRITE);
    if (f != INVALID_FILE) {
        for (i = 0; i < HASHTABLE_SIZE(table.table_bits); i++) {
            hash_entry_t *e;
            for (e = table.table[i]; e != NULL; e = e->next) {
                bb_t *b = (bb_t *)e->payload;
                uint k;
                if (b->count == 0)
                    continue;
                dr_fprintf(f, "B %llx %llx %x", (unsigned long long)(b->start - mod_start),
                           (unsigned long long)b->count, b->n);
                for (k = 0; k < b->n; k++)
                    dr_fprintf(f, " %x", b->offs[k]);
                dr_fprintf(f, "\n");
            }
        }
        dr_close_file(f);
    }
    hashtable_delete(&table);
    dr_mutex_destroy(lock);
    drx_exit();
    drreg_exit();
    drmgr_exit();
}

DR_EXPORT void
dr_client_main(client_id_t id, int argc, const char *argv[])
{
    module_data_t *exe;
    dr_set_client_name("bbfreq", "");
    dr_snprintf(out_dir, sizeof(out_dir), "%s", argc > 1 ? argv[1] : ".");
    out_dir[sizeof(out_dir) - 1] = 0;
    drreg_options_t ops = { sizeof(ops), 2 /*max slots needed: aflags, a register*/, false };
    drmgr_init();
    if (drreg_init(&ops) != DRREG_SUCCESS)
        DR_ASSERT(false);
    drx_init();
    lock = dr_mutex_create();
    hashtable_init_ex(&table, 16, HASH_INTPTR, false, false, bb_free, NULL, NULL);
    exe = dr_get_main_module();
    mod_start = exe->start;
    mod_end = exe->end;
    dr_free_module_data(exe);
    drmgr_register_exit_event(event_exit);
    drmgr_register_bb_instrumentation_event(NULL, event_insert, NULL);
}
