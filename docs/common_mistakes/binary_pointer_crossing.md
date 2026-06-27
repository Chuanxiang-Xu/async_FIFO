# Binary Pointer Crossing

## Tempting Idea

Keep the FIFO write and read pointers in binary, then send each binary pointer
through a multi-bit synchronizer into the opposite clock domain. After all,
the destination only needs an approximate remote pointer for `full` or
`empty`.

## Why Simple Simulation May Pass

RTL simulation samples all bits deterministically. If the write pointer moves
from `3` to `4`, simulation sees one clean old value or one clean new value.
It does not model different arrival times, metastability resolution, or a
destination flop sampling some old bits and some new bits.

Many directed tests also use gentle traffic. They may avoid the pointer
transitions where several binary bits toggle at once.

## Hardware Risk

Binary pointers can change many bits on one increment:

```text
0011 -> 0100
```

If those bits cross an asynchronous boundary directly, the destination can
sample a mixed value that was never a real pointer. That can make the FIFO
believe it has space when it is full, believe data exists when it is empty, or
compute a wildly wrong occupancy view.

## Correct Approach

Keep binary pointers local for arithmetic and RAM addressing, but export a
registered Gray-coded pointer to the other domain. Adjacent reflected-Gray
values change by one bit, which limits what the destination can sample during
normal one-step pointer movement.

The destination must still synchronize the Gray pointer before using it in
`full` or `empty` logic.

## Where This Repo Handles It

- `rtl/core/wptr_full.v` keeps `wptr_bin` local and exports `wptr_gray`.
- `rtl/core/rptr_empty.v` keeps `rptr_bin` local and exports `rptr_gray`.
- `rtl/core/sync_w2r.v` synchronizes the write Gray pointer into the read
  domain.
- `rtl/core/sync_r2w.v` synchronizes the read Gray pointer into the write
  domain.
- `formal/pointer_formal.sv` checks that Gray pointers change by at most one
  bit per local pointer step.

For the complete map, see [Cummings-style FIFO mapping](../cummings_mapping.md).
