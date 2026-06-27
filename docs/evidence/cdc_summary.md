# CDC Summary

This repository implements the logical CDC structure of a Cummings-style
asynchronous FIFO and provides source-level and template-level checks. Final
CDC and timing sign-off still belongs to the consuming FPGA project.

## What Is Checked

The open-source checks cover:

- two-stage pointer synchronizer source structure;
- registered Gray-pointer crossings from write to read and read to write
  domains;
- source-level intent in the Xilinx and Intel constraint templates;
- generic synthesis hierarchy and process checks with Yosys;
- bounded formal behavior of FIFO logic and wrapper contracts.

The Xilinx-specific flow additionally checks scoped Vivado template behavior:

- exact FIFO instance matching;
- `ADDR_WIDTH + 1` endpoint coverage for both Gray-pointer crossings;
- source-register discovery from first-stage synchronizer D pins;
- default and multi-instance constraint-template elaboration.

## How to Reproduce

Run the source-level CDC check:

```bash
make cdc
```

Run generic synthesis checks:

```bash
make synth
```

Run the Vivado template validation when Vivado 2025.2 is available:

```bash
make xilinx-cdc
```

The Xilinx template lives at `constraints/xilinx/async_fifo.xdc`, with
companion checking logic in `constraints/xilinx/check_async_fifo.tcl`. The
Intel template lives at `constraints/intel/async_fifo.sdc`.

## What This Does Not Prove

These checks do not close timing for a user's final FPGA design. They do not
prove routed bus skew, setup/hold closure, reset recovery/removal, CDC tool
classification quality, synchronizer placement, or MTBF for a specific
product.

Do not synchronize payload bits one by one. Payload data crosses through RAM;
only registered Gray pointers should cross through the pointer synchronizers.
Every target design still needs clock definitions, Gray-bus timing
constraints, synchronizer recognition, reset review, timing reports, CDC
reports, and waiver review where applicable.

## Where to Look Next

- [CDC and Timing Constraints](../cdc_constraints.md) is the authoritative
  CDC and sign-off guide.
- [PYNQ-Z2 Summary](fpga_pynq_z2_summary.md) summarizes one Vivado
  implementation flow.
- [Known Limits](known_limits.md) lists the boundaries that should stay
  visible in integration and release claims.
