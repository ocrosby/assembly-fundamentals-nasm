NAME    := fork-signal
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# libproc for fork/kill/wait4, libtime for sleep_ms, libsig for
# the SIGTERM constant that syscall.inc exposes (no runtime
# calls into libsig — the include just resolves the SIGTERM
# symbol at assembly time).
LIBS    := ../../libs/proc/libproc.a ../../libs/time/libtime.a

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
	$(MAKE) -C ../../libs/proc
	$(MAKE) -C ../../libs/time

# The source %include's libsig's syscall.inc for SIGTERM.
# -I ../../libs/sig/syscall lets nasm resolve it; -I ../../libs
# picks up the shared syscall-common.inc chain.
$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) -I ../../libs -I ../../libs/sig/syscall $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
