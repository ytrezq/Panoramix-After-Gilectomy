// The trace machine (lot 11): any stage's trace run on concrete values -
// the raw VM trace (LABEL/GOTO), the whiles, the simplified trace, the
// analysed one (params, storage P forms) and the folded ast (LAND, LOR,
// REQUIRE, ASSERT, MERGED_IF, SAFEMATH) - by the operational semantics of
// ir.md section 4. One engine, two uses: the validation (rule 5: each
// stage's trace against evmone, cxx/validate/stage_check.hpp adapts a
// validate::Session to the Host below) and lot 9's bytes getters (a trace
// and its rewrite run on storage worlds, with SimpleHost or a Host of its
// own). The library has no intx: every word here is a Word256, the
// validation converts at its boundary.
//
// A call (Machine::call):
//   1. dispatch (lot 5's discovery): with 4 bytes of calldata or more, the
//      first Selector function of Program::functions whose selector is
//      calldataload(0) >> 224 (the hinted one tried first); else, or when
//      none is, the first Fallback function. None: Unsupported.
//      entry.checks are facts for the VM, never evaluated here.
//   2. a function whose decompilation failed (`problem`, or no trace):
//      Unsupported.
//   3. entry.entry_lines: the dispatcher's lines on the path (SETMEMs, and
//      an IF per check whose other branch halts), run as trace lines.
//   4. entry.nonpayable and callvalue != 0: entry.value_fails, the halting
//      line of the check lot 8 took out of the body (NIL: REVERT of no data).
//   5. the trace (the body).
//
// Words (ir.md 4.3): mod 2^256; the pure ops through alg::eval_op (the one
// definition of MASK_SHL, BOOL, LE..SGE, MAX, MIN on words); LAND/LOR short
// circuit; True/False are 1/0. A MASK_SHL (or MASK) of a byte string reads
// its big-endian number whatever its length: past 32 bytes its bits past
// 256 exist (lot 2's may_be_wide), the result is mod 2^256. Name(PARAM, k): in a selector function or
// the fallback the calldata word at params[k].calldata_offset (raw, never
// masked), in an internal function its k-th argument. Names TMP, LOOP,
// MSIZE_VAR, PRECOMPILE, SAFEMATH_PARAM: the frame's variables; reading one
// never set is a stage's bug (Status::Bug). Call results are numbered: the
// call line with id k (CALL...CREATE2, PRECOMPILED) writes record k of the
// frame; CALL_SUCCESS k, CREATE_ADDRESS k, RETURNDATASIZE k,
// RETURNDATA_BYTES(k, off, len) read it (k = 0: no call, size 0; a record
// not written yet: Bug). MSIZE: the high-water mark of the memory the run
// touched (word rounded). GAS: the host's env().gas.
//
// Bytes (ir.md 4.2): SIZED(n, v): the low n bytes of v big-endian (v a
// bytes expression of another length: resized, zeroes before or its last n
// bytes); DATA: concatenation, an ARR element ABI-encoded (its offset in the
// head, length + content padded in the tail); MEM(RANGE(p, n)),
// CALLDATA_BYTES, CODE_BYTES, EXTCODE_BYTES, RETURNDATA_BYTES (zero padded
// past the end: the VM makes RETURNDATACOPY's halt an explicit IF); a BYTES
// node: its bytes (a codecopy of known code); None: no bytes. Every byte
// element of a DATA, SHA3, LOG, call, RETURN/REVERT payload carries its width
// (SIZED, set by the stage that knows it); a word without one is a stage's
// bug, counted in Outcome::unsized and run with ir.md 4.2's fallback
// (python's sizeof, not stable under the algebra's normal forms):
// MASK_SHL(size, off, shl, x) (size + off + shl) / 8 bytes, STORAGE/ST
// size / 8, an int of more than 256 bits its bytes, anything else 32. As a
// word, a bytes expression of at most 32 bytes is its big-endian number
// (more: Bug). SETMEM(RANGE(p, n), v): a word v gives its low n bytes (the
// range is its width); a bytes v must have n bytes (else Bug).
//
// Lines (ir.md 4.4): SETVAR, SETMEM (the range's n bytes: a value's low n
// bytes), STORE (read-modify-write of the bits [off, off + size)), TSTORE,
// IF, WHILE (its setvars, then: cond == 0 exits; the body; a CONTINUE of
// this loop applies its setvars and tests again; a body that ends without
// one leaves the loop), CONTINUE, BREAK, LABEL / GOTO (raw traces: a GOTO
// applies its setvars and resumes after its LABEL, in the enclosing trace
// that holds it), all setvars simultaneous; LOGk, the calls (input =
// bytes(selector) ++ bytes(params); the output's setmem is the next line,
// never the machine's), CREATE/CREATE2, PRECOMPILED (its name := the first
// word of the output), INTERNAL(entry, [args], [names]) (the internal
// function at that entry pc in a fresh frame - its own variables and call
// records, Name(PARAM, k) = args[k]; its LEAVE([values]) binds names[i] :=
// values[i] in the caller), RETURN, REVERT, STOP, INVALID,
// SELFDESTRUCT (then stop), ASM (nothing), UNDEFINED (Status::Undefined:
// inconclusive), REQUIRE(cond[, data]) (when 0: revert of data, none when
// absent or None), ASSERT (invalid when 0), MERGED_IF (as IF). The end of
// the trace: stop.
//
// Limits: steps (lines and loop rounds), the bytes of one byte string,
// the bytes all of a run's byte strings make (work), the memory, the depth
// of the internal calls - past one: Status::Exhausted (inconclusive, as
// evmone's out of gas). The budget's poll() is called as the run goes (the
// watchdog's Timeout goes through: it is an Abort).
#pragma once

