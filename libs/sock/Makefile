NAME    := sock
ARCHIVE := lib$(NAME).a

# Connection lifecycle.
SRCS := \
    socket.asm \
    bind.asm \
    listen.asm \
    accept.asm \
    connect.asm \
    shutdown.asm \
    close.asm

OBJS := $(SRCS:.asm=.o)

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

# Every wrapper %include's syscall.inc, so rebuild all .o files
# when the shared header changes.
%.o: %.asm syscall.inc
	nasm $(NASM_FLAGS) $< -o $@

# Smoke-test the socket path end to end: build this archive and
# libasm.a, then run the loopback client/server harness. Requires
# python3. Invoked via bash so no exec bit is required on run.sh.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/tcp-smoke test/tcp-smoke.o
