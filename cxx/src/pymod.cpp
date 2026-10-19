// The python module (CPython's C API): the asm's panoramix_asm module's
// functions and objects - decompile, decompile_bytecode -> Decompilation,
// decompile_address, disasm, set_log_level, build_signature_db (its _test
// is gone) - over the core's interface (decompile.hpp). This only converts
// the arguments and the results; a str of hex is made bytes by hex.hpp's
// machine. Built as panoramix_cxx, and again as panoramix_asm for the
// repository's scripts (-DPAN_PYMODULE=NAME: the module's name and its
// PyInit_ function).
#define PY_SSIZE_T_CLEAN
#include <Python.h>

#include <algorithm>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <new>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

#include "cli.hpp"
#include "decompile.hpp"
#include "fetch.hpp"
#include "hex.hpp"
#include "io.hpp"
#include "sigdb.hpp"
#include "version.hpp"

#ifndef PAN_PYMODULE
#define PAN_PYMODULE panoramix_cxx
#endif
#define PAN_STRING_(x) #x
#define PAN_STRING(x) PAN_STRING_(x)
#define PAN_CONCAT_(a, b) a##b
#define PAN_CONCAT(a, b) PAN_CONCAT_(a, b)

namespace {

constexpr const char* module_name = PAN_STRING(PAN_PYMODULE);

// --- errors -------------------------------------------------------------------

// a python exception of the type, its message any bytes (a message of the
// core's or of a node's: not necessarily UTF-8)
PyObject* raise(PyObject* type, std::string_view message)
{
    PyObject* text = PyUnicode_DecodeUTF8(message.data(), static_cast<Py_ssize_t>(message.size()), "surrogateescape");
    if (text) {
        PyErr_SetObject(type, text);
        Py_DECREF(text);
    }
    return nullptr;
}

// the C++ exception being handled, as a python one
PyObject* python_error() noexcept
{
    try {
        throw;
    } catch (const pan::fetch::Error& e) {
        return raise(PyExc_ConnectionError, e.what());
    } catch (const std::bad_alloc&) {
        return PyErr_NoMemory();
    } catch (const std::exception& e) {
        return raise(PyExc_RuntimeError, e.what());
    } catch (...) {
        return raise(PyExc_RuntimeError, "unknown error");
    }
}

// --- the calls into the library -------------------------------------------------

// The GIL let go of while it lives (the work runs without it: other python
// threads go on meanwhile)
class Unlocked {
public:
    Unlocked() : state_(PyEval_SaveThread()) {}
    ~Unlocked() { PyEval_RestoreThread(state_); }
    Unlocked(const Unlocked&) = delete;
    Unlocked& operator=(const Unlocked&) = delete;

private:
    PyThreadState* state_;
};

// f() without the GIL, the signals the program handles held meanwhile
// (io::HeldSignals): a call into the library is not interrupted halfway - a
// CTRL+C waits for it to return; python's handler only sets a flag for the
// main thread's next bytecode, so it couldn't stop the call anyway, but
// delivered in the middle of one it cut the system calls running on this
// thread short (a node's connection given up). Let in when f returns, the
// signals are delivered at once and PyErr_CheckSignals runs their python
// handlers: the exception one raises (KeyboardInterrupt) is the call's
// (nullopt), and what f made is dropped. Then what f returned, or its
// exception rethrown.
template <class F>
std::optional<std::invoke_result_t<F>> call(F&& f)
{
    std::optional<std::invoke_result_t<F>> result;
    std::exception_ptr failure;
    {
        pan::io::HeldSignals held;
        Unlocked unlocked;
        try {
            result.emplace(f());
        } catch (...) {
            failure = std::current_exception();
        }
    }  // (the GIL back, then the signals let in)
    if (PyErr_CheckSignals() < 0)
        return std::nullopt;
    if (failure)
        std::rethrow_exception(failure);
    return result;
}

// --- the arguments ----------------------------------------------------------------

// The bytecode of an argument: bytes, or any object with a contiguous buffer
// (bytearray, memoryview...: the raw bytecode, held - a bytearray can't be
// resized while it's exported - until the object goes, since the work runs
// without the GIL), or str (hex, 0x optional: made bytes here).
class Code {
public:
    Code() = default;
    Code(const Code&) = delete;
    Code& operator=(const Code&) = delete;
    ~Code()
    {
        if (has_view_)
            PyBuffer_Release(&view_);
    }

