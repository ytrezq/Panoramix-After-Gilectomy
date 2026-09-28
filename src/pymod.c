/* panoramix_asm: the CPython wrapper. Everything happens in the assembly
 * library, this only converts the arguments and the result. */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>

int pan_init(void);
int pan_disasm(const unsigned char *code, size_t len, char **out, size_t *outlen);
void pan_free(void *p);
int pan_test(const char *name, const char *text, size_t len, char **out, size_t *outlen);
int pan_decompile(const unsigned char *code, size_t len, size_t threads, const char *only_func, char **out, size_t *outlen);
int pan_decompile_ex(const unsigned char *code, size_t len, size_t threads, const char *only_func, char **out, size_t *outlen, long flags);
typedef struct {
    char *text;
    size_t textlen;
    char *data;
    size_t datalen;
    char *explain;
    size_t explainlen;
} pan_output;
#define PAN_NO_COLOR 1
#define PAN_VERBOSE 8
#define PAN_EXPLAIN 16
#define PAN_REPR 32
#define PAN_RETURNS 64

/* python's `"--verbose" in sys.argv` (the lines of assembly) and
 * `"--explain" in sys.argv` (the traces of every stage printed): an
 * argument's value when given (not None), else sys.argv's say */
static int argv_flag(PyObject *given, const char *name, long *flags, long flag)
{
    int on;
    if (given && given != Py_None) {
        on = PyObject_IsTrue(given);
        if (on < 0) return -1;
    } else {
        PyObject *argv = PySys_GetObject("argv");     /* borrowed */
        on = 0;
        if (argv && PySequence_Check(argv)) {
            PyObject *s = PyUnicode_FromString(name);
            if (!s) return -1;
            on = PySequence_Contains(argv, s);
            Py_DECREF(s);
            if (on < 0) {
                PyErr_Clear();
                on = 0;
            }
        }
    }
    if (on) *flags |= flag;
    return 0;
}

/* python's print() of what --explain printed: to sys.stdout */
static int print_explain(const char *text, size_t len)
{
    PyObject *out = PySys_GetObject("stdout");      /* borrowed */
    PyObject *s, *r;
    if (!out || out == Py_None || !len) return 0;
    s = PyUnicode_DecodeUTF8(text, (Py_ssize_t)len, "surrogateescape");
    if (!s) return -1;
    r = PyObject_CallMethod(out, "write", "O", s);
    Py_DECREF(s);
    if (!r) return -1;
    Py_DECREF(r);
    return 0;
}
int pan_decompile_data(const unsigned char *code, size_t len, size_t threads, const char *only_func, long flags, pan_output *out);
int pan_build_sigdb(const char *xz_path, const char *out_path);
void pan_set_log_level(long level);
long pan_log_level_from_name(const char *name);

/* The bytecode of an argument: bytes, or any object with a contiguous
 * buffer (bytearray, memoryview...: the raw bytecode, held - a bytearray
 * can't be resized while it's exported - until release_code, since the
 * work runs without the GIL), or str (hex, 0x optional). */
typedef struct {
    Py_buffer view;
    int has_view;
    PyObject *holder;
} code_ref;

static int get_code(PyObject *arg, unsigned char **code, size_t *len, code_ref *ref)
{
    ref->has_view = 0;
    ref->holder = NULL;
    if (PyBytes_Check(arg)) {
        *code = (unsigned char *)PyBytes_AS_STRING(arg);
        *len = PyBytes_GET_SIZE(arg);
        return 0;
    }
    if (PyUnicode_Check(arg)) {
        PyObject *b = PyObject_CallMethod(arg, "strip", NULL);
        if (!b) return -1;
        PyObject *hexed = PyObject_CallMethod(b, "removeprefix", "s", "0x");
        Py_DECREF(b);
        if (!hexed) return -1;
        PyObject *raw = PyObject_CallMethod((PyObject *)&PyBytes_Type, "fromhex", "O", hexed);
        Py_DECREF(hexed);
        if (!raw) return -1;
        ref->holder = raw;
        *code = (unsigned char *)PyBytes_AS_STRING(raw);
        *len = PyBytes_GET_SIZE(raw);
        return 0;
    }
    if (PyObject_CheckBuffer(arg)) {
        if (PyObject_GetBuffer(arg, &ref->view, PyBUF_SIMPLE)) return -1;
        ref->has_view = 1;
        *code = (unsigned char *)ref->view.buf;
        *len = (size_t)ref->view.len;
        return 0;
    }
    PyErr_SetString(PyExc_TypeError, "expected bytes (or a bytes-like object) or a hex string");
    return -1;
}

