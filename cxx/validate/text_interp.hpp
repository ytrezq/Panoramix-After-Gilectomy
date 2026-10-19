// A concrete interpreter of the decompiled text (a Program of
// text_parser.hpp) against the validation's world: one call of the
// contract, run the way the text says, its effects recorded by a Session
// (session.hpp) - to be compared with evmone's for the same call.
//
// The meaning of each construct is the one docs/OUTPUT.md (panoramix's)
// gives it, and text_grammar.md sums up. What the text doesn't say
// precisely enough to be run - msize, a line the decompiler aborted, a
// member of a struct param whose names aren't known, a Mask of a size out
// of range... - ends the run `unsupported`, and is counted by its reason.
#pragma once

#include "validate/effects.hpp"
#include "validate/session.hpp"
#include "validate/text_ast.hpp"

#include <array>
#include <cstdint>
#include <functional>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace validate::text
{
struct InterpLimits
{
    std::uint64_t steps = 20'000'000;      ///< statements and expressions a call evaluates
    std::uint64_t memory = 8u << 20;       ///< the bytes of memory a call may use
    std::uint32_t depth = 10000;           ///< nested blocks and expressions (the C++ stack)
    std::uint32_t internal_depth = 1024;   ///< nested calls of the recursive internal functions
                                           ///< (and the EVM's 1024 words: depth * frame)
};

/// Why a run was unsupported.
enum class Unsupported : std::uint8_t
{
    msize,           ///< msize: the memory the EVM uses, the text doesn't show all of it
    aborted,         ///< `...  # Decompilation aborted`
    unparsed,        ///< a line the parser couldn't read
    member,          ///< a member of a struct param, its names unknown
    mask_range,      ///< Mask(size, offset, x) of a size or an offset out of [0, 256]
    wide_number,     ///< bytes of more than 32 used as a number
    data_size,       ///< mem[a len n] = data of another size than n
    unset_variable,  ///< a variable read before it's set
    storage_path,    ///< a place of the storage its type can't place (x[k] of a value...)
    param_path,      ///< a place of a param its type can't place
    recursion,       ///< internal functions nested deeper than the limit
    results,         ///< an internal (or SafeMath) function without the results it's used for
    no_function,     ///< the call's selector has no function, and there is no fallback
    lvalue,          ///< an assignment to something that can't be set
    depth,           ///< blocks or expressions nested deeper than the limit
    bytes_encoding,  ///< a bytes of the storage whose slot isn't a valid encoding (short
                     ///< of 32 bytes or more, long of less): the compiler's code reads past it
    other,
    count
};

std::string_view to_string(Unsupported u) noexcept;

/// The names of the components of a function's tuple params (the ABI's),
/// for `order.makerAsset`: what the signature database knows.
struct NameTree
{
    std::string name;
    std::vector<NameTree> components;
};

/// selector -> one NameTree per param of the function (nullopt: not known).
using ParamNames = std::function<std::optional<std::vector<NameTree>>(std::uint32_t selector)>;

/// The statements a call runs, for debugging: the line of each one, and the
/// value it sets (a variable, the storage, the memory's word...), if any.
using Trace = std::function<void(std::uint32_t line, const Word* value)>;

class Interpreter
{
public:
    explicit Interpreter(const Program& program, InterpLimits limits = {});

    /// The names of the struct params' members (none by default: such a
    /// member is unsupported).
    void set_param_names(ParamNames names)
    {
        param_names_ = std::move(names);
        id_trees_.clear();
    }
    void set_trace(Trace trace) { trace_ = std::move(trace); }

    /// Runs the session's call - the function of its selector, the fallback
    /// when there's none - and finishes the session.
    Effects run(Session& session);
    /// One call against a State.
    Effects run(State& state, const CallContext& call);

    const Program& program() const noexcept { return *program_; }
    /// The function a selector calls (none: the fallback's).
    std::optional<std::uint32_t> function_of(std::uint32_t selector) const;
    /// How many runs were unsupported, by reason.
    const std::array<std::uint64_t, static_cast<std::size_t>(Unsupported::count)>& unsupported() const noexcept
    {
        return unsupported_;
    }

    /// The names of a param's components as the text's names (their ids in
    /// Program::names, `none` for a name the text doesn't use).
    struct IdTree
    {
        std::uint32_t name = none;
        std::vector<IdTree> components;
    };

private:
    friend class Run;

    /// The id trees of a function's params, from param_names_: made once.
    const std::vector<IdTree>* id_trees(std::uint32_t function);

    const Program* program_;
    InterpLimits limits_;
    ParamNames param_names_;
    Trace trace_;
    std::unordered_map<std::uint32_t, std::optional<std::vector<IdTree>>> id_trees_;
    std::unordered_map<std::string_view, std::uint32_t> name_ids_;  // Program::names
    std::vector<std::pair<std::uint32_t, std::uint32_t>> by_selector_;  // sorted (selector, function)
    std::optional<std::uint32_t> fallback_;
    std::array<std::uint64_t, static_cast<std::size_t>(Unsupported::count)> unsupported_{};
};
}  // namespace validate::text
