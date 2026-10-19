// parse_sexpr: the inverse of dump (dump.hpp), a Ragel 6 scanner (-G2).
// The machine recognises every token; the actions only build the Values on an
// explicit stack of open brackets. Op names are found by binary search in a
// sorted table built once from the op table.
#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "core/ops.hpp"

namespace pan {
namespace {

struct OpEntry {
  std::string_view name;
  Op op;
};

const std::vector<OpEntry>& op_table() {
  static const std::vector<OpEntry> table = [] {
    std::vector<OpEntry> t;
    for (std::uint32_t i = 0; i < 0xffffu; ++i) {
      Op op = static_cast<Op>(i);
      if (!info(op).defined) continue;
      const char* n = op_name(op);
      if (n && *n) t.push_back({n, op});
    }
    std::sort(t.begin(), t.end(),
              [](const OpEntry& a, const OpEntry& b) { return a.name < b.name; });
    return t;
  }();
  return table;
}

std::optional<Op> find_op(std::string_view n) {
  const auto& t = op_table();
  auto it = std::lower_bound(t.begin(), t.end(), n,
                             [](const OpEntry& e, std::string_view k) { return e.name < k; });
  if (it == t.end() || it->name != n) return std::nullopt;
  return it->op;
}

unsigned hexval(char c) {
  if (c >= '0' && c <= '9') return static_cast<unsigned>(c - '0');
  if (c >= 'a' && c <= 'f') return static_cast<unsigned>(c - 'a' + 10);
  return static_cast<unsigned>(c - 'A' + 10);
}

struct Frame {
  char open;            // '(' '[' '{'
  const char* at;
  bool head = false;    // '(' : the op name was read
  Op op = Op::NONE;
  std::vector<Value> items;
};

class Parser {
 public:
  explicit Parser(std::string_view src) : src_(src) {}

  [[noreturn]] void fail(const char* at, std::string_view what) const {
    std::string m = "sexpr: ";
    m += what;
    m += " at offset ";
    m += std::to_string(at - src_.data());
    throw InvalidInput(std::move(m));
  }

  void open(char c, const char* at) {
    Frame f;
    f.open = c;
    f.at = at;
    st_.push_back(std::move(f));
  }

  void close(char c, const char* at) {
    if (st_.empty()) fail(at, "unbalanced closing bracket");
    Frame f = std::move(st_.back());
    st_.pop_back();
    char want = f.open == '(' ? ')' : f.open == '[' ? ']' : '}';
    if (c != want) fail(at, "mismatched closing bracket");
    Value v;
    try {
      if (f.open == '[') {
        v = mk_list(f.items);
      } else if (f.open == '{') {
        v = mk_trace(f.items);
      } else {
        if (!f.head) fail(f.at, "empty ()");
        if (info(f.op).leaf) {
          if (f.items.size() != 1 || !f.items[0].is_small() || f.items[0].small_val() < 0 ||
              f.items[0].small_val() > 0xffffffffll)
            fail(f.at, "a leaf takes one number (n)");
          v = Value::leaf(f.op, static_cast<std::uint32_t>(f.items[0].small_val()));
        } else {
          v = mk(f.op, std::span<const Value>(f.items));
        }
      }
    } catch (const InternalError& e) {
      fail(f.at, e.what());
    }
    atom(v, f.at);
  }

  void atom(Value v, const char* at) {
    if (st_.empty()) {
      if (have_) fail(at, "more than one value");
      result_ = v;
      have_ = true;
      return;
    }
    Frame& f = st_.back();
    if (f.open == '(' && !f.head) fail(at, "expected an operation name after '('");
    f.items.push_back(v);
  }

  void ident(const char* b, const char* e) {
    std::optional<Op> op = find_op(std::string_view(b, static_cast<std::size_t>(e - b)));
    if (!op) fail(b, "unknown operation");
    if (!st_.empty() && st_.back().open == '(' && !st_.back().head) {
      st_.back().head = true;
      st_.back().op = *op;
      return;
    }
    if (info(*op).leaf) {
      atom(Value::leaf(*op, 0), b);
      return;
    }
    Value v;
    try {
      v = mk(*op, std::span<const Value>());
    } catch (const InternalError& x) {
      fail(b, x.what());
    }
    atom(v, b);
  }

  std::uint32_t dec32(const char* b, const char* e) const {
    std::uint64_t x = 0;
    for (const char* q = b; q != e; ++q) {
      x = x * 10 + static_cast<std::uint64_t>(*q - '0');
      if (x > 0xffffffffull) fail(b, "number too large for a name");
    }
    return static_cast<std::uint32_t>(x);
  }

  void name(NameKind k, std::uint32_t id, const char* at) { atom(Value::name(k, id), at); }

  void dec_name(NameKind k, const char* b, const char* e, const char* at) {
    name(k, dec32(b, e), at);
  }

  // prec_A_K: payload (A << 24) | K
  void prec(const char* b, const char* e, const char* at) {
    const char* u = b;
    while (*u != '_') ++u;
    std::uint32_t a = dec32(b, u), k = dec32(u + 1, e);
    if (a > 0xff || k > 0xffffff) fail(at, "precompile name out of range");
    name(NameKind::PRECOMPILE, (a << 24) | k, at);
  }

  // name_K_I: a name of any kind
  void any_name(const char* b, const char* e, const char* at) {
    const char* u = b;
    while (*u != '_') ++u;
    std::uint32_t k = dec32(b, u), i = dec32(u + 1, e);
    if (k > 0xffff) fail(at, "name kind out of range");
    name(static_cast<NameKind>(k), i, at);
  }

