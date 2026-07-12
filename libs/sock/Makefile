NAME    := sock
ARCHIVE := lib$(NAME).a

# syscall/ holds the direct kernel-syscall wrappers plus their
# shared syscall.inc header. inet/ holds the pure-computation
# helpers from <arpa/inet.h> — byte-order and text↔binary
# routines that never enter the kernel. util/ (v1.1) holds
# composed helpers that string several syscalls together into a
# single call — for example server_bind_listen wraps socket +
# setsockopt + bind + listen.
SYSCALL_SRCS := $(wildcard syscall/*.asm)
INET_SRCS    := $(wildcard inet/*.asm)
UTIL_SRCS    := $(wildcard util/*.asm)
SRCS         := $(SYSCALL_SRCS) $(INET_SRCS) $(UTIL_SRCS)
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

# inet/ helpers are self-contained — no shared header, no syscall.
inet/%.o: inet/%.asm
	nasm $(NASM_FLAGS) $< -o $@

# util/ helpers compose syscall wrappers, so they include
# syscall.inc for the AF_INET / SIN_HEADER / SOL_SOCKET constants
# and the SYSCALL_* macros.
util/%.o: util/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# Smoke-test the socket path end to end: build this archive and
# libasm.a, then run the loopback client/server harness. Requires
# python3. Invoked via bash so no exec bit is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
