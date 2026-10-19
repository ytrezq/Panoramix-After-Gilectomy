// The storage analysis of a contract (storage.hpp; python storage.py's
// rewrite_functions, Storage, language, narrow, checked_below, var_values,
// index_like, getter_path, rewrite_accesses, rewrite_raw).
#include <algorithm>
#include <functional>
#include <map>

#include "algebra/construct.hpp"
#include "algebra/masks.hpp"
#include "analysis/traits.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "sigdb.hpp"
#include "storage/check.hpp"
#include "storage/getters.hpp"
#include "storage/internal.hpp"
#include "storage/names.hpp"
#include "storage/regroup.hpp"
#include "storage/storage.hpp"

namespace pan::storage {

namespace detail {

namespace {

void check_deadline(i64 deadline) {
    poll();
    if (deadline && platform::monotonic_ns() > deadline)
        throw Timeout("the post-processing and the text took more than 3 minutes");
}

// ---- a rewrite of every expression of traces ------------------------------------------------

// The lines of traces with their operands rewritten: traces line by line,
// lists item by item, expressions by exp() (memoized), lines by line().
class TraceMap {
public:
    virtual ~TraceMap() = default;

    Value trace(Value t) {
        check_stack();
        if (!t.is_trace()) return t;
        if (const Value* m = traces_.find(t)) return *m;
        SmallVec<Value, 32> lines;
        bool changed = false;
        for (Value l : t.args()) {
            poll();
            const Value nl = line(l);
            changed |= nl != l;
            lines.push_back(nl);
        }
        const Value r = changed ? mk_trace(lines.span()) : t;
        traces_.put(t, r);
        return r;
    }

protected:
    virtual Value exp(Value e) = 0;

    virtual Value line(Value l) { return operands(l); }

    // l with its operands rewritten
    Value operands(Value l) {
        if (!l.is_expr()) return any(l);
        SmallVec<Value, 8> ops;
        bool c = false;
        for (Value a : l.args()) {
            const Value na = any(a);
            c |= na != a;
            ops.push_back(na);
        }
        if (!c) return l;
        const Value r = mk_like(l, ops.span());
        cx().pcs.inherit(r, l);
        return r;
    }

    Value any(Value v) {
        check_stack();
        if (v.is_trace()) return trace(v);
        if (v.is_list()) {
            SmallVec<Value, 8> items;
            bool c = false;
            for (Value x : v.args()) {
                const Value nx = any(x);
                c |= nx != x;
                items.push_back(nx);
            }
            return c ? mk_list(items.span()) : v;
        }
        if (v.is_expr() && info(v.op()).sort == Sort::Line) return line(v);
        if (v.is_expr()) return exp(v);
        return v;
    }

