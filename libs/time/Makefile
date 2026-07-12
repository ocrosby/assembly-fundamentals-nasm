NAME    := time
ARCHIVE := lib$(NAME).a

# syscall/ holds the direct kernel-syscall wrappers plus their
# shared syscall.inc header. util/ holds composed helpers that
# never enter the kernel and can be reused independently — for
# example `time_diff_us`, which computes a signed microsecond
# delta between two `struct timeval`s.
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

# util/ helpers %include "syscall.inc" for shared constants
# (TV_SEC_OFF / TV_USEC_OFF / TIMEVAL_SIZE) even though they
# never call the kernel.
util/%.o: util/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# Smoke-test the archive end to end. libasm.a joins the co-deps
# for time-smoke's panic call in the .fail path. Invoked via
# bash so no exec bit is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o test/c-smoke