    // false with the python exception set
    bool take(PyObject* arg)
    {
        if (PyBytes_Check(arg)) {
            bytes_ = {reinterpret_cast<const std::uint8_t*>(PyBytes_AS_STRING(arg)),
                      static_cast<std::size_t>(PyBytes_GET_SIZE(arg))};
            return true;
        }
        if (PyUnicode_Check(arg)) {
            Py_ssize_t size = 0;
            const char* text = PyUnicode_AsUTF8AndSize(arg, &size);
            if (!text)
                return false;
            auto decoded = pan::hex::decode({text, static_cast<std::size_t>(size)});
            if (!decoded) {
                if (decoded.error().odd)
                    PyErr_SetString(PyExc_ValueError, "the code isn't hex: an odd number of digits");
                else
                    PyErr_Format(PyExc_ValueError, "the code isn't hex: a non-hexadecimal character at position %zu",
                                 decoded.error().offset);
                return false;
            }
            decoded_ = std::move(*decoded);
            bytes_ = decoded_;
            return true;
        }
        if (PyObject_CheckBuffer(arg)) {
            if (PyObject_GetBuffer(arg, &view_, PyBUF_SIMPLE) != 0)
                return false;
            has_view_ = true;
            bytes_ = {static_cast<const std::uint8_t*>(view_.buf), static_cast<std::size_t>(view_.len)};
            return true;
        }
        PyErr_SetString(PyExc_TypeError, "expected bytes (or a bytes-like object) or a hex string");
        return false;
    }

