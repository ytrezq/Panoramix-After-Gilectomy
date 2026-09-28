/* The C interface: decompiles a small contract twice at once from two
 * threads and checks the texts (and the disassembly, and the json, and
 * the --explain / --verbose outputs). */
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
    /* the text again, with python's json */
    pan_output o;
    int rc = pan_decompile_data(code, code_len, 1, NULL, PAN_NO_COLOR | PAN_JSON, &o);
    int ok = strcmp(ta, tb) == 0 && strstr(ta, "def storage:") && strstr(ta, "def get() payable:")
             && strchr(ta, '\033') == NULL && strstr(dis, "jumpdest")
             && rc == 0 && strcmp(o.text, ta) == 0 && o.datalen == strlen(o.data)
             && strncmp(o.data, "{\"problems\": {}, \"stor_defs\": [", 31) == 0
             && strstr(o.data, "\"functions\": [{\"hash\": \"0x6d4ce63c\"");
    /* --explain apart (pan_output.explain), and before the text
       (pan_decompile_ex); --verbose's instructions in the text */
    pan_output e;
    char *te, *tv;
    size_t le, lv;
    int rce = pan_decompile_data(code, code_len, 2, NULL, PAN_NO_COLOR | PAN_EXPLAIN, &e);
    int rcx = pan_decompile_ex(code, code_len, 2, NULL, &te, &le, PAN_NO_COLOR | PAN_EXPLAIN);
    int rcv = pan_decompile_ex(code, code_len, 2, NULL, &tv, &lv, PAN_NO_COLOR | PAN_VERBOSE);
    int ok_explain = rce == 0 && rcx == 0 && rcv == 0 && e.explain && e.explainlen == strlen(e.explain)
                     && strstr(e.explain, " Initial decompiled trace: ") && strstr(e.explain, " function traits: ")
                     && strchr(e.explain, '\033') == NULL
                     && le == e.explainlen + e.textlen && strncmp(te, e.explain, e.explainlen) == 0
                     && strcmp(te + e.explainlen, e.text) == 0
                     && strstr(tv, "# [56] push1 0") && strstr(tv, "#        [uint32(call.func_hash) >> 224, 0]");
    printf("%s", ta);
    printf("%.200s...\n", o.data);
    printf("%.300s...\n", e.explain);
    printf("c_api_test: %s\n", ok && ok_explain ? "ok" : "FAILED");
    pan_free(ta);
    pan_free(tb);
    pan_free(dis);
    pan_free(o.text);
    pan_free(o.data);
    pan_free(e.text);
    pan_free(e.data);
    pan_free(e.explain);
    pan_free(te);
    pan_free(tv);
    return ok && ok_explain ? 0 : 1;
}
