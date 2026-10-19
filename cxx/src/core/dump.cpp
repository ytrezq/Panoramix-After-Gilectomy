// Debug and test text of Values (see dump.hpp).
#include "core/dump.hpp"

#include <charconv>
#include <cstdint>
#include <string>

#include "core/evmint.hpp"
#include "core/node.hpp"
#include "core/ops.hpp"

namespace pan {
namespace {

// §2.1: a node Value's raw word is its 16-aligned NodeHeader*; §3.1: a LIST's
// header op is its ListKind (values or trace).
bool is_trace_list(Value v) {
  if (!v.is_list()) return false;
  auto* h = reinterpret_cast<const NodeHeader*>(static_cast<std::uintptr_t>(v.raw()));
  return h->op == static_cast<std::uint16_t>(ListKind::Trace);
}

void put_u(std::string& o, std::uint64_t x) {
  char buf[24];
  auto r = std::to_chars(buf, buf + sizeof buf, x);
  o.append(buf, r.ptr);
}

void put_i(std::string& o, std::int64_t x) {
  char buf[24];
  auto r = std::to_chars(buf, buf + sizeof buf, x);
  o.append(buf, r.ptr);
}

void put_hex(std::string& o, std::uint64_t x, int width) {
  static constexpr char kHex[] = "0123456789abcdef";
  for (int i = width - 1; i >= 0; --i) o += kHex[(x >> (4 * i)) & 15];
}

// Big ints: 0x + magnitude (lower-case hex), -0x... when negative.
void put_big(std::string& o, Value v) {
  static constexpr char kHex[] = "0123456789abcdef";
  EvmInt e(v);
  bool neg = e.sign() < 0;
  EvmInt m = neg ? -e : e;
  std::uint32_t bits = m.bit_length();
  std::uint32_t nibbles = bits == 0 ? 1 : (bits + 3) / 4;
  if (neg) o += '-';
  o += "0x";
  for (std::uint32_t i = nibbles; i-- > 0;) {
    unsigned d = 0;
    for (unsigned b = 0; b < 4; ++b)
      if (m.test_bit(4 * i + b)) d |= 1u << b;
    o += kHex[d];
  }
}

void put_bytes(std::string& o, Value v) {
  o += "b\"";
  for (std::uint8_t c : v.bytes()) {
    switch (c) {
      case '\\': o += "\\\\"; break;
      case '"': o += "\\\""; break;
      case '\n': o += "\\n"; break;
      case '\t': o += "\\t"; break;
      case '\r': o += "\\r"; break;
      case 0: o += "\\0"; break;
      default:
        if (c >= 0x20 && c < 0x7f) {
          o += static_cast<char>(c);
        } else {
          o += "\\x";
          put_hex(o, c, 2);
        }
    }
  }
  o += '"';
}

void put_name(std::string& o, Value v) {
  std::uint32_t id = v.name_id();
  switch (v.name_kind()) {
    case NameKind::TMP: o += "tmp"; put_u(o, id); return;
    case NameKind::LOOP: o += "loop"; put_u(o, id); return;
    case NameKind::MSIZE_VAR: o += "_msize"; return;
    case NameKind::PRECOMPILE:
      o += "prec_"; put_u(o, id >> 24); o += '_'; put_u(o, id & 0xffffffu); return;
    case NameKind::PARAM: o += "param"; put_u(o, id); return;
    case NameKind::STORVAR: o += "stor"; put_u(o, id); return;
    case NameKind::FUNC: o += "func_"; put_hex(o, id, 8); return;
    case NameKind::FALLBACK: o += "fallback"; return;
    case NameKind::INTERNAL: o += "internal_"; put_u(o, id); return;
    case NameKind::LOOP_ID: o += "loopid"; put_u(o, id); return;
    case NameKind::SAFEMATH_PARAM: o += "sm"; put_u(o, id); return;
  }
  o += "name_";
  put_u(o, static_cast<std::uint16_t>(v.name_kind()));
  o += '_';
  put_u(o, id);
}

void put_op(std::string& o, Op op) {
  const char* n = op_name(op);
  if (n) {
    o += n;
  } else {
    o += "op_";
    put_hex(o, static_cast<std::uint16_t>(op), 4);
  }
}

void put(std::string& o, Value v) {
  switch (v.tag()) {
    case Tag::Nil: o += "NIL"; return;
    case Tag::SmallInt: put_i(o, v.small_val()); return;
    case Tag::BigInt: put_big(o, v); return;
    case Tag::Bool: o += v.is_true() ? "True" : "False"; return;
    case Tag::None: o += "None"; return;
    case Tag::Name: put_name(o, v); return;
    case Tag::Bytes: put_bytes(o, v); return;
    case Tag::Leaf:
      if (v.leaf_n() == 0) {
        put_op(o, v.op());
      } else {
        o += '(';
        put_op(o, v.op());
        o += ' ';
        put_u(o, v.leaf_n());
        o += ')';
      }
      return;
    case Tag::Expr:
      o += '(';
      put_op(o, v.op());
      for (Value a : v.args()) {
        o += ' ';
        put(o, a);
      }
      o += ')';
      return;
    case Tag::List: {
      bool tr = is_trace_list(v);
      o += tr ? '{' : '[';
      bool first = true;
      for (Value a : v.args()) {
        if (!first) o += ' ';
        first = false;
        put(o, a);
      }
      o += tr ? '}' : ']';
      return;
    }
  }
  o += "NIL";
}

void indent(std::string& o, int n) { o.append(static_cast<std::size_t>(n), ' '); }

void trace_block(std::string& o, Value t, int ind);

// One trace line at `ind`; its trace operands become indented blocks.
void trace_line(std::string& o, Value l, int ind) {
  indent(o, ind);
  bool nested = false;
  if (l.is_expr())
    for (Value a : l.args())
      if (is_trace_list(a)) { nested = true; break; }
  if (!nested) {
    put(o, l);
    o += '\n';
    return;
  }
  o += '(';
  put_op(o, l.op());
  bool broke = false;
  for (Value a : l.args()) {
    if (is_trace_list(a)) {
      o += '\n';
      trace_block(o, a, ind + 2);
      broke = true;
    } else if (broke) {
      o += '\n';
      indent(o, ind + 2);
      put(o, a);
    } else {
      o += ' ';
      put(o, a);
    }
  }
  o += ")\n";
}

void trace_block(std::string& o, Value t, int ind) {
  indent(o, ind);
  o += "{\n";
  for (Value l : t.args()) trace_line(o, l, ind + 2);
  indent(o, ind);
  o += '}';
}

}  // namespace

std::string dump(Value v) {
  std::string o;
  put(o, v);
  return o;
}

std::string dump_trace(Value v) {
  std::string o;
  if (is_trace_list(v)) {
    for (Value l : v.args()) trace_line(o, l, 0);
  } else {
    trace_line(o, v, 0);
  }
  return o;
}

}  // namespace pan
