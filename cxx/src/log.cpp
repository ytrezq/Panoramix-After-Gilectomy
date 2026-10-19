// The log lines (decompile.hpp): coloredlogs' format with milliseconds, as
// `python -m panoramix` installs it (and the asm's rt_log.s writes it):
//   2026-09-27 21:17:30,527 host panoramix.loader[pid] INFO message
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <format>
#include <mutex>
#include <string>

#include "cli.hpp"
#include "decompile.hpp"
#include "io.hpp"

namespace pan {

namespace {

constexpr std::string_view green = "\033[32m", magenta = "\033[35m", blue = "\033[34m",
                           yellow = "\033[33m", red = "\033[31m", bold = "\033[1m", reset = "\033[0m";

// made at its first use (several threads at once wait for it): the host,
// the colors, the level of $PANORAMIX_LOG - which set_log_level overrides
struct Logging {
    Logging() : color(io::is_terminal(io::Stream::err)), host(io::host_name())
    {
        if (const char* name = std::getenv("PANORAMIX_LOG"))
            if (const auto named = cli::log_level_from_name(name))
                level = *named;
    }

    std::atomic<int> level{log_info};
    bool color = false;  // stderr is a terminal
    std::string host;
    std::mutex writing;  // a line at a time: the lines of threads don't mix
};

Logging& logging()
{
    static Logging state;
    return state;
}

std::string_view level_name(int level)
{
    return level < log_info ? "DEBUG" : level < log_warning ? "INFO" : level < log_error ? "WARNING" : "ERROR";
}

// the message's color: by its level
std::string_view message_color(int level)
{
    return level >= log_error ? red : level >= log_warning ? yellow : level == log_debug ? green : "";
}

}  // namespace

void set_log_level(int level) noexcept
{
    try {
        logging().level.store(level, std::memory_order_relaxed);
    } catch (...) {  // (the host's name made: no memory - no logging either)
    }
}

int log_level() noexcept
{
    try {
        return logging().level.load(std::memory_order_relaxed);
    } catch (...) {
        return log_info;
    }
}

bool log_enabled(int level) noexcept
{
    return level >= log_level();
}

void log(int level, std::string_view logger, std::string_view message) noexcept
{
    try {
        Logging& state = logging();
        if (level < state.level.load(std::memory_order_relaxed))
            return;
        const auto now = std::chrono::system_clock::now();
        const io::LocalTime t = io::local_time(now);
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000;
        const auto c = [&](std::string_view code) { return state.color ? code : std::string_view(); };
        const std::string_view tint = c(message_color(level));
        const std::string line = std::format(
            "{}{:04}-{:02}-{:02} {:02}:{:02}:{:02},{:03}{} {}{}{} {}{}[{}]{} {}{}{} {}{}{}\n",
            c(green), t.year, t.month, t.day, t.hour, t.minute, t.second, ms, c(reset),
            c(magenta), state.host, c(reset),
            c(blue), logger, io::process_id(), c(reset),
            c(bold), level_name(level), c(reset),
            tint, message, c(reset));
        const std::lock_guard lock(state.writing);
        io::write_all(io::Stream::err, line);
    } catch (...) {  // (no memory for the line: not written)
    }
}

}  // namespace pan
