NAME    := resolv
ARCHIVE := lib$(NAME).a

# Flat layout: five sources at the top level. If the file count
# grows past ~10, split by concern (wire/, syscall/) the way
# libsock did.
SRCS := \
    wire-encode.asm \
    wire-decode.asm \
    random.asm \
    resolv-a.asm \
    hosts.asm \
    resolvconf.asm \
    hostname.asm

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

# Every source %include's syscall.inc, so the dependency is
# declared explicitly.
%.o: %.asm syscall.inc
	nasm $(NASM_FLAGS) $< -o $@

# Smoke-test the resolver path end to end: build this archive
# plus libsock (DNS transport + close + inet_pton4), libio
# (open + pread for /etc/hosts and /etc/resolv.conf), and
# libasm. Then run the harness.
test: $(ARCHIVE)
	$(MAKE) -C ../sock
	$(MAKE) -C ../io
	$(MAKE) -C ../asm
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