static void release_code(code_ref *ref)
{
    if (ref->has_view) PyBuffer_Release(&ref->view);
    Py_XDECREF(ref->holder);
}

static PyObject *py_disasm(PyObject *self, PyObject *args)
{
    PyObject *arg;
    code_ref ref;
    unsigned char *code;
    size_t len, outlen;
    char *out;
    int rc;

    if (!PyArg_ParseTuple(args, "O", &arg)) return NULL;
    if (get_code(arg, &code, &len, &ref)) return NULL;
    Py_BEGIN_ALLOW_THREADS
    rc = pan_disasm(code, len, &out, &outlen);
    Py_END_ALLOW_THREADS
    release_code(&ref);
    if (rc) {
        PyErr_SetString(PyExc_RuntimeError, "disassembly failed");
        return NULL;
    }
    PyObject *res = PyUnicode_FromStringAndSize(out, outlen);
    pan_free(out);
    return res;
}

static PyObject *py_decompile(PyObject *self, PyObject *args, PyObject *kwargs)
{
    static char *kwlist[] = {"code", "threads", "function", "color", "verbose", "explain", NULL};
    PyObject *arg;
    code_ref ref;
    unsigned char *code;
    size_t len, outlen;
    char *out;
    Py_ssize_t threads = 0;
    const char *function = NULL;
    int color = 1, verbose = 0, explain = 0;
    long flags;
    int rc;

    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O|nzppp", kwlist, &arg, &threads, &function, &color, &verbose, &explain)) return NULL;
    if (get_code(arg, &code, &len, &ref)) return NULL;
    if (threads <= 0) {
        threads = (Py_ssize_t)sysconf(_SC_NPROCESSORS_ONLN);
        if (threads <= 0) threads = 1;
    }
    flags = (color ? 0 : PAN_NO_COLOR) | (verbose ? PAN_VERBOSE : 0) | (explain ? PAN_EXPLAIN : 0);
    Py_BEGIN_ALLOW_THREADS
    rc = pan_decompile_ex(code, len, (size_t)threads, function, &out, &outlen, flags);
    Py_END_ALLOW_THREADS
    release_code(&ref);
    if (rc) {
        /* out: the message */
        PyErr_SetString(PyExc_RuntimeError, out ? out : "decompilation failed");
        pan_free(out);
        return NULL;
    }
    PyObject *res = PyUnicode_FromStringAndSize(out, outlen);
    pan_free(out);
    return res;
}

/* python's objects back from the binary form of the data (data.s) */
typedef struct {
    const unsigned char *p, *end;
} reader;

#define MAX_DEPTH 20000

static int read_u32(reader *r, size_t *n)
{
    uint32_t v;
    if (r->end - r->p < 4) return -1;
    memcpy(&v, r->p, 4);
    r->p += 4;
    *n = v;
    return 0;
}