    // e with its children through exp (none changed: e)
    Value children(Value e) {
        SmallVec<Value, 8> ops;
        bool c = false;
        for (Value a : e.args()) {
            const Value na = a.is_expr() ? exp(a) : any(a);
            c |= na != a;
            ops.push_back(na);
        }
        return c ? mk_like(e, ops.span()) : e;
    }

private:
    Memo<Value, Value> traces_;
};

// python narrow(): a read of the storage as wide as what's used of it - of
// Mask(32, 72, storage(104, 0, x)), the bits 72 to 104: storage(32, 72, x) << 72
class Narrow final : public TraceMap {
public:
    Value exp(Value e) override {
        check_stack();
        if (!e.is_expr() || !e.has_flags(F_STORAGE)) return e;
        if (const Value* m = memo_.find(e)) return *m;
        Value r = children(e);
        if (const auto m = alg::as_mask(r); m && m->size.is_small() && m->off.is_small() && m->x.is(Op::STORAGE, 3) &&
                                            m->x[0].is_small() && m->x[1].is_small()) {
            const i64 size = m->size.small_val(), moff = m->off.small_val();
            const i64 s_size = m->x[0].small_val(), s_off = m->x[1].small_val();
            const bool word_times = s_size == 256 && s_off == 0 && moff == 0 && is_small(m->shl, 256 - size) && size % 8;
            if (0 < size && 0 <= moff && moff + size <= s_size && !(size == s_size && moff == 0) && !word_times &&
                s_off >= 0 && s_off + moff < 256) {
                const Value shl = moff ? alg::add(m->shl, small(moff)) : m->shl;
                r = alg::mask(small(size), small(0), shl, mk(Op::STORAGE, small(size), small(s_off + moff), m->x[2]));
            }
        }
        memo_.put(e, r);
        return r;
    }

private:
    Memo<Value, Value> memo_;
};

// ---- what the code checks: python checked_below, var_values, points, index_like -------------------

// x -> the least bound n of the checks `x < n` (numbers), or none (any bound)
struct Bounded {
    std::vector<std::pair<Value, std::optional<EvmInt>>> list;
    Memo<Value, u32> map;  // x -> index + 1
    const std::optional<EvmInt>* find(Value x) const {
        if (const u32* k = map.find(x)) return &list[*k - 1].second;
        return nullptr;
    }
    bool contains(Value x) const { return map.find(x) != nullptr; }
};

bool reverts(Value branch) {
    return branch.is_trace() && branch.size() == 1 && (branch[0].is(Op::REVERT) || branch[0].is(Op::INVALID));
}

void bounded_add(Bounded& res, Value cond, bool numbers) {
    while (cond.is(Op::ISZERO, 1) && cond[0].is(Op::ISZERO, 1)) cond = cond[0][0];
    struct Pat {
        bool neg;   // under an ISZERO
        Op op;
        bool x_first;
        i64 delta;
    };
    static constexpr Pat pats[] = {
        {false, Op::LT, true, 0}, {false, Op::GT, false, 0}, {false, Op::LE, true, 1}, {false, Op::GE, false, 1},
        {true, Op::GE, true, 0},  {true, Op::LE, false, 0},  {true, Op::GT, true, 1},  {true, Op::LT, false, 1},
    };
    for (const Pat& p : pats) {
        Value c = cond;
        if (p.neg) {
            if (!c.is(Op::ISZERO, 1)) continue;
            c = c[0];
        }
        if (!c.is(p.op, 2)) continue;
        const Value x = p.x_first ? c[0] : c[1];
        const Value n = p.x_first ? c[1] : c[0];
        if (x.is_int()) continue;
        if (!numbers) {
            bool ins = false;
            u32& k = res.map.slot(x, &ins);
            if (ins) {
                res.list.emplace_back(x, std::nullopt);
                k = u32(res.list.size());
            } else {
                res.list[k - 1].second.reset();
            }
            continue;
        }
        if (!n.is_int()) continue;
        const EvmInt b = EvmInt(n) + EvmInt(p.delta);
        if (!(b.sign() > 0 && b < EvmInt::pow2(32))) continue;
        bool ins = false;
        u32& k = res.map.slot(x, &ins);
        if (ins) {
            res.list.emplace_back(x, b);
            k = u32(res.list.size());
        } else if (auto& cur = res.list[k - 1].second; cur && b < *cur) {
            cur = b;
        }
    }
}

void bounded_visit(Bounded& res, Value t, bool loops, bool numbers) {
    check_stack();
    if (!t.is_trace()) return;
    for (Value l : t.args()) {
        poll();
        if (l.is(Op::IF, 3)) {
            if (reverts(l[2])) bounded_add(res, l[0], numbers);
            if (reverts(l[1])) bounded_add(res, mk(Op::ISZERO, l[0]), numbers);
            bounded_visit(res, l[1], loops, numbers);
            bounded_visit(res, l[2], loops, numbers);
        } else if (l.is(Op::WHILE, 4)) {
            if (loops) bounded_add(res, l[0], numbers);
            bounded_visit(res, l[1], loops, numbers);
        }
    }
}

Bounded checked_below(Value trace, bool loops, bool numbers) {
    Bounded b;
    bounded_visit(b, trace, loops, numbers);
    return b;
}

// a variable -> the values it is set to (setvars, a loop's first values, its steps)
struct VarValues {
    std::vector<std::pair<Value, std::vector<Value>>> list;
    Memo<Value, u32> map;
    const std::vector<Value>* find(Value v) const {
        if (const u32* k = map.find(v)) return &list[*k - 1].second;
        return nullptr;
    }
    void add(Value name, Value e) {
        bool ins = false;
        u32& k = map.slot(name, &ins);
        if (ins) {
            list.emplace_back(name, std::vector<Value>{});
            k = u32(list.size());
        }
        list[k - 1].second.push_back(e);
    }
};

void values_visit(VarValues& res, Value lines) {
    check_stack();
    if (!lines.is_list()) return;
    for (Value l : lines.args()) {
        poll();
        if (l.is(Op::SETVAR, 2)) {
            res.add(l[0], l[1]);
        } else if (l.is(Op::IF, 3)) {
            values_visit(res, l[1]);
            values_visit(res, l[2]);
        } else if (l.is(Op::WHILE, 4)) {
            values_visit(res, l[1]);
            values_visit(res, l[3]);
        } else if (l.is(Op::CONTINUE, 2)) {
            values_visit(res, l[1]);
        }
    }
}

bool is_var(Value v) noexcept {
    if (!v.is_name()) return false;
    switch (v.name_kind()) {
        case NameKind::TMP:
        case NameKind::LOOP:
        case NameKind::MSIZE_VAR:
        case NameKind::PRECOMPILE:
            return true;
        default:
            return false;
    }
}

// whether v may be a slot a storage pointer holds: a hash, a big number, a
// word of the memory (where solidity keeps them)
bool points(Value v, Memo<Value, u8>& seen) {
    check_stack();
    if (v.is_int()) {
        const EvmInt n(v);
        return !(-EvmInt::pow2(32) < n && n < EvmInt::pow2(32));
    }
    if (v.is(Op::SHA3) || v.is(Op::MEM)) return true;
    if (!(v.is_expr() || v.is_list()) || !seen.add(v)) return false;
    for (Value c : v.children())
        if (points(c, seen)) return true;
    return false;
}

struct Known {
    Bounded bounded;
    VarValues values;
};

bool index_like(Value e, const Known& k, std::vector<Value>& seen) {
    check_stack();
    if (e.is_int()) {
        const EvmInt n(e);
        return -EvmInt::pow2(32) < n && n < EvmInt::pow2(32);
    }
    if (is_var(e)) {
        if (std::find(seen.begin(), seen.end(), e) != seen.end()) return true;
        const std::vector<Value>* vs = k.values.find(e);
        if (vs)
            for (Value v : *vs) {
                Memo<Value, u8> s;
                if (points(v, s)) return false;
            }
        if (k.bounded.contains(e)) return true;
        if (!vs || vs->empty()) return false;
        seen.push_back(e);
        bool all = true;
        for (Value v : *vs)
            if (!index_like(v, k, seen)) {
                all = false;
                break;
            }
        seen.pop_back();
        return all;
    }
    if (k.bounded.contains(e)) return true;
    switch (e.op()) {
        case Op::ADD:
        case Op::MUL:
        case Op::DIV:
            for (Value t : e.args())
                if (!index_like(t, k, seen)) return false;
            return true;
        case Op::MOD:
            return true;
        case Op::MASK_SHL:
            if (e.size() == 4 && e[0].is_small() && e[1].is_small() && e[2].is_small())
                return e[0].small_val() <= 64 || index_like(e[3], k, seen);
            return false;
        default:
            return false;
    }
}

// ---- the language: how the mappings hash ---------------------------------------------------------

void hashes_of(Value v, Memo<Value, u8>& seen, std::vector<Value>& out) {
    check_stack();
    if (!(v.is_expr() || v.is_list()) || !seen.add(v)) return;
    if (v.is(Op::SHA3)) out.push_back(v);
    for (Value c : v.children()) hashes_of(c, seen, out);
}

Lang vote_language(const Accesses& accesses) {
    i64 votes = 0;
    for (usize i = 0; i < accesses.size(); ++i) {
        Memo<Value, u8> seen;
        std::vector<Value> hs;
        hashes_of(accesses[i].idx, seen, hs);
        for (Value h : hs) {
            std::span<const Value> parts = h.args();
            if (parts.size() == 1 && parts[0].is(Op::DATA)) parts = parts[0].args();
            if (parts.size() != 2) continue;
            const Value a = word(parts[0]), b = word(parts[1]);
            if (a.is_int() && !b.is_int())
                ++votes;
            else if (b.is_int() && !a.is_int())
                --votes;
        }
    }
    return votes > 0 ? Lang::Vyper : Lang::Solidity;
}

// ---- the analysis ---------------------------------------------------------------------------------

struct Fn {
    FunctionInfo* info;
    Value trace;  // being rewritten
};

// a placeholder variable (python's ("sv", None)): the shape of a form only
constexpr u32 NO_VAR = 0xffffffffu;

class FormRewrite;

class Analysis {
public:
    Analysis(std::vector<Fn>& fns, std::span<const FunctionInfo> internals, const ContractShared& shared, Lang lang,
             Parser& parser, const Options& opts)
        : fns_(fns),
          internals_(internals),
          shared_(shared),
          parser_(parser),
          opts_(opts),
          layout_(std::make_shared<StorageLayout>()),
          types_(layout_->types) {
        layout_->lang = lang;
    }

