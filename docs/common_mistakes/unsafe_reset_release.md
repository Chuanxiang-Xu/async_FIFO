# Unsafe Reset Release

## Tempting Idea

Assert or release reset whenever one side of the system needs it. If the write
side resets, the read side can keep draining old data. If one clock domain
comes out of reset earlier, traffic can begin immediately.

## Why Simple Simulation May Pass

A simple testbench often resets both domains at the same time, waits many
cycles, then starts traffic. That proves a clean startup path, but it does not
exercise reset skew, request inputs held high during reset, or a unilateral
runtime reset while the other domain is active.

## Hardware Risk

An async FIFO has state in both domains: local binary pointers, registered
Gray pointers, synchronized remote pointers, flags, read-valid state, and RAM
contents. If one side resets while the other side continues transferring, the
two domains no longer agree about which stored words are valid.

Asynchronous reset assertion is acceptable, but release must be synchronized
to each local clock. Reset recovery/removal timing and CDC/reset methodology
still need target review.

## Correct Approach

Use coordinated destructive reset:

- reset may assert asynchronously;
- each domain's reset must deassert synchronously to that domain's clock;
- do not transfer data until both domains have completed initialization;
- treat queued data as discarded by reset;
- do not rely on RAM contents or `rd_data` during reset.

If a design needs data-preserving one-sided reset, it needs a different
contract and more verification than this repository provides.

## Where This Repo Handles It

- `docs/interface.md` defines reset as destructive and coordinated.
- `rtl/util/async_reset_sync.v` provides an async-assert, sync-release helper.
- `rtl/core/async_fifo_core.v` gates RAM access with local reset.
- `formal/reset_skew_formal.sv` checks write-first and read-first coordinated
  startup.
- `formal/stream_reset_skew_formal.sv` extends the reset checks through the
  stream wrapper.
- `test/tb_reset_sync.sv` checks reset synchronizer behavior.

Read [CDC and Timing Constraints](../cdc_constraints.md#reset-crossings) for
the sign-off boundary.