    std::span<const std::uint8_t> bytes() const { return bytes_; }

private:
    std::span<const std::uint8_t> bytes_;
    std::vector<std::uint8_t> decoded_;
    Py_buffer view_{};
    bool has_view_ = false;
};

// python's `"--verbose" in sys.argv`: the argument's truth when it is given
// (not None), else whether sys.argv holds the flag. -1 with the exception set.
int argv_flag(PyObject* given, const char* flag)
{
    if (given && given != Py_None)
        return PyObject_IsTrue(given);
    PyObject* argv = PySys_GetObject("argv");  // (borrowed)
    if (!argv || !PySequence_Check(argv))
        return 0;
    PyObject* name = PyUnicode_FromString(flag);
    if (!name)
        return -1;
    int in = PySequence_Contains(argv, name);
    Py_DECREF(name);
    if (in < 0) {
        PyErr_Clear();
        in = 0;
    }
    return in;
}

// the threads asked for: 0 or less for one per CPU (the options' 0)
std::size_t thread_count(Py_ssize_t threads)
{
    return threads > 0 ? static_cast<std::size_t>(threads) : 0;
}

// --- the results ------------------------------------------------------------------

PyObject* text_object(std::string_view text)
{
    return PyUnicode_DecodeUTF8(text.data(), static_cast<Py_ssize_t>(text.size()), "surrogateescape");
}

// python's print() of what --explain printed: to sys.stdout
bool print_explain(std::string_view text)
{
    PyObject* out = PySys_GetObject("stdout");  // (borrowed)
    if (!out || out == Py_None || text.empty())
        return true;
    PyObject* s = text_object(text);
    if (!s)
        return false;
    PyObject* r = PyObject_CallMethod(out, "write", "O", s);
    Py_DECREF(s);
    Py_XDECREF(r);
    return r != nullptr;
}

// the decompilation's JSON as python's objects (the json module's)
PyObject* json_object(std::string_view text)
{
    if (text.empty())
        return PyDict_New();
    PyObject* json = PyImport_ImportModule("json");
    if (!json)
        return nullptr;
    PyObject* r = PyObject_CallMethod(json, "loads", "s#", text.data(), static_cast<Py_ssize_t>(text.size()));
    Py_DECREF(json);
    return r;
}

PyObject* list_object(const std::vector<std::string>& lines)
{
    PyObject* list = PyList_New(static_cast<Py_ssize_t>(lines.size()));
    if (!list)
        return nullptr;
    for (std::size_t i = 0; i < lines.size(); ++i) {
        PyObject* line = text_object(lines[i]);
        if (!line) {
            Py_DECREF(list);
            return nullptr;
        }
        PyList_SET_ITEM(list, static_cast<Py_ssize_t>(i), line);
    }
    return list;
}

PyStructSequence_Field decompilation_fields[] = {
    {"text", "the decompiled contract, as `python -m panoramix` prints it"},
    {"asm", "the disassembly: a str per instruction"},
    {"json", "python's decompilation.json: the problems, the storage definitions, the functions"},
    {"explain", "what --explain printed (on sys.stdout too, as python prints it), or None"},
    {nullptr, nullptr},
};

const std::string decompilation_type_name = std::string(module_name) + ".Decompilation";

PyStructSequence_Desc decompilation_desc = {
    decompilation_type_name.c_str(),
    "What panoramix.decompiler.decompile_bytecode returns: text, asm, json",
    decompilation_fields,
    3,
};

PyTypeObject* decompilation_type = nullptr;

// The Decompilation of the code: --explain's text printed along the way
// (even when it failed), then the text, the disassembly, the json
PyObject* decompilation(std::span<const std::uint8_t> code, const pan::DecompileOptions& options)
{
    std::optional<pan::Decompilation> d;
    try {
        d = call([&] { return pan::decompile(code, options); });
    } catch (const pan::DecompileError& e) {
        if (options.explain && !print_explain(e.explain()))
            return nullptr;
        throw;
    }
    if (!d)
        return nullptr;
    PyObject* explained = Py_None;
    if (options.explain) {
        if (!print_explain(d->explain))
            return nullptr;
        explained = text_object(d->explain);
        if (!explained)
            return nullptr;
    } else {
        Py_INCREF(Py_None);
    }
    PyObject* text = text_object(d->text);
    PyObject* asm_lines = text ? list_object(d->asm_lines) : nullptr;
    PyObject* json = asm_lines ? json_object(d->json) : nullptr;
    PyObject* result = json ? PyStructSequence_New(decompilation_type) : nullptr;
    if (!result) {
        Py_XDECREF(text);
        Py_XDECREF(asm_lines);
        Py_XDECREF(json);
        Py_DECREF(explained);
        return nullptr;
    }
    PyStructSequence_SET_ITEM(result, 0, text);
    PyStructSequence_SET_ITEM(result, 1, asm_lines);
    PyStructSequence_SET_ITEM(result, 2, json);
    PyStructSequence_SET_ITEM(result, 3, explained);
    return result;
}

// decompile_bytecode's and decompile_address's options: python's flags of
// sys.argv (--verbose, --explain unless given; --repr, --returns), the
// json and the disassembly made. false with the exception set.
bool decompilation_options(pan::DecompileOptions& options, const char* function, Py_ssize_t threads, int color,
                           PyObject* verbose, PyObject* explain)
{
    options.only_function = function ? function : "";
    options.threads = thread_count(threads);
    options.color = color != 0;
    const int v = argv_flag(verbose, "--verbose");
    const int x = v < 0 ? -1 : argv_flag(explain, "--explain");
    const int r = x < 0 ? -1 : argv_flag(nullptr, "--repr");
    const int s = r < 0 ? -1 : argv_flag(nullptr, "--returns");
    if (s < 0)
        return false;
    options.verbose = v || x;
    options.explain = x;
    options.repr = r;
    options.returns = s;
    options.json = options.asm_lines = true;
    return true;
}

// --- the functions --------------------------------------------------------------

PyObject* py_disasm(PyObject*, PyObject* args)
{
    try {
        PyObject* arg;
        if (!PyArg_ParseTuple(args, "O", &arg))
            return nullptr;
        Code code;
        if (!code.take(arg))
            return nullptr;
        std::optional<std::string> text;
        try {
            text = call([&] { return pan::disassemble(code.bytes()); });
        } catch (const std::bad_alloc&) {
            throw;
        } catch (const std::exception&) {
            return raise(PyExc_RuntimeError, "disassembly failed");
        }
        return text ? text_object(*text) : nullptr;
    } catch (...) {
        return python_error();
    }
}

PyObject* py_decompile(PyObject*, PyObject* args, PyObject* kwargs)
{
    try {
        static const char* kwlist[] = {"code", "threads", "function", "color", "verbose", "explain", nullptr};
        PyObject* arg;
        Py_ssize_t threads = 0;
        const char* function = nullptr;
        int color = 1, verbose = 0, explain = 0;
        if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O|nzppp", const_cast<char**>(kwlist), &arg, &threads,
                                         &function, &color, &verbose, &explain))
            return nullptr;
        Code code;
        if (!code.take(arg))
            return nullptr;
        pan::DecompileOptions options;
        options.threads = thread_count(threads);
        options.only_function = function ? function : "";
        options.color = color != 0;
        options.verbose = verbose || explain;
        options.explain = explain != 0;
        const auto d = call([&] { return pan::decompile(code.bytes(), options); });
        if (!d)
            return nullptr;
        // (--explain's text first, as `python -m panoramix --explain` prints it)
        return text_object(options.explain ? d->explain + d->text : d->text);
    } catch (...) {
        return python_error();
    }
}