    std::shared_ptr<StorageLayout> run();

private:
    // ---- python Storage.__init__ ----
    void find_accesses();
    void type_roots();
    void fixed_lengths_and_moves();
    void find_bytes_getters();
    void names();
    // ---- forms ----
    Value form(Value size, Value off, Value idx, bool write);
    Value path_form(const Path& p, i64 size, Value off);
    bool getter_path(std::optional<u32> t, std::span<const Step> sts, i64 size, Value off);
    Value rewrite(Value trace);
    Value getter_trace(usize fn);

    struct Root {
        std::vector<RootAccess> accs;
        std::optional<u32> type;
        std::optional<std::vector<Range>> fields;
    };

    std::vector<Fn>& fns_;
    std::span<const FunctionInfo> internals_;
    const ContractShared& shared_;
    Parser& parser_;
    const Options& opts_;
    std::shared_ptr<StorageLayout> layout_;
    Types types_;

    Accesses accesses_;
    std::vector<std::vector<u32>> where_;          // per access: the functions it is in
    std::vector<std::unique_ptr<Known>> known_;    // per function, made when asked
    std::vector<std::optional<Path>> steps_;       // per access (python self.steps)
    std::map<Word256, Root> roots_;                // python by_root, types, fields
    std::map<Word256, u64> lengths_;               // python self.lengths
    std::vector<std::optional<std::pair<Value, Value>>> bytes_getters_;  // per function: (key, trace)
    std::map<Word256, u32> var_of_root_;
    std::map<std::pair<Word256, std::pair<i64, i64>>, u32> var_of_field_;
    Memo<Key3, Value> forms_read_, forms_write_;
    std::unique_ptr<Worlds> worlds_;
    std::unique_ptr<FormRewrite> rewriter_;

