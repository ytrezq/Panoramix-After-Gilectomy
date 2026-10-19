// The names of a function's text (python prettify.set_names, var_name,
// NICE_NAMES, BUILTIN_NAMES; function.py rename_params, make_names;
// signatures.get_func_name, fix_input_names): made from the integer ids of
// the IR's names when printed (rule 1).
#include <algorithm>
#include <format>
#include <unordered_set>

#include "analysis/safemath.hpp"
#include "core/budget.hpp"
#include "output/print.hpp"
#include "sigdb.hpp"
#include "storage/storage.hpp"

namespace pan::output::detail {

namespace {

// python's BUILTIN_NAMES: the names the text has for what the EVM gives,
// the first names of the dotted ones, the precompiles' (sorted)
constexpr std::string_view kBuiltins[] = {
    "False",          "True",          "bigModExp", "block",         "bn256Add",  "bn256Pairing",
    "bn256ScalarMul", "call",          "calldata",  "caller",        "chainid",   "code",
    "create",         "create2",       "delegate",  "ecrecover",     "eth",       "ext_call",
    "ext_code",       "gas_remaining", "mem",       "memcopy",       "msize",     "return_data",
    "ripemd160hash",  "sha256hash",    "stor",      "this",          "transient", "tx",
};

// python's NICE_NAMES: the names of the loops' variables
constexpr std::string_view kNice[] = {"idx", "s", "t", "u", "v", "w", "x", "y", "z",
                                      "a",   "b", "c", "d", "e", "f", "g", "h"};

// python's precompiled_var_names, and identity's
std::string_view precompile_base(u32 addr) noexcept
{
    switch (addr) {
        case 1: return "signer";
        case 2:
        case 3: return "hash";
        case 4: return "copied";
        case 5: return "mod_exp";
        case 6: return "bn_add";
        case 7: return "bn_scalar_mul";
        case 8: return "bn_pairing";
        default: return "precompiled";
    }
}

// a param's base name (python re.match(r"\w*", name)): desc of desc.srcToken
std::string_view base_name(std::string_view n) noexcept
{
    usize i = 0;
    while (i < n.size()) {
        const char c = n[i];
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'))
            break;
        ++i;
    }
    return n.substr(0, i);
}

std::string abi_kind_text(const ParamInfo& p)
{
    switch (p.kind) {
        case AbiKind::Word: return "uint256";
        case AbiKind::Uint: return std::format("uint{}", p.bits);
        case AbiKind::Int: return std::format("int{}", p.bits);
        case AbiKind::Address: return "address";
        case AbiKind::Bool: return "bool";
        case AbiKind::BytesN: return std::format("bytes{}", p.bits / 8);
        case AbiKind::Bytes: return "bytes";
        case AbiKind::String: return "string";
        case AbiKind::Array: return "array";
        case AbiKind::Tuple: return "tuple";
        case AbiKind::Unknown: return "uint256";
    }
    return "uint256";
}

// python's head_words: the words of a param in the head of the calldata
constexpr usize kMaxHeadWords = usize{1} << 16;

usize head_count(const sigdb::Type& t, usize cap)
{
    if (t.dynamic())
        return 1;
    switch (t.kind()) {
        case sigdb::TypeKind::static_array: {
            const usize per = head_count(t.element(), cap);
            const u64 n = t.length();
            if (per && n > cap / per)
                return cap + 1;
            return usize(n) * per;
        }
        case sigdb::TypeKind::tuple: {
            usize sum = 0;
            for (const sigdb::Field f : t.fields()) {
                sum += head_count(f.type(), cap);
                if (sum > cap)
                    return cap + 1;
            }
            return sum;
        }
        default:
            return 1;
    }
}

void head_words(const sigdb::Type& t, const std::string& name, std::vector<ParamWord>& out)
{
    check_stack();
    auto one = [&]() {
        ParamWord w;
        w.name = name;
        t.append_text(w.type);
        w.type = db_text(w.type);
        const sigdb::TypeKind k = t.kind();
        w.has_length = k == sigdb::TypeKind::bytes || k == sigdb::TypeKind::string || k == sigdb::TypeKind::array;
        w.array_of_words = k == sigdb::TypeKind::array && head_count(t.element(), kMaxHeadWords) == 1;
        out.push_back(std::move(w));
    };
    if (t.dynamic()) {
        one();
        return;
    }
    switch (t.kind()) {
        case sigdb::TypeKind::static_array: {
            if (head_count(t, kMaxHeadWords) > kMaxHeadWords) {
                one();  // (more words than calldata can hold: as one)
                return;
            }
            const u64 n = t.length();
            for (u64 i = 0; i < n; ++i)
                head_words(t.element(), std::format("{}[{}]", name, i), out);
            return;
        }
        case sigdb::TypeKind::tuple: {
            usize i = 0;
            for (const sigdb::Field f : t.fields()) {
                const std::string c = f.name().empty() ? std::format("_param{}", i + 1) : db_text(f.name());
                head_words(f.type(), name + "." + c, out);
                ++i;
            }
            return;
        }
        default:
            one();
            return;
    }
}

}  // namespace

bool builtin_name(std::string_view name) noexcept
{
    return std::binary_search(std::begin(kBuiltins), std::end(kBuiltins), name);
}

namespace {

// python's hex(n) of a slot: its digits, no leading zero
std::string slot_hex_digits(const Word256& w) { return int_hex(w.to_int()).substr(2); }

// python Storage.names' default(n, off): stor<n> (n < 2^32), else stor and
// the first 4 hex digits of n, uppercase; a field past bit 0: _<off>
std::string default_storage_name(const StorageVar& v)
{
    std::string name;
    if (const auto s = v.slot.as_u64(); s && *s < (u64(1) << 32)) {
        name = std::format("stor{}", *s);
    } else {
        std::string h = slot_hex_digits(v.slot).substr(0, 4);
        for (char& c : h)
            if (c >= 'a' && c <= 'f')
                c = char(c - 'a' + 'A');
        name = "stor" + h;
    }
    if (v.off)
        name += std::format("_{}", v.off);
    return name;
}

// the name of the getter of a variable (python's f.name.split("(")[0],
// getBalance -> balance), or none when the database doesn't know it
std::optional<std::string> getter_name(const StorageVar& v, const sigdb::Database* db)
{
    if (!v.getter || !db)
        return std::nullopt;
    const auto e = db->function(*v.getter);
    if (!e || !e->known())
        return std::nullopt;
    std::string name(e->name());
    if (name.empty())
        return std::nullopt;
    if (v.strip_get && name.size() > 3) {
        const char c = name[3];
        name = std::string(1, c >= 'A' && c <= 'Z' ? char(c - 'A' + 'a') : c) + name.substr(4);
    }
    return name;
}

}  // namespace

ContractNames contract_names(const StorageLayout* storage, const SafeMathTable* safemath, const sigdb::Database* db)
{
    ContractNames n;
    n.storage = storage;
    n.safemath = safemath;
    if (!storage)
        return n;
    // python's unique(): the variables in their order, a name taken
    // already + _<slot> (decimal below 2^32, else its first 8 hex digits),
    // then _2, _3... while taken
    std::unordered_set<std::string> taken;
    n.storage_names.reserve(storage->vars.size());
    for (const StorageVar& v : storage->vars) {
        std::string name = getter_name(v, db).value_or(default_storage_name(v));
        if (taken.contains(name)) {
            const auto s = v.slot.as_u64();
            name += "_" + (s && *s < (u64(1) << 32) ? std::to_string(*s) : slot_hex_digits(v.slot).substr(0, 8));
        }
        const std::string base = name;
        for (u64 k = 2; taken.contains(name); ++k)
            name = std::format("{}_{}", base, k);
        taken.insert(name);
        n.storage_names.push_back(db_text(name));
    }
    return n;
}

std::string safemath_name(const SafeMathTable& t, u32 index)
{
    static constexpr std::string_view ops[] = {"add", "sub", "mul", "div", "mod", "inc", "dec"};
    if (index >= t.fns.size())
        return std::format("f{}", index);
    const SafeMathTable::Fn& f = t.fns[index];
    const usize op = usize(f.op);
    std::string name(op < std::size(ops) ? ops[op] : std::string_view("op"));
    if (f.number > 1)
        name += std::to_string(f.number);
    return name;
}

FnEnv::FnEnv(const FunctionInfo* fn, const sigdb::Database* db, Value trace, const ContractNames* names)
    : fn_(fn), db_(db), names_c_(names)
{
    // the storage's names (python's _names["storage"])
    const auto storage_name = [&](std::string_view n) {
        return names_c_ && std::find(names_c_->storage_names.begin(), names_c_->storage_names.end(), n) !=
                               names_c_->storage_names.end();
    };
    // the params, as the header names them (python inferred_params: the
    // ABI's, renamed past the storage's names and the builtins; _paramN)
    if (fn && fn->kind == FunctionInfo::Kind::Selector && db) {
        if (const auto e = db->function(fn->selector); e && e->known()) {
            known_ = true;
            usize i = 0;
            for (const sigdb::Field f : e->params()) {
                Param p;
                f.type().append_text(p.type);
                p.type = db_text(p.type);
                p.name = f.name().empty() ? std::format("_param{}", i + 1) : db_text(f.name());
                params_.push_back(std::move(p));
                ++i;
            }
            // python rename_params: a param named as something the text
            // has (a builtin, a storage variable) is _name
            std::vector<std::string> names;
            for (const Param& p : params_)
                names.push_back(p.name);
            std::vector<std::pair<std::string, std::string>> renames;
            for (Param& p : params_) {
                auto it = std::find_if(renames.begin(), renames.end(), [&](const auto& r) { return r.first == p.name; });
                if (it != renames.end()) {
                    p.name = it->second;
                    continue;
                }
                if (!builtin_name(p.name) && !storage_name(p.name))
                    continue;
                std::string fresh = "_" + p.name;
                while (builtin_name(fresh) || storage_name(fresh) ||
                       std::find(names.begin(), names.end(), fresh) != names.end())
                    fresh = "_" + fresh;
                renames.emplace_back(p.name, fresh);
                names.push_back(fresh);
                p.name = fresh;
            }
            // the head words of the params (python calldata_params)
            usize k = 0;
            for (const sigdb::Field f : e->params()) {
                const usize from = words_.size();
                head_words(f.type(), params_[k].name, words_);
                ++k;
                (void)from;
            }
            i64 loc = 4;
            for (ParamWord& w : words_) {
                w.offset = loc;
                loc += 32;
            }
        }
    }
    if (fn && !known_) {
        if (fn->kind == FunctionInfo::Kind::Internal) {
            for (usize k = 0; k < fn->params.size(); ++k)
                params_.push_back(Param{"", std::format("_param{}", k + 1)});
        } else if (fn->kind == FunctionInfo::Kind::Selector) {
            for (usize k = 0; k < fn->params.size(); ++k)
                params_.push_back(Param{abi_kind_text(fn->params[k]), std::format("_param{}", k + 1)});
        }
    }
    // python's _names["taken"]: the builtins, the storage's names, the params'
    for (const std::string_view b : kBuiltins)
        taken_.emplace_back(b);
    if (names_c_)
        for (const std::string& n : names_c_->storage_names)
            taken_.push_back(n);
    for (const Param& p : params_)
        taken_.emplace_back(base_name(p.name));
    std::sort(taken_.begin(), taken_.end());
    taken_.erase(std::unique(taken_.begin(), taken_.end()), taken_.end());
    if (trace.is_trace())
        scan(trace);
}

// the call lines of the trace, any depth: their kinds by id
void FnEnv::scan(Value trace)
{
    std::vector<Value> todo{trace};
    std::unordered_set<u64> seen;
    while (!todo.empty()) {
        const Value t = todo.back();
        todo.pop_back();
        if (!t.is_list() || !seen.insert(t.raw()).second)
            continue;
        for (const Value l : t.args()) {
            if (!l.is_expr())
                continue;
            const Op op = l.op();
            switch (op) {
                case Op::CALL:
                case Op::CALLCODE:
                case Op::DELEGATECALL:
                case Op::STATICCALL:
                case Op::CREATE:
                case Op::CREATE2:
                case Op::PRECOMPILED:
                    if (l.size() > 0 && l[0].is_small()) {
                        const u32 id = u32(l[0].small_val());
                        u32 addr = 0;
                        if (op == Op::PRECOMPILED && l.size() > 2 && l[2].is_small())
                            addr = u32(l[2].small_val());
                        if (std::none_of(calls_.begin(), calls_.end(), [&](const CallRec& c) { return c.id == id; }))
                            calls_.push_back(CallRec{id, op, addr});
                    }
                    break;
                default:
                    break;
            }
            for (const Value a : l.args())
                if (a.is_list())
                    todo.push_back(a);
        }
    }
    std::sort(calls_.begin(), calls_.end(), [](const CallRec& a, const CallRec& b) { return a.id < b.id; });
}

const ParamWord* FnEnv::word_at(i64 offset) const noexcept
{
    if (offset < 4 || (offset - 4) % 32)
        return nullptr;
    const u64 i = u64(offset - 4) / 32;
    return i < words_.size() ? &words_[i] : nullptr;
}

const ParamWord* FnEnv::word_of_param(u32 k) const noexcept
{
    if (!fn_ || k >= fn_->params.size())
        return nullptr;
    return word_at(i64(fn_->params[k].calldata_offset));
}

bool FnEnv::taken(std::string_view name) const noexcept
{
    return std::binary_search(taken_.begin(), taken_.end(), name);
}

std::string FnEnv::var_name(std::string_view base) const
{
    std::string n(base);
    while (taken(n))
        n += '_';
    return n;
}

Op FnEnv::call_kind(u32 id) const noexcept
{
    auto it = std::lower_bound(calls_.begin(), calls_.end(), id, [](const CallRec& c, u32 i) { return c.id < i; });
    return it != calls_.end() && it->id == id ? it->kind : Op::NONE;
}

u32 FnEnv::precompile_address(u32 id) const noexcept
{
    auto it = std::lower_bound(calls_.begin(), calls_.end(), id, [](const CallRec& c, u32 i) { return c.id < i; });
    return it != calls_.end() && it->id == id ? it->addr : 0;
}

const std::string& FnEnv::name_text(Value name) const
{
    for (const NameCache& c : names_)
        if (c.raw == name.raw())
            return c.text;
    std::string t;
    const u32 id = name.name_id();
    switch (name.name_kind()) {
        case NameKind::TMP:
            t = var_name(std::format("_{}", id));
            break;
        case NameKind::LOOP: {
            // (not a name the text has for something else, see set_names)
            if (!nice_made_) {
                for (const std::string_view n : kNice)
                    if (!taken(n))
                        nice_free_.emplace_back(n);
                nice_made_ = true;
            }
            if (id < nice_free_.size())
                t = nice_free_[id];
            else
                t = var_name(std::format("var{}", id));
            break;
        }
        case NameKind::MSIZE_VAR:
            t = var_name("_msize");
            break;
        case NameKind::PRECOMPILE: {
            const u32 addr = id >> 24, k = id & 0xffffff;
            t = var_name(k > 1 ? std::format("{}{}", precompile_base(addr), k) : std::string(precompile_base(addr)));
            break;
        }
        case NameKind::PARAM:
            // FunctionInfo::params[id]: a word of the head of the calldata -
            // a known function's by the name of that word (python's
            // calldata_params: desc.srcToken, amounts[2]), else _param<k+1>
            if (known_) {
                const ParamWord* w = word_of_param(id);
                t = w ? w->name : std::format("_param{}", id + 1);
            } else if (id < params_.size()) {
                t = params_[id].name;
            } else {
                t = std::format("_param{}", id + 1);
            }
            break;
        case NameKind::STORVAR:
            // StorageLayout::vars[id]'s name
            if (names_c_ && id < names_c_->storage_names.size())
                t = names_c_->storage_names[id];
            else
                t = std::format("stor{}", id);
            break;
        case NameKind::FUNC:
            t = std::format("unknown{:08x}", id);
            break;
        case NameKind::FALLBACK:
            t = "_fallback";
            break;
        case NameKind::INTERNAL:
            t = std::format("internal_0x{:x}", id);
            break;
        case NameKind::LOOP_ID:
            t = std::format("loop{}", id);
            break;
        case NameKind::SAFEMATH_PARAM:
            // python's ("var", "a"): var_name's
            t = var_name(id == 0 ? std::string("a") : id == 1 ? std::string("b") : std::format("arg{}", id));
            break;
        default:
            t = std::format("name_{}_{}", u32(name.name_kind()), id);
            break;
    }
    names_.push_back(NameCache{name.raw(), std::move(t)});
    return names_.back().text;
}

Col FnEnv::name_color(Value name) const noexcept
{
    switch (name.name_kind()) {
        case NameKind::PARAM:
        case NameKind::STORVAR:
            return Col::green;
        default:
            return Col::blue;
    }
}

bool known_fname(Out& o, const sigdb::Database* db, u32 selector)
{
    if (!db)
        return false;
    const auto e = db->function(selector);
    if (!e || !e->known())
        return false;
    std::string name = db_text(e->name());
    // (a name of the database that's no name: python's
    // re.match(r"unknown_?([0-9a-f]{8})?\(", name) - nor are its params)
    if (name.starts_with("unknown")) {
        std::string_view r = std::string_view(name).substr(7);
        if (!r.empty() && r[0] == '_')
            r.remove_prefix(1);
        if (r.size() >= 8 && std::all_of(r.begin(), r.begin() + 8, [](char c) {
                return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
            }))
            r.remove_prefix(8);
        if (r.empty())  // (the "(" python's regexp ends with: the params follow)
            return false;
    }
    o.put(name);
    o.put('(');
    usize i = 0;
    for (const sigdb::Field f : e->params()) {
        if (i)
            o.put(", ");
        // python's Loader.find_sig: the type gray, the name as it is - the
        // names the database doesn't have (_paramN) dropped
        std::string type;
        f.type().append_text(type);
        o.col(Col::gray, db_text(type));
        const std::string_view n = f.name();
        const bool param_n = n.empty() || (n.starts_with("_param") && n.size() > 6 &&
                                           std::all_of(n.begin() + 6, n.end(), [](char c) { return c >= '0' && c <= '9'; }));
        if (!param_n) {
            o.put(' ');
            o.put(db_text(n));
        }
        ++i;
    }
    o.put(')');
    return true;
}

}  // namespace pan::output::detail
