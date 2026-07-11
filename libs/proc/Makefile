NAME    := proc
ARCHIVE := lib$(NAME).a

# syscall/ holds the direct kernel-syscall wrappers plus their
# shared syscall.inc header. util/ (future) will hold composed
# helpers — for example, spawn_wait(argv) combining fork +
# execve + wait4 into a single call.
SYSCALL_SRCS := $(wildcard syscall/*.asm)
SRCS         := $(SYSCALL_SRCS)
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

# Smoke-test the archive end to end. Invoked via bash so no exec
# bit is required on run.sh.
test: $(ARCHIVE)
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o test/c-smoke
