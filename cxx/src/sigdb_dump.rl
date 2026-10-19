// The signature dump's parser: panoramix's abi_dump.xz, decompressed, one
// JSON object per line (python reads it with json.loads, line by line):
//     {"selector": "0x...", "abi": {"name": ..., "type": ..., "inputs": [...], ...}}
// One Ragel machine (ragel -G2): the JSON grammar - the whole of it, as
// python's json accepts it (NaN and Infinity too), strings in UTF-8 - with the
// keys this needs recognized by the machine itself: "selector", "abi", and
// the abi's "name", "type", "inputs", their "name", "type", "components",
// "indexed". The nesting (objects in arrays...) goes through Ragel's call
// stack. Everything else is checked and skipped.
//
// As python's dict, a key given twice is its last value. Python would
// choke on (or never find) an abi that isn't an object, a name or a type that
// isn't a string, inputs or a tuple's components that aren't a list, an input
// that isn't an object, a string that isn't valid Unicode (a lone surrogate):
// such an entry isn't one (RawEntry::ok false, RawParam::ok false). A line
// that isn't JSON, or has no "selector" or no "abi", fails the whole dump, as
// in python. (Keys, the kinds and a type's "tuple" are matched as they are
// written: json.dumps never escapes letters; written with escapes, they are
// other words here.)
#include <string>
#include <vector>

#include "sigdb_impl.hpp"

namespace pan::sigdb {

namespace {
// the call stack: python's json gives up at about 1000 levels too
constexpr int stack_size = 1024;
}  // namespace

struct DumpParser::State {
    explicit State(EntrySink& s) : sink(s) {}
    EntrySink& sink;

    int stack[stack_size];

    // the string being decoded: its bytes, a \u escape's value, a high
    // surrogate waiting for its low one, a lone surrogate seen
    std::string buf;
    std::uint32_t u = 0, hi = 0;
    bool bad_string = false;

    // the line
    bool has_selector = false, selector_ok = false, has_abi = false, abi_object = false;
    std::uint32_t selector = 0;
    bool name_ok = false;
    std::string name;
    Kind kind = Kind::unspecified;
    bool has_inputs = false, inputs_ok = false;
    std::size_t inputs_begin = 0, inputs_end = 0;

    // the inputs' objects open (a stack: frames[0 .. depth))
    struct Frame {
        std::string name, type;
        bool name_ok, has_type, type_ok, type_tuple, comps_set, comps_list, indexed;
        std::size_t comps_begin, comps_end;
    };
    std::vector<Frame> frames;
    std::size_t depth = 0;
    // the lists open (inputs, components): their first item in done, and
    // whose they are (0: the abi's inputs, d: frames[d - 1]'s components)
    struct List {
        std::size_t begin, owner;
    };
    std::vector<List> lists;
    // the finished inputs of the lists open, the components of the finished
    // inputs
    std::vector<RawParam> done, arena;

    void unicode(std::uint32_t c)
    {
        if (c >= 0xd800 && c <= 0xdbff) {
            if (hi)
                bad_string = true;
            hi = c;
            return;
        }
        if (c >= 0xdc00 && c <= 0xdfff) {
            if (!hi) {
                bad_string = true;
                return;
            }
            c = 0x10000 + ((hi - 0xd800) << 10) + (c - 0xdc00);
            hi = 0;
        } else if (hi) {
            bad_string = true;
            hi = 0;
        }
        if (c < 0x80) {
            buf.push_back(static_cast<char>(c));
        } else if (c < 0x800) {
            buf.push_back(static_cast<char>(0xc0 | c >> 6));
            buf.push_back(static_cast<char>(0x80 | (c & 0x3f)));
        } else if (c < 0x10000) {
            buf.push_back(static_cast<char>(0xe0 | c >> 12));
            buf.push_back(static_cast<char>(0x80 | (c >> 6 & 0x3f)));
            buf.push_back(static_cast<char>(0x80 | (c & 0x3f)));
        } else {
            buf.push_back(static_cast<char>(0xf0 | c >> 18));
            buf.push_back(static_cast<char>(0x80 | (c >> 12 & 0x3f)));
            buf.push_back(static_cast<char>(0x80 | (c >> 6 & 0x3f)));
            buf.push_back(static_cast<char>(0x80 | (c & 0x3f)));
        }
    }
    // the string complete: was it valid Unicode?
    bool string_ok()
    {
        if (hi) {
            bad_string = true;
            hi = 0;
        }
        return !bad_string;
    }

