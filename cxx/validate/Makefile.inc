# The validation by execution (cxx/validate, AGENTS.md rule 5): evmone and
# its dependencies (cxx/third_party/{evmone,evmc,intx}, see their NOTICE),
# the shared world and effects, the EVM runner, the calldata generator, the
# evmrun tool and the tests. Included by cxx/Makefile (make runs in cxx/: the
# paths are relative to it), which builds the objects with the mandated
# flags; no CMake.
#
#   EVMONE_SRCS        evmone's C++ sources (the VM, and the precompiles but
#                      BLS12-381 and KZG, which need blst) -> libevmone.a
#   EVMONE_CSRCS       its C sources (ethash's keccak), gcc-14 -std=gnu17
#   EVMONE_CPPFLAGS    include paths and macros of evmone's sources and of
#                      everything that includes them
#   EVMONE_CXXFLAGS    extra flags for evmone's sources only
#   VALIDATE_CPPFLAGS  for validate/*.cpp (every one but the tools ->
#                      libvalidate.a) and tests/*.cpp; a user of
#                      validate/*.hpp needs at least
#                      -I third_party/intx/include -I .
#   VALIDATE_TOOLS     the validate/*.cpp holding a main (linked with
#                      libvalidate.a and libevmone.a)
#   VALIDATE_LDLIBS    the libraries they need

EVMONE_DIR := third_party/evmone

EVMONE_SRCS := \
	$(EVMONE_DIR)/lib/evmone/advanced_analysis.cpp \
	$(EVMONE_DIR)/lib/evmone/advanced_execution.cpp \
	$(EVMONE_DIR)/lib/evmone/advanced_instructions.cpp \
	$(EVMONE_DIR)/lib/evmone/baseline_analysis.cpp \
	$(EVMONE_DIR)/lib/evmone/baseline_execution.cpp \
	$(EVMONE_DIR)/lib/evmone/baseline_instruction_table.cpp \
	$(EVMONE_DIR)/lib/evmone/create_address.cpp \
	$(EVMONE_DIR)/lib/evmone/delegation.cpp \
	$(EVMONE_DIR)/lib/evmone/instructions_calls.cpp \
	$(EVMONE_DIR)/lib/evmone/instructions_storage.cpp \
	$(EVMONE_DIR)/lib/evmone/tracing.cpp \
	$(EVMONE_DIR)/lib/evmone/vm.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/blake2b.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/bn254.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/modexp.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/mulmod.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/pairing/bn254/pairing.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/ripemd160.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/secp256k1.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/secp256r1.cpp \
	$(EVMONE_DIR)/lib/evmone_precompiles/sha256.cpp

EVMONE_CSRCS := \
	$(EVMONE_DIR)/lib/evmone_precompiles/keccak.c

# EVMONE_FIXED_GAS: what GAS gives (the local change of evmone, see its
# NOTICE) - validate::fixed_gas, world.hpp checks they agree
EVMONE_CPPFLAGS := \
	-I $(EVMONE_DIR)/include \
	-I $(EVMONE_DIR)/lib \
	-I third_party/evmc/include \
	-I third_party/intx/include \
	-DEVMONE_FIXED_GAS=30000000 \
	-DPROJECT_VERSION='"0.24.0"'

EVMONE_CXXFLAGS := -Wno-attributes

# (third-party headers as system ones: their warnings aren't ours)
VALIDATE_CPPFLAGS := -I . \
	-isystem $(EVMONE_DIR)/include \
	-isystem $(EVMONE_DIR)/lib \
	-isystem third_party/evmc/include \
	-isystem third_party/intx/include \
	-DEVMONE_FIXED_GAS=30000000

VALIDATE_TOOLS := validate/evmrun.cpp

VALIDATE_LDLIBS :=