PyObject* py_decompile_bytecode(PyObject*, PyObject* args, PyObject* kwargs)
{
    try {
        static const char* kwlist[] = {"code", "only_func_name", "threads", "color", "verbose", "explain", nullptr};
        PyObject *arg, *verbose = nullptr, *explain = nullptr;
        const char* function = nullptr;
        Py_ssize_t threads = 0;
        int color = 1;
        if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O|znpOO", const_cast<char**>(kwlist), &arg, &function,
                                         &threads, &color, &verbose, &explain))
            return nullptr;
        pan::DecompileOptions options;
        if (!decompilation_options(options, function, threads, color, verbose, explain))
            return nullptr;
        Code code;
        if (!code.take(arg))
            return nullptr;
        return decompilation(code.bytes(), options);
    } catch (...) {
        return python_error();
    }
}

PyObject* py_decompile_address(PyObject*, PyObject* args, PyObject* kwargs)
{
    try {
        static const char* kwlist[] = {"address", "only_func_name", "threads", "color", "verbose", "explain", nullptr};
        PyObject *verbose = nullptr, *explain = nullptr;
        const char* address;
        const char* function = nullptr;
        Py_ssize_t threads = 0;
        int color = 1;
        if (!PyArg_ParseTupleAndKeywords(args, kwargs, "s|znpOO", const_cast<char**>(kwlist), &address, &function,
                                         &threads, &color, &verbose, &explain))
            return nullptr;
        pan::DecompileOptions options;
        if (!decompilation_options(options, function, threads, color, verbose, explain))
            return nullptr;
        const std::string_view where = address;
        const auto code = call([&] { return pan::fetch::code_at(where); });
        if (!code)
            return nullptr;
        return decompilation(*code, options);
    } catch (...) {
        return python_error();
    }
}

PyObject* py_build_signature_db(PyObject*, PyObject* args)
{
    try {
        const char *dump, *out = nullptr;
        if (!PyArg_ParseTuple(args, "s|z", &dump, &out))
            return nullptr;
        const std::string dump_path = dump, out_path = out ? out : "";
        const auto rc = call([&] { return pan::build_signature_db(dump_path, out_path); });
        if (!rc)
            return nullptr;  // (the database built or not: as it is)
        if (*rc != 0)
            return raise(PyExc_RuntimeError, "building the signature database failed");
        Py_RETURN_NONE;
    } catch (...) {
        return python_error();
    }
}

// set_log_level(level): an int (logging.DEBUG...) or a name ("debug"...)
PyObject* py_set_log_level(PyObject*, PyObject* arg)
{
    try {
        long level;
        if (PyLong_Check(arg)) {
            level = PyLong_AsLong(arg);
            if (level == -1 && PyErr_Occurred())
                return nullptr;
        } else if (PyUnicode_Check(arg)) {
            Py_ssize_t size = 0;
            const char* name = PyUnicode_AsUTF8AndSize(arg, &size);
            if (!name)
                return nullptr;
            const auto named = pan::cli::log_level_from_name({name, static_cast<std::size_t>(size)});
            if (!named)
                return PyErr_Format(PyExc_ValueError, "unknown log level: %s", name);
            level = *named;
        } else {
            PyErr_SetString(PyExc_TypeError, "expected an int or a level name");
            return nullptr;
        }
        pan::set_log_level(static_cast<int>(std::clamp<long>(level, INT_MIN, INT_MAX)));
        Py_RETURN_NONE;
    } catch (...) {
        return python_error();
    }
}