    void line_begin()
    {
        has_selector = selector_ok = has_abi = false;
        abi_reset();
    }
    void abi_reset()
    {
        abi_object = name_ok = has_inputs = inputs_ok = false;
        name.clear();
        kind = Kind::unspecified;
        inputs_begin = inputs_end = 0;
        depth = 0;
        lists.clear();
        done.clear();
        arena.clear();
    }

    Frame& frame() { return frames[depth - 1]; }
    void param_begin()
    {
        if (depth == frames.size())
            frames.emplace_back();
        Frame& f = frames[depth++];
        f.name.clear();
        f.type.clear();
        f.name_ok = f.has_type = f.type_ok = f.type_tuple = false;
        f.comps_set = f.comps_list = f.indexed = false;
        f.comps_begin = f.comps_end = 0;
    }
    // an element of a list that isn't an object: python can't read it
    void param_not_object()
    {
        RawParam& r = done.emplace_back();
        r.ok = false;
    }
    void param_end()
    {
        Frame& f = frames[--depth];
        RawParam r;
        r.ok = f.has_type && f.type_ok;
        bool tuple_text = f.type_tuple;  // (python's kind.startswith("tuple"))
        if (tuple_text && f.comps_set && !f.comps_list)
            r.ok = false;  // (python iterates what isn't a list)
        r.tuple_text = tuple_text;
        if (tuple_text && f.comps_list) {
            // python's canonical_type: the components' types in parentheses
            r.canonical = "(";
            for (std::size_t i = f.comps_begin; i < f.comps_end; i++) {
                if (i > f.comps_begin)
                    r.canonical += ',';
                r.canonical += done[i].canonical;
                r.ok = r.ok && done[i].ok;
            }
            r.canonical += ')';
            r.canonical.append(f.type, 5);
        } else {
            r.canonical = f.type;
        }
        if (f.comps_list) {
            // (kept even where python ignores them: what a struct written by
            // its name is made of, for the repairs)
            r.has_components = true;
            r.children = static_cast<std::uint32_t>(arena.size());
            r.child_count = static_cast<std::uint32_t>(f.comps_end - f.comps_begin);
            for (std::size_t i = f.comps_begin; i < f.comps_end; i++)
                arena.push_back(std::move(done[i]));
        }
        if (f.comps_set)
            done.resize(f.comps_begin);  // (the components: the last ones)
        r.name = f.name_ok ? std::move(f.name) : std::string();
        r.type = std::move(f.type);
        r.indexed = f.indexed;
        done.push_back(std::move(r));
    }
    void list_begin(std::size_t owner) { lists.push_back({done.size(), owner}); }
    void list_end()
    {
        List l = lists.back();
        lists.pop_back();
        if (l.owner == 0) {
            inputs_begin = l.begin;
            inputs_end = done.size();
        } else {
            Frame& f = frames[l.owner - 1];
            f.comps_begin = l.begin;
            f.comps_end = done.size();
        }
    }
    // the abi's inputs again: the previous ones go (they are the last ones)
    void inputs_reset()
    {
        if (has_inputs)
            done.resize(inputs_begin);
        has_inputs = true;
        inputs_ok = false;
        inputs_begin = inputs_end = done.size();
    }
    void comps_reset()
    {
        Frame& f = frame();
        if (f.comps_set && f.comps_list)
            done.resize(f.comps_begin);
        f.comps_set = true;
        f.comps_list = false;
        f.comps_begin = f.comps_end = done.size();
    }

