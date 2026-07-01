NAME    := shared-lib
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
NASM_FLAGS := -f macho64 -DMACOS
SDK        := $(shell xcrun -sdk macosx --show-sdk-path)
# `-w` silences a benign ld warning about nasm not emitting the LC_BUILD_VERSION load command.
LINK       := ld -w -macos_version_min 11.0 -lSystem -syslibroot $(SDK) $(OBJ) -o $(BIN)
else
NASM_FLAGS := -f elf64
# Use gcc as the linker driver on Linux. Its crt0 initializes libc,
# calls `main`, and calls `exit()` with `eax` as the status. Linking
# with plain `ld` would leave libc uninitialized and `puts` would
# crash on first use.
LINK       := gcc -no-pie $(OBJ) -o $(BIN)
endif

.PHONY: all build link run clean

all: $(BIN)

build: $(OBJ)

link: $(BIN)

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ)
	$(LINK)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
