NAME    := io
ARCHIVE := lib$(NAME).a

# syscall/ holds the direct kernel-syscall wrappers plus their
# shared syscall.inc header. util/ (v1.1) holds pure-computation
# helpers that compose one or more syscalls into a portable API
# — for example io_size wraps fstat and extracts st_size at
# the platform-specific offset so callers never see the raw
# struct layout.
SYSCALL_SRCS := $(wildcard syscall/*.asm)
UTIL_SRCS    := $(wildcard util/*.asm)
SRCS         := $(SYSCALL_SRCS) $(UTIL_SRCS)
OBJS         := $(SRCS:.asm=.o)

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
NASM_FLAGS := -f macho64 -DMACOS
else
NASM_FLAGS := -f elf64
endif

.PHONY: all build test clean

all: $(ARCHIVE)

build: $(OBJS)

$(ARCHIVE): $(OBJS)
	ar rcs $(ARCHIVE) $(OBJS)

# Syscall wrappers %include "syscall.inc". -I syscall/ lets NASM
# resolve the include regardless of the source-file working
# directory. The dependency on syscall.inc forces every wrapper
# to rebuild when the shared header changes.
syscall/%.o: syscall/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# util/ objects also use syscall.inc (for ST_SIZE_OFF and
# STATBUF_SIZE), so they share the same -I flag and dependency.
util/%.o: util/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# Smoke-test the file-syscall path end to end: build this archive
# and its co-dependencies, then run the harness. libsock (for
# read/write/close in the smokes), libasm (panic in .fail), and
# libstr (memcmp in iov-smoke). Invoked via bash so no exec bit
# is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../sock
	$(MAKE) -C ../asm
	$(MAKE) -C ../str
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
