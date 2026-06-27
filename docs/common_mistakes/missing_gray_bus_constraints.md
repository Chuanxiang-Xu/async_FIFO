# Missing Gray-Bus Constraints

## Tempting Idea

Use Gray coding and two-flop synchronizers, then mark the clocks asynchronous
or false-path the entire crossing. The logic is "CDC-safe", so physical timing
constraints can be skipped.

## Why Simple Simulation May Pass

RTL simulation has no routed delay. All Gray-pointer bits reach the
synchronizer inputs at the same simulated time, and the destination sees a
clean legal Gray value.

Source-level CDC checks can also pass because the synchronizer structure is
present. That proves the intended structure exists; it does not prove the
routed paths meet the timing intent.

## Hardware Risk

Gray coding guarantees that adjacent source pointer values differ by one bit.
It does not guarantee that all routed bits arrive at the first destination
synchronizer stage within an acceptable window.

If one Gray bit takes much longer than another, the destination can observe
effects from more than one source transition in one sampling window. That
defeats the single-bit-change assumption the async FIFO relies on.

Broad false-path or asynchronous-clock-group constraints can make this worse
if they override the intended max-delay or bus-skew constraints.

## Correct Approach

Constrain the paths from each registered source Gray pointer bit to the first
stage of the destination synchronizer. The exact command is tool- and
netlist-specific, but the intent is consistent:

- define both clocks accurately;
- identify the source Gray-pointer registers;
- identify the first-stage synchronizer registers;
- apply max-delay or bus-skew constraints for each crossing;
- review post-synthesis and post-route reports.

## Where This Repo Handles It

- `constraints/xilinx/async_fifo.xdc` captures Vivado-style Gray-path intent.
- `constraints/xilinx/check_async_fifo.tcl` checks scoped endpoint discovery.
- `constraints/intel/async_fifo.sdc` provides an Intel template.
- `scripts/check_cdc.py` checks source structure and template intent.
- `make xilinx-cdc` validates Xilinx template behavior when Vivado is
  available.

Read [CDC and Timing Constraints](../cdc_constraints.md) before integrating
the FIFO into a real FPGA project.
