AS      = as
ASFLAGS = -I include --64 -g
CC      = cc
CFLAGS  = -O2 -fPIC -Wall
LDFLAGS = -Wl,-z,text -Wl,-z,noexecstack
LDLIBS  = -L/usr/lib/x86_64-linux-gnu -l:libgmp.so.10 -l:liblzma.so.5 -lpthread -lm
PY_INC  = $(shell python3 -c "import sysconfig; print(sysconfig.get_paths()['include'])")
PY_EXT  = $(shell python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")
# the python implementation, for the tests that compare with it
PANORAMIX_REPO   ?= $(abspath ../panoramix)
PANORAMIX_PYTHON ?= $(PANORAMIX_REPO)/.venv/bin/python

SRCS = $(wildcard src/*.s)
OBJS = $(patsubst src/%.s,build/%.o,$(SRCS))
LIBOBJS = $(filter-out build/main.o,$(OBJS))

all: build/panasm build/panoramix_asm$(PY_EXT) build/libpanoramix_asm.so

include/opcodes.inc src/opcodes_table.s: tools/gen_opcodes.py
	python3 tools/gen_opcodes.py

build/%.o: src/%.s include/defs.inc include/opcodes.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -o $@ $<

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

build/c_api_test: tests/c_api_test.c include/panoramix_asm.h build/libpanoramix_asm.so
	$(CC) -O2 -Wall -Iinclude -o $@ tests/c_api_test.c -Lbuild -lpanoramix_asm -Wl,-rpath,'$$ORIGIN'

check: build/c_api_test all
	python3 tools/recursion.py --check
	build/c_api_test
	tests/run_corpus.sh
	tests/robustness.sh
	python3 tests/test_watchdog.py
	python3 tests/test_json_value.py
	python3 tests/test_json.py
	python3 tests/test_verbose.py

# python's Decompilation of the corpus (pypy, a few minutes), for
# tests/test_json.py
json-expected:
	mkdir -p build/json_expected
	for f in tests/corpus/*.hex; do n=$$(basename $$f .hex); \
	  [ -f build/json_expected/$$n.pickle ] || PYTHONPATH=$(PANORAMIX_REPO) PYTHONINTMAXSTRDIGITS=0 \
	    $(PANORAMIX_PYTHON) tests/gen_json_expected.py $$f build/json_expected/$$n.pickle; done

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

clean:
	rm -rf build

.PHONY: all clean check json-expected verbose-expected
