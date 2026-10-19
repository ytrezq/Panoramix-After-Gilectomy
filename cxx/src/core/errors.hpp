// The decompiler's exceptions.
//
//   std::exception
//   ├── Error                  the decompiler's errors: a stage catches them
//   │   ├── Unsupported        an analysis can't: the stage degrades
//   │   ├── InvalidInput       malformed input (CLI/pymod map to their messages)
//   │   ├── InternalError      a broken invariant (a bug)
//   │   └── LimitExceeded      a protection against hostile contracts
//   │       ├── MemoryLimit    a function's memory limit (PANORAMIX_MAX_MEMORY)
//   │       ├── DepthLimit     recursion too deep for the stack
//   │       └── SizeLimit      a structural cap (nodes, bytes, shift)
//   └── Abort                  NOT an Error: `catch (const Error&)` never
//       └── Timeout            swallows it; the watchdog's
//
// std::bad_alloc from the system: the job maps it to MemoryLimit (never an
// abort).
#pragma once

#include <exception>
#include <memory>
#include <string>
#include <utility>

namespace pan {

namespace detail {

// An exception's message, shared between the copies: copying an exception
// never throws (the copies std::exception_ptr and `throw e;` make).
class ExcMessage {
public:
    explicit ExcMessage(std::string s)
        : p_(std::make_shared<const std::string>(std::move(s))) {}
    const char* c_str() const noexcept { return p_ ? p_->c_str() : ""; }

private:
    std::shared_ptr<const std::string> p_;
};

}  // namespace detail

// the decompiler's errors; caught by the stages
class Error : public std::exception {
public:
    explicit Error(std::string msg) : msg_(std::move(msg)) {}
    explicit Error(const char* msg) : msg_(std::string(msg)) {}
    const char* what() const noexcept override { return msg_.c_str(); }

private:
    detail::ExcMessage msg_;
};

// an analysis can't: the stage degrades
class Unsupported : public Error {
public:
    using Error::Error;
};

// malformed input (the CLI and the python module map it to their messages)
class InvalidInput : public Error {
public:
    using Error::Error;
};

// a broken invariant (a bug)
class InternalError : public Error {
public:
    using Error::Error;
};

// a protection against hostile contracts went off
class LimitExceeded : public Error {
public:
    using Error::Error;
};

// a function's memory limit was reached (PANORAMIX_MAX_MEMORY)
class MemoryLimit : public LimitExceeded {
public:
    using LimitExceeded::LimitExceeded;
    MemoryLimit()
        : LimitExceeded(
              "out of memory: a function's memory limit was reached "
              "(PANORAMIX_MAX_MEMORY)") {}
};

// recursion too deep for the stack
class DepthLimit : public LimitExceeded {
public:
    using LimitExceeded::LimitExceeded;
};

// a structural cap (nodes, bytes, shift)
class SizeLimit : public LimitExceeded {
public:
    using LimitExceeded::LimitExceeded;
};

// the whole job stops: NOT an Error, so `catch (const Error&)` never
// swallows it
class Abort : public std::exception {
public:
    explicit Abort(std::string msg) : msg_(std::move(msg)) {}
    explicit Abort(const char* msg) : msg_(std::string(msg)) {}
    const char* what() const noexcept override { return msg_.c_str(); }

private:
    detail::ExcMessage msg_;
};

// the watchdog's (PANORAMIX_TIMEOUT)
class Timeout : public Abort {
public:
    using Abort::Abort;
};

}  // namespace pan
