NAME    := asm
ARCHIVE := lib$(NAME).a

SRCS    := print-string.asm print-int.asm sys-exit.asm
OBJS    := $(SRCS:.asm=.o)

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
NASM_FLAGS := -f macho64 -DMACOS
else
NASM_FLAGS := -f elf64
endif

.PHONY: all build clean

all: $(ARCHIVE)

build: $(OBJS)

$(ARCHIVE): $(OBJS)
	ar rcs $(ARCHIVE) $(OBJS)

%.o: %.asm
	nasm $(NASM_FLAGS) $< -o $@

clean:
	rm -f $(OBJS) $(ARCHIVE)
