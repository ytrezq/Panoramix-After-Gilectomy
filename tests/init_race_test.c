/* Several threads whose first call to the library is at the same moment
 * (legal: panoramix_asm.h promises any thread, several at once, and the
 * functions call pan_init themselves). The initialization was a flag
 * tested then set before the work: a thread that came second ran on
 * tables not made yet (str_intern probed a table of capacity 0 - a read
 * and a write anywhere), about one run in three crashed or gave a wrong
 * text. Run a process per try (the race is the first call's):
 *
 *     for i in $(seq 30); do build/init_race_test 8 || exit 1; done
 */
#include <panoramix_asm.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* the contract of c_api_test.c: a getter over storage 0 and another one */
static const char *HEX =
    "6080604052348015600f57600080fd5b506004361060325760003560e01c80636d4ce63c146037578063d09de08a14604c575b600080fd5b60005460405190815260200160405180910390f35b60526054565b005b600080549080606283606b565b91905055565b600060018201608a57634e487b7160e01b600052601160045260246000fd5b506001019056fea164736f6c6343000811000a";

static uint8_t code[4096];
static size_t code_len;
static pthread_barrier_t barrier;

static void *run(void *arg)
{
    char *out = NULL;
    size_t len = 0;
    (void)arg;
    pthread_barrier_wait(&barrier);
    if (pan_decompile_ex(code, code_len, 1, NULL, &out, &len, PAN_NO_COLOR) != 0)
        return NULL;
    return out;
}

int main(int argc, char **argv)
{
    int n = argc > 1 ? atoi(argv[1]) : 8, i, bad = 0;
    pthread_t t[64];
    char *texts[64];

    if (n < 2 || n > 64)
        n = 8;
    /* quiet (read by the first call's log_init: pan_set_log_level would
     * initialize the library before the threads, and test nothing) */
    setenv("PANORAMIX_LOG", "error", 0);
    for (code_len = 0; HEX[2 * code_len]; code_len++)
        sscanf(HEX + 2 * code_len, "%2hhx", &code[code_len]);
    pthread_barrier_init(&barrier, NULL, n);
    for (i = 0; i < n; i++)
        pthread_create(&t[i], NULL, run, NULL);
    for (i = 0; i < n; i++)
        pthread_join(t[i], (void **)&texts[i]);
    /* every thread got the whole text, and the same one */
    for (i = 0; i < n; i++) {
        if (!texts[i] || !strstr(texts[i], "def get(): # not payable")) {
            fprintf(stderr, "init_race_test: thread %d: %.200s\n", i,
                    texts[i] ? texts[i] : "(failed)");
            bad = 1;
        } else if (strcmp(texts[i], texts[0]) != 0) {
            fprintf(stderr, "init_race_test: thread %d: another text\n", i);
            bad = 1;
        }
    }
    for (i = 0; i < n; i++)
        pan_free(texts[i]);
    return bad;
}
