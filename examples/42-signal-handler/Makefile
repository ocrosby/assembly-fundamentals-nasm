NAME    := signal-handler
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# libio for pipe, libsig for sigaction (and the
# platform-specific sig_restorer trampoline pulled in only on
# Linux via extern). libsig's syscall.inc supplies SIG_IGN,
# SIGPIPE, SA_RESTORER, and the struct sigaction offsets.
LIBS    := ../../libs/io/libio.a ../../libs/sig/libsig.a

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
	$(MAKE) -C ../../libs/sig

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) -I ../../libs -I ../../libs/sig/syscall $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