#include <map>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <variant>
#include <vector>

#include "core/base.hpp"
#include "core/budget.hpp"
#include "core/contract.hpp"
#include "core/evmint.hpp"
#include "core/value.hpp"

namespace pan {
// declared by their lots (forward declarations only: null = their forms are
// Unsupported until the machine reads them)
struct StorageLayout;  // lot 9: the P forms ST SV SI SL SBL SF SR SALL SET
struct SafeMathTable;  // lot 8: SAFEMATH
}  // namespace pan

namespace pan::exec {

// ---- the world, as the machine sees it ---------------------------------------

enum class CallKind : u8 { Call, StaticCall, DelegateCall, CallCode };
enum class CreateKind : u8 { Create, Create2 };

struct CallResult {
    bool success = false;
    std::vector<u8> output;  // the return data (or a revert's)
};

struct CreateResult {
    bool success = false;
    Word256 address{};       // 0 when it failed
    std::vector<u8> output;  // empty when it succeeded, the revert data when not
};

// the constants of one call
struct CallEnv {
    Word256 address{}, caller{}, origin{}, callvalue{}, gasprice{}, gas{};
    Word256 coinbase{}, timestamp{}, number{}, prevrandao{}, gaslimit{}, chainid{}, basefee{}, blobbasefee{};
    std::span<const u8> calldata;
    std::span<const u8> code;  // the contract's own (CODESIZE, CODE_BYTES)
};

// Every read of the world and every effect of a run goes through the host
// (the validation's: a validate::Session; lot 9's: a storage world).
class Host {
public:
    virtual const CallEnv& env() = 0;
    virtual Word256 sload(const Word256& slot) = 0;
    virtual void sstore(const Word256& slot, const Word256& value) = 0;
    virtual Word256 tload(const Word256& key) = 0;
    virtual void tstore(const Word256& key, const Word256& value) = 0;
    virtual Word256 balance(const Word256& account) = 0;  // SELFBALANCE: balance(env().address)
    virtual Word256 code_size(const Word256& account) = 0;
    virtual Word256 code_hash(const Word256& account) = 0;
    virtual std::vector<u8> code_of(const Word256& account) = 0;  // EXTCODECOPY
    virtual Word256 block_hash(const Word256& number) = 0;
    virtual Word256 blob_hash(const Word256& index) = 0;
    virtual void log(std::span<const Word256> topics, std::span<const u8> data) = 0;
    // value: 0 for StaticCall and DelegateCall; a precompile (PRECOMPILED
    // lines: a StaticCall to its address) is the host's to compute
    virtual CallResult call(CallKind kind, const Word256& target, const Word256& value,
                            std::span<const u8> input) = 0;
    // salt: CREATE2's
    virtual CreateResult create(CreateKind kind, const Word256& value, std::span<const u8> init_code,
                                const Word256& salt) = 0;
    virtual void selfdestruct(const Word256& beneficiary) = 0;

protected:
    ~Host() = default;
};

// A world in memory (tests; lot 9's storage worlds): the env as set, the
// storage from `storage` (else initial(slot), 0 unless overridden), every
// effect recorded in order; calls answer `call_answer`, creations fail.
class SimpleHost : public Host {
public:
    struct Sstore { Word256 slot, value; bool operator==(const Sstore&) const = default; };
    struct Tstore { Word256 key, value; bool operator==(const Tstore&) const = default; };
    struct Log {
        std::vector<Word256> topics;
        std::vector<u8> data;
        bool operator==(const Log&) const = default;
    };
    struct Call {
        CallKind kind;
        Word256 target, value;
        std::vector<u8> input;
        bool operator==(const Call&) const = default;
    };
    struct Create {
        CreateKind kind;
        Word256 value, salt;
        std::vector<u8> init_code;
        bool operator==(const Create&) const = default;
    };
    struct SelfDestruct { Word256 beneficiary; bool operator==(const SelfDestruct&) const = default; };
    using Effect = std::variant<Sstore, Tstore, Log, Call, Create, SelfDestruct>;

    CallEnv call_env;
    std::vector<u8> calldata;  // env().calldata points here
    std::vector<u8> code;      // env().code points here
    std::map<Word256, Word256> storage, transient, balances;
    CallResult call_answer{true, {}};
    std::vector<Effect> effects;

    virtual Word256 initial(const Word256& slot) { (void)slot; return Word256{}; }

