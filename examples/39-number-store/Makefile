NAME    := number-store
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# libio for file_read_all + file_write_all + munmap; libstr for
# atoi + itoa + strchr. Order does not matter since the two
# archives are independent.
LIBS    := ../../libs/io/libio.a ../../libs/str/libstr.a

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
	$(MAKE) -C ../../libs/str

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
