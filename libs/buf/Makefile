NAME    := buf
ARCHIVE := lib$(NAME).a

# libbuf owns no raw syscalls: it composes mmap and munmap from
# libio. Sources sit flat at the archive root, matching the
# libresolv layout (also composes from another archive). If the
# file count ever grows past ~10 files, split by concern the way
# libsock did (util/, syscall/).
SRCS := \
    buf-init.asm    \
    buf-free.asm    \
    buf-reserve.asm \
    buf-append.asm  \
    buf-reset.asm

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

# Every source %include's buf.inc for BUF_SIZE / BUF_*_OFF /
# mmap flags — declare the dependency explicitly so a change to
# the header forces every wrapper to rebuild.
%.o: %.asm buf.inc
	nasm $(NASM_FLAGS) -I .. $< -o $@

# Smoke test the archive end to end. Needs libio for mmap /
# munmap (which libbuf calls internally) and libasm for the
# panic used in the fail path of the smoke.
test: $(ARCHIVE)
	$(MAKE) -C ../asm
	$(MAKE) -C ../io
	bash ./test/run.sh

clean:
	rm -f $(OBJS) $(ARCHIVE) test/*-smoke test/*-smoke.o
