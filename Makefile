AS      = as
ASFLAGS = -I include --64 -g
CC      = cc
CFLAGS  = -O2 -fPIC -Wall
LDFLAGS = -Wl,-z,text -Wl,-z,noexecstack
LDLIBS  = -L/usr/lib/x86_64-linux-gnu -l:libgmp.so.10 -l:liblzma.so.5 -lpthread -lm
PY_INC  = $(shell python3 -c "import sysconfig; print(sysconfig.get_paths()['include'])")
PY_EXT  = $(shell python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")

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

clean:
	rm -rf build

.PHONY: all clean check
