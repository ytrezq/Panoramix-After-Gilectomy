// The pipeline (pipeline.hpp): until it is written, run_pipeline throws.
#include "driver/pipeline.hpp"

#include <format>

#include "core/errors.hpp"
#include "sigdb.hpp"

namespace pan::driver {

bool stage_available(Stage s) noexcept { return s <= Stage::Simplified; }

Stage last_available() noexcept { return Stage::Simplified; }

std::string function_name(const sigdb::Database* db, const FunctionInfo& fn)
{
    switch (fn.kind) {
        case FunctionInfo::Kind::Fallback:
            return "_fallback(?)";
        case FunctionInfo::Kind::Internal:
            return std::format("internal_0x{:x}", fn.entry_pc);
        case FunctionInfo::Kind::Selector:
            break;
    }
    if (db)
        if (const auto e = db->function(fn.selector); e && e->trust() == sigdb::Trust::verified) {
            // python's get_func_name: name(type name, ...), an unnamed param _param<i + 1>
            std::string s(e->name());
            s += '(';
            usize i = 0;
            for (const sigdb::Field f : e->params()) {
                if (i)
                    s += ", ";
                f.type().append_text(s);
                s += ' ';
                if (f.name().empty())
                    s += std::format("_param{}", i + 1);
                else
                    s += f.name();
                ++i;
            }
            s += ')';
            return s;
        }
    return std::format("unknown{:08x}(?)", fn.selector);
}

ContractResult run_pipeline(std::span<const u8>, const PipelineOptions&)
{
    throw Unsupported("driver: not yet");
}

ContractResult run_until(std::span<const u8> code, Stage upto, const PipelineOptions& options)
{
    PipelineOptions o = options;
    o.upto = upto;
    return run_pipeline(code, o);
}

}  // namespace pan::driver
