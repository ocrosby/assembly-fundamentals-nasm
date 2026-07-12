; buf.inc — struct offsets and mmap flags for libbuf.
;
; A `struct buf` is a caller-allocated 24-byte block. libbuf
; never allocates the struct itself; the caller reserves it in
; `.bss` (`resb BUF_SIZE`) or on the stack. libbuf owns only the
; mmap'd data region referenced from the struct.
;
;   +0    data   u64   pointer to mmap'd bytes, 0 before init /
;                      after free
;   +8    len    u64   used-byte count, 0 <= len <= cap
;   +16   cap    u64   mmap'd capacity in bytes, multiple of
;                      BUF_PAGE_SIZE
;
; The grow strategy in buf_reserve doubles the current cap and
; rounds up to BUF_PAGE_SIZE (4096). Consumers get amortized
; O(1) per byte appended; the page-granularity rounding keeps
; mmap happy on both platforms without a syscall to query the
; runtime page size.

%ifndef BUF_INC
%define BUF_INC 1

%define BUF_DATA_OFF          0
%define BUF_LEN_OFF           8
%define BUF_CAP_OFF          16
%define BUF_SIZE             24

; 4096 works on x86-64 Linux and on macOS Intel / macOS Apple
; Silicon under Rosetta 2. Native Apple Silicon uses 16 KiB
; pages, but this repo assembles for x86-64 only (see
; platform-priority.md), so 4096 is the correct constant here.
%define BUF_PAGE_SIZE      4096

%define BUF_PROT_READ_WRITE   3       ; PROT_READ | PROT_WRITE
%define BUF_MAP_PRIVATE       2

%ifdef MACOS
%define BUF_MAP_ANON     0x1000
%else
%define BUF_MAP_ANON       0x20
%endif

%define BUF_MAP_FLAGS   (BUF_MAP_PRIVATE | BUF_MAP_ANON)

%endif ; BUF_INC