  void func(const char* b, const char* e, const char* at) {
    std::uint32_t x = 0;
    for (const char* q = b; q != e; ++q) x = (x << 4) | hexval(*q);
    name(NameKind::FUNC, x, at);
  }

  void dec(const char* b, const char* e) {
    bool neg = *b == '-';
    const char* q = neg ? b + 1 : b;
    std::int64_t x = 0;
    bool over = false;
    for (const char* r = q; r != e && !over; ++r) {
      std::int64_t d = *r - '0';
      over = __builtin_mul_overflow(x, std::int64_t{10}, &x) ||
             (neg ? __builtin_sub_overflow(x, d, &x) : __builtin_add_overflow(x, d, &x));
    }
    if (!over) {
      atom(mk_int(x), b);
      return;
    }
    EvmInt big(0);
    for (const char* r = q; r != e; ++r) big = big * EvmInt(10) + EvmInt(*r - '0');
    if (neg) big = -big;
    atom(big.value(), b);
  }

  void hex(const char* b, const char* e) {
    bool neg = *b == '-';
    const char* q = (neg ? b + 1 : b) + 2;  // past 0x
    std::size_t n = static_cast<std::size_t>(e - q);
    std::vector<std::uint8_t> be((n + 1) / 2, 0);
    std::size_t j = be.size() * 2 - n;  // nibble index of the first digit
    for (const char* r = q; r != e; ++r, ++j)
      be[j / 2] |= static_cast<std::uint8_t>(hexval(*r) << (j % 2 ? 0 : 4));
    EvmInt x = EvmInt::from_be(std::span<const std::uint8_t>(be));
    if (neg) x = -x;
    atom(x.value(), b);
  }

  // b"...": the machine has checked the escapes.
  void bytes(const char* b, const char* e) {
    std::vector<std::uint8_t> out;
    for (const char* q = b + 2; q != e - 1; ++q) {
      if (*q != '\\') {
        out.push_back(static_cast<std::uint8_t>(*q));
        continue;
      }
      ++q;
      switch (*q) {
        case 'n': out.push_back('\n'); break;
        case 't': out.push_back('\t'); break;
        case 'r': out.push_back('\r'); break;
        case '0': out.push_back(0); break;
        case 'x':
          out.push_back(static_cast<std::uint8_t>(hexval(q[1]) << 4 | hexval(q[2])));
          q += 2;
          break;
        default: out.push_back(static_cast<std::uint8_t>(*q));  // \\ and \"
      }
    }
    atom(mk_bytes(std::span<const std::uint8_t>(out)), b);
  }

  Value finish(const char* at) {
    if (!st_.empty()) fail(st_.back().at, "unclosed bracket");
    if (!have_) fail(at, "no value");
    return result_;
  }

 private:
  std::string_view src_;
  std::vector<Frame> st_;
  Value result_;
  bool have_ = false;
};

%%{
  machine sexpr;
  write data;

  dec   = '-'? digit+;
  hex   = '-'? '0x' xdigit+;
  ident = [A-Za-z_] [A-Za-z0-9_]*;
  esc   = '\\' ( [\\"ntr0] | 'x' xdigit xdigit );
  bytes = 'b"' ( [^"\\] | esc )* '"';

  main := |*
    space+;
    '(' => { P.open('(', ts); };
    '[' => { P.open('[', ts); };
    '{' => { P.open('{', ts); };
    ')' => { P.close(')', ts); };
    ']' => { P.close(']', ts); };
    '}' => { P.close('}', ts); };
    'True'  => { P.atom(Value(true), ts); };
    'False' => { P.atom(Value(false), ts); };
    'None'  => { P.atom(Value::none(), ts); };
    'NIL'   => { P.atom(Value(), ts); };
    'tmp' digit+      => { P.dec_name(NameKind::TMP, ts + 3, te, ts); };
    'loop' digit+     => { P.dec_name(NameKind::LOOP, ts + 4, te, ts); };
    'loopid' digit+   => { P.dec_name(NameKind::LOOP_ID, ts + 6, te, ts); };
    '_msize'          => { P.name(NameKind::MSIZE_VAR, 0, ts); };
    'param' digit+    => { P.dec_name(NameKind::PARAM, ts + 5, te, ts); };
    'stor' digit+     => { P.dec_name(NameKind::STORVAR, ts + 4, te, ts); };
    'sm' digit+       => { P.dec_name(NameKind::SAFEMATH_PARAM, ts + 2, te, ts); };
    'prec_' digit+ '_' digit+ => { P.prec(ts + 5, te, ts); };
    'func_' xdigit{8} => { P.func(ts + 5, te, ts); };
    'fallback'        => { P.name(NameKind::FALLBACK, 0, ts); };
    'internal_' digit+ => { P.dec_name(NameKind::INTERNAL, ts + 9, te, ts); };
    'name_' digit+ '_' digit+ => { P.any_name(ts + 5, te, ts); };
    dec   => { P.dec(ts, te); };
    hex   => { P.hex(ts, te); };
    bytes => { P.bytes(ts, te); };
    ident => { P.ident(ts, te); };
  *|;
}%%

}  // namespace

Value parse_sexpr(std::string_view text) {
  Parser P(text);
  const char* p = text.data();
  const char* pe = p + text.size();
  const char* eof = pe;
  const char* ts = nullptr;
  const char* te = nullptr;
  int cs = 0;
  int act = 0;
  (void)act;
  (void)sexpr_en_main;
  (void)sexpr_first_final;
  %% write init;
  %% write exec;
  if (cs == sexpr_error) P.fail(p, "syntax error");
  return P.finish(pe);
}

}  // namespace pan