template <class F>
PyCFunction method(F* f)
{
    return reinterpret_cast<PyCFunction>(reinterpret_cast<void (*)()>(f));
}

PyMethodDef methods[] = {
    {"build_signature_db", method(py_build_signature_db), METH_VARARGS,
     "build_signature_db(abi_dump_xz, out=None): convert panoramix's signature dump into the database file (in "
     "the cache directory by default)"},
    {"set_log_level", method(py_set_log_level), METH_O,
     "set_log_level(level): the level of the messages printed on stderr, an int (logging.INFO...) or a name "
     "(\"debug\", \"info\", \"warning\", \"error\"); WARNING by default, as a library, unless PANORAMIX_LOG is set"},
    {"disasm", method(py_disasm), METH_VARARGS,
     "disasm(code) -> str: the disassembly, one instruction per line (code: as for decompile)"},
    {"decompile_bytecode", method(py_decompile_bytecode), METH_VARARGS | METH_KEYWORDS,
     "decompile_bytecode(code, only_func_name=None, threads=0, color=True, verbose=None, explain=None) -> "
     "Decompilation(text, asm, json): as panoramix.decompiler.decompile_bytecode - the text, the disassembly (a "
     "list of str) and python's decompilation.json (a dict of python's objects: the problems, the storage "
     "definitions, the functions); color only changes the text. verbose, explain: python's --verbose (the "
     "instructions run as comments of the text) and --explain (every stage's trace, printed on sys.stdout as "
     "python prints it, and in the result's .explain) - by default, as python, whether sys.argv holds them"},
    {"decompile_address", method(py_decompile_address), METH_VARARGS | METH_KEYWORDS,
     "decompile_address(address, only_func_name=None, threads=0, color=True, verbose=None, explain=None) -> "
     "Decompilation: as panoramix.decompiler.decompile_address - the code deployed at the address (0x and 40 hex "
     "digits) fetched with eth_getCode from a node found as web3's automatic provider finds one "
     "($WEB3_PROVIDER_URI: http:// or file:// for an IPC socket; the default IPC sockets; $WEB3_HTTP_PROVIDER_URI "
     "or http://localhost:8545 - no TLS), then decompiled as by decompile_bytecode; ConnectionError when it can't "
     "be had"},
    {"decompile", method(py_decompile), METH_VARARGS | METH_KEYWORDS,
     "decompile(code, threads=0, function=None, color=True, verbose=False, explain=False) -> str: the decompiled "
     "contract, as `python -m panoramix` prints it (code: bytes or a bytes-like object, or hex; threads: 0 for "
     "one per CPU; function: only the functions whose name starts with it; verbose, explain: as its --verbose and "
     "--explain, what --explain prints first)"},
    {nullptr, nullptr, 0, nullptr},
};

PyModuleDef module = {
    PyModuleDef_HEAD_INIT, module_name, "EVM decompiler (C++ core)", -1, methods, nullptr, nullptr, nullptr, nullptr,
};

}  // namespace

PyMODINIT_FUNC PAN_CONCAT(PyInit_, PAN_PYMODULE)(void)
{
    try {
        // as a library, like python's logging without a handler: the
        // warnings and the errors only (the command line shows INFO, like
        // `python -m panoramix`)
        if (!std::getenv("PANORAMIX_LOG"))
            pan::set_log_level(pan::log_warning);
        pan::sigdb::set_log_sink(&pan::log);  // (the signature database's messages: the log's)
        PyObject* m = PyModule_Create(&module);
        if (!m)
            return nullptr;
        if (!decompilation_type)
            decompilation_type = PyStructSequence_NewType(&decompilation_desc);
        if (!decompilation_type) {
            Py_DECREF(m);
            return nullptr;
        }
        Py_INCREF(decompilation_type);
        if (PyModule_AddObject(m, "Decompilation", reinterpret_cast<PyObject*>(decompilation_type)) < 0) {
            Py_DECREF(decompilation_type);
            Py_DECREF(m);
            return nullptr;
        }
        const std::string version(panoramix::build_info().version);
        if (PyModule_AddStringConstant(m, "__version__", version.c_str()) < 0) {
            Py_DECREF(m);
            return nullptr;
        }
        return m;
    } catch (...) {
        return python_error();
    }
}
