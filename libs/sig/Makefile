NAME    := sig
ARCHIVE := lib$(NAME).a

# syscall/ holds direct kernel wrappers plus their shared
# syscall.inc header. util/ will land here in v1.1+ once the
# archive grows composed helpers.
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

# -I .. lets the wrappers %include the shared syscall-common.inc
# up in libs/. -I syscall/ resolves the archive's own syscall.inc.
# The dependency on syscall.inc forces every wrapper to rebuild
# when the shared header changes.
syscall/%.o: syscall/%.asm syscall/syscall.inc
	nasm $(NASM_FLAGS) -I .. -I syscall/ $< -o $@

# Smoke-test builds the archive plus libasm.a (for panic in
# the sig-smoke fail path) and runs the harness. Invoked via
# bash so no exec bit is required.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
