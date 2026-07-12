; format_time_rfc1123(seconds: rdi, out: rsi) -> void
;
; Write the RFC 1123 (§5.2.14) / RFC 7231 (§7.1.1.1) fixed-form
; date string
;
;     "Sun, 06 Nov 1994 08:49:37 GMT"
;
; — exactly 29 bytes, no trailing NUL — into the caller's
; buffer at `out`, given `seconds` since the Unix epoch (UTC).
;
; Arguments:
;   rdi = seconds     u64 Unix time. No timezone handling —
;                     this is always UTC.
;   rsi = out         u8[29] buffer. Untouched past byte 28.
;
; Return: none. rax is 0 on exit; callee-saved registers
; preserved per the archive convention.
;
; No syscalls. Pure integer arithmetic. Motivated by the HTTP
; `Date:` response header, but the output is exactly the shape
; that RFC 5322 (§3.3), RFC 5321 (SMTP), and every "log a wall
; clock as a fixed-width string" caller wants. libtime keeps
; the formatter timezone-neutral so it composes with any
; caller's clock source.
;
; Algorithm: Howard Hinnant's civil_from_days
; (http://howardhinnant.github.io/date_algorithms.html) turns
; a day count since the Unix epoch into (year, month, day) in
; branchless integer arithmetic — no tables, no month-length
; loop, no leap-year branch cascade. Weekday is
; `(days + 4) mod 7` since 1970-01-01 fell on a Thursday
; (index 4 with Sunday = 0).
;
; Overflow: `seconds` is treated as unsigned. Values that
; exceed the Hinnant algorithm's domain — beyond roughly the
; year 292 277 026 596 — will still produce a syntactically
; valid 29-byte string, but the year field will exceed four
; digits and overflow into the following bytes. Callers who
; care about a bound on the output width clamp `seconds`
; before the call.

%include "syscall.inc"

default rel

global format_time_rfc1123

section .rodata
; Three-character abbreviations, packed. Indexed by
; `(days + 4) mod 7` — the standard Sunday-based convention
; RFC 1123 requires.
wday_names: db "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
; Three-character month abbreviations, indexed by month - 1.
mon_names:  db "Jan", "Feb", "Mar", "Apr", "May", "Jun"
            db "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"

section .text

format_time_rfc1123:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov  r14, rsi                    ; r14 = out (survives every call)

    ; Split seconds into (days, seconds_in_day).
    mov  rax, rdi
    xor  edx, edx
    mov  rcx, 86400
    div  rcx                         ; rax = days, rdx = 0..86399
    mov  r12, rax                    ; r12 = days since epoch
    mov  rbx, rdx                    ; rbx = seconds in day

    ; ---- Weekday name → out[0..2] --------------------------
    ; weekday = (days + 4) mod 7. 1970-01-01 was Thursday.
    lea  rax, [r12 + 4]
    xor  edx, edx
    mov  rcx, 7
    div  rcx                         ; rdx = weekday (0..6)

    lea  rcx, [rel wday_names]
    add  rcx, rdx                    ; base + wday
    lea  rcx, [rcx + rdx * 2]        ; + 2*wday → base + 3*wday
    mov  ax, [rcx]
    mov  [r14], ax
    mov  al, [rcx + 2]
    mov  [r14 + 2], al

    ; ", " at out[3..4]. Little-endian word: ',' then ' '.
    mov  word [r14 + 3], (' ' << 8) | ','

    ; ---- Hinnant civil_from_days --------------------------
    ; z = days + 719468
    add  r12, 719468

    ; era = z / 146097, doe = z mod 146097
    mov  rax, r12
    xor  edx, edx
    mov  rcx, 146097
    div  rcx
    mov  r15, rax                    ; r15 = era
    mov  r13, rdx                    ; r13 = doe (0..146096)

    ; yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    mov  rax, r13
    xor  edx, edx
    mov  rcx, 1460
    div  rcx
    mov  r8, rax                     ; r8 = doe/1460

    mov  rax, r13
    xor  edx, edx
    mov  rcx, 36524
    div  rcx
    mov  r9, rax                     ; r9 = doe/36524

    mov  rax, r13
    xor  edx, edx
    mov  rcx, 146096
    div  rcx
    mov  rcx, rax                    ; rcx = doe/146096

    mov  rax, r13
    sub  rax, r8
    add  rax, r9
    sub  rax, rcx
    xor  edx, edx
    mov  rcx, 365
    div  rcx                         ; rax = yoe (0..399)
    mov  r8, rax                     ; r8 = yoe

    ; y = yoe + era * 400
    mov  rax, r15
    mov  rcx, 400
    mul  rcx
    add  rax, r8
    push rax                         ; stash y — the mp/day math will
                                     ; clobber every scratch reg

    ; doy = doe - (365*yoe + yoe/4 - yoe/100)
    mov  rax, r8
    xor  edx, edx
    mov  rcx, 100
    div  rcx
    mov  r9, rax                     ; r9 = yoe/100

    mov  rax, r8
    shr  rax, 2                      ; yoe/4 — yoe < 400, unsigned works

    mov  rcx, r8
    imul rcx, 365
    add  rcx, rax
    sub  rcx, r9                     ; 365*yoe + yoe/4 - yoe/100

    mov  rax, r13
    sub  rax, rcx                    ; doy (0..365)
    mov  r13, rax                    ; r13 = doy

    ; mp = (5*doy + 2) / 153
    lea  rax, [r13 * 4 + r13]        ; 5*doy
    add  rax, 2
    xor  edx, edx
    mov  rcx, 153
    div  rcx
    mov  r8, rax                     ; r8 = mp (0..11)

    ; d = doy - (153*mp + 2)/5 + 1
    mov  rax, r8
    mov  rcx, 153
    mul  rcx
    add  rax, 2
    xor  edx, edx
    mov  rcx, 5
    div  rcx
    mov  rcx, r13
    sub  rcx, rax
    inc  rcx                         ; rcx = day (1..31)
    mov  r9, rcx                     ; r9 = day

    ; Recover y and decide (m, y_calendar):
    ;   mp <  10 → m = mp + 3, y unchanged
    ;   mp >= 10 → m = mp - 9, y += 1  (January/February belong
    ;                                    to the next calendar year)
    pop  rax                         ; y (Hinnant civil-year)
    cmp  r8, 10
    jb   .mp_lo
    sub  r8, 9
    inc  rax
    jmp  .have_ym
.mp_lo:
    add  r8, 3
.have_ym:
    mov  r10, rax                    ; r10 = year (4-digit)
    mov  r11, r8                     ; r11 = month (1..12)

    ; ---- Day of month → out[5..6] --------------------------
    mov  rax, r9
    xor  edx, edx
    mov  rcx, 10
    div  rcx
    add  al, '0'
    mov  [r14 + 5], al
    add  dl, '0'
    mov  [r14 + 6], dl

    mov  byte [r14 + 7], ' '

    ; ---- Month name → out[8..10] ---------------------------
    lea  rcx, [rel mon_names]
    mov  rax, r11
    dec  rax                         ; index = month - 1
    add  rcx, rax                    ; base + (month-1)
    lea  rcx, [rcx + rax * 2]        ; + 2*(month-1) → base + 3*(month-1)
    mov  ax, [rcx]
    mov  [r14 + 8], ax
    mov  al, [rcx + 2]
    mov  [r14 + 10], al

    mov  byte [r14 + 11], ' '

    ; ---- Year → out[12..15] --------------------------------
    ; Emit four digits, most significant first.
    mov  rax, r10
    xor  edx, edx
    mov  rcx, 1000
    div  rcx
    add  al, '0'
    mov  [r14 + 12], al
    mov  rax, rdx
    xor  edx, edx
    mov  rcx, 100
    div  rcx
    add  al, '0'
    mov  [r14 + 13], al
    mov  rax, rdx
    xor  edx, edx
    mov  rcx, 10
    div  rcx
    add  al, '0'
    mov  [r14 + 14], al
    add  dl, '0'
    mov  [r14 + 15], dl

    mov  byte [r14 + 16], ' '

    ; ---- HH:MM:SS → out[17..24] ---------------------------
    ; hour = seconds_in_day / 3600
    ; rem  = seconds_in_day mod 3600
    mov  rax, rbx
    xor  edx, edx
    mov  rcx, 3600
    div  rcx
    mov  r8, rax                     ; r8 = hour

    ; minute = rem / 60, second = rem mod 60
    mov  rax, rdx
    xor  edx, edx
    mov  rcx, 60
    div  rcx
    mov  r9, rax                     ; r9 = minute
    mov  r10, rdx                    ; r10 = second

    ; HH at out[17..18]
    mov  rax, r8
    xor  edx, edx
    mov  rcx, 10
    div  rcx
    add  al, '0'
    mov  [r14 + 17], al
    add  dl, '0'
    mov  [r14 + 18], dl
    mov  byte [r14 + 19], ':'

    ; MM at out[20..21]
    mov  rax, r9
    xor  edx, edx
    mov  rcx, 10
    div  rcx
    add  al, '0'
    mov  [r14 + 20], al
    add  dl, '0'
    mov  [r14 + 21], dl
    mov  byte [r14 + 22], ':'

    ; SS at out[23..24]
    mov  rax, r10
    xor  edx, edx
    mov  rcx, 10
    div  rcx
    add  al, '0'
    mov  [r14 + 23], al
    add  dl, '0'
    mov  [r14 + 24], dl

    ; " GMT" at out[25..28] — packed little-endian dword.
    mov  dword [r14 + 25], (('T' << 24) | ('M' << 16) | ('G' << 8) | ' ')

    xor  eax, eax
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    ret
