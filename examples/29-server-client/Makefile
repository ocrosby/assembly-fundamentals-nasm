NAME    := server-client
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# First example to link against two archives at once — libsock
# supplies the socket / bind / listen / accept / connect / read
# / write / close / getsockname wrappers, libproc supplies fork
# and wait4. The static-archive scan order is left-to-right;
# neither archive references symbols in the other, so the
# order does not matter here.
LIBS    := ../../libs/sock/libsock.a ../../libs/proc/libproc.a

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

# Ensure both archives exist. `make -C` is idempotent — a
# fresh clone that has never touched libs/sock or libs/proc
# still builds cleanly.
libs $(LIBS):
	$(MAKE) -C ../../libs/sock
	$(MAKE) -C ../../libs/proc

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
