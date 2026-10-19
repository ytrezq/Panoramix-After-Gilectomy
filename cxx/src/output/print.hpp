// The printer's parts (lot 10, internal): the text being made (Out: the
// colors as python's add_color and the terminal's, the characters python's
// colors take - the priority of a function is the length of its colored
// text), the names of a function (python's set_names, var_name, NICE_NAMES,
// the ABI's params), the expression printer (python prettify, pretty_memory,
// pretty_bytes) and the line printer (pretty_line, pprint_logic). Nothing
// here makes a Value: the printer reads the contract's context from any
// thread.
#pragma once

#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/evmint.hpp"
#include "core/value.hpp"
#include "output/output.hpp"

namespace pan::sigdb {
class Database;
class Entry;
}  // namespace pan::sigdb

namespace pan {
struct StorageLayout;  // storage/storage.hpp (lot 9)
struct SafeMathTable;  // analysis/safemath.hpp (lot 8)
}  // namespace pan

namespace pan::output::detail {

// ---- colors -----------------------------------------------------------------------

// python's helpers.C
enum class Col : u8 { header, blue, okgreen, warning, fail, bold, underline, green, gray, asm_code, green_back, blue_back };
std::string_view col_code(Col c) noexcept;
inline constexpr std::string_view END = "\033[0m";

// The text being made. `emit`: the terminal's codes written (else plain
// text); `add_color`: python's flag where the text is made (whether python's
// text has codes there) - both count the characters python's codes take
// (pycodes: the length of python's colored text, the functions' priority).
class Out {
public:
    explicit Out(bool emit) : emit_(emit) {}
    std::string s;
    bool add_color = true;

    bool emit() const noexcept { return emit_; }
    u64 pycodes() const noexcept { return pycodes_; }

    void put(std::string_view t) { s += t; }
    void put(char c) { s += c; }
    void spaces(usize n) { s.append(n, ' '); }
    // python's color(t, c, add_color): nothing for an empty t
    void col(Col c, std::string_view t) {
        if (t.empty()) return;
        if (add_color) code(c);
        s += t;
        if (add_color) end();
    }
    // a color python writes whatever add_color is (COLOR_WARNING + "delegate" + ENDC)
    void raw_col(Col c, std::string_view t) {
        code(c);
        s += t;
        end();
    }
    // a code alone (python's COLOR_GREEN + ... + ENDC around text it builds)
    void code(Col c) {
        const std::string_view k = col_code(c);
        pycodes_ += k.size();
        if (emit_) s += k;
    }
    void end() {
        pycodes_ += END.size();
        if (emit_) s += END;
    }
    // another Out's text and its codes after this one's
    void append(const Out& o) {
        s += o.s;
        pycodes_ += o.pycodes_;
    }
    // an Out for a part of this one (the same terminal, the same add_color)
    Out sub() const {
        Out o(emit_);
        o.add_color = add_color;
        return o;
    }
    // python's len(clean_color(text)): the characters of the text alone
    u64 visible_chars() const noexcept;
    // python's len(text) of its colored text
    u64 python_chars() const noexcept { return visible_chars() + pycodes_; }
    void clear() {
        s.clear();
        pycodes_ = 0;
    }

private:
    bool emit_;
    u64 pycodes_ = 0;
};

// add_color set for a scope
class AddColor {
public:
    AddColor(Out& o, bool on) : o_(o), prev_(o.add_color) { o.add_color = on; }
    ~AddColor() { o_.add_color = prev_; }
    AddColor(const AddColor&) = delete;
    AddColor& operator=(const AddColor&) = delete;

private:
    Out& o_;
    bool prev_;
};

// UTF-8 code points of a text (python's len)
u64 code_points(std::string_view s) noexcept;

// ---- text from outside (escape.rl) -----------------------------------------------

// A name or a type of the signature database, as the text prints it (the
// asm's db_intern): valid UTF-8 as it is, but C0, DEL, C1 (U+0080..U+009F),
// U+061C, U+200E, U+200F, U+2028..U+202E, U+2066..U+2069 and the bytes of no
// valid UTF-8 - each byte \xNN.
void append_db_text(std::string& out, std::string_view raw);
std::string db_text(std::string_view raw);
// python's pretty_text(b, short): the bytes as a string literal ('...' with
// \\ \' \n \r \t) if they're text - the printable ASCII and \n \r \t only,
// a letter or a digit among them (or, short, at most 2 of them)
std::optional<std::string> pretty_text(std::span<const u8> b, bool short_ok = false);
// python safemath.failure's message: the string of an Error(string) revert's
// data (its selector, 32, its length, the words of its bytes) as a string
// literal, if it's text
std::optional<std::string> error_message_text(Value data);

// ---- numbers ------------------------------------------------------------------------

// python's precedences (prettify.OPERATOR_PRECEDENCE), the higher binding tighter
enum Prec : int { P_NONE = 0, P_OR = 1, P_AND, P_NOT, P_CMP, P_BOR, P_BXOR, P_BAND, P_SHIFT, P_ADD, P_MUL, P_UNARY, P_POW, P_ATOM };

// python's str() / hex() of an int
std::string int_dec(const EvmInt& x);
std::string int_hex(const EvmInt& x);
// python's padded_hex(x, n): "0x" + n digits ("?" * n when it has more)
std::string padded_hex(const EvmInt& x, u32 digits);
// python's pretty_num(x) (ints only): hex past 8**50, 10**k * m, decimal
// below 8**30 as a word, hex else (or its negative decimal)
std::string pretty_num(const EvmInt& x);
// python's num_precedence of pretty_num's text
int num_precedence(std::string_view text) noexcept;
// An int as python's trace has it, the IR keeping words in [0, 2^256):
// python's simplify_exp makes one in (2^256 - 8**22, 2^256) its negative
// (to_real_int) - `!= -1`, `const MAX_UINT = -1` - but unsigned comparisons
// print their words (`x < 0xff..ff`: the asm's texts)
EvmInt display_int(const EvmInt& x);
// python's str() of a term of its IR, as python's --repr and its prettifier's
// fallback print one: ('storage', 256, 0, 7) - numbers decimal, the leaves
// 'caller', the VM's variables ('var', '_1'), lists [...]
void python_repr(std::string& out, Value v);

// ---- the names of a function ----------------------------------------------------------

// A word of the head of the calldata a known function's params take
// (python's calldata_params / head_words): the params' words, a static
// tuple's or array's all of them (name.member, name[2]), a dynamic one's
// offset.
struct ParamWord {
    i64 offset = 0;           // its place: 4 + 32 k
    std::string name;         // python's: name, name.member, name[2]
    std::string type;         // its type's text (the element's, the member's)
    bool has_length = false;  // bytes, string, T[]: the data it points to starts with its length
    bool array_of_words = false;  // T[] of one head word each: name[k] is its k-th
};

// What the contract's analyses made that the text names (lots 8 and 9):
// the storage's variables (python Storage.names: a getter's name, else
// stor<slot>, made unique), the functions of its SafeMath.
struct ContractNames {
    const StorageLayout* storage = nullptr;
    const SafeMathTable* safemath = nullptr;
    std::vector<std::string> storage_names;  // vars[i]'s, as printed
};
ContractNames contract_names(const StorageLayout* storage, const SafeMathTable* safemath, const sigdb::Database* db);
// a function of the SafeMath as its calls name it: add, add2, sub...
std::string safemath_name(const SafeMathTable& t, u32 index);

// What the printer knows of the function printed (python's set_names,
// set_func): the names its text has for its params and loop variables, the
// call kinds of its call ids, the database, the contract's names.
class FnEnv {
public:
    FnEnv(const FunctionInfo* fn, const sigdb::Database* db, Value trace, const ContractNames* names = nullptr);

