/* panoramix_asm: the CPython wrapper. Everything happens in the assembly
 * library, this only converts the arguments and the result. */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <unistd.h>

int pan_init(void);
int pan_disasm(const unsigned char *code, size_t len, char **out, size_t *outlen);
void pan_free(void *p);
int pan_test(const char *name, const char *text, size_t len, char **out, size_t *outlen);
int pan_decompile(const unsigned char *code, size_t len, size_t threads, const char *only_func, char **out, size_t *outlen);
int pan_decompile_ex(const unsigned char *code, size_t len, size_t threads, const char *only_func, char **out, size_t *outlen, long flags);
int pan_build_sigdb(const char *xz_path, const char *out_path);
void pan_set_log_level(long level);
long pan_log_level_from_name(const char *name);

/* accepts bytes (raw bytecode) or str (hex, 0x optional) */
static int get_code(PyObject *arg, unsigned char **code, size_t *len, PyObject **holder)
{
    *holder = NULL;
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
        *holder = raw;
        *code = (unsigned char *)PyBytes_AS_STRING(raw);
        *len = PyBytes_GET_SIZE(raw);
        return 0;
    }
    PyErr_SetString(PyExc_TypeError, "expected bytes or a hex string");
    return -1;
}

static PyObject *py_disasm(PyObject *self, PyObject *args)
{
    PyObject *arg, *holder;
    unsigned char *code;
    size_t len, outlen;
    char *out;
    int rc;

    if (!PyArg_ParseTuple(args, "O", &arg)) return NULL;
    if (get_code(arg, &code, &len, &holder)) return NULL;
    Py_BEGIN_ALLOW_THREADS
    rc = pan_disasm(code, len, &out, &outlen);
    Py_END_ALLOW_THREADS
    Py_XDECREF(holder);
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
    static char *kwlist[] = {"code", "threads", "function", "color", NULL};
    PyObject *arg, *holder;
    unsigned char *code;
    size_t len, outlen;
    char *out;
    Py_ssize_t threads = 0;
    const char *function = NULL;
    int color = 1;
    int rc;

    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O|nzp", kwlist, &arg, &threads, &function, &color)) return NULL;
    if (get_code(arg, &code, &len, &holder)) return NULL;
    if (threads <= 0) {
        threads = (Py_ssize_t)sysconf(_SC_NPROCESSORS_ONLN);
        if (threads <= 0) threads = 1;
    }
    Py_BEGIN_ALLOW_THREADS
    rc = pan_decompile_ex(code, len, (size_t)threads, function, &out, &outlen, color ? 0 : 1);
    Py_END_ALLOW_THREADS
    Py_XDECREF(holder);
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
    {"disasm", py_disasm, METH_VARARGS, "disasm(code) -> str: the disassembly, one instruction per line"},
    {"decompile", (PyCFunction)py_decompile, METH_VARARGS | METH_KEYWORDS, "decompile(code, threads=0, function=None, color=True) -> str: the decompiled contract, as `python -m panoramix` prints it (code: bytes, or hex; threads: 0 for one per CPU; function: only the functions whose name starts with it)"},
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
    return PyModule_Create(&module);
}
