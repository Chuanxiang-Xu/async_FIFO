# Cummings-Style FIFO Mapping

This document maps the classic Cummings/Sunburst asynchronous FIFO mental
model to the RTL in this repository. It is meant to sit between the
step-by-step tutorial and the deeper implementation notes:

```text
tutorial -> Cummings mapping -> learning guide -> formal guide
```

The repository does not try to clone one paper line for line. It keeps the
same core ideas: local binary pointers, Gray-coded crossing pointers, an extra
wrap bit, two-flop pointer synchronizers, and local-domain `full`/`empty`
generation.

## Where the Ideas Live

| Cummings-style concept | This repository | Why it matters |
|---|---|---|
| Power-of-two circular storage | `fifo_mem`, indexed by `waddr` and `raddr` | Pointer low bits select the RAM entry; wrap is tracked separately. |
| Extra pointer bit | `[ADDR_WIDTH:0]` pointers in `async_fifo_core` | Distinguishes empty from full when RAM address bits are equal. |
| Local binary pointers | `wptr_bin` in `wptr_full`, `rptr_bin` in `rptr_empty` | Binary is simple for incrementing, addressing, and occupancy estimates. |
| Binary-to-Gray conversion | `(ptr_bin_next >> 1) ^ ptr_bin_next` | Only one bit changes per adjacent pointer step before synchronization. |
| Registered Gray source pointers | `wptr_gray`, `rptr_gray` | The synchronized object is a registered pointer, not combinational logic. |
| Pointer synchronizers | `sync_w2r`, `sync_r2w` | Pointers cross domains through two `ASYNC_REG` stages. |
| Empty test | `rptr_gray_next == wptr_gray_sync` | The read side is empty when the next read pointer catches the synchronized write pointer. |
| Full test | `wptr_gray_next == (rptr_gray_sync ^ FULL_MASK)` | The write side is full when the next write pointer is one complete wrap ahead of the synchronized read pointer. |
| Conservative flags | Registered `full` and `empty` in local domains | Synchronizer latency may delay flag deassertion, but must not allow overflow or underflow. |
| Payload storage is not synchronized bit-by-bit | `fifo_mem` | Data stays in dual-clock RAM; only pointers cross the clock boundary. |

## Pointer Width and the Extra Bit

The RAM has `2**ADDR_WIDTH` entries, so `waddr` and `raddr` use
`ADDR_WIDTH` bits:

```verilog
wire [ADDR_WIDTH-1:0] waddr;
wire [ADDR_WIDTH-1:0] raddr;
```

The FIFO pointers use one more bit:

```verilog
wire [ADDR_WIDTH:0] wptr_gray;
wire [ADDR_WIDTH:0] rptr_gray;
```

The low `ADDR_WIDTH` bits select the RAM address. The extra bit records which
wrap of the circular buffer the pointer is on. Without that bit, equal address
bits would be ambiguous: the FIFO could be empty or exactly full.

## Binary Locally, Gray Across the Boundary

Inside each local clock domain, the pointer is kept in binary form for simple
arithmetic:

```verilog
wptr_bin_next = wptr_bin + (winc && !wfull);
rptr_bin_next = rptr_bin + (rinc && !rempty);
```

The pointer exported to the other clock domain is Gray-coded:

```verilog
wptr_gray_next = (wptr_bin_next >> 1) ^ wptr_bin_next;
rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;
```

This split is the heart of the design. Binary is convenient locally; Gray is
safer to sample asynchronously because adjacent pointer values differ by one
bit.

## Synchronizer Direction

The write pointer crosses into the read domain so the read side can decide
whether data is available:

```text
wptr_gray -> sync_w2r -> wptr_gray_sync -> rptr_empty
```

The read pointer crosses into the write domain so the write side can decide
whether space is available:

```text
rptr_gray -> sync_r2w -> rptr_gray_sync -> wptr_full
```

Each crossing is a vector synchronizer over a Gray-coded pointer. This is why
the physical constraints still matter: the Gray bus must be routed so the
destination does not observe multiple bit changes caused by excessive skew.
See [CDC Constraints](cdc_constraints.md).

