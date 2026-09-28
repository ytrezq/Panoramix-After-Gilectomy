/* The C interface: decompiles a small contract twice at once from two
 * threads and checks the texts (and the disassembly). */
#include <panoramix_asm.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* a small contract: a getter over storage 0, and another function */
static const char *HEX =
    "6080604052348015600f57600080fd5b506004361060325760003560e01c80636d4ce63c146037578063d09de08a14604c575b600080fd5b60005460405190815260200160405180910390f35b60526054565b005b600080549080606283606b565b91905055565b600060018201608a57634e487b7160e01b600052601160045260246000fd5b506001019056fea164736f6c6343000811000a";

static uint8_t code[4096];
static size_t code_len;

static void *run(void *arg)
{
    char *out;
    size_t len;
    (void)arg;
    pan_decompile_ex(code, code_len, 2, NULL, &out, &len, PAN_NO_COLOR);
    return out;
}

int main(void)
{
    pthread_t a, b;
    char *ta, *tb, *dis;
    size_t dlen;

    for (code_len = 0; HEX[2 * code_len]; code_len++)
        sscanf(HEX + 2 * code_len, "%2hhx", &code[code_len]);
    pan_set_log_level(40);
    pthread_create(&a, NULL, run, NULL);
    pthread_create(&b, NULL, run, NULL);
    pthread_join(a, (void **)&ta);
    pthread_join(b, (void **)&tb);
    pan_disasm(code, code_len, &dis, &dlen);
    int ok = strcmp(ta, tb) == 0 && strstr(ta, "def storage:") && strstr(ta, "def get() payable:")
             && strchr(ta, '\033') == NULL && strstr(dis, "jumpdest");
    printf("%s", ta);
    printf("c_api_test: %s\n", ok ? "ok" : "FAILED");
    pan_free(ta);
    pan_free(tb);
    pan_free(dis);
    return ok ? 0 : 1;
}
