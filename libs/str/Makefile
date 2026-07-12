NAME    := str
ARCHIVE := lib$(NAME).a

# libstr is pure computation — no syscalls, no OS-specific paths.
# Everything sits in the top level of libs/str/ the same way
# libs/asm/ does. `asm/` predates libstr; the layouts converge.
SRCS    := memcpy.asm memset.asm memcmp.asm memchr.asm \
           strlen.asm strcmp.asm strncmp.asm strchr.asm strcpy.asm \
           strcasecmp.asm strncasecmp.asm \
           atoi.asm itoa.asm
OBJS    := $(SRCS:.asm=.o)

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

%.o: %.asm
	nasm $(NASM_FLAGS) $< -o $@

# Smoke-test builds the archive plus libasm.a (for panic) and
# runs the harness. Invoked via bash so no exec bit is needed.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
