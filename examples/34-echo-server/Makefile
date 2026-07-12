NAME    := echo-server
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# socket, bind, listen, accept, connect, close, getsockname,
# read, and send_all all live in libsock. fork/wait4 live in
# libproc. memcmp (verifying the echoed "HELLO WORLD!") lives
# in libstr.
LIBS    := ../../libs/sock/libsock.a ../../libs/proc/libproc.a ../../libs/str/libstr.a

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
	$(MAKE) -C ../../libs/sock
	$(MAKE) -C ../../libs/proc
	$(MAKE) -C ../../libs/str

$(OBJ): $(SRC)
	nasm $(NASM_FLAGS) $(SRC) -o $(OBJ)

$(BIN): $(OBJ) $(LIBS)
	$(LD) $(OBJ) $(LIBS) -o $(BIN)

run: $(BIN)
	@./$(BIN); status=$$?; echo "exit=$$status"

clean:
	rm -f $(OBJ) $(BIN)