    const CallEnv& env() override;
    Word256 sload(const Word256& slot) override;
    void sstore(const Word256& slot, const Word256& value) override;
    Word256 tload(const Word256& key) override;
    void tstore(const Word256& key, const Word256& value) override;
    Word256 balance(const Word256& account) override;
    Word256 code_size(const Word256& account) override;
    Word256 code_hash(const Word256& account) override;
    std::vector<u8> code_of(const Word256& account) override;
    Word256 block_hash(const Word256& number) override;
    Word256 blob_hash(const Word256& index) override;
    void log(std::span<const Word256> topics, std::span<const u8> data) override;
    CallResult call(CallKind kind, const Word256& target, const Word256& value, std::span<const u8> input) override;
    CreateResult create(CreateKind kind, const Word256& value, std::span<const u8> init_code,
                        const Word256& salt) override;
    void selfdestruct(const Word256& beneficiary) override;

    virtual ~SimpleHost() = default;
};

// ---- what runs ----------------------------------------------------------------

// A contract at some stage: its functions (lot 12's ContractResult, lot 5's
// discovery until then) and what the forms of the later stages read.
struct Program {
    std::span<const FunctionInfo> functions;  // Selector and Fallback kinds, in dispatch order
    std::span<const FunctionInfo> internals;  // Internal kind: INTERNAL(entry, ...) by entry_pc
    const ContractShared* shared = nullptr;   // lang (the storage forms); may be null
    const StorageLayout* layout = nullptr;    // lot 9 (ST SV SI SL SBL SF SR SALL SET)
    const SafeMathTable* safemath = nullptr;  // lot 8 (SAFEMATH)
};

struct MachineLimits {
    u32 steps = 4'000'000;                   // lines and loop rounds of a run
    usize bytes_max = limits::RT_BYTES_MAX;  // one byte string
    usize work_max = limits::RT_WORK_MAX;    // the bytes of all the byte strings a run makes
    usize memory_max = usize{32} << 20;      // the EVM memory
    u32 depth_max = 1024;                    // nested INTERNAL calls

    // lot 9's checks (python runtrace's: 20000 steps, 1 MiB of memory)
    static constexpr MachineLimits storage_check() {
        return {limits::RT_STEPS, limits::RT_BYTES_MAX, limits::RT_WORK_MAX, limits::RT_MEMORY, 1024};
    }
};

enum class Status : u8 {
    Stop,         // STOP, the end of the trace, SELFDESTRUCT
    Return,       // RETURN(data)
    Revert,       // REVERT(data)
    Invalid,      // INVALID, ASSERT
    Exhausted,    // a limit (steps, bytes, work, memory, depth): inconclusive
    Undefined,    // an UNDEFINED line (the decompiler gave up there): inconclusive
    Unsupported,  // the machine can't run it (no function for the call, a failed
                  // function, a form whose table is missing): inconclusive
    Bug,          // the trace breaks the IR's rules (a variable never set, a call
                  // record never written, a GOTO without its LABEL...): the stage's bug
};

struct Outcome {
    Status status = Status::Stop;
    std::vector<u8> data;               // Return, Revert
    u32 reason = 0;                     // Invalid by an INVALID line: its reason operand
    std::string note;                   // Exhausted, Undefined, Unsupported, Bug: why (diagnostics)
    Value line;                         // the line the run ended at (Bug: where), NIL when none
    std::optional<usize> function;      // call(): the function run (index in Program::functions)
    u64 steps = 0;                      // lines and loop rounds run
    u32 unsized = 0;                    // byte elements without SIZED (their width guessed): a stage's bug
    Value unsized_element;              // the first of them (NIL: none)
    Value unsized_line;                 // the line it was in

    bool halted() const noexcept { return status <= Status::Invalid; }  // conclusive
    bool success() const noexcept { return status == Status::Stop || status == Status::Return; }
};

// The machine of a program: reused from run to run (its buffers kept). Its
// Values (the traces) are the current context's: a machine lives on the
// thread and context its program was made on. Not thread-safe.
class Machine {
public:
    explicit Machine(const Program& program, MachineLimits limits = {});
    ~Machine();
    Machine(const Machine&) = delete;
    Machine& operator=(const Machine&) = delete;

    // One call of the contract, the host's env() its inputs: dispatch, entry
    // conditions, the function's trace. selector_hint: the selector function
    // tried first (the planned call's).
    Outcome call(Host& host, std::optional<u32> selector_hint = {});

    // One trace as the body of fn (its params, internal calls, call ids; no
    // dispatch, no entry conditions unless with_entry): lot 9's getters run a
    // trace and its rewrite this way.
    Outcome run(Host& host, const FunctionInfo& fn, Value trace, bool with_entry = false);
    Outcome run(Host& host, const FunctionInfo& fn, bool with_entry = false) {
        return run(host, fn, fn.trace, with_entry);
    }

    const Program& program() const noexcept;
    const MachineLimits& limits() const noexcept;
    void set_limits(const MachineLimits& l) noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

// keccak-256 (the EVM's SHA3) of bytes
Word256 keccak256(std::span<const u8> data) noexcept;

// for messages
const char* status_name(Status s) noexcept;

}  // namespace pan::exec
