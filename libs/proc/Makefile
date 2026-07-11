NAME    := proc
ARCHIVE := lib$(NAME).a

# syscall/ holds the direct kernel-syscall wrappers plus their
# shared syscall.inc header. util/ holds composed helpers —
# spawn_wait(path, argv, envp) combines fork + execve + wait4
# into a single call.
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
	nasm $(NASM_FLAGS) -I syscall/ $< -o $@

# util/ helpers compose syscall wrappers and also %include
# "syscall.inc" for the SYS_exit / SYS_execve constants used
# on the child-side exec failure path.
util/%.o: util/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I syscall/ $< -o $@

# Smoke-test the archive end to end. Invoked via bash so no exec
# bit is required on run.sh.
test: $(ARCHIVE)
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o test/c-smoke
