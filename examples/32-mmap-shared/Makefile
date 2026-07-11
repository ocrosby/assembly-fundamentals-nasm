NAME    := mmap-shared
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# First example to link libio and libproc on the same ld line.
# libio supplies mmap and munmap; libproc supplies fork and
# wait4. Neither archive references symbols in the other, so
# the left-to-right scan order does not matter.
LIBS    := ../../libs/io/libio.a ../../libs/proc/libproc.a

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
	$(MAKE) -C ../../libs/io
	$(MAKE) -C ../../libs/proc

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
