// The effects of a call: their comparison, their readable forms.
#include "effects.hpp"

#include <algorithm>

namespace validate
{
namespace
{
constexpr char digits[] = "0123456789abcdef";

/// The bytes in hex, the middle elided past `max` bytes.
std::string hex_short(BytesView bytes, std::size_t max = 96)
{
    if (bytes.size() <= max)
        return hex(bytes);
    return hex(bytes.first(max / 2)) + "..(" + std::to_string(bytes.size()) + " bytes).." +
           hex(bytes.last(max / 2)).substr(2);
}

std::string topics_string(const std::vector<Word>& topics)
{
    std::string s = "[";
    for (std::size_t i = 0; i < topics.size(); ++i)
        s += (i != 0 ? ", " : "") + hex(topics[i]);
    return s + "]";
}

/// The revert data readably: Error(string) and Panic(uint256) decoded.
std::string revert_string(BytesView data)
{
    if (data.size() >= 4 + 64 && data[0] == 0x08 && data[1] == 0xc3 && data[2] == 0x79 &&
        data[3] == 0xa0)
    {
        const auto args = data.subspan(4);
        const auto offset = load_word(args, 0);
        const auto length = offset < args.size() ? load_word(args, offset) : Word{0};
        if (offset < args.size() && length < 1024 && offset + 32 + length <= args.size())
        {
            const auto start = static_cast<std::size_t>(offset) + 32;
            std::string text = "Error(\"";
            for (std::size_t i = 0; i < static_cast<std::size_t>(length); ++i)
            {
                const auto c = args[start + i];
                if (c >= 0x20 && c < 0x7f && c != '"' && c != '\\')
                    text += static_cast<char>(c);
                else
                    text += std::string{"\\x"} + digits[c >> 4] + digits[c & 15];
            }
            return text + "\")";
        }
    }
    if (data.size() == 4 + 32 && data[0] == 0x4e && data[1] == 0x48 && data[2] == 0x7b &&
        data[3] == 0x71)
        return "Panic(" + hex(load_word(data.subspan(4), 0)) + ")";
    return hex_short(data);
}

bool same_event(const Event& a, const Event& b)
{
    if (a.index() != b.index())
        return false;
    if (const auto* x = std::get_if<ExternalCall>(&a))
    {
        const auto& y = std::get<ExternalCall>(b);
        return x->kind == y.kind && x->target == y.target && x->value == y.value &&
               x->input == y.input;
    }
    if (const auto* x = std::get_if<Creation>(&a))
    {
        const auto& y = std::get<Creation>(b);
        return x->kind == y.kind && x->value == y.value && x->init_code == y.init_code &&
               x->address == y.address;
    }
    return a == b;
}

/// The events compared, in order.
std::vector<const Event*> compared_events(const Effects& e, const CompareOptions& options)
{
    std::vector<const Event*> out;
    if (!e.end.success() && !options.failed_events)
        return out;
    for (const auto& ev : e.events)
    {
        if (std::holds_alternative<StorageWrite>(ev) && !options.write_order)
            continue;
        if (std::holds_alternative<TransientWrite>(ev) && !options.transient)
            continue;
        if (const auto* c = std::get_if<ExternalCall>(&ev); c && c->precompile && !options.precompiles)
            continue;
        out.push_back(&ev);
    }
    return out;
}

/// Where two byte strings first differ, for the messages.
std::string first_byte_difference(BytesView a, BytesView b)
{
    const auto n = std::min(a.size(), b.size());
    std::size_t i = 0;
    while (i < n && a[i] == b[i])
        ++i;
    if (i == n)
        return "lengths " + std::to_string(a.size()) + " and " + std::to_string(b.size());
    return "first difference at byte " + std::to_string(i);
}
}  // namespace

std::string hex(BytesView bytes)
{
    std::string s = "0x";
    s.reserve(2 + 2 * bytes.size());
    for (const auto b : bytes)
    {
        s += digits[b >> 4];
        s += digits[b & 15];
    }
    return s;
}

std::string hex(const Word& word)
{
    return "0x" + intx::to_string(word, 16);
}

std::string to_string(CallKind kind)
{
    switch (kind)
    {
    case CallKind::call:
        return "call";
    case CallKind::staticcall:
        return "staticcall";
    case CallKind::delegatecall:
        return "delegatecall";
    case CallKind::callcode:
        return "callcode";
    }
    return "?";
}

std::string to_string(CreateKind kind)
{
    return kind == CreateKind::create ? "create" : "create2";
}

std::string to_string(Status status)
{
    switch (status)
    {
    case Status::stop:
        return "stop";
    case Status::return_:
        return "return";
    case Status::revert:
        return "revert";
    case Status::invalid:
        return "invalid";
    case Status::exhausted:
        return "exhausted";
    case Status::unsupported:
        return "unsupported";
    case Status::error:
        return "error";
    }
    return "?";
}

std::string to_string(Fault fault)
{
    switch (fault)
    {
    case Fault::none:
        return "none";
    case Fault::invalid_instruction:
        return "invalid instruction";
    case Fault::undefined_instruction:
        return "undefined instruction";
    case Fault::bad_jump:
        return "bad jump destination";
    case Fault::stack_underflow:
        return "stack underflow";
    case Fault::stack_overflow:
        return "stack overflow";
    case Fault::static_violation:
        return "static mode violation";
    case Fault::other:
        return "other";
    }
    return "?";
}

std::string to_string(const Event& event)
{
    struct Visitor
    {
        std::string operator()(const StorageWrite& e) const
        {
            return "sstore [" + hex(e.slot) + "] = " + hex(e.value);
        }
        std::string operator()(const TransientWrite& e) const
        {
            return "tstore [" + hex(e.slot) + "] = " + hex(e.value);
        }
        std::string operator()(const Log& e) const
        {
            return "log" + std::to_string(e.topics.size()) + " " + topics_string(e.topics) + " " +
                   hex_short(e.data);
        }
        std::string operator()(const ExternalCall& e) const
        {
            std::string s = to_string(e.kind) + " " + hex(e.target);
            if (e.value != 0)
                s += " value " + hex(e.value);
            s += " " + hex_short(e.input) + (e.precompile ? " (precompile)" : "") + " -> " +
                 (e.result.success ? "ok " : "fail ") +
                 (e.result.success ? hex_short(e.result.output) : revert_string(e.result.output));
            return s;
        }
        std::string operator()(const Creation& e) const
        {
            std::string s = to_string(e.kind);
            if (e.salt)
                s += " salt " + hex(*e.salt);
            if (e.value != 0)
                s += " value " + hex(e.value);
            s += " " + hex_short(e.init_code) + " -> " + hex(e.address) +
                 (e.result.success ? " ok" : " fail " + revert_string(e.result.output));
            return s;
        }
        std::string operator()(const SelfDestruct& e) const
        {
            return "selfdestruct " + hex(e.beneficiary);
        }
    };
    return std::visit(Visitor{}, event);
}

std::string to_string(const End& end)
{
    std::string s = to_string(end.status);
    switch (end.status)
    {
    case Status::return_:
        s += " " + hex_short(end.data);
        break;
    case Status::revert:
        s += " " + revert_string(end.data);
        break;
    case Status::invalid:
        if (end.fault != Fault::none)
            s += " (" + to_string(end.fault) + ")";
        break;
    default:
        break;
    }
    if (!end.note.empty())
        s += ": " + end.note;
    return s;
}

std::string to_string(const Effects& effects)
{
    std::string s;
    for (const auto& e : effects.events)
        s += to_string(e) + "\n";
    s += to_string(effects.end) + "\n";
    for (const auto& [slot, value] : effects.storage_diff)
        s += "  storage [" + hex(slot) + "] = " + hex(value) + "\n";
    return s;
}

Comparison compare(const Effects& expected, const Effects& actual, const CompareOptions& options)
{
    if (expected.end.inconclusive() || actual.end.inconclusive())
    {
        std::string why;
        if (expected.end.inconclusive())
            why = "evm: " + to_string(expected.end);
        if (actual.end.inconclusive())
            why += (why.empty() ? "" : "; ") + std::string{"decompiled: "} + to_string(actual.end);
        return {Verdict::inconclusive, why};
    }

    const auto& ee = expected.end;
    const auto& ae = actual.end;
    if (ee.status != ae.status || (options.faults && ee.fault != ae.fault))
        return {Verdict::different,
            "end: expected " + to_string(ee) + ", got " + to_string(ae)};
    if (ee.data != ae.data)
        return {Verdict::different, "end: expected " + to_string(ee) + ", got " + to_string(ae) +
                                        " (" + first_byte_difference(ee.data, ae.data) + ")"};

    const auto ev = compared_events(expected, options);
    const auto av = compared_events(actual, options);
    for (std::size_t i = 0; i < std::max(ev.size(), av.size()); ++i)
    {
        const auto where = "event " + std::to_string(i) + ": ";
        if (i >= av.size())
            return {Verdict::different, where + "expected " + to_string(*ev[i]) + ", got nothing"};
        if (i >= ev.size())
            return {Verdict::different, where + "expected nothing, got " + to_string(*av[i])};
        if (!same_event(*ev[i], *av[i]))
            return {Verdict::different,
                where + "expected " + to_string(*ev[i]) + ", got " + to_string(*av[i])};
    }

    // the storage diffs (empty when the calls failed)
    auto ei = expected.storage_diff.begin();
    auto ai = actual.storage_diff.begin();
    while (ei != expected.storage_diff.end() || ai != actual.storage_diff.end())
    {
        if (ai == actual.storage_diff.end() ||
            (ei != expected.storage_diff.end() && ei->first < ai->first))
            return {Verdict::different, "storage [" + hex(ei->first) + "]: expected " +
                                            hex(ei->second) + ", got unchanged"};
        if (ei == expected.storage_diff.end() || ai->first < ei->first)
            return {Verdict::different, "storage [" + hex(ai->first) + "]: expected unchanged, got " +
                                            hex(ai->second)};
        if (ei->second != ai->second)
            return {Verdict::different, "storage [" + hex(ei->first) + "]: expected " +
                                            hex(ei->second) + ", got " + hex(ai->second)};
        ++ei;
        ++ai;
    }
    return {Verdict::same, {}};
}
}  // namespace validate