    const Known& known(u32 fn) {
        if (!known_[fn]) {
            auto k = std::make_unique<Known>();
            bounded_visit(k->bounded, fns_[fn].trace, true, false);
            values_visit(k->values, fns_[fn].trace);
            known_[fn] = std::move(k);
        }
        return *known_[fn];
    }
};

void Analysis::find_accesses() {
    where_.clear();
    for (u32 i = 0; i < fns_.size(); ++i) {
        Accesses own;
        own.find(fns_[i].trace);
        for (usize k = 0; k < own.size(); ++k) {
            accesses_.add(own[k], own.written(k));
            const usize at = *accesses_.index(own[k]);
            if (where_.size() <= at) where_.resize(at + 1);
            where_[at].push_back(i);
        }
    }
    known_.clear();
    known_.resize(fns_.size());
    where_.resize(accesses_.size());
    steps_.assign(accesses_.size(), std::nullopt);
    std::vector<bool> pointer(accesses_.size(), false);
    for (usize i = 0; i < accesses_.size(); ++i) {
        poll();
        std::optional<Path> st;
        try {
            st = parser_.parse(accesses_[i].idx);
        } catch (const Error&) {  // (python logs the exception: the access is raw)
            st.reset();
        }
        if (st && !st->steps.empty() && st->steps[0].kind == Step::Kind::Off && !st->steps[0].e.is_int()) {
            bool any = false;
            for (u32 f : where_[i]) {
                std::vector<Value> seen;
                if (index_like(st->steps[0].e, known(f), seen)) {
                    any = true;
                    break;
                }
            }
            if (!any) pointer[i] = true;
        }
        steps_[i] = std::move(st);
    }
    // A slot plus what's no index (a storage pointer plus a member's offset,
    // a slot read from the calldata) is taken for an element of a fixed array
    // only where nothing else is: not to make the variable, the mapping or the
    // array at that slot an array of what it isn't - it's the slot it is then.
    std::vector<Word256> others;
    for (usize i = 0; i < accesses_.size(); ++i)
        if (steps_[i] && !pointer[i]) others.push_back(steps_[i]->root);
    std::sort(others.begin(), others.end());
    for (usize i = 0; i < accesses_.size(); ++i)
        if (pointer[i] && std::binary_search(others.begin(), others.end(), steps_[i]->root)) steps_[i].reset();
    for (usize i = 0; i < accesses_.size(); ++i) {
        const Access& a = accesses_[i];
        if (steps_[i] && a.size.is_small())
            roots_[steps_[i]->root].accs.push_back(RootAccess{steps_[i]->steps, a.size, a.off, accesses_.written(i)});
    }
}

void Analysis::type_roots() {
    for (auto& [n, r] : roots_) {
        poll();
        r.type.reset();
        r.fields.reset();
        bool direct = true, in_word = true;
        for (const RootAccess& a : r.accs) {
            if (!a.steps.empty() || !a.off.is_small()) direct = false;
            else if (a.off.small_val() < 0 || a.off.small_val() >= 256) in_word = false;
        }
        if (direct && !in_word) continue;  // (bits out of the word: raw, stor[slot])
        if (direct) {
            auto read = [&](i64 s, i64 o) {
                for (const RootAccess& a : r.accs)
                    if (is_small(a.size, s) && is_small(a.off, o)) return true;
                return false;
            };
            if (read(1, 0) && read(7, 1) && read(255, 1)) {
                // (none of its data read: a bytes, or a string, only if its
                // length is read as theirs is - the lowest bit tells a short one,
                // whose length is the 7 bits from the bit 1, from a long one, the
                // bits from 1 on. A flag in the bit 0 of an uint8 and the 7 bits
                // above it are no bytes)
                r.type = types_.bytes();
                continue;
            }
            try {
                r.fields = fields_layout(r.accs);
            } catch (const Error&) {
                r.fields.reset();
            }
            continue;
        }
        try {
            r.type = type_of(types_, r.accs);
        } catch (const Error&) {  // (python logs it: the root has no type, its accesses raw)
            r.type.reset();
        }
    }
}

void Analysis::fixed_lengths_and_moves() {
    // root -> the length of the fixed array there, when the functions that
    // index it check the index is below a number first (and all the same)
    std::map<Word256, std::vector<EvmInt>> found;
    for (u32 fi = 0; fi < fns_.size(); ++fi) {
        const Bounded checked = checked_below(fns_[fi].trace, false, true);
        if (checked.list.empty()) continue;
        Accesses own;
        own.find(fns_[fi].trace);
        for (usize k = 0; k < own.size(); ++k) {
            const auto at = accesses_.index(own[k]);
            if (!at || !steps_[*at]) continue;
            const Path& st = *steps_[*at];
            if (st.steps.empty() || st.steps[0].kind != Step::Kind::Off || st.steps[0].e.is_int()) continue;
            const auto rit = roots_.find(st.root);
            if (rit == roots_.end() || !rit->second.type) continue;
            const StorageType& t = types_[*rit->second.type];
            if (t.kind != StorageType::Kind::Fixed) continue;
            const Access& a = own[k];
            const Value e = st.steps[0].e;
            Value i;
            if (types_.elem_width(t.elem) < 256 && a.size.is_small()) {
                i = packed(e, a.off, a.size);
            } else {
                const Lin l = linear(e);
                if (l.stride == EvmInt::from_u64(t.stride) && l.c.is_zero()) i = l.index;
            }
            if (i.nil()) continue;
            if (const auto* n = checked.find(i); n && *n) {
                auto& v = found[st.root];
                if (std::find(v.begin(), v.end(), **n) == v.end()) v.push_back(**n);
            }
        }
    }
    for (const auto& [n, ls] : found)
        if (ls.size() == 1)
            if (const auto u = ls[0].to_u64()) lengths_[n] = *u;

    // the roots a getter returns, as a variable
    std::vector<Word256> named;
    for (Fn& f : fns_) {
        if (!f.info->getter) continue;
        const auto g = traits::getter_of(*f.info);
        if (!g) continue;
        Narrow nw;
        const auto ga = getter_access(*g, nw.exp(g->value));
        if (!ga || ga->root) continue;
        if (const auto at = accesses_.index(ga->access); at && steps_[*at] && steps_[*at]->steps.empty())
            named.push_back(steps_[*at]->root);
    }
    // the fixed arrays whose length the functions check: the slots after the
    // first are theirs, not other variables - but the ones a getter returns
    bool moved = false;
    for (const auto& [n, length] : lengths_) {
        const auto rit = roots_.find(n);
        if (rit == roots_.end() || !rit->second.type) continue;
        const StorageType t = types_[*rit->second.type];
        if (t.kind != StorageType::Kind::Fixed) continue;
        const u16 width = types_.elem_width(t.elem);
        const EvmInt slots = width < 256 ? floordiv(EvmInt::from_u64(length) + EvmInt(i64(256 / width) - 1),
                                                    EvmInt(i64(256 / width)))
                                         : EvmInt::from_u64(length) * EvmInt::from_u64(t.stride);
        std::vector<Word256> moving;
        for (const auto& [r, root] : roots_) {
            if (r <= n) continue;
            const Word256 d = pan::sub(r, n);
            const auto du = d.as_u64();
            if (!du || !(EvmInt::from_u64(*du) < slots)) continue;
            if (root.fields && std::find(named.begin(), named.end(), r) == named.end()) moving.push_back(r);
        }
        for (const Word256& r : moving) {
            const u64 d = *pan::sub(r, n).as_u64();
            const Value off = mk_uint(d);
            for (auto& st : steps_)
                if (st && st->root == r && st->steps.empty()) {
                    st->root = n;
                    st->steps.push_back(Step{Step::Kind::Off, off, false});
                }
            auto it = roots_.find(r);
            for (RootAccess& a : it->second.accs) {
                a.steps.insert(a.steps.begin(), Step{Step::Kind::Off, off, false});
                roots_[n].accs.push_back(a);
            }
            roots_.erase(it);
            moved = true;
        }
    }
    if (moved) type_roots();
}

// python getter_path
bool Analysis::getter_path(std::optional<u32> t, std::span<const Step> sts, i64 size, Value off) {
    if (!t || (types_[*t].kind == StorageType::Kind::Bytes && sts.empty())) return false;
    const Value f = detail::form(FormCtx{types_, layout_->lang}, sv_form(NO_VAR), *t, sts, size, off);
    if (!f.is(Op::ST, 3)) return false;
    Value loc = f[1];
    std::vector<Value> keys;
    if (loc.is(Op::SBL, 1) && !sts.empty() && sts.back().kind == Step::Kind::Blen) loc = loc[0];
    while (!loc.is(Op::SV)) {
        if (loc.is(Op::SI, 2))
            keys.push_back(loc[1]);
        else if (!loc.is(Op::SF, 2))
            return false;
        loc = loc[0];
    }
    for (usize i = 0; i < keys.size(); ++i) {
        if (!from_calldata(keys[i])) return false;
        for (usize j = 0; j < i; ++j)
            if (keys[j] == keys[i]) return false;
    }
    return true;
}

void Analysis::find_bytes_getters() {
    bytes_getters_.assign(fns_.size(), std::nullopt);
    if (!opts_.bytes_getters) return;
    for (usize fi = 0; fi < fns_.size(); ++fi) {
        const FunctionInfo& f = *fns_[fi].info;
        if (!f.read_only || f.kind != FunctionInfo::Kind::Selector) continue;
        check_deadline(opts_.deadline_ns);
        // the slots whose bytes length it reads (python: the first three)
        std::vector<Value> keys;
        {
            Memo<Value, u8> seen;
            std::vector<Value> todo{fns_[fi].trace};
            // (pre-order, as python's find_f_list)
            auto visit = [&](auto&& self, Value v) -> void {
                check_stack();
                if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_STORAGE) || !seen.add(v)) return;
                if (v.is(Op::STORAGE, 3)) {
                    Value k;
                    if (v[2].is(Op::LENGTH, 1))
                        k = v[2][0];
                    else if (is_small(v[0], 1) && is_small(v[1], 0))
                        k = v[2];
                    if (!k.nil() && k.is(Op::LOC, 1)) k = k[0];
                    if (!k.nil() && std::find(keys.begin(), keys.end(), k) == keys.end()) keys.push_back(k);
                }
                for (Value c : v.children()) self(self, c);
            };
            visit(visit, fns_[fi].trace);
        }
        if (keys.size() > 3) keys.resize(3);
        for (Value key : keys) {
            if (key.is_int()) key = mk(Op::LOC, key);
            const Access length{small(256), small(0), mk(Op::LENGTH, key)};
            std::optional<Path> st;
            if (const auto at = accesses_.index(length)) {
                st = steps_[*at];
            } else {
                try {
                    st = parser_.parse(length.idx);
                } catch (const Error&) {
                    continue;
                }
                accesses_.add(length, Written::No);
                steps_.push_back(st);
                where_.emplace_back();
            }
            if (!st) continue;
            const auto rit = roots_.find(st->root);
            if (rit == roots_.end() || !rit->second.type) continue;
            const Value f_len =
                detail::form(FormCtx{types_, layout_->lang}, sv_form(NO_VAR), *rit->second.type, st->steps, 256, small(0));
            if (!(f_len.is(Op::ST, 3) && is_small(f_len[0], 256) && f_len[1].is(Op::SBL, 1) && is_small(f_len[2], 256)))
                continue;
            BytesTail bt(f, internals_, &shared_);
            const Value t = bt.find(fns_[fi].trace, key);
            if (!t.nil()) {
                bytes_getters_[fi] = std::make_pair(key, t);
                break;
            }
        }
    }
}

void Analysis::names() {
    // the getters' names: ("root", n) / ("field", n, off, end) -> (selector, strip)
    struct Name {
        u32 selector;
        bool strip;
    };
    std::map<Word256, Name> root_names;
    std::map<std::pair<Word256, std::pair<i64, i64>>, Name> field_names;
    const sigdb::Database* db = shared_.db;
    for (usize fi = 0; fi < fns_.size(); ++fi) {
        const FunctionInfo& f = *fns_[fi].info;
        if (f.kind != FunctionInfo::Kind::Selector || !db) continue;
        if (!f.getter && !bytes_getters_[fi]) continue;
        const auto e = db->function(f.selector);
        if (!e || e->trust() != sigdb::Trust::verified) continue;
        const std::string_view nm = e->name();
        const GetterName gn = getter_name(std::span<const u8>(reinterpret_cast<const u8*>(nm.data()), nm.size()));
        if (!gn.good) continue;
        const Name name{f.selector, gn.strip};
        if (bytes_getters_[fi]) {
            const Access length{small(256), small(0), mk(Op::LENGTH, bytes_getters_[fi]->first)};
            const auto at = accesses_.index(length);
            if (!at || !steps_[*at]) continue;
            const Path& p = *steps_[*at];
            const auto rit = roots_.find(p.root);
            if (rit != roots_.end() && getter_path(rit->second.type, p.steps, 256, small(0)))
                root_names.emplace(p.root, name);
            continue;
        }
        const auto g = traits::getter_of(f);
        if (!g) continue;
        Narrow nw;
        const auto ga = getter_access(*g, nw.exp(g->value));
        if (!ga) continue;
        if (ga->root) {
            root_names.emplace(ga->slot, name);
            continue;
        }
        const Access& a = ga->access;
        std::optional<Path> st;
        if (const auto at = accesses_.index(a))
            st = steps_[*at];
        else
            try {
                st = parser_.parse(a.idx);
            } catch (const Error&) {
                continue;
            }
        if (!st) continue;
        const auto rit = roots_.find(st->root);
        if (rit != roots_.end() && rit->second.fields && st->steps.empty()) {
            // (a field is bits known: not the bits of an access at a place
            // computed at runtime, a byte of the slot by an index)
            if (a.off.is_small() && a.size.is_small())
                field_names.emplace(std::make_pair(st->root, std::make_pair(a.off.small_val(), a.off.small_val() + a.size.small_val())),
                                    name);
        } else if (a.size.is_small() && rit != roots_.end() &&
                   getter_path(rit->second.type, st->steps, a.size.small_val(), a.off)) {
            root_names.emplace(st->root, name);
        }
    }
    // the variables, by slot then offset
    for (const auto& [n, r] : roots_) {
        if (r.fields) {
            for (const Range& fr : *r.fields) {
                StorageVar v;
                v.slot = n;
                v.off = u16(fr.off);
                v.type = types_.value(u16(fr.end - fr.off));
                if (const auto it = field_names.find({n, {fr.off, fr.end}}); it != field_names.end()) {
                    v.getter = it->second.selector;
                    v.strip_get = it->second.strip;
                }
                var_of_field_[{n, {fr.off, fr.end}}] = u32(layout_->vars.size());
                layout_->vars.push_back(v);
            }
        } else if (r.type) {
            StorageVar v;
            v.slot = n;
            v.type = *r.type;
            if (const auto it = lengths_.find(n); it != lengths_.end() && types_[*r.type].kind == StorageType::Kind::Fixed) {
                StorageType t = types_[*r.type];
                t.length = it->second;
                v.type = types_.intern(t);
            }
            if (const auto it = root_names.find(n); it != root_names.end()) {
                v.getter = it->second.selector;
                v.strip_get = it->second.strip;
            }
            var_of_root_[n] = u32(layout_->vars.size());
            layout_->vars.push_back(v);
        }
    }
}

// python Storage.path_form
Value Analysis::path_form(const Path& p, i64 size, Value off) {
    const FormCtx c{types_, layout_->lang};
    const auto rit = roots_.find(p.root);
    if (rit == roots_.end()) return Value();
    const Root& r = rit->second;
    if (r.fields) {
        if (!p.steps.empty() || !off.is_small()) return Value();
        const i64 o = off.small_val();
        for (const Range& fr : *r.fields)
            if (fr.off <= o && o + size <= fr.end) {
                const u32 var = var_of_field_.at({p.root, {fr.off, fr.end}});
                return detail::form(c, sv_form(var), types_.value(u16(fr.end - fr.off)), {}, size, small(o - fr.off));
            }
        return Value();
    }
    const auto vit = var_of_root_.find(p.root);
    if (vit == var_of_root_.end()) return Value();
    return detail::form(c, sv_form(vit->second), *r.type, p.steps, size, off);
}

// python Storage.form: the printed access, checked, else raw; NIL for a
// write: the whole word (set with the bits around kept)
Value Analysis::form(Value size, Value off, Value idx, bool write) {
    Memo<Key3, Value>& memo = write ? forms_write_ : forms_read_;
    const Key3 key{size.raw(), off.raw(), idx.raw()};
    if (const Value* m = memo.find(key)) return m->is_none() ? Value() : *m;
    poll();
    const Access a{size, off, idx};
    Value f;
    if (const auto at = accesses_.index(a); at && steps_[*at] && size.is_small()) {
        f = path_form(*steps_[*at], size.small_val(), off);
        if (write && f.is(Op::MASK_SHL, 4) && f[3].is(Op::ST, 3) && f[3][1].is(Op::SV, 1) && off.is_small()) {
            // some bits of a variable at the bit 0 of its slot
            const u32 var = f[3][1][0].name_id();
            if (var < layout_->vars.size() && layout_->vars[var].off == 0 && off.small_val() > 0 && off.small_val() < 256)
                f = st_form(size.small_val(), mk(Op::SF, f[3][1], off), 256 - off.small_val());
        }
        if (!f.nil() && write && !f.is(Op::ST)) f = Value();
        if (!f.nil() && !worlds_->check(*layout_, f, a)) f = Value();
    }
    if (f.nil()) f = write ? raw_target(size, off, idx) : raw_read(size, off, idx);
    // (a NIL target: the whole word - kept NIL in the memo, the slot made again)
    memo.put(key, f.nil() ? None : f);
    return f;
}

// python rewrite_accesses with Storage.form
class FormRewrite final : public TraceMap {
public:
    explicit FormRewrite(std::function<Value(Value, Value, Value, bool)> form) : form_(std::move(form)) {}
    Value exp(Value e) override {
        check_stack();
        if (!e.is_expr() || !e.has_flags(F_STORAGE)) return e;
        if (const Value* m = memo_.find(e)) return *m;
        Value r;
        if (e.is(Op::STORAGE, 3)) {
            const Value f = form_(e[0], e[1], e[2], false);
            r = exp(f);
        } else {
            r = children(e);
        }
        memo_.put(e, r);
        return r;
    }
    Value line(Value l) override {
        if (!l.is(Op::STORE, 4)) return operands(l);
        const Value size = l[0], off = l[1], idx = l[2], val = l[3];
        Value target = form_(size, off, idx, true);
        Value r;
        if (!target.nil() && target.is(Op::ST, 3) && target[0].is_small() &&
            !(target[1].is(Op::SF, 2) && !target[1][1].is_small())) {
            r = mk(Op::SET, exp(target), exp(val));
        } else {
            // bits at an offset computed at runtime: the whole word
            const Value whole = st_form(256, mk(Op::SR, idx.is(Op::LOC, 1) ? idx[0] : idx), 256);
            const Value ones = Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}}.to_value();
            const Value mask = alg::mask(size, small(0), off, ones);
            const Value merged = alg::bor(alg::band(whole, alg::bnot(mask)), alg::mask(size, small(0), off, val));
            r = mk(Op::SET, exp(whole), exp(merged));
        }
        cx().pcs.inherit(r, l);
        return r;
    }
