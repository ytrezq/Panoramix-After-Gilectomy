// Stores of whole variables (python storage.py: slot_class, Regroup): the
// stores of the parts a store of a whole word was split in (lot 4's
// split_store) made again stores of the variables of the slot - 1 in the
// bits 216-224 and 0 in the 224-240 are 1 in the uint16 at 216 and 0 in the
// uint8 at 232 - the variables being those of all the slots of the same
// place (its slot class).
#include "storage/regroup.hpp"

#include <algorithm>

#include "algebra/construct.hpp"
#include "algebra/masks.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"

namespace pan::storage::detail {

namespace {

std::optional<SlotClass> slot_class(const std::optional<Path>& p) {
    if (!p) return std::nullopt;
    SlotClass c;
    c.root = p->root;
    for (const Step& s : p->steps) {
        ClassStep k;
        switch (s.kind) {
            case Step::Kind::Map:
                k.kind = ClassStep::Kind::Map;
                k.bytes_key = s.bytes_key;
                break;
            case Step::Kind::Data:
                k.kind = ClassStep::Kind::Data;
                break;
            case Step::Kind::Off: {
                const Lin l = linear(s.e);
                k.kind = ClassStep::Kind::Off;
                k.stride = l.stride;
                k.c = l.c;
                break;
            }
            case Step::Kind::Blen:
                return std::nullopt;
        }
        c.steps.push_back(std::move(k));
    }
    return c;
}

}  // namespace

u32 Regroup::class_id(const SlotClass& c) {
    for (u32 i = 0; i < classes_.size(); ++i)
        if (classes_[i] == c) return i;
    classes_.push_back(c);
    fields_.emplace_back();
    accs_.emplace_back();
    return u32(classes_.size() - 1);
}

Regroup::Regroup(const Accesses& accesses, Parser& parser) {
    for (usize i = 0; i < accesses.size(); ++i) {
        poll();
        const Access& a = accesses[i];
        std::optional<SlotClass> c;
        try {
            c = slot_class(parser.parse(a.idx));
        } catch (const Error&) {  // (python: an exception there is no class)
            c.reset();
        }
        u32 id = NO_CLASS;
        if (c) {
            id = class_id(*c);
            accs_[id].push_back(RootAccess{{}, a.size, a.off, accesses.written(i)});
        }
        cls_.put(a.key(), id + 1);
    }
    for (u32 id = 0; id < classes_.size(); ++id) {
        bool ints = true;
        for (const RootAccess& r : accs_[id])
            if (!r.size.is_small() || !r.off.is_small()) ints = false;
        if (ints) {
            fields_[id] = fields_layout(accs_[id]);
            has_fields_.push_back(id);
        }
    }
}

bool Regroup::has_fields(u32 id) const noexcept {
    return std::find(has_fields_.begin(), has_fields_.end(), id) != has_fields_.end();
}

std::optional<u32> Regroup::class_of(const Access& a) const noexcept {
    if (const u32* k = cls_.find(a.key())) return *k - 1;
    return std::nullopt;
}

std::optional<Regroup::Store> Regroup::store(Value line) const {
    if (!line.is(Op::STORE, 4) || !line[0].is_small() || !line[1].is_small()) return std::nullopt;
    const auto c = class_of(Access{line[0], line[1], line[2]});
    if (!c || *c == NO_CLASS || !has_fields(*c)) return std::nullopt;
    return Store{*c, line[0].small_val(), line[1].small_val(), line[3], line[2], line};
}

Value Regroup::trace(Value t) {
    check_stack();
    if (!t.is_trace()) return t;
    if (const Value* m = memo_.find(t)) return *m;
    std::vector<Value> lines;
    lines.reserve(t.size());
    bool changed = false;
    for (Value line : t.args()) {
        poll();
        Value nl = line;
        if (line.is_expr()) {
            SmallVec<Value, 8> ops;
            bool c = false;
            for (Value a : line.args()) {
                const Value na = a.is_trace() ? trace(a) : a;
                c |= na != a;
                ops.push_back(na);
            }
            if (c) {
                nl = mk_like(line, ops.span());
                cx().pcs.inherit(nl, line);
            }
        }
        changed |= nl != line;
        lines.push_back(nl);
    }
    std::vector<Value> res;
    res.reserve(lines.size());
    for (usize i = 0; i < lines.size();) {
        const std::optional<Store> first = store(lines[i]);
        usize j = i + 1;
        if (first)
            while (j < lines.size()) {
                const std::optional<Store> s = store(lines[j]);
                if (!s || s->idx != first->idx) break;
                ++j;
            }
        if (first) {
            const std::vector<Value> r = run(std::span<const Value>(lines.data() + i, j - i));
            if (r.size() != j - i || !std::equal(r.begin(), r.end(), lines.begin() + i)) changed = true;
            res.insert(res.end(), r.begin(), r.end());
        } else {
            res.push_back(lines[i]);
        }
        i = j;
    }
    const Value out = changed ? mk_trace(std::span<const Value>(res.data(), res.size())) : t;
    memo_.put(t, out);
    return out;
}

std::vector<Value> Regroup::run(std::span<const Value> lines) {
    std::vector<Value> same(lines.begin(), lines.end());
    std::vector<Store> parts;
    for (Value l : lines) parts.push_back(*store(l));
    const u32 c = parts[0].cls;
    const Value idx = parts[0].idx;
    // parts of different bits
    std::vector<std::pair<i64, i64>> bits;
    for (const Store& p : parts) bits.emplace_back(p.off, p.off + p.size);
    std::sort(bits.begin(), bits.end());
    for (usize k = 1; k < bits.size(); ++k)
        if (bits[k - 1].second > bits[k].first) return same;
    // their values not reading the slot (else they'd read what the others
    // write) - nor another of the same place: it may be the same
    for (const Store& p : parts) {
        Accesses reads;
        reads.find(p.val);
        for (usize k = 0; k < reads.size(); ++k) {
            const auto rc = class_of(reads[k]);
            if (!rc || *rc == NO_CLASS || *rc == c) return same;
        }
    }
    const std::vector<Range>& fields = fields_[c];
    auto whole = [&](i64 size, i64 off) {
        i64 sum = 0;
        for (const Range& r : fields)
            if (r.off < off + size && off < r.end) {
                if (!(off <= r.off && r.end <= off + size)) return false;
                sum += r.end - r.off;
            }
        return sum == size;
    };
    struct Part {
        i64 size, off;
        Value val;
    };
    std::vector<Part> res;
    std::vector<Store> rest;
    for (const Store& p : parts) {
        if (p.val.is_int() && whole(p.size, p.off))
            res.push_back(Part{p.size, p.off, p.val});
        else
            rest.push_back(p);
    }
    for (const Range& f : fields) {
        std::vector<Part> ps;
        for (const Store& p : rest) {
            const i64 a = std::max(f.off, p.off), b = std::min(f.end, p.off + p.size);
            if (a >= b) continue;
            if (p.val.is_int()) {
                // (a number's bits in this variable)
                const EvmInt v = (EvmInt(p.val) >> u64(a - p.off)).mod_2exp(u64(b - a));
                ps.push_back(Part{b - a, a, v.value()});
            } else if (a == p.off && b == p.off + p.size) {
                ps.push_back(Part{p.size, p.off, p.val});
            } else {
                return same;  // a value over two variables
            }
        }
        if (ps.empty()) continue;
        i64 covered = 0;
        std::vector<const Part*> others;
        bool zero_ints = true;
        for (const Part& p : ps) {
            covered += p.size;
            if (!p.val.is_int())
                others.push_back(&p);
            else if (!EvmInt(p.val).is_zero())
                zero_ints = false;
        }
        const bool full = covered == f.end - f.off;
        if (full && others.empty()) {
            EvmInt value(0);
            for (const Part& p : ps) value = value + (EvmInt(p.val) << u64(p.off - f.off));
            ps = {Part{f.end - f.off, f.off, value.value()}};
        } else if (full && others.size() == 1 && others[0]->off == f.off &&
                   i64(alg::max_bits(others[0]->val)) <= others[0]->size && zero_ints) {
            const Value v = others[0]->val;
            ps = {Part{f.end - f.off, f.off, v}};
        }
        for (const Part& p : ps) res.push_back(p);
    }
    // the same stores - or some still not of whole variables
    std::vector<std::pair<i64, i64>> a, b;
    for (const Part& p : res) a.emplace_back(p.size, p.off);
    for (const Store& p : parts) b.emplace_back(p.size, p.off);
    std::sort(a.begin(), a.end());
    std::sort(b.begin(), b.end());
    if (a == b) return same;
    for (const Part& p : res)
        if (!whole(p.size, p.off)) return same;
    std::stable_sort(res.begin(), res.end(), [](const Part& x, const Part& y) { return x.off < y.off; });
    std::vector<Value> out;
    for (const Part& p : res) {
        const Value line = mk(Op::STORE, small(p.size), small(p.off), idx, p.val);
        cx().pcs.inherit(line, lines[0]);
        cls_.put(Access{line[0], line[1], line[2]}.key(), c + 1);
        out.push_back(line);
    }
    return out;
}

}  // namespace pan::storage::detail
