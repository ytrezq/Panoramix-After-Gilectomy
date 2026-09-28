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

all: build/panasm build/panoramix_asm$(PY_EXT)

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

clean:
	rm -rf build

.PHONY: all clean
