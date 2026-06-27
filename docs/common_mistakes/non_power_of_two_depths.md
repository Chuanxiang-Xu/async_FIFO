# Non-Power-of-Two Depths

## Tempting Idea

Set FIFO depth to any convenient number, such as 24, 100, or 1000 entries.
The RAM can be sized that way, so the pointer logic should be able to wrap at
that value too.

## Why Simple Simulation May Pass

A short test may never reach wraparound. Another test may write and read at
nearly the same rate, so the pointer sequence stays far away from the
non-power-of-two boundary.

That can hide bugs in full detection, empty detection, and Gray-code
adjacency at the wrap point.

## Hardware Risk

The conventional reflected-Gray pointer scheme used here assumes a
power-of-two circular sequence. The low pointer bits index a `2**ADDR_WIDTH`
RAM, and the extra pointer bit distinguishes empty from full after wrap.

For full detection, the write side compares its next Gray pointer against the
synchronized read pointer with the two most significant bits inverted. That
relationship depends on the power-of-two reflected-Gray sequence.

Arbitrary-depth wrap can break the one-bit adjacent transition property or the
full/empty equations unless the encoding, comparisons, constraints, tests, and
formal harnesses are redesigned together.

## Correct Approach

Use a power-of-two core depth:

```text
DEPTH = 2 ** ADDR_WIDTH
```

If the system needs a logical non-power-of-two capacity, common options are:

- use the next larger power-of-two FIFO and limit traffic at a higher layer;
- add a carefully verified wrapper-level capacity policy;
- use a vendor FIFO IP that explicitly supports the required depth and target.

Do not change only the RAM depth while leaving the pointer algorithm
unchanged.

## Where This Repo Handles It

- `rtl/core/async_fifo_core.v` uses `ADDR_WIDTH` for a power-of-two RAM depth
  and `ADDR_WIDTH + 1` pointer width.
- `rtl/core/wptr_full.v` implements the two-MSB-invert full test for the
  reflected-Gray pointer sequence.
- `rtl/wrappers/async_fifo_width_conv.v` and
  `rtl/wrappers/async_fifo_stream.v` intentionally keep the core depth as a
  power of two.
- `scripts/check_parameters.sh` verifies unsupported parameter combinations
  fail clearly.
- [Known Limits](../evidence/known_limits.md) keeps the depth boundary visible
  for users and release notes.
