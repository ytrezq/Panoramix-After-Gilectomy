# cxx/Makefile: the build of the C++23 decompiler (cxx/BUILD.md explains it).
#
## Targets (make runs in cxx/; `make -C cxx` from the repository's root):
##   all        $(B)/libpanoramix_cxx.a, the CLI $(B)/pancxx, the python
##              module $(B)/panoramix_cxx<EXT_SUFFIX> and the same module
##              named panoramix_asm in $(B)/compat/ (the repository's scripts:
##              PANASM_BUILD=cxx/$(B)/compat)
##   check      the doctest binary $(B)/pancxx_test (tests/*_test.cpp + the
##              libraries), run with $(TEST_ARGS); then every tests/*.py, run
##              as `$(PYTHON) tests/X.py $(B)`
##   unit       only the doctest binary, built and run
##   validate   the validation tools (validate/; validate/Makefile.inc)
##   sigdb      $(SIGDB), the signature database: `pancxx build-db $(ABI_DUMP)`
##   pgo        the PGO build in $(B)/pgo/: instrumented, trained over
##              $(CORPUS) (tools/corpus.py --train), rebuilt -fprofile-use
##   debug      $(B)/debug/: -O1 -g, ASan + UBSan, no LTO; builds the CLI and
##              the unit tests and runs them (any target: make VARIANT=debug X)
##   bench      tools/bench.py: the asm, $(B)/pancxx and $(B)/pgo/pancxx over
##              $(CORPUS), $(BENCH_ARGS)
##   clean      rm -rf $(B)
## Variables:
##   B=build    the build directory: each worker its own, B=build-NAME
##   V=1        show the commands
##   JOBS=2     the contracts decompiled at once by the PGO training run
##   CORPUS     a list of .hex files (or a directory, or .hex files)
##   SIGDB, ABI_DUMP, ASM, ASM_SIGDB, PYTHON, TEST_ARGS, BENCH_ARGS,
##   EXTRA_CXXFLAGS, EXTRA_LDFLAGS (experiments only: the flags are fixed)
## -j2 at most: the machine has 2 CPUs shared by every worker.
#
# Every source is found by a glob: a new src/*.cpp, src/*.rl, src/*.S,
# tests/*_test.cpp, validate/*.cpp or validate/*.rl needs no edit here.

MAKEFLAGS += --no-builtin-rules --no-print-directory
.SUFFIXES:
.DELETE_ON_ERROR:
.SECONDARY:
.DEFAULT_GOAL := all

# --- the tools ----------------------------------------------------------------

CXX    := g++-14
CC     := gcc-14
AR     := gcc-ar-14
RAGEL  := ragel
PYTHON ?= python3

# --- the variables of the command line ----------------------------------------

B         ?= build
V         ?= 0
VARIANT   ?= release
JOBS      ?= 2
CORPUS    ?= /tmp/claude-0/-home-claude/0fe601fa-3d3d-56af-9a22-c5068d00d0e0/scratchpad/prof/all_hex.txt
ABI_DUMP  ?= /home/claude/panoramix/panoramix/data/abi_dump.xz
SIGDB     ?= $(B)/sigdb1.bin
ASM       ?= $(abspath ../build/panasm)
ASM_SIGDB ?= $(abspath ../build/abi_db.bin)
TEST_ARGS ?=
BENCH_ARGS ?=
EXTRA_CXXFLAGS ?=
EXTRA_LDFLAGS ?=

# --- the flags ----------------------------------------------------------------

# the user's rule: always these, at every compilation (and -flto=auto at the
# link); only the debug build differs
OPT     := -march=native -mtune=native -Ofast -flto -fmerge-all-constants -fweb
OPTLINK := $(patsubst -flto,-flto=auto,$(OPT))
WARN    := -Wall -Wextra
# ragel -G2's code jumps into the cases of its switch
GENWARN := -Wno-implicit-fallthrough