    const FunctionInfo* fn() const noexcept { return fn_; }
    const sigdb::Database* db() const noexcept { return db_; }
    const ContractNames* names() const noexcept { return names_c_; }
    const SafeMathTable* safemath() const noexcept { return names_c_ ? names_c_->safemath : nullptr; }

    // python's _names["taken"]: BUILTIN_NAMES, the storage's names, the params'
    bool taken(std::string_view name) const noexcept;
    // the text of a Name (python's var_name, NICE_NAMES, param names); the
    // color it's printed with
    const std::string& name_text(Value name) const;
    Col name_color(Value name) const noexcept;
    // a variable named `base` (python's var_name: `_` added while taken)
    std::string var_name(std::string_view base) const;

    // the kind of the call line of an id (CALL, STATICCALL, DELEGATECALL,
    // CALLCODE, CREATE, CREATE2, PRECOMPILED), the precompile's address
    Op call_kind(u32 id) const noexcept;
    u32 precompile_address(u32 id) const noexcept;

    // the params of the function, as its header names them: (type, name)
    struct Param {
        std::string type, name;
    };
    const std::vector<Param>& params() const noexcept { return params_; }
    // the database's entry of the function, when it knows it (verified)
    bool known() const noexcept { return known_; }
    // the head word of the known function's params at a calldata offset
    const ParamWord* word_at(i64 offset) const noexcept;
    // Name(PARAM, k)'s word (FunctionInfo::params[k]'s offset)
    const ParamWord* word_of_param(u32 k) const noexcept;

private:
    void scan(Value trace);
    const FunctionInfo* fn_;
    const sigdb::Database* db_;
    const ContractNames* names_c_;
    std::vector<std::string> taken_;  // sorted
    std::vector<Param> params_;
    std::vector<ParamWord> words_;  // by offset
    bool known_ = false;
    struct CallRec {
        u32 id;
        Op kind;
        u32 addr;
    };
    std::vector<CallRec> calls_;  // by id
    struct NameCache {
        u64 raw;
        std::string text;
    };
    mutable std::vector<NameCache> names_;
    mutable std::vector<std::string> nice_free_;  // NICE_NAMES not taken
    mutable bool nice_made_ = false;
};

// the names the text has for what the EVM gives (python BUILTIN_NAMES)
bool builtin_name(std::string_view name) noexcept;

// python's known_fname(sel): the function (or error) of a selector as printed
// after an address (its params' types gray, their names but the _paramN
// ones) written to o; false (nothing written) when the database doesn't know it
bool known_fname(Out& o, const sigdb::Database* db, u32 selector);
// the name of a function as its header prints it (python's color_name)
void function_header_name(Out& o, const FunctionInfo& fn, const FnEnv& env);

// ---- the expression printer ----------------------------------------------------------

struct MemoryOpts {
    bool abi_text = false;  // the data of a return or a revert
    bool selector = false;  // the data of a revert or a call: its first 4 bytes a selector
};

class Printer {
public:
    Printer(Out& o, const FnEnv& env) : o_(o), env_(env) {}

