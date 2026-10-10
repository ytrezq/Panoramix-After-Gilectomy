AS      = as
ASFLAGS = -I include --64 -g
CC      = cc
CFLAGS  = -O2 -fPIC -Wall
LDFLAGS = -Wl,-z,text -Wl,-z,noexecstack
LDLIBS  = -L/usr/lib/x86_64-linux-gnu -l:libgmp.so.10 -l:liblzma.so.5 -lpthread -lm
# the python the module is built for (setup.py passes its own)
PYTHON  ?= python3
PY_INC  = $(shell $(PYTHON) -c "import sysconfig; print(sysconfig.get_paths()['include'])")
PY_EXT  = $(shell $(PYTHON) -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")
PREFIX  ?= /usr/local
# the python implementation, for the tests that compare with it
PANORAMIX_REPO   ?= $(abspath ../panoramix)
PANORAMIX_PYTHON ?= $(PANORAMIX_REPO)/.venv/bin/python

SRCS = $(wildcard src/*.s)
OBJS = $(patsubst src/%.s,build/%.o,$(SRCS))
LIBOBJS = $(filter-out build/main.o,$(OBJS))

all: build/panasm build/panoramix_asm$(PY_EXT) build/libpanoramix_asm.so

include/opcodes.inc src/opcodes_table.s: tools/gen_opcodes.py
	python3 tools/gen_opcodes.py

# the decoder (src/decoder.s, docs/DESIGN.md): the instructions of
# spec/evm.def as ragel machines and as the tables of their opcodes
# (tools/gen_dfa.py), the automaton of spec/evm_decoder.rl as tables
# (tools/rl2asm.py, which needs ragel: `make dfa`, the tables being kept in
# the repository), and the proof that it decodes what spec/evm.def says
# and recognizes the idioms of tools/evm_spec.py, where they are and only
# there (`make dfa-check`: tools/verify_dfa.py, and the tables the same
# as ragel makes them now)
build/gen_dfa.stamp: spec/evm.def tools/gen_dfa.py tools/evm_spec.py
	@mkdir -p build
	python3 tools/gen_dfa.py
	@touch $@

spec/evm_insns.rl src/evm_ops.s include/evm_ops.inc: build/gen_dfa.stamp

build/decoder.o build/decode_report.o: include/evm_ops.inc include/evm_dfa.inc
build/evm_dfa.o: include/evm_dfa.inc

dfa: spec/evm_insns.rl
	python3 tools/rl2asm.py

dfa-check: spec/evm_insns.rl
	python3 tools/verify_dfa.py
	python3 tools/rl2asm.py build/dfa_check >/dev/null
	cmp src/evm_dfa.s build/dfa_check/src/evm_dfa.s && cmp include/evm_dfa.inc build/dfa_check/include/evm_dfa.inc

build/%.o: src/%.s include/defs.inc include/opcodes.inc include/storage.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -o $@ $<

# the tables of the hashes a compiler writes as numbers (src/storage.s
# includes them, .incbin): made once here, with keccak.s, where every
# process made them (tools/gen_htab.c)
build/gen_htab: tools/gen_htab.c build/keccak.o
	$(CC) -O2 -Wall -o $@ tools/gen_htab.c build/keccak.o

build/storage_htab.bin: build/gen_htab
	build/gen_htab $@

build/storage.o build/cov/storage.o: build/storage_htab.bin

build/panasm: $(OBJS)
	$(CC) -pie $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

build/pymod.o: src/pymod.c
	$(CC) $(CFLAGS) -I$(PY_INC) -c -o $@ $<

build/panoramix_asm$(PY_EXT): build/pymod.o $(LIBOBJS)
	$(CC) -shared $(LDFLAGS) -o $@ build/pymod.o $(LIBOBJS) $(LDLIBS)

# the library for C (include/panoramix_asm.h): only the pan_* functions
# are exported
build/libpanoramix_asm.so: $(LIBOBJS)
	$(CC) -shared $(LDFLAGS) -Wl,-soname,libpanoramix_asm.so -o $@ $(LIBOBJS) $(LDLIBS)

# `make coverage`: build/cov/, the tool and the module counting the calls of
# every function (FUNC's COV_COUNT), written at exit to $PANORAMIX_COVERAGE
# ("count name" lines, appended): tools/cov_report.py lists the ones never
# called
COV_OBJS = $(patsubst src/%.s,build/cov/%.o,$(SRCS))
COV_LIBOBJS = $(filter-out build/cov/main.o,$(COV_OBJS))

build/cov/%.o: src/%.s include/defs.inc include/opcodes.inc
	@mkdir -p build/cov
	$(AS) $(ASFLAGS) --defsym COVERAGE=1 -o $@ $<

build/cov/panasm: $(COV_OBJS)
	$(CC) -pie $(LDFLAGS) -o $@ $(COV_OBJS) $(LDLIBS)

build/cov/panoramix_asm$(PY_EXT): build/pymod.o $(COV_LIBOBJS)
	$(CC) -shared $(LDFLAGS) -o $@ build/pymod.o $(COV_LIBOBJS) $(LDLIBS)

coverage: build/cov/panasm build/cov/panoramix_asm$(PY_EXT)

# the profiler (tools/psamp.c): build/psamp OUT 250000 build/panasm decompile ...,
# then tools/psym.py OUT
build/psamp: tools/psamp.c
	@mkdir -p build
	$(CC) -O2 -Wall -o $@ $<

build/c_api_test: tests/c_api_test.c include/panoramix_asm.h build/libpanoramix_asm.so
	$(CC) -O2 -Wall -Iinclude -o $@ tests/c_api_test.c -Lbuild -lpanoramix_asm -Wl,-rpath,'$$ORIGIN'

build/init_race_test: tests/init_race_test.c include/panoramix_asm.h build/libpanoramix_asm.so
	$(CC) -O2 -Wall -Iinclude -o $@ tests/init_race_test.c -Lbuild -lpanoramix_asm -lpthread -Wl,-rpath,'$$ORIGIN'

check: build/c_api_test build/init_race_test all
	python3 tools/recursion.py --check
	build/c_api_test
	for i in $$(seq 30); do build/init_race_test 8 || exit 1; done
	tests/security.sh
	tests/run_corpus.sh
	tests/robustness.sh
	python3 tests/test_watchdog.py
	python3 tests/test_json_value.py
	python3 tests/test_json.py
	python3 tests/test_verbose.py
	python3 tests/test_fetch.py

# python's Decompilation of the corpus (pypy, a few minutes), for
# tests/test_json.py
json-expected:
	mkdir -p build/json_expected
	for f in tests/corpus/*.hex; do n=$$(basename $$f .hex); \
	  [ -f build/json_expected/$$n.pickle ] || PYTHONPATH=$(PANORAMIX_REPO) PYTHONINTMAXSTRDIGITS=0 \
	    $(PANORAMIX_PYTHON) tests/gen_json_expected.py $$f build/json_expected/$$n.pickle; done

# what reached python's Function and make_ast in its decompilations of the
# corpus and the synthetic programs (pypy, ~40 minutes), for
# tests/test_function.py, test_folder.py, test_postprocess.py
fn-inputs:
	PANORAMIX_PY=$(PANORAMIX_REPO) PANORAMIX_TIMEOUT=5 PYTHONINTMAXSTRDIGITS=0 \
	  $(PANORAMIX_PYTHON) tests/gen_function_inputs.py build/fn_inputs tests/synthetic/*.hex tests/corpus/*.hex

# what python's storage.rewrite_functions is given in its decompilations of
# the corpus and the synthetic programs (pypy, ~20 minutes), for
# tests/test_storage.py
storage-caps:
	mkdir -p build/storage_caps
	for f in tests/synthetic/*.hex tests/corpus/*.hex; do n=$$(basename $$f .hex); \
	  [ -f build/storage_caps/$$n.pkl ] || PANORAMIX_PY=$(PANORAMIX_REPO) PANORAMIX_TIMEOUT=5 PYTHONINTMAXSTRDIGITS=0 \
	    $(PANORAMIX_PYTHON) tests/storage_capture.py $$f build/storage_caps/$$n.pkl; done

# python's --verbose and --explain outputs of small contracts of the
# corpus, and its text with --repr and --returns in sys.argv (pypy, a few
# minutes), for tests/test_verbose.py
VERBOSE_CONTRACTS = USDC_proxy AaveV3Pool_proxy WETH Multicall3 ENSRegistry Permit2
verbose-expected:
	mkdir -p build/verbose_expected
	for n in $(VERBOSE_CONTRACTS); do for m in verbose explain; do \
	  [ -f build/verbose_expected/$$n.$$m.txt ] || tests/gen_verbose_expected.sh \
	    $(PANORAMIX_PYTHON) $(PANORAMIX_REPO) tests/corpus/$$n.hex --$$m build/verbose_expected/$$n.$$m.txt; done; \
	  [ -f build/verbose_expected/$$n.repr.txt ] || PYTHONPATH=$(PANORAMIX_REPO) PYTHONINTMAXSTRDIGITS=0 \
	    $(PANORAMIX_PYTHON) tests/gen_repr_expected.py tests/corpus/$$n.hex build/verbose_expected/$$n.repr.txt; done

# the command line tool, the C library and its header (the python module:
# pip install .)
install: build/panasm build/libpanoramix_asm.so
	install -d $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/lib $(DESTDIR)$(PREFIX)/include
	install -m 755 build/panasm $(DESTDIR)$(PREFIX)/bin/panasm
	install -m 755 build/libpanoramix_asm.so $(DESTDIR)$(PREFIX)/lib/libpanoramix_asm.so
	install -m 644 include/panoramix_asm.h $(DESTDIR)$(PREFIX)/include/panoramix_asm.h

clean:
	rm -rf build

.PHONY: all clean check install json-expected verbose-expected fn-inputs storage-caps coverage dfa dfa-check
