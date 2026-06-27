# Async FIFO Interview Guide

This guide turns the repository into a focused interview review path. It is
not a replacement for the tutorial or RTL docs; it is a checklist of the ideas
you should be able to explain aloud, then point to in code.

For a deeper first pass, read [Async FIFO Step-by-Step Tutorial](tutorial.md)
and [Cummings-style FIFO mapping](cummings_mapping.md).

## Core Story

A strong async FIFO answer should land on this sentence:

```text
Data crosses through dual-clock RAM; control crosses as registered Gray
pointers; full and empty are generated locally and conservatively.
```

In this repository:

| Idea | RTL location | What to say |
|---|---|---|
| Local binary pointers | `rtl/core/wptr_full.v`, `rtl/core/rptr_empty.v` | Binary is used for incrementing, addressing, and occupancy estimates. |
| Extra pointer bit | `rtl/core/async_fifo_core.v` | Low bits address RAM; the extra bit distinguishes full from empty after wrap. |
| Gray pointers | `wptr_gray`, `rptr_gray` | Adjacent pointer steps change one bit before synchronization. |
| Two-flop synchronizers | `rtl/core/sync_w2r.v`, `rtl/core/sync_r2w.v` | The remote pointer is synchronized before local flag logic uses it. |
| Full equation | `wfull_next` in `wptr_full.v` | Next write Gray pointer equals synchronized read pointer with the two MSBs inverted. |
| Empty equation | `rempty_next` in `rptr_empty.v` | Next read Gray pointer equals synchronized write pointer. |
| `rd_valid` | `rtl/core/async_fifo_core.v` | Synchronous RAM read data is qualified by a read-domain valid pulse. |
| CDC constraints | `constraints/xilinx/async_fifo.xdc`, `docs/cdc_constraints.md` | Gray coding does not remove the need for bus-skew or max-delay constraints. |

## Questions to Practice

### Why not synchronize binary pointers?

Binary increments can toggle multiple bits. A destination clock can sample a
mixed value that was never a real pointer. This can corrupt `full`, `empty`, or
occupancy. This repo keeps binary local and synchronizes registered Gray
pointers instead.

Read:

- [Binary Pointer Crossing](common_mistakes/binary_pointer_crossing.md)
- [Cummings-style FIFO mapping](cummings_mapping.md#binary-locally-gray-across-the-boundary)

### Why does the pointer need one extra bit?

With only RAM address bits, equal write and read addresses could mean empty or
full. The extra bit records wrap state. It lets the design distinguish "same
address, same wrap" from "same address, one full lap apart."

Read:

- [Cummings-style FIFO mapping](cummings_mapping.md#pointer-width-and-the-extra-bit)

### How are `full` and `empty` generated?

`empty` is generated in the read domain by comparing the next read Gray
pointer with the synchronized write Gray pointer. `full` is generated in the
write domain by comparing the next write Gray pointer with the synchronized
read Gray pointer with the two MSBs inverted.

The "next pointer" style makes registered flags describe whether the next
local transfer can be accepted.

Read:

- [Cummings-style FIFO mapping](cummings_mapping.md#empty-generation)
- [Cummings-style FIFO mapping](cummings_mapping.md#full-generation)

### Why are flags conservative?

Each side sees the remote pointer after synchronizer latency. A read can free
space before the write domain sees it; a write can add data before the read
domain sees it. Conservative flag deassertion is safe: it may delay a legal
transfer, but it must not permit overflow or underflow.

Read:

- [Wrong Full/Empty Assumptions](common_mistakes/wrong_full_empty_assumptions.md)
- [Interface and Timing](interface.md#advanced-status-signals)

### What does `rd_valid` mean?

For standard `async_fifo`, `rd_en && !empty` accepts a read request. The RAM
has a synchronous read port, so `rd_valid` marks the cycle where `rd_data`
contains the returned word. Do not sample `rd_data` from `rd_en` alone.

FWFT mode is different: `rd_valid` is a level meaning a word is already
visible, and `rd_en && rd_valid` pops it.

Read:

- [Waveform Gallery](waveform_gallery.md)
- [FWFT / Fallthrough Design Notes](fwft_design.md)

### Why are Gray-bus constraints still needed?

Gray code is a logical coding property. It does not guarantee routed arrival
time matching. A target project still needs timing constraints and report
review for the Gray-pointer paths into the first synchronizer stage.

Read:

- [Missing Gray-Bus Constraints](common_mistakes/missing_gray_bus_constraints.md)
- [CDC and Timing Constraints](cdc_constraints.md)

### What does formal verification prove here?

The formal harnesses prove bounded, parameter-sampled properties: pointer
movement, no overflow through blocked writes, no underflow through blocked
reads, ordering, `rd_valid` alignment, reset release, FWFT behavior, and
wrapper contracts. They do not replace target STA/CDC sign-off.

Read:

- [Formal Verification Guide](formal_verification.md)
- [Formal Summary](evidence/formal_summary.md)

## Fast Review Route

For a 30-minute review:

1. Read [Waveform Gallery](waveform_gallery.md).
2. Read [Cummings-style FIFO mapping](cummings_mapping.md) through full/empty.
3. Skim [Common Async FIFO Mistakes](common_mistakes/README.md).
4. Open `rtl/core/wptr_full.v` and `rtl/core/rptr_empty.v`.
5. Run `make smoke`.

For a deeper review:

1. Run `make tutorial` and inspect `build/tutorial_async_fifo.vcd`.
2. Read [Interface and Timing](interface.md).
3. Read [Formal Verification Guide](formal_verification.md).
4. Read [CDC and Timing Constraints](cdc_constraints.md).
5. Run relevant tests or formal tasks from [Evidence Center](evidence/README.md).
