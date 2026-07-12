NAME    := http
ARCHIVE := lib$(NAME).a

# libhttp implements the HTTP/1.1 wire format (RFC 9112) and
# composes libstr (byte scans), libbuf (message accumulation),
# libtime (Date: header formatting), libio, libsock, and
# libresolv. Nothing here owns a raw syscall.
#
# Flat layout at the archive root, matching libresolv's pattern
# for archives that compose from others. Split into parse/ +
# emit/ + util/ subdirectories only if the file count grows
# past ~10.
SRCS := parse-request-line.asm

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

# Every source %include's http.inc for constants and struct
# offsets — declare the dependency explicitly so a change to
# the header forces every wrapper to rebuild.
%.o: %.asm http.inc
	nasm $(NASM_FLAGS) -I .. $< -o $@

# Smoke test the archive end to end. Needs libstr for memchr /
# memcmp and libasm for panic on the fail path.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	$(MAKE) -C ../str
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