static PyObject *read_value(reader *r, int depth)
{
    size_t n, i;
    PyObject *res, *k, *v;
    char *tmp;
    unsigned char tag;

    if (depth > MAX_DEPTH) {
        PyErr_SetString(PyExc_RecursionError, "the decompilation's data nests too deep");
        return NULL;
    }
    if (r->p >= r->end) goto truncated;
    tag = *r->p++;
    switch (tag) {
    case 'N':
        Py_RETURN_NONE;
    case 'T':
        Py_RETURN_TRUE;
    case 'F':
        Py_RETURN_FALSE;
    case 'i': {
        int64_t x;
        if (r->end - r->p < 8) goto truncated;
        memcpy(&x, r->p, 8);
        r->p += 8;
        return PyLong_FromLongLong(x);
    }
    case 'I':
    case 'f':
    case 's':
        if (read_u32(r, &n) || (size_t)(r->end - r->p) < n) goto truncated;
        if (tag == 's') {
            res = PyUnicode_DecodeUTF8((const char *)r->p, (Py_ssize_t)n, "surrogateescape");
            r->p += n;
            return res;
        }
        tmp = PyMem_Malloc(n + 1);
        if (!tmp) return PyErr_NoMemory();
        memcpy(tmp, r->p, n);
        tmp[n] = 0;
        r->p += n;
        if (tag == 'I') {
            res = PyLong_FromString(tmp, NULL, 16);
        } else {
            double d = PyOS_string_to_double(tmp, NULL, NULL);
            res = (d == -1.0 && PyErr_Occurred()) ? NULL : PyFloat_FromDouble(d);
        }
        PyMem_Free(tmp);
        return res;
    case '(':
    case '[':
        if (read_u32(r, &n)) goto truncated;
        if (n > (size_t)(r->end - r->p)) goto truncated;   /* (a byte at least each) */
        res = tag == '(' ? PyTuple_New((Py_ssize_t)n) : PyList_New((Py_ssize_t)n);
        if (!res) return NULL;
        for (i = 0; i < n; i++) {
            v = read_value(r, depth + 1);
            if (!v) {
                Py_DECREF(res);
                return NULL;
            }
            if (tag == '(')
                PyTuple_SET_ITEM(res, (Py_ssize_t)i, v);
            else
                PyList_SET_ITEM(res, (Py_ssize_t)i, v);
        }
        return res;
    case '{':
        if (read_u32(r, &n)) goto truncated;
        res = PyDict_New();
        if (!res) return NULL;
        for (i = 0; i < n; i++) {
            k = read_value(r, depth + 1);
            if (!k) {
                Py_DECREF(res);
                return NULL;
            }
            v = read_value(r, depth + 1);
            if (!v || PyDict_SetItem(res, k, v)) {
                Py_DECREF(k);
                Py_XDECREF(v);
                Py_DECREF(res);
                return NULL;
            }
            Py_DECREF(k);
            Py_DECREF(v);
        }
        return res;
    }
    PyErr_Format(PyExc_ValueError, "the decompilation's data: unexpected tag %d", tag);
    return NULL;
truncated:
    PyErr_SetString(PyExc_ValueError, "the decompilation's data is cut short");
    return NULL;
}

static PyStructSequence_Field decompilation_fields[] = {
    {"text", "the decompiled contract, as `python -m panoramix` prints it"},
    {"asm", "the disassembly: a str per instruction"},
    {"json", "python's decompilation.json: the problems, the storage definitions, the functions"},
    {"explain", "what --explain printed (on sys.stdout too, as python prints it), or None"},
    {NULL, NULL}
};

static PyStructSequence_Desc decompilation_desc = {
    "panoramix_asm.Decompilation",
    "What panoramix.decompiler.decompile_bytecode returns: text, asm, json",
    decompilation_fields,
    3
};

static PyTypeObject *DecompilationType;

