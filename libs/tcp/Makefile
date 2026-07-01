NAME    := tcp
ARCHIVE := lib$(NAME).a

SRCS    := tcp-connect.asm tcp-send.asm tcp-recv.asm tcp-close.asm
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

# Smoke-test the socket path end to end: build this archive and
# libasm.a, then run the loopback client/server harness. Requires
# python3. Invoked via bash so no exec bit is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/tcp-smoke test/tcp-smoke.o
