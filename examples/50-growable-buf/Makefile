NAME    := growable-buf
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# libbuf resolves buf_init / buf_append / buf_free; libio
# resolves the mmap / munmap that libbuf calls internally.
# Left-to-right archive scan means references (libbuf) must
# come before definitions (libio).
LIBS    := ../../libs/buf/libbuf.a ../../libs/io/libio.a

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
NASM_FLAGS := -f macho64 -DMACOS
SDK        := $(shell xcrun -sdk macosx --show-sdk-path)
# `-w` silences a benign ld warning about nasm not emitting the LC_BUILD_VERSION load command.
LD         := ld -w -macos_version_min 11.0 -lSystem -syslibroot $(SDK)
else
NASM_FLAGS := -f elf64
LD         := ld
endif

.PHONY: all build link run clean libs

all: $(BIN)

build: $(OBJ)

link: $(BIN)

libs $(LIBS):
	$(MAKE) -C ../../libs/buf
	$(MAKE) -C ../../libs/io

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
