# Simulation Summary

The simulation suite provides concrete, self-checking scenarios for the public
FIFO modules and wrappers. It is the fastest way to catch interface timing,
ordering, reset, and wrapper behavior regressions before running heavier
formal or vendor flows.

## What Is Checked

`make test` runs the Icarus Verilog testbenches listed in the top-level
Makefile. The suite covers:

- equal-width FIFO transfers, boundary conditions, almost flags, random
  traffic, and reset access gating;
- FWFT first-word behavior, stalled output behavior, empty pops, and reset;
- bidirectional FIFO composition with independent A->B and B->A channels;
- external RAM-interface wrappers with the documented one-cycle RAM contract;
- request-style width conversion for pack and split ratios;
- stream ready/valid behavior, `keep`, `last`, random traffic, and throughput
  cases;
- reset synchronizer behavior.

The assertions in `test/fifo_assertions.sv` and
`test/stream_assertions.sv` provide reusable simulation checks for common FIFO
and stream interface rules.

## How to Reproduce

Run the complete simulation suite:

```bash
make test
```

For a faster local sanity check that includes one equal-width simulation plus
documentation and CDC source checks:

```bash
make smoke
```

For tutorial waveform generation:

```bash
make tutorial
```

The tutorial testbench is `test/tb_fifo_tutorial.sv`; generated outputs are
placed under `build/`.

## What This Does Not Prove

Simulation exercises selected scenarios. It does not exhaust every clock
relationship, every reset interleaving, every legal parameter combination, or
every reachable internal state. Use formal checks for bounded exhaustive
behavior under selected harnesses, and use target STA/CDC analysis for
physical implementation sign-off.

## Where to Look Next

- [Step-by-step tutorial](../tutorial.md) explains the main waveform story.
- [Interface and Timing](../interface.md) defines accepted transfers,
  `rd_valid`, reset, flags, and occupancy semantics.
- [Formal Summary](formal_summary.md) explains the complementary formal
  evidence.