## Empty Generation

The read domain predicts the next read pointer and compares it against the
synchronized write pointer:

```verilog
assign rptr_bin_next =
    rptr_bin + {{(PTR_WIDTH-1){1'b0}}, (rinc && !rempty)};
assign rptr_gray_next =
    (rptr_bin_next >> 1) ^ rptr_bin_next;
assign rempty_next = (rptr_gray_next == wptr_gray_sync);
```

Using the next pointer means the registered `empty` flag describes whether the
next read request can be accepted. A read while `empty` is high does not move
the pointer and does not qualify data.

## Full Generation

The write domain predicts the next write pointer and checks whether it is one
complete wrap ahead of the synchronized read pointer:

```verilog
localparam [PTR_WIDTH-1:0] FULL_MASK =
    {2'b11, {(PTR_WIDTH-2){1'b0}}};

assign wptr_gray_next =
    (wptr_bin_next >> 1) ^ wptr_bin_next;
assign wfull_next =
    (wptr_gray_next == (rptr_gray_sync ^ FULL_MASK));
```

In reflected Gray code, a full FIFO is detected by inverting the two most
significant bits of the synchronized opposite pointer while leaving the lower
bits unchanged. Inverting only one MSB is a common bug.

## What This Repository Does Differently

The project follows the Cummings-style model, but it makes a few deliberate
implementation choices for portability and teaching clarity.

| Choice | Effect |
|---|---|
| Synchronized-pointer comparison | `full` and `empty` are generated after the opposite pointer has crossed through a two-flop synchronizer. |
| Synchronous read RAM | `fifo_mem` infers a simple dual-clock RAM with registered read data. |
| Explicit `rd_valid` | Consumers qualify `rd_data` with `rd_valid` instead of assuming immediate fallthrough behavior. |
| Equal-width CDC core | Width conversion and stream packet semantics stay in wrappers, not inside the crossing pointer mechanism. |
| Fixed two-flop pointer synchronizers | The design is easy to read and matches common FPGA CDC practice; deeper synchronizers would be a future parameterized extension. |
| Static almost thresholds | `almost_full` and `almost_empty` are simple local-domain flow-control hints. |

The most visible difference for users is `rd_valid`. Many textbook diagrams
focus on pointer safety and show data as if it is immediately visible. This
repository uses a synchronous read memory template, so a read request accepted
on a read-clock edge is marked by `rd_valid` with the corresponding registered
`rd_data`.

## Common Wrong Implementations

These are the mistakes this repository tries to make easy to spot:

- Synchronizing a binary pointer directly across the clock boundary.
- Comparing unsynchronized opposite-domain pointers in local control logic.
- Using only the RAM address bits and omitting the extra wrap bit.
- Treating equal address bits as enough to distinguish full from empty.
- Inverting only one Gray-code MSB for the full comparison.
- Updating `full` or `empty` from combinational cross-domain logic.
- Crossing payload bits through single-bit synchronizers instead of storing
  data in dual-clock RAM.
- Treating `wr_used` and `rd_used` as one exact global occupancy value.
- Using `almost_full` or `almost_empty` as the transfer qualifier instead of
  `!full` or `!empty`.
- Forgetting physical timing constraints for the Gray pointer bus.
- Assuming reset preserves FIFO contents.

## How to Read the RTL

A good reading path is:

1. `rtl/async_fifo.v`: public equal-width entry point.
2. `rtl/core/async_fifo_core.v`: accepted transfers, RAM instance,
   synchronizer connections, and `rd_valid`.
3. `rtl/core/wptr_full.v`: write-side binary pointer, Gray pointer, `full`,
   `almost_full`, and write-domain occupancy estimate.
4. `rtl/core/rptr_empty.v`: read-side binary pointer, Gray pointer, `empty`,
   `almost_empty`, and read-domain occupancy estimate.
5. `rtl/core/sync_w2r.v` and `rtl/core/sync_r2w.v`: Gray pointer crossings.
6. `rtl/core/fifo_mem.v`: payload storage.

Then connect that reading to [Formal Verification Guide](formal_verification.md)
to see how the behavior is checked.