    Out& out() noexcept { return o_; }
    const FnEnv& env() const noexcept { return env_; }

    // python's prettify(e, rem_bool, parentheses=ctx): ctx 0 for none
    void exp(Value e, int ctx = P_NONE, bool rem_bool = false);
    // python's pretty_memory(e, add_color, abi_text, selector): its items' texts
    void memory(Value e, const MemoryOpts& m, std::vector<Out>& items);
    // pretty_memory(("data",) + els)
    void memory_elements(std::span<const Value> els, const MemoryOpts& m, std::vector<Out>& items);
    // the items joined with ", "
    void memory_joined(Value e, const MemoryOpts& m);
    // python's prettify(is_zero(e), rem_bool=True)
    void negated(Value e, int ctx = P_NONE);
    // python's prettify(x) of an int
    void integer(const EvmInt& x, int ctx = P_NONE);

    // names printed as others for a scope (sequential_setvars' _old copies)
    using Subst = std::vector<std::pair<Value, std::string>>;
    class SubstScope {
    public:
        SubstScope(Printer& p, const Subst& s) : p_(p), prev_(p.subst_) { p.subst_ = &s; }
        ~SubstScope() { p_.subst_ = prev_; }
        SubstScope(const SubstScope&) = delete;
        SubstScope& operator=(const SubstScope&) = delete;

    private:
        Printer& p_;
        const Subst* prev_;
    };
    const Subst* subst() const noexcept { return subst_; }

    // python's view of a trace before its function's traits and storage
    // (--explain's sections; the stacks of --verbose's lines, strings python
    // made in its VM): the calldata as cd[k] - no param names -, a storage
    // read as python's tuple ('storage', size, off, slot)
    class RawView {
    public:
        explicit RawView(Printer& p, bool on = true) : p_(p), prev_(p.raw_view_) { p.raw_view_ = on; }
        ~RawView() { p_.raw_view_ = prev_; }
        RawView(const RawView&) = delete;
        RawView& operator=(const RawView&) = delete;

    private:
        Printer& p_;
        bool prev_;
    };
    bool raw_view() const noexcept { return raw_view_; }
    // python's pretty_line / pprint_logic: the lines of a trace at an
    // indentation (loops: the loops it's in)
    struct LoopRef {
        Value id;   // Name(LOOP_ID, k)
        int label;  // 0: none, else loopN
    };
    void lines(Value trace, u32 indent, std::span<const LoopRef> loops = {}, bool add_breaks = false);
    // one line's text lines (python pretty_line), each at indent
    void line(Value l, u32 indent, std::span<const LoopRef> loops);
    // python safemath.pretty_defs: the lines of the functions of the
    // contract's `def SafeMath:` block
    void safemath_defs(const SafeMathTable& t);

private:
    friend struct ExpImpl;
    Out& o_;
    const FnEnv& env_;
    const Subst* subst_ = nullptr;
    bool raw_view_ = false;
};

// ---- the contract's text (contract.cpp) --------------------------------------------------

// One function's text (python Function.print / InternalFunction.print): its
// lines joined with "\n"; r: the contract's result (an internal function's
// record, the storage's and the SafeMath's names), may be null; names: the
// contract's names when they're made already (else made of r's)
Out function_text(const driver::ContractResult* r, const FunctionInfo& fn, const PrintOptions& s,
                  const ContractNames* names = nullptr);
// the contract's `def storage:` block (python decompiler.py's), and its
// `def SafeMath:` block: nothing when it has none
void storage_block(Out& t, const ContractNames& names);
void safemath_block(Out& t, const ContractNames& names, const sigdb::Database* db);
// the whole text (python decompiler.py's)
std::string contract_text(const driver::ContractResult& r, const PrintOptions& s);
// python's pprint_repr (--repr): the lines as S-expressions
void repr_lines(std::string& out, Value trace, u32 indent);
// the JSON (json.cpp)
std::string contract_json(const driver::ContractResult& r, const PrintOptions& s);

}  // namespace pan::output::detail