private:
    std::function<Value(Value, Value, Value, bool)> form_;
    Memo<Value, Value> memo_;
};

// SALL(SR(key)) -> SALL(loc), any depth (the tail of a bytes getter)
class SallMap final : public TraceMap {
public:
    SallMap(Value key, Value loc) : key_(key), loc_(loc) {}
    Value exp(Value e) override {
        check_stack();
        if (!e.is_expr() || !e.has_flags(F_STORAGE)) return e;
        if (e.is(Op::SALL, 1) && e[0].is(Op::SR, 1) && e[0][0] == key_) return mk(Op::SALL, loc_);
        if (const Value* m = memo_.find(e)) return *m;
        const Value r = children(e);
        memo_.put(e, r);
        return r;
    }

private:
    Value key_, loc_;
    Memo<Value, Value> memo_;
};

Value Analysis::rewrite(Value trace) {
    if (!rewriter_)
        rewriter_ = std::make_unique<FormRewrite>(
            [this](Value size, Value off, Value idx, bool write) { return form(size, off, idx, write); });
    return rewriter_->trace(trace);
}

// python Storage.getter_trace: a bytes getter's trace, `return name[all]`
Value Analysis::getter_trace(usize fi) {
    if (!bytes_getters_[fi]) return Value();
    const auto& [key, trace] = *bytes_getters_[fi];
    const Value f_len = form(small(256), small(0), mk(Op::LENGTH, key), false);
    if (!(f_len.is(Op::ST, 3) && is_small(f_len[0], 256) && f_len[1].is(Op::SBL, 1) && is_small(f_len[2], 256)))
        return Value();
    SallMap sm(key, f_len[1][0]);
    return rewrite(sm.trace(trace));
}