ifeq ($(VARIANT),release)
D        := $(B)
VFLAGS   := $(OPT)
VLDFLAGS := $(OPTLINK)
VWARN    :=
VNAME    := release
else ifeq ($(VARIANT),pgo-gen)
# the object paths are the same in both PGO builds: the .gcda files written
# next to the objects by the training run are read back by -fprofile-use
D        := $(B)/pgo
VFLAGS   := $(OPT) -fprofile-generate -fprofile-update=prefer-atomic
VLDFLAGS := $(OPTLINK) -fprofile-generate -fprofile-update=prefer-atomic
VWARN    :=
VNAME    := pgo-instrumented
else ifeq ($(VARIANT),pgo-use)
D        := $(B)/pgo
VFLAGS   := $(OPT) -fprofile-use -fprofile-partial-training
VLDFLAGS := $(OPTLINK) -fprofile-use -fprofile-partial-training
# what the training never ran (the module's glue, the tests) has no profile;
# a source changed since the training loses its profile instead of failing
VWARN    := -Wno-missing-profile -Wno-error=coverage-mismatch
VNAME    := pgo
else ifeq ($(VARIANT),debug)
D        := $(B)/debug
VFLAGS   := -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined \
            -fno-sanitize-recover=all -D_GLIBCXX_ASSERTIONS
VLDFLAGS := -g -fsanitize=address,undefined
VWARN    :=
VNAME    := debug
else
$(error VARIANT=$(VARIANT): release, debug, pgo-gen or pgo-use)
endif

O := $(D)/obj
G := $(B)/gen

# every object is position-independent: the python module is a shared object
# made of the library's objects (at the link, LTO makes the CLI's code PIE)
CXXFLAGS := -std=gnu++23 $(VFLAGS) -fPIC -pthread $(EXTRA_CXXFLAGS)
CFLAGS   := -std=gnu17 $(VFLAGS) -fPIC -pthread $(EXTRA_CXXFLAGS)
ASFLAGS  := $(VFLAGS) -fPIC -Wa,--noexecstack
LDFLAGS  := $(VLDFLAGS) -pthread -Wl,-z,noexecstack -Wl,-z,text $(EXTRA_LDFLAGS)
LDLIBS   := -llzma

# --- the sources ----------------------------------------------------------------

PLATFORM := $(if $(findstring mingw,$(shell $(CXX) -dumpmachine)),win32,posix)
NOTPLAT  := $(filter-out $(PLATFORM),posix win32)

# $(call sources,DIR): DIR/*.cpp *.rl *.S, the other platform's files left out
sources = $(filter-out $(foreach p,$(NOTPLAT),$(1)/%_$(p).cpp $(1)/%_$(p).rl $(1)/%_$(p).S),\
            $(wildcard $(1)/*.cpp $(1)/*.rl $(1)/*.S))
# $(call obj,SOURCES): DIR/X.cpp -> $(O)/DIR/X.cpp.o; DIR/X.rl -> ragel ->
# $(G)/DIR/X.cpp -> $(O)/gen/DIR/X.cpp.o
obj = $(foreach s,$(1),$(if $(filter %.rl,$(s)),$(O)/gen/$(s:.rl=.cpp).o,$(O)/$(s).o))

# validate/Makefile.inc (the evmone harness): EVMONE_SRCS, EVMONE_CSRCS,
# EVMONE_CPPFLAGS, EVMONE_CXXFLAGS, VALIDATE_CPPFLAGS, VALIDATE_TOOLS,
# VALIDATE_LDLIBS
-include validate/Makefile.inc

TP_INC := $(patsubst %,-isystem %,$(wildcard third_party/*/include))
CPPFLAGS_SRC := -Isrc $(TP_INC)
CPPFLAGS_VAL := -Isrc -I. $(TP_INC) $(VALIDATE_CPPFLAGS)
CPPFLAGS_TST := -Isrc -I. $(TP_INC) -isystem third_party/doctest $(VALIDATE_CPPFLAGS)
CPPFLAGS_TP  := $(EVMONE_CPPFLAGS)

# the library: everything in src/ but the two front-ends' main files
LIB_SRCS := $(filter-out src/main.cpp src/pymod.cpp,$(call sources,src))
LIB_OBJS := $(call obj,$(LIB_SRCS))
LIB      := $(D)/libpanoramix_cxx.a

