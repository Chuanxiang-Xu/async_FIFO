# Wrong Full/Empty Assumptions

## Tempting Idea

Treat `full`, `empty`, `almost_full`, `almost_empty`, `wr_used`, and `rd_used`
as one instantaneous global FIFO state. If the write side just wrote data,
the read side should immediately stop being empty. If the read side just
freed space, the write side should immediately stop being full.

## Why Simple Simulation May Pass

When clocks are close together or traffic is sparse, the synchronization delay
may be hard to notice. A testbench may also wait several cycles between writes
and reads, making the flags appear almost immediate.

That can hide the real async FIFO contract: each side only knows the remote
pointer after synchronization latency.

## Hardware Risk

The flags are intentionally local. The read domain generates `empty` from the
read pointer and the synchronized write pointer. The write domain generates
`full` from the write pointer and the synchronized read pointer.

This means flag deassertion can be conservative:

- the FIFO may already contain data while the read side still sees `empty`;
- the FIFO may already have space while the write side still sees `full`.

Using advisory or local status as if it were a global transaction guarantee can
create underflow, overflow, or protocol bugs at wrapper boundaries.

## Correct Approach

Use the documented transfer qualifier for the selected interface:

| Interface style | Data moves when |
|---|---|
| Standard request FIFO | `wr_rstn && wr_en && !full`; `rd_rstn && rd_en && !empty` |
| FWFT FIFO | `rd_valid` means data is visible; `rd_en && rd_valid` pops it |
| Stream FIFO | `wr_valid && wr_ready`; `rd_valid && rd_ready` |

Treat almost flags and occupancy counts as local flow-control hints, not exact
global snapshots.

## Where This Repo Handles It

- `rtl/core/wptr_full.v` generates `full` in the write domain.
- `rtl/core/rptr_empty.v` generates `empty` in the read domain.
- `docs/interface.md` defines transfer qualification and status semantics.
- `formal/core_formal.sv` checks ordering, `rd_valid`, and occupancy bounds.
- `test/fifo_assertions.sv` and `test/stream_assertions.sv` catch common
  transfer-qualification mistakes in simulation.

For precise public behavior, see [Interface and Timing](../interface.md).
