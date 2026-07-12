NAME    := sig
ARCHIVE := lib$(NAME).a

# syscall/ holds direct kernel wrappers plus their shared
# syscall.inc header. util/ (v1.1+) holds pure-computation
# helpers — sigset bit manipulation for now.
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

# -I .. lets the wrappers %include the shared syscall-common.inc
# up in libs/. -I syscall/ resolves the archive's own syscall.inc.
# The dependency on syscall.inc forces every wrapper to rebuild
# when the shared header changes.
syscall/%.o: syscall/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# util/ objects use syscall.inc for SIGSET_BYTES, so they
# share the same -I flag and dependency.
util/%.o: util/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# Smoke-test builds the archive plus its co-dependencies.
# libasm for panic in .fail. libio (v1.2+) for sig-smoke's
# pipe wrapper in the SIG_IGN test path. Invoked via bash so
# no exec bit is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	$(MAKE) -C ../io
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
