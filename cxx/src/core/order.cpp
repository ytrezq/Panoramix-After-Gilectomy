#include "core/order.hpp"

#include <cstring>

#include "core/budget.hpp"
#include "core/intops.hpp"
#include "core/node.hpp"

namespace pan {

namespace {

// the rank of a value's class in the order
int rank(Value v) {
    switch (v.tag()) {
        case Tag::Nil: return 0;
        case Tag::SmallInt:
        case Tag::BigInt: return 1;
        case Tag::Bool: return 2;
        case Tag::None: return 3;
        case Tag::Leaf: return 4;
        case Tag::Name: return 5;
        case Tag::Bytes: return 6;
        case Tag::Expr: return 7;
        case Tag::List: return 8;
    }
    return 9;
}

template <class T>
int cmp3(T a, T b) {
    return (a > b) - (a < b);
}

}  // namespace

int compare(Value a, Value b) {
    if (a == b) return 0;
    int ra = rank(a), rb = rank(b);
    if (ra != rb) return ra < rb ? -1 : 1;
    switch (ra) {
        case 1: return int_cmp(a, b);
        case 2: return a.is_true() ? 1 : -1;  // False < True (a != b)
        case 4:
        case 5:
            if (int c = cmp3(a.imm_sub(), b.imm_sub())) return c;
            return cmp3(a.imm_payload(), b.imm_payload());
        case 6: {
            if (int c = cmp3(a.size(), b.size())) return c;
            int c = std::memcmp(a.bytes().data(), b.bytes().data(), a.size());
            return (c > 0) - (c < 0);
        }
        case 7:
        case 8: {
            check_stack();
            const NodeHeader* na = a.node();
            const NodeHeader* nb = b.node();
            if (int c = cmp3(na->op, nb->op)) return c;
            if (int c = cmp3(na->size, nb->size)) return c;
            for (u32 i = 0; i < na->size; i++)
                if (int c = compare(node_args(na)[i], node_args(nb)[i])) return c;
            return 0;  // equal structures from different contexts
        }
        default: return 0;
    }
}

}  // namespace pan
