NAME    := divmod
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

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

.PHONY: all build link run clean

all: $(BIN)

build: $(OBJ)

link: $(BIN)

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ)
	$(LD) $(OBJ) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
