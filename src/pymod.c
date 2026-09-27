/* panoramix_asm: the CPython wrapper. Everything happens in the assembly
 * library, this only converts the arguments and the result. */
#define PY_SSIZE_T_CLEAN
#include <Python.h>

int pan_init(void);
int pan_disasm(const unsigned char *code, size_t len, char **out, size_t *outlen);
void pan_free(void *p);
int pan_test(const char *name, const char *text, size_t len, char **out, size_t *outlen);

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
    {"_test", py_test, METH_VARARGS, "_test(name, literal) -> str: apply a library function to a python literal"},
    {"disasm", py_disasm, METH_VARARGS, "disasm(code) -> str: the disassembly, one instruction per line"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "panoramix_asm", "EVM decompiler (assembly core)", -1, methods
};

PyMODINIT_FUNC PyInit_panoramix_asm(void)
{
    pan_init();
    return PyModule_Create(&module);
}
