NAME    := sock
ARCHIVE := lib$(NAME).a

# syscall/ holds the direct kernel-syscall wrappers plus their
# shared syscall.inc header. inet/ holds the pure-computation
# helpers from <arpa/inet.h> — byte-order and text↔binary
# routines that never enter the kernel.
SYSCALL_SRCS := $(wildcard syscall/*.asm)
INET_SRCS    := $(wildcard inet/*.asm)
SRCS         := $(SYSCALL_SRCS) $(INET_SRCS)
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
	nasm $(NASM_FLAGS) -I syscall/ $< -o $@

# inet/ helpers are self-contained — no shared header, no syscall.
inet/%.o: inet/%.asm
	nasm $(NASM_FLAGS) $< -o $@

# Smoke-test the socket path end to end: build this archive and
# libasm.a, then run the loopback client/server harness. Requires
# python3. Invoked via bash so no exec bit is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/tcp-smoke test/tcp-smoke.o
