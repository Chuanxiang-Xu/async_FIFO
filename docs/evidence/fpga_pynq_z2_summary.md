# PYNQ-Z2 Summary

The PYNQ-Z2 flow is a concrete Vivado validation of the minimal
`async_fifo` integration and Xilinx Gray-pointer constraint strategy. It is a
board-oriented smoke test for one target, not coverage of every public wrapper.

## What Is Checked

The checked-in PYNQ-Z2 example builds a synthesizable test design for:

- device `xc7z020clg400-1`;
- a 125 MHz board clock;
- generated 100 MHz write and 75 MHz read FIFO clocks;
- the minimal equal-width `async_fifo`;
- Xilinx Gray-pointer constraint discovery and endpoint coverage;
- synthesis, placement, routing, timing, DRC, bitstream generation, and report
  production.

The top-level design moves a counter sequence through the FIFO. LED0 is a
sticky mismatch indicator, LED2 blinks only after successful reads, and LED3
shows MMCM lock.

## Existing Recorded Result

[PYNQ-Z2 Vivado Validation](../pynq_z2_vivado.md) records a local Vivado
2025.2 build result for `xc7z020clg400-1` on 2026-06-21. The recorded result
includes non-negative setup and hold slack, Gray exception coverage for all
expected bits in both directions, passing Gray bus-skew checks, and successful
bitstream generation.

Treat that page as the detailed source of truth for numbers, report names,
LED behavior, DRC notes, and limitations.

## How to Reproduce

With Vivado 2025.2 in `PATH`:

```bash
make pynq-z2
```

Or pass the Vivado executable explicitly:

```bash
make pynq-z2 VIVADO=/path/to/Vivado/bin/vivado
```

Vivado writes the disposable project under `examples/pynq_z2/build/` and
reports under `examples/pynq_z2/reports/`.

## What This Does Not Prove

This flow validates one device, one clocking setup, one parameter set, and the
minimal `async_fifo` integration. It does not validate FWFT, bidirectional,
RAMIF, bidirectional RAMIF, width-conversion, or stream wrappers on the board.
Those wrappers are covered by simulation, formal checks, lint, and generic
synthesis.

The recorded Vivado result also does not prove physical board operation by
itself. After programming hardware, LED0 must remain off, LED2 must keep
blinking, and LED3 must remain on.

## Where to Look Next

- [PYNQ-Z2 Vivado Validation](../pynq_z2_vivado.md) has the full board-flow
  explanation.
- [CDC Summary](cdc_summary.md) summarizes the broader CDC evidence.
- [Compatibility and Release Support](../compatibility.md) records the
  supported tool and target matrix.
