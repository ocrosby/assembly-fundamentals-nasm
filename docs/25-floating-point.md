# Floating Point

Scalar single- and double-precision arithmetic on x86-64 uses the SSE
unit — the same 128-bit `xmm` registers that also carry SIMD packed
data. The integer `mov`/`add`/`sub`/`mul` from earlier chapters do
not touch floating-point values; you need a separate vocabulary.

## The xmm registers

Sixteen registers, `xmm0` through `xmm15`, each 128 bits wide. Scalar
work uses only the low 32 bits (`float`) or low 64 bits (`double`);
the upper bits stay put but are ignored. There is no partial-register
zeroing rule — write to `xmm0.d` and `xmm0.high` is unchanged.

## Scalar data movement

| Type    | Load / store from memory | Register-to-register |
|---------|--------------------------|----------------------|
| single  | `movss`                  | `movss`              |
| double  | `movsd`                  | `movsd`              |

Loading a constant from `.rodata`:

```nasm
default rel

section .rodata
pi:   dq 3.14159265358979
half: dd 0.5

section .text
    movsd xmm0, [pi]              ; xmm0.low64 = 3.14159...
    movss xmm1, [half]            ; xmm1.low32 = 0.5
```

NASM understands floating-point literals directly: `dq 3.14` emits an
IEEE-754 `double`, `dd 0.5` emits a `float`.

## Arithmetic

Every scalar op comes in `ss` (single) and `sd` (double) forms:

```nasm
addss xmm0, xmm1                  ; xmm0.s = xmm0.s + xmm1.s
addsd xmm0, xmm1                  ; xmm0.d = xmm0.d + xmm1.d

subss / subsd
mulss / mulsd
divss / divsd
sqrtss / sqrtsd
```

Two-operand form: destination first, source second. Upper bits of
the destination are preserved.

## Comparison

`ucomiss` / `ucomisd` set the integer flags (`ZF`, `PF`, `CF`) after
a floating-point compare. Pair with the *unsigned* conditional jumps
because the FP encoding uses the same three flags an unsigned integer
compare would:

| Meaning      | Jump   |
|--------------|--------|
| `a > b`      | `ja`   |
| `a >= b`     | `jae`  |
| `a < b`      | `jb`   |
| `a <= b`     | `jbe`  |
| `a == b`     | `je`   |
| unordered    | `jp`   |

## Integer ↔ float conversion

- `cvtsi2ss xmm, r`  — signed integer → single.
- `cvtsi2sd xmm, r`  — signed integer → double.
- `cvttss2si r, xmm` — single → integer (truncating).
- `cvttsd2si r, xmm` — double → integer (truncating).

## System V AMD64 calling convention

- Floating-point args: `xmm0` … `xmm7` (up to eight).
- Floating-point return: `xmm0`.
- No callee-saved `xmm` registers — treat them all as scratch across
  a `call`.
- When calling a variadic C function (e.g., `printf`) with FP args,
  set `al` to the count of `xmm` args before the call:
  `mov al, 1` for one `%f`.

## Packed / SIMD variants

Every scalar `ss`/`sd` instruction has a matching packed form: `ps`
(four floats at once) and `pd` (two doubles). Same encoding, wider
operand: `addps`, `mulpd`, `sqrtps`, and so on. Chapter left to a
future guide.

## Pitfalls

- `movsd` between two `xmm` registers preserves the upper 64 bits;
  `movaps xmm, xmm` copies all 128. Use the latter when you actually
  want a full-register clone.
- `xorps xmm, xmm` is the canonical zero — faster than `movss` from a
  memory literal.
- Denormals and NaN comparisons follow IEEE-754 rules; `ucomiss` sets
  `PF=1` on unordered.

## See also

- [Registers](04-registers.md) — the general-purpose register story.
- [Cheat Sheet](20-cheat-sheet.md) — integer-side quick reference.
- [Index](README.md)