static PyObject *py_decompile_bytecode(PyObject *self, PyObject *args, PyObject *kwargs)
{
    static char *kwlist[] = {"code", "only_func_name", "threads", "color", "verbose", "explain", NULL};
    PyObject *arg, *text = NULL, *json = NULL, *asm_text = NULL, *asm_list = NULL, *res;
    PyObject *verbose = NULL, *explain = NULL, *explained = NULL;
    code_ref ref;
    unsigned char *code;
    size_t len, asmlen = 0;
    char *asm_out = NULL;
    pan_output out;
    Py_ssize_t threads = 0;
    const char *function = NULL;
    int color = 1;
    long flags;
    int rc, asm_rc;

    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O|znpOO", kwlist, &arg, &function, &threads, &color, &verbose, &explain)) return NULL;
    flags = color ? 0 : PAN_NO_COLOR;
    if (argv_flag(verbose, "--verbose", &flags, PAN_VERBOSE) || argv_flag(explain, "--explain", &flags, PAN_EXPLAIN)
        || argv_flag(NULL, "--repr", &flags, PAN_REPR) || argv_flag(NULL, "--returns", &flags, PAN_RETURNS)) return NULL;
    if (get_code(arg, &code, &len, &ref)) return NULL;
    if (threads <= 0) {
        threads = (Py_ssize_t)sysconf(_SC_NPROCESSORS_ONLN);
        if (threads <= 0) threads = 1;
    }
    memset(&out, 0, sizeof out);
    Py_BEGIN_ALLOW_THREADS
    rc = pan_decompile_data(code, len, (size_t)threads, function, flags, &out);
    asm_rc = rc ? 0 : pan_disasm(code, len, &asm_out, &asmlen);
    Py_END_ALLOW_THREADS
    release_code(&ref);
    if (out.explain) {
        /* printed along the way by python, even when it failed after */
        if (!rc) explained = PyUnicode_DecodeUTF8(out.explain, (Py_ssize_t)out.explainlen, "surrogateescape");
        if (print_explain(out.explain, out.explainlen) || (!rc && !explained)) {
            pan_free(out.explain);
            pan_free(out.text);
            pan_free(out.data);
            pan_free(asm_out);
            Py_XDECREF(explained);
            return NULL;
        }
        pan_free(out.explain);
    }
    if (rc) {
        PyErr_SetString(PyExc_RuntimeError, out.text ? out.text : "decompilation failed");
        pan_free(out.text);
        pan_free(out.data);
        return NULL;
    }
    text = PyUnicode_FromStringAndSize(out.text, (Py_ssize_t)out.textlen);
    if (text) {
        reader r = {(const unsigned char *)out.data, (const unsigned char *)out.data + out.datalen};
        json = out.data ? read_value(&r, 0) : PyDict_New();
    }
    if (json && !asm_rc) {
        asm_text = PyUnicode_FromStringAndSize(asm_out, (Py_ssize_t)asmlen);
        if (asm_text) asm_list = PyUnicode_Splitlines(asm_text, 0);
    } else if (json) {
        PyErr_SetString(PyExc_RuntimeError, "disassembly failed");
    }
    pan_free(out.text);
    pan_free(out.data);
    pan_free(asm_out);
    Py_XDECREF(asm_text);
    if (!asm_list) {
        Py_XDECREF(text);
        Py_XDECREF(json);
        Py_XDECREF(explained);
        return NULL;
    }
    res = PyStructSequence_New(DecompilationType);
    if (!res) {
        Py_DECREF(text);
        Py_DECREF(json);
        Py_DECREF(asm_list);
        Py_XDECREF(explained);
        return NULL;
    }
    if (!explained) {
        explained = Py_None;
        Py_INCREF(Py_None);
    }
    PyStructSequence_SET_ITEM(res, 0, text);
    PyStructSequence_SET_ITEM(res, 1, asm_list);
    PyStructSequence_SET_ITEM(res, 2, json);
    PyStructSequence_SET_ITEM(res, 3, explained);
    return res;
}

static PyObject *py_build_signature_db(PyObject *self, PyObject *args)
{
    const char *xz, *out = NULL;
    int rc;

    if (!PyArg_ParseTuple(args, "s|z", &xz, &out)) return NULL;
    Py_BEGIN_ALLOW_THREADS
    rc = pan_build_sigdb(xz, out);
    Py_END_ALLOW_THREADS
    if (rc) {
        PyErr_SetString(PyExc_RuntimeError, "building the signature database failed");
        return NULL;
    }
    Py_RETURN_NONE;
}