std::shared_ptr<StorageLayout> Analysis::run() {
    const i64 deadline = opts_.deadline_ns;
    find_accesses();
    check_deadline(deadline);
    type_roots();
    check_deadline(deadline);
    fixed_lengths_and_moves();
    check_deadline(deadline);
    find_bytes_getters();
    check_deadline(deadline);
    names();
    worlds_ = std::make_unique<Worlds>();
    for (usize fi = 0; fi < fns_.size(); ++fi) {
        check_deadline(deadline);
        const Value g = getter_trace(fi);
        fns_[fi].trace = g.nil() ? rewrite(fns_[fi].trace) : g;
    }
    return layout_;
}

}  // namespace

// the traces of the functions and internal functions to rewrite
std::vector<Fn> functions_of(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals) {
    std::vector<Fn> fns;
    for (FunctionInfo& f : functions)
        if (!f.problem && f.trace.is_trace()) fns.push_back(Fn{&f, f.trace});
    for (FunctionInfo& f : internals)
        if (!f.problem && f.trace.is_trace()) fns.push_back(Fn{&f, f.trace});
    return fns;
}

}  // namespace detail

std::shared_ptr<const StorageLayout> analyse(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                             const ContractShared& shared, const Options& opts) {
    using namespace detail;
    std::vector<Fn> fns = functions_of(functions, internals);
    // python narrow, then the language (the metadata's, else how the mappings hash)
    {
        Narrow nw;
        for (Fn& f : fns) f.trace = nw.trace(f.trace);
    }
    check_deadline(opts.deadline_ns);
    Lang lang = shared.lang;
    {
        Accesses all;
        for (Fn& f : fns) all.find(f.trace);
        if (lang == Lang::Unknown) lang = vote_language(all);
        Parser parser(lang);
        // the stores of whole variables
        Regroup rg(all, parser);
        for (Fn& f : fns) f.trace = rg.trace(f.trace);
    }
    check_deadline(opts.deadline_ns);
    Parser parser(lang);
    Analysis a(fns, internals, shared, lang, parser, opts);
    std::shared_ptr<StorageLayout> layout = a.run();
    // (every trace made: swapped in)
    for (Fn& f : fns) f.info->trace = f.trace;
    return layout;
}

std::shared_ptr<const StorageLayout> rewrite_raw(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                                 Lang lang) {
    using namespace detail;
    std::vector<Fn> fns = functions_of(functions, internals);
    FormRewrite rw([](Value size, Value off, Value idx, bool write) {
        return write ? raw_target(size, off, idx) : raw_read(size, off, idx);
    });
    for (Fn& f : fns) f.trace = rw.trace(f.trace);
    for (Fn& f : fns) f.info->trace = f.trace;
    auto layout = std::make_shared<StorageLayout>();
    layout->lang = lang == Lang::Vyper ? Lang::Vyper : Lang::Solidity;
    return layout;
}

}  // namespace pan::storage
