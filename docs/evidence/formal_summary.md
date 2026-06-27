# Formal Summary

The formal suite checks bounded FIFO safety and wrapper behavior with small,
readable harnesses. The emphasis is teaching-grade confidence: each harness is
named by intent and tied back to user-visible FIFO requirements.

## What Is Checked

The main suite is:

```bash
make formal
```

It includes:

- pointer rules: Gray pointers change by at most one bit, and blocked
  full/empty transfers do not advance pointers;
- equal-width core behavior: no overflow through accepted writes, no
  underflow through accepted reads, ordering, `rd_valid` alignment, reset, and
  local occupancy bounds;
- reset skew behavior for write-first and read-first release sequences;
- FWFT ordering, visible output stability while stalled, fallthrough behavior,
  and reset clearing;
- bidirectional wrapper independence for A->B and B->A streams;
- RAMIF and bidirectional RAMIF behavior under the documented one-cycle RAM
  model;
- request width-conversion pack and split ordering;
- stream data, `keep`, `last`, backpressure, and wrapper parameter samples;
- matrix tasks for representative widths, ratios, and address sizes.

Cover tasks demonstrate that important states are reachable inside the bounded
models, including full occupancy, reads beyond one FIFO depth, FWFT stalls,
wrapper transfers, and stream packet cases.

## How to Reproduce

Run the full formal suite:

```bash
make formal
```

When studying or debugging, start smaller:

```bash
sby -f -d build/formal-pointer formal/pointer.sby
sby -f -d build/formal-core-bmc formal/core.sby bmc
sby -f -d build/formal-core-cover formal/core.sby cover
sby -f -d build/formal-fwft-bmc formal/fwft.sby bmc
```

Then add the wrapper harnesses relevant to the change.

## What This Does Not Prove

The formal checks are bounded and parameter-sampled. A PASS means the solver
proved the selected property under the selected harness assumptions, bounds,
and parameters. It does not prove every possible FIFO depth, width, clock
waveform, target FPGA implementation, routed delay, metastability behavior, or
CDC report quality.

Formal also does not replace simulation. Simulation remains useful for larger
concrete regressions, waveform-led learning, and integration-style scenarios.

## Where to Look Next

- [Formal Verification Guide](../formal_verification.md) explains the proof
  strategy from user-visible behavior to properties and covers.
- [CDC Summary](cdc_summary.md) explains why logical proofs do not replace
  physical CDC and timing closure.
- [Interface and Timing](../interface.md) is the contract the harnesses are
  meant to protect.