/* set_log_level(level): an int (logging.DEBUG...) or a name ("debug"...) */
static PyObject *py_set_log_level(PyObject *self, PyObject *arg)
{
    long level;

    if (PyLong_Check(arg)) {
        level = PyLong_AsLong(arg);
        if (level == -1 && PyErr_Occurred()) return NULL;
    } else if (PyUnicode_Check(arg)) {
        const char *name = PyUnicode_AsUTF8(arg);
        if (!name) return NULL;
        level = pan_log_level_from_name(name);
        if (level < 0) {
            PyErr_Format(PyExc_ValueError, "unknown log level: %s", name);
            return NULL;
        }
    } else {
        PyErr_SetString(PyExc_TypeError, "expected an int or a level name");
        return NULL;
    }
    pan_set_log_level(level);
    Py_RETURN_NONE;
}

static PyObject *py_test(PyObject *self, PyObject *args)
{
    const char *name, *text;
    Py_ssize_t len;
    char *out;
    size_t outlen;

    if (!PyArg_ParseTuple(args, "ss#", &name, &text, &len)) return NULL;
    if (pan_test(name, text, len, &out, &outlen)) {
        PyErr_SetString(PyExc_RuntimeError, "test call failed");
        return NULL;
    }
    PyObject *res = PyUnicode_FromStringAndSize(out, outlen);
    pan_free(out);
    return res;
}

static PyMethodDef methods[] = {
    {"build_signature_db", py_build_signature_db, METH_VARARGS, "build_signature_db(abi_dump_xz, out=None): convert panoramix's signature dump into the database file (in the cache directory by default)"},
    {"_test", py_test, METH_VARARGS, "_test(name, literal) -> str: apply a library function to a python literal"},
    {"set_log_level", py_set_log_level, METH_O, "set_log_level(level): the level of the messages printed on stderr, an int (logging.INFO...) or a name (\"debug\", \"info\", \"warning\", \"error\"); WARNING by default, as a library, unless PANORAMIX_LOG is set"},
    {"disasm", py_disasm, METH_VARARGS, "disasm(code) -> str: the disassembly, one instruction per line (code: as for decompile)"},
    {"decompile_bytecode", (PyCFunction)py_decompile_bytecode, METH_VARARGS | METH_KEYWORDS, "decompile_bytecode(code, only_func_name=None, threads=0, color=True, verbose=None, explain=None) -> Decompilation(text, asm, json): as panoramix.decompiler.decompile_bytecode - the text, the disassembly (a list of str) and python's decompilation.json (a dict of python's objects: the problems, the storage definitions, the functions); color only changes the text. verbose, explain: python's --verbose (the instructions run as comments of the text) and --explain (every stage's trace, printed on sys.stdout as python prints it, and in the result's .explain) - by default, as python, whether sys.argv holds them"},
    {"decompile", (PyCFunction)py_decompile, METH_VARARGS | METH_KEYWORDS, "decompile(code, threads=0, function=None, color=True, verbose=False, explain=False) -> str: the decompiled contract, as `python -m panoramix` prints it (code: bytes or a bytes-like object, or hex; threads: 0 for one per CPU; function: only the functions whose name starts with it; verbose, explain: as its --verbose and --explain, what --explain prints first)"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "panoramix_asm", "EVM decompiler (assembly core)", -1, methods
};

PyMODINIT_FUNC PyInit_panoramix_asm(void)
{
    pan_init();
    /* as a library, like python's logging without a handler: the warnings
       and the errors only (the command line tool shows INFO, like
       `python -m panoramix`) */
    if (!getenv("PANORAMIX_LOG"))
        pan_set_log_level(30);
    PyObject *m = PyModule_Create(&module);
    if (!m) return NULL;
    DecompilationType = PyStructSequence_NewType(&decompilation_desc);
    if (!DecompilationType || PyModule_AddObject(m, "Decompilation", (PyObject *)DecompilationType)) {
        Py_XDECREF(DecompilationType);
        Py_DECREF(m);
        return NULL;
    }
    Py_INCREF(DecompilationType);
    return m;
}
