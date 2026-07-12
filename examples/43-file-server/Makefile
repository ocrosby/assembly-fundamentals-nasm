NAME    := file-server
SRC     := $(NAME).asm
OBJ     := $(NAME).o
BIN     := $(NAME)

# libsock for socket/bind/listen/accept/connect/close/read/
# getsockname. libio for file_write_all + file_copy_stream.
# libproc for fork + wait4. Order does not matter — none of
# the archives call into each other.
LIBS    := ../../libs/sock/libsock.a ../../libs/io/libio.a ../../libs/proc/libproc.a

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
