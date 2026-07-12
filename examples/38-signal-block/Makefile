NAME    := signal-block
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# libio for pipe, libsig for sigprocmask + sigpending +
# sig_zero/sig_add/sig_test. Order does not matter since the
# two archives are independent.
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

# signal-block.asm %include's libsig's syscall.inc for SIG_BLOCK,
# SIGPIPE, etc. -I ../../libs/sig/syscall lets nasm resolve it.
# -I ../../libs picks up the shared syscall-common.inc referenced
# by libsig's syscall.inc.
$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) -I ../../libs -I ../../libs/sig/syscall $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