    void line_end(std::uint64_t line)
    {
        if (!has_selector || !has_abi)
            throw Error(Error::Code::failed,
                        "line " + std::to_string(line) + ": no \"" +
                            (has_selector ? "abi" : "selector") + "\"");
        RawEntry e;
        e.has_selector = has_selector;
        e.has_abi = has_abi;
        e.selector_ok = selector_ok;
        e.selector = selector;
        e.ok = abi_object && name_ok && has_inputs && inputs_ok;
        e.kind = kind;
        e.name = name;
        if (e.ok) {
            e.params = std::span<const RawParam>(done).subspan(inputs_begin,
                                                               inputs_end - inputs_begin);
            for (const RawParam& r : e.params)
                e.ok = e.ok && r.ok;
        }
        e.arena = arena;
        sink.entry(e);
    }
};

%%{
machine dump;
alphtype unsigned char;

# --- the calls (the only action of their transition: nothing would run
# after the jump) ---
action call_skip_array { if (top == stack_size) { deep = true; fbreak; } fcall skip_array; }
action call_skip_object { if (top == stack_size) { deep = true; fbreak; } fcall skip_object; }
action ret { fret; }

# --- JSON ---
ws = [ \t\r]*;   # (a newline ends the line: python reads the dump by lines)
utf8_cont = 0x80..0xbf;
# a character of a string: not a control one, not " nor \, valid UTF-8
str_char = 0x20..0x21 | 0x23..0x5b | 0x5d..0x7f
         | 0xc2..0xdf utf8_cont
         | 0xe0 0xa0..0xbf utf8_cont | 0xe1..0xec utf8_cont utf8_cont
         | 0xed 0x80..0x9f utf8_cont | 0xee..0xef utf8_cont utf8_cont
         | 0xf0 0x90..0xbf utf8_cont utf8_cont | 0xf1..0xf3 utf8_cont utf8_cont utf8_cont
         | 0xf4 0x80..0x8f utf8_cont utf8_cont;
hex = [0-9a-fA-F];
string = '"' ( str_char | '\\' ( ["\\/bfnrt] | 'u' hex{4} ) )* '"';
number = '-'? ( '0' | [1-9] [0-9]* ) ( '.' [0-9]+ )? ( [eE] [+\-]? [0-9]+ )?;
literal = 'true' | 'false' | 'null' | 'NaN' | 'Infinity' | '-Infinity';
scalar = string | number | literal;
value = scalar | '[' @call_skip_array | '{' @call_skip_object;
member = string ws ':' ws value;

skip_array := ws ( ']' @ret | value ws ( ',' ws value ws )* ']' @ret );
skip_object := ws ( '}' @ret | member ws ( ',' ws member ws )* '}' @ret );

# --- a string decoded (into st.buf): its plain runs appended whole, at
# an escape and at its end ---
action c_begin { st.buf.clear(); st.hi = 0; st.bad_string = false; run = p + 1; }
action c_flush {
    if (p > run) {
        if (st.hi) { st.bad_string = true; st.hi = 0; }  // (a high surrogate alone)
        st.buf.append(reinterpret_cast<const char*>(run), static_cast<std::size_t>(p - run));
    }
}
action c_quote { st.unicode('"'); run = p + 1; }
action c_backslash { st.unicode('\\'); run = p + 1; }
action c_slash { st.unicode('/'); run = p + 1; }
action c_b { st.unicode('\b'); run = p + 1; }
action c_f { st.unicode('\f'); run = p + 1; }
action c_n { st.unicode('\n'); run = p + 1; }
action c_r { st.unicode('\r'); run = p + 1; }
action c_t { st.unicode('\t'); run = p + 1; }
action u_begin { st.u = 0; }
action u_dec { st.u = st.u * 16 + (fc - '0'); }
action u_lower { st.u = st.u * 16 + (fc - 'a' + 10); }
action u_upper { st.u = st.u * 16 + (fc - 'A' + 10); }
action u_end { st.unicode(st.u); run = p + 1; }
u_digit = [0-9] @u_dec | [a-f] @u_lower | [A-F] @u_upper;
escape = '\\' @c_flush ( '"' @c_quote | '\\' @c_backslash | '/' @c_slash | 'b' @c_b | 'f' @c_f
                       | 'n' @c_n | 'r' @c_r | 't' @c_t | 'u' @u_begin u_digit u_digit u_digit u_digit @u_end );
cstring = '"' @c_begin ( str_char | escape )* '"' @c_flush;

# --- the selector: "0x" and 8 lowercase hex digits (python's keys) ---
action sel_reset { st.has_selector = true; st.selector_ok = false; st.selector = 0; }
action sel_dec { st.selector = st.selector << 4 | static_cast<std::uint32_t>(fc - '0'); }
action sel_hex { st.selector = st.selector << 4 | static_cast<std::uint32_t>(fc - 'a' + 10); }
action sel_ok { st.selector_ok = true; }
selector = '"0x' ( [0-9] @sel_dec | [a-f] @sel_hex ){8} '"' @sel_ok;

# --- the abi ---
action abi_reset { st.has_abi = true; st.abi_reset(); }
action call_abi { if (top == stack_size) { deep = true; fbreak; } st.abi_object = true; fcall abi_object; }
action name_reset { st.name_ok = false; st.name.clear(); }
action name_set { st.name_ok = st.string_ok(); st.name = st.buf; }
action kind_reset { st.kind = Kind::unspecified; }
action k_function { st.kind = Kind::function; }
action k_event { st.kind = Kind::event; }
action k_error { st.kind = Kind::error; }
action k_constructor { st.kind = Kind::constructor; }
action k_fallback { st.kind = Kind::fallback; }
action k_receive { st.kind = Kind::receive; }
action k_other { st.kind = Kind::other; }
action inputs_reset { st.inputs_reset(); }
action call_inputs {
    if (top == stack_size) { deep = true; fbreak; }
    st.inputs_ok = true;
    st.list_begin(0);
    fcall param_list;
}
kinds = '"function"' | '"event"' | '"error"' | '"constructor"' | '"fallback"' | '"receive"';
kind = '"function"' @k_function | '"event"' @k_event | '"error"' @k_error
     | '"constructor"' @k_constructor | '"fallback"' @k_fallback | '"receive"' @k_receive
     | ( string - kinds ) @k_other | number | literal
     | '[' @call_skip_array | '{' @call_skip_object;
abi_keys = '"name"' | '"type"' | '"inputs"';
abi_member = '"name"' ws ':' @name_reset ws ( cstring @name_set | value )
           | '"type"' ws ':' @kind_reset ws kind
           | '"inputs"' ws ':' @inputs_reset ws ( '[' @call_inputs | scalar | '{' @call_skip_object )
           | ( string - abi_keys ) ws ':' ws value;
abi_object := ws ( '}' @ret | abi_member ws ( ',' ws abi_member ws )* '}' @ret );

# --- the inputs, a tuple's components: lists of objects ---
action call_param {
    if (top == stack_size) { deep = true; fbreak; }
    st.param_begin();
    fcall param_object;
}
action param_not_object { st.param_not_object(); }
action param_not_object_array {
    if (top == stack_size) { deep = true; fbreak; }
    st.param_not_object();
    fcall skip_array;
}
action list_end { st.list_end(); fret; }
element = '{' @call_param | scalar @param_not_object | '[' @param_not_object_array;
param_list := ws ( ']' @list_end | element ws ( ',' ws element ws )* ']' @list_end );

action pname_reset { st.frame().name_ok = false; }
action pname_set { st.frame().name_ok = st.string_ok(); st.frame().name = st.buf; }
action ptype_reset {
    st.frame().has_type = true;
    st.frame().type_ok = st.frame().type_tuple = false;
    st.frame().type.clear();
}
action ptype_tuple { st.frame().type_tuple = true; }
# an input's type: the same, telling whether it begins with "tuple" (python
# substitutes the components there)
type_string = '"' @c_begin ( 'tuple' @ptype_tuple )? ( str_char | escape )* '"' @c_flush;
action ptype_set { st.frame().type_ok = st.string_ok(); st.frame().type = st.buf; }
action comps_reset { st.comps_reset(); }
action comps_null { st.frame().comps_set = false; }
action call_comps {
    if (top == stack_size) { deep = true; fbreak; }
    st.frame().comps_list = true;
    st.list_begin(st.depth);
    fcall param_list;
}
action ix_true { st.frame().indexed = true; }
action ix_false { st.frame().indexed = false; }
action call_ix_array { if (top == stack_size) { deep = true; fbreak; } fcall ix_array; }
action call_ix_object { if (top == stack_size) { deep = true; fbreak; } fcall ix_object; }
action ix_true_ret { st.frame().indexed = true; fret; }
action ix_false_ret { st.frame().indexed = false; fret; }
action param_end { st.param_end(); fret; }

# "indexed": python's truth (i.get("indexed")): false, null, 0, "", [], {}
# are false
zero = '-'? '0' ( '.' '0'+ )? ( [eE] [+\-]? [0-9]+ )?;
indexed = 'true' @ix_true | ( 'false' | 'null' ) @ix_false
        | ( number - zero ) @ix_true | zero @ix_false
        | ( 'NaN' | 'Infinity' | '-Infinity' ) @ix_true
        | '""' @ix_false | ( string - '""' ) @ix_true
        | '[' @call_ix_array | '{' @call_ix_object;
ix_array := ws ( ']' @ix_false_ret | value ws ( ',' ws value ws )* ']' @ix_true_ret );
ix_object := ws ( '}' @ix_false_ret | member ws ( ',' ws member ws )* '}' @ix_true_ret );

param_keys = '"name"' | '"type"' | '"components"' | '"indexed"';
param_member = '"name"' ws ':' @pname_reset ws ( cstring @pname_set | value )
             | '"type"' ws ':' @ptype_reset ws ( type_string @ptype_set | value )
             | '"components"' ws ':' @comps_reset ws
                 ( '[' @call_comps | 'null' @comps_null | ( scalar - 'null' ) | '{' @call_skip_object )
             | '"indexed"' ws ':' ws indexed
             | ( string - param_keys ) ws ':' ws value;
param_object := ws ( '}' @param_end | param_member ws ( ',' ws param_member ws )* '}' @param_end );

# --- a line ---
action line_begin { st.line_begin(); }
action line_end { st.line_end(line + 1); }
action newline { line++; }
top_keys = '"selector"' | '"abi"';
top_member = '"selector"' ws ':' @sel_reset ws ( selector | value )
           | '"abi"' ws ':' @abi_reset ws ( '{' @call_abi | scalar | '[' @call_skip_array )
           | ( string - top_keys ) ws ':' ws value;
object = '{' @line_begin ws ( '}' @line_end | top_member ws ( ',' ws top_member ws )* '}' @line_end );
main := ( ws object? ws '\n' @newline )*;
}%%

namespace {
%% write data;
}  // namespace

DumpParser::DumpParser(EntrySink& sink) : s_(std::make_unique<State>(sink)) {}
DumpParser::~DumpParser() = default;

void DumpParser::parse(const std::uint8_t* p, const std::uint8_t* pe)
{
    State& st = *s_;
    int* stack = st.stack;
    int top = 0;
    const std::uint8_t* run = p;  // (a string's plain run: where it begins)
    std::uint64_t line = line_;
    bool deep = false;
    int cs;
    const std::uint8_t* eof = pe;
    (void)eof;
    %% write init;
    %% write exec;
    line_ = line;
    if (deep)
        throw Error(Error::Code::bad_dump,
                    "line " + std::to_string(line + 1) + ": nested too deep");
    if (cs < dump_first_final || p != pe)
        throw Error(Error::Code::failed,
                    "line " + std::to_string(line + 1) + ": not the JSON expected");
}

}  // namespace pan::sigdb