# the validation: the tools (each a validate/X.cpp with a main -> $(D)/X;
# validate/X_main.cpp -> $(D)/X), the rest of validate/ (libvalidate.a),
# evmone & co. (libevmone.a)
VAL_TOOLS := $(sort $(VALIDATE_TOOLS) $(wildcard validate/*_main.cpp))
VAL_OBJS  := $(call obj,$(filter-out $(VAL_TOOLS),$(call sources,validate)))
VAL_LIB   := $(if $(VAL_OBJS),$(D)/libvalidate.a)
EVM_OBJS  := $(call obj,$(EVMONE_SRCS) $(EVMONE_CSRCS))
EVM_LIB   := $(if $(EVM_OBJS),$(D)/libevmone.a)
tool_name  = $(patsubst %_main,%,$(basename $(notdir $(1))))
VAL_BINS  := $(foreach t,$(VAL_TOOLS),$(D)/$(call tool_name,$(t)))

TEST_OBJS := $(call obj,$(wildcard tests/*_test.cpp))
TEST_BIN  := $(D)/pancxx_test
PYTESTS   := $(if $(filter debug,$(VARIANT)),,$(wildcard tests/*.py))

CLI      := $(if $(wildcard src/main.cpp),$(D)/pancxx)
ifneq ($(wildcard src/pymod.cpp),)
ifneq ($(VARIANT),debug)
PY_INFO  := $(shell $(PYTHON) -c "import sysconfig as s; print(s.get_paths()['include'], s.get_config_var('EXT_SUFFIX'))")
PY_INC   := $(word 1,$(PY_INFO))
PY_EXT   := $(word 2,$(PY_INFO))
PYMODS   := $(D)/panoramix_cxx$(PY_EXT) $(D)/compat/panoramix_asm$(PY_EXT)
endif
endif

RLH := $(wildcard src/*.rlh validate/*.rlh)

# --- the output -----------------------------------------------------------------

ifeq ($(V),0)
Q   := @
say  = @printf '  %-7s %s\n' '$(1)' '$(2)'
else
Q   :=
say  = @:
endif
# a word quoted for the shell's single quotes; a string for a C literal
shq = $(subst ','\'',$(1))
cq  = $(subst ",\",$(subst \,\\,$(1)))
# write $(2) into $(1) when it differs (the stamps: only a change rebuilds)
define write_if_changed
@mkdir -p $(dir $(1)); printf '%s\n' $(2) > $(1).tmp; \
 if cmp -s $(1).tmp $(1); then rm -f $(1).tmp; else mv -f $(1).tmp $(1); fi
endef

# --- the main targets -------------------------------------------------------------

all: $(LIB) $(CLI) $(PYMODS)
	@$(if $(CLI),:,echo "  (no src/main.cpp yet: no pancxx)")
	@$(if $(wildcard src/pymod.cpp),:,echo "  (no src/pymod.cpp yet: no python module)")

lib: $(LIB)
cli: $(CLI)
pymod: $(PYMODS)

check: unit $(if $(PYTESTS),pytests)

unit: $(TEST_BIN)
	$(call say,TEST,$(TEST_BIN) $(TEST_ARGS))
	$(Q)$(TEST_BIN) $(TEST_ARGS)

pytests: all
	@for t in $(PYTESTS); do printf '  %-7s %s\n' PYTEST "$$t"; $(PYTHON) "$$t" $(D) || exit 1; done

validate: $(VAL_BINS) $(VAL_LIB) $(EVM_LIB)

help:
	@sed -n 's/^## \{0,1\}//p' Makefile

# --- the signature database, PGO, debug, bench ---------------------------------

sigdb: $(SIGDB)

$(SIGDB): $(ABI_DUMP) $(B)/pancxx
	$(call say,BUILDDB,$@)
	$(Q)$(B)/pancxx build-db $(ABI_DUMP) $@.tmp && mv -f $@.tmp $@

ifeq ($(VARIANT),release)
pgo: $(SIGDB)
	@find $(B)/pgo -name '*.gcda' -delete 2>/dev/null; true
	$(Q)$(MAKE) VARIANT=pgo-gen cli
	$(call say,TRAIN,$(CORPUS))
	$(Q)$(PYTHON) tools/corpus.py --train --cli $(B)/pgo/pancxx --sigdb $(abspath $(SIGDB)) \
	  -j $(JOBS) $(CORPUS)
	$(Q)$(MAKE) VARIANT=pgo-use all

debug:
	$(Q)$(MAKE) VARIANT=debug lib cli unit

bench: all $(SIGDB)
	$(Q)$(PYTHON) tools/bench.py --asm $(ASM) --asm-sigdb $(abspath $(ASM_SIGDB)) \
	  --cxx $(B)/pancxx --pgo $(B)/pgo/pancxx --sigdb $(abspath $(SIGDB)) $(BENCH_ARGS) $(CORPUS)
endif

clean:
	rm -rf $(B)

.PHONY: all lib cli pymod check unit pytests validate help sigdb pgo debug bench clean FORCE
FORCE:

# --- the links ------------------------------------------------------------------

# an archive is made anew (gcc-ar: the LTO objects' symbol index); the list
# of its members is a stamp, so that a deleted source rebuilds it too
$(D)/%.a:
	@mkdir -p $(@D)
	$(call say,AR,$@)
	$(Q)rm -f $@ && $(AR) rcs $@ $(filter %.o,$^)

$(LIB): $(LIB_OBJS) $(O)/lib.list
$(D)/libvalidate.a: $(VAL_OBJS) $(O)/validate.list
$(D)/libevmone.a: $(EVM_OBJS) $(O)/evmone.list
$(O)/lib.list: FORCE
	$(call write_if_changed,$@,'$(LIB_OBJS)')
$(O)/validate.list: FORCE
	$(call write_if_changed,$@,'$(VAL_OBJS)')
$(O)/evmone.list: FORCE
	$(call write_if_changed,$@,'$(EVM_OBJS)')
$(O)/tests.list: FORCE
	$(call write_if_changed,$@,'$(TEST_OBJS)')

# the links run with `+`: -flto=auto then shares make's job slots
$(D)/pancxx: $(O)/src/main.cpp.o $(LIB) $(O)/ldflags
	$(call say,LD,$@)
	+$(Q)$(CXX) $(LDFLAGS) -o $@ $< $(LIB) $(LDLIBS)

$(TEST_BIN): $(TEST_OBJS) $(VAL_LIB) $(EVM_LIB) $(LIB) $(O)/ldflags $(O)/tests.list
	$(call say,LD,$@)
	+$(Q)$(CXX) $(LDFLAGS) -o $@ $(TEST_OBJS) $(VAL_LIB) $(EVM_LIB) $(LIB) $(LDLIBS) $(VALIDATE_LDLIBS)

define tool_rule
$(D)/$(call tool_name,$(1)): $(call obj,$(1)) $$(VAL_LIB) $$(EVM_LIB) $$(LIB) $$(O)/ldflags
	$$(call say,LD,$$@)
	+$$(Q)$$(CXX) $$(LDFLAGS) -o $$@ $$< $$(VAL_LIB) $$(EVM_LIB) $$(LIB) $$(LDLIBS) $$(VALIDATE_LDLIBS)
endef
$(foreach t,$(VAL_TOOLS),$(eval $(call tool_rule,$(t))))

# the python module exports PyInit_* only (LTO internalizes everything else)
$(D)/panoramix_cxx$(PY_EXT): $(O)/src/pymod.cpp.o $(LIB) $(O)/pymod.map $(O)/ldflags
	$(call say,LD,$@)
	+$(Q)$(CXX) -shared $(LDFLAGS) -Wl,--version-script=$(O)/pymod.map -o $@ $< $(LIB) $(LDLIBS)

$(D)/compat/panoramix_asm$(PY_EXT): $(O)/src/pymod_compat.cpp.o $(LIB) $(O)/pymod.map $(O)/ldflags
	@mkdir -p $(@D)
	$(call say,LD,$@)
	+$(Q)$(CXX) -shared $(LDFLAGS) -Wl,--version-script=$(O)/pymod.map -o $@ $< $(LIB) $(LDLIBS)

$(O)/pymod.map:
	$(call write_if_changed,$@,'{ global: PyInit_*; local: *; };')

# --- the compilations -------------------------------------------------------------

# the stamps of the flags, one per kind of source: a change rebuilds those
# objects (a PGO phase, a variable of the command line, validate/Makefile.inc
# for validate/ and third_party/ only); of the link flags, relinks
FLAGS_ALL = $(CXX) $(CC) | $(CXXFLAGS) | $(CFLAGS) | $(ASFLAGS) | $(WARN) $(VWARN) $(GENWARN)
FLAGS_src = $(FLAGS_ALL) | $(CPPFLAGS_SRC) | $(PY_INC)
FLAGS_val = $(FLAGS_ALL) | $(CPPFLAGS_VAL)
FLAGS_tst = $(FLAGS_ALL) | $(CPPFLAGS_TST)
FLAGS_tp  = $(FLAGS_ALL) | $(CPPFLAGS_TP) | $(EVMONE_CXXFLAGS)
$(O)/flags.%: FORCE
	$(call write_if_changed,$@,'$(call shq,$(FLAGS_$*))')
$(O)/ldflags: FORCE
	$(call write_if_changed,$@,'$(call shq,$(LDFLAGS) | $(LDLIBS) | $(VALIDATE_LDLIBS))')

# for `pancxx --version` (src/version.cpp): the build and its flags
NATIVE = $(shell $(CXX) -march=native -Q --help=target 2>/dev/null | awk '$$1 == "-march=" { print $$2; exit }')
BUILD_FLAGS = $(strip $(CXXFLAGS))$(if $(filter -march=native,$(CXXFLAGS)), (native: $(NATIVE)))
$(O)/build_info.h: FORCE
	$(call write_if_changed,$@,'#define PANORAMIX_VARIANT "$(VNAME)"' '#define PANORAMIX_FLAGS "$(call shq,$(call cq,$(BUILD_FLAGS)))"')
$(O)/src/version.cpp.o: $(O)/build_info.h
$(O)/src/version.cpp.o: private XFLAGS := -I$(O)

$(O)/src/pymod.cpp.o: private XFLAGS := -DPAN_PYMODULE=panoramix_cxx -isystem $(PY_INC)
$(O)/src/pymod_compat.cpp.o: src/pymod.cpp $(O)/flags.src
	@mkdir -p $(@D)
	$(call say,CXX,$< (panoramix_asm))
	$(Q)$(CXX) $(CPPFLAGS_SRC) -DPAN_PYMODULE=panoramix_asm -isystem $(PY_INC) $(CXXFLAGS) $(WARN) $(VWARN) -MMD -MP -c -o $@ $<

$(G)/%.cpp: %.rl $(RLH)
	@mkdir -p $(@D)
	$(call say,RAGEL,$<)
	$(Q)$(RAGEL) -G2 -I $(<D) -I src -o $@ $<

$(O)/src/%.cpp.o: src/%.cpp $(O)/flags.src
	@mkdir -p $(@D)
	$(call say,CXX,$<)
	$(Q)$(CXX) $(CPPFLAGS_SRC) $(XFLAGS) $(CXXFLAGS) $(WARN) $(VWARN) -MMD -MP -c -o $@ $<

$(O)/gen/src/%.cpp.o: $(G)/src/%.cpp $(O)/flags.src
	@mkdir -p $(@D)
	$(call say,CXX,$<)
	$(Q)$(CXX) $(CPPFLAGS_SRC) $(CXXFLAGS) $(WARN) $(GENWARN) $(VWARN) -MMD -MP -c -o $@ $<

$(O)/src/%.S.o: src/%.S $(O)/flags.src
	@mkdir -p $(@D)
	$(call say,AS,$<)
	$(Q)$(CC) $(CPPFLAGS_SRC) $(ASFLAGS) -MMD -MP -c -o $@ $<

$(O)/tests/%.cpp.o: tests/%.cpp $(O)/flags.tst
	@mkdir -p $(@D)
	$(call say,CXX,$<)
	$(Q)$(CXX) $(CPPFLAGS_TST) $(CXXFLAGS) $(WARN) $(VWARN) -MMD -MP -c -o $@ $<

$(O)/validate/%.cpp.o: validate/%.cpp $(O)/flags.val
	@mkdir -p $(@D)
	$(call say,CXX,$<)
	$(Q)$(CXX) $(CPPFLAGS_VAL) $(CXXFLAGS) $(WARN) $(VWARN) -MMD -MP -c -o $@ $<

$(O)/gen/validate/%.cpp.o: $(G)/validate/%.cpp $(O)/flags.val
	@mkdir -p $(@D)
	$(call say,CXX,$<)
	$(Q)$(CXX) $(CPPFLAGS_VAL) $(CXXFLAGS) $(WARN) $(GENWARN) $(VWARN) -MMD -MP -c -o $@ $<

$(O)/validate/%.S.o: validate/%.S $(O)/flags.val
	@mkdir -p $(@D)
	$(call say,AS,$<)
	$(Q)$(CC) $(CPPFLAGS_VAL) $(ASFLAGS) -MMD -MP -c -o $@ $<

# third-party code: its own flags, no warnings of ours
$(O)/third_party/%.cpp.o: third_party/%.cpp $(O)/flags.tp
	@mkdir -p $(@D)
	$(call say,CXX,$<)
	$(Q)$(CXX) $(CPPFLAGS_TP) $(CXXFLAGS) $(VWARN) $(EVMONE_CXXFLAGS) -MMD -MP -c -o $@ $<

$(O)/third_party/%.c.o: third_party/%.c $(O)/flags.tp
	@mkdir -p $(@D)
	$(call say,CC,$<)
	$(Q)$(CC) $(CPPFLAGS_TP) $(CFLAGS) $(VWARN) -MMD -MP -c -o $@ $<

-include $(shell find $(O) -name '*.d' 2>/dev/null)
