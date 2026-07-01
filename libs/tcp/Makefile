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

.PHONY: all build clean

all: $(ARCHIVE)

build: $(OBJS)

$(ARCHIVE): $(OBJS)
	ar rcs $(ARCHIVE) $(OBJS)

%.o: %.asm
	nasm $(NASM_FLAGS) $< -o $@

clean:
	rm -f $(OBJS) $(ARCHIVE)
