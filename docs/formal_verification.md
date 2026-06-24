# Formal Verification Guide

This guide explains how the formal checks connect back to user-visible FIFO
requirements. It is a reading map, not a replacement for the harness source.

If you are new to the design, read the [step-by-step tutorial](tutorial.md)
and [Learning Async FIFO](learning_async_fifo.md) first. If you need the public
contract, read [Interface and Timing](interface.md).

## The proof strategy

The formal checks are split into small harnesses so each one has a clear job:

| User-visible requirement | Formal location | What it protects |
|---|---|---|
| Gray pointers change by at most one bit per local step | [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) | CDC pointer discipline |
| Write while full does not advance the write pointer | [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) | No overflow through blocked writes |
| Read while empty does not advance the read pointer | [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) | No underflow through blocked reads |
| Equal-width FIFO preserves order | [`formal/core_formal.sv`](../formal/core_formal.sv) | No loss, duplication, or reordering |
| `rd_valid` matches accepted reads | [`formal/core_formal.sv`](../formal/core_formal.sv) | Correct synchronous-read timing |
| Local status counts stay in range | [`formal/core_formal.sv`](../formal/core_formal.sv) | Conservative `full`, `empty`, and occupancy views |
| Reset release works write-first or read-first | [`formal/reset_skew_formal.sv`](../formal/reset_skew_formal.sv) | Coordinated startup after reset skew |
| FWFT visible pops preserve order | [`formal/fwft_formal.sv`](../formal/fwft_formal.sv) | No loss, duplication, or reordering through the prefetch slots |
| FWFT stalled output stays stable | [`formal/fwft_formal.sv`](../formal/fwft_formal.sv) | Correct fallthrough backpressure behavior |
| Request width conversion preserves slice order | [`formal/width_conv_formal.sv`](../formal/width_conv_formal.sv) | Pack/split data ordering |
| Stream metadata stays attached to data | [`formal/stream_formal.sv`](../formal/stream_formal.sv) | `keep`, `last`, and backpressure behavior |
| Wrapper parameters are sampled across ratios and depths | [`formal/matrix_formal.sv`](../formal/matrix_formal.sv) | Regression coverage over representative configurations |

The harnesses use deterministic token streams rather than a large shadow RAM
where possible. For example, `core_formal.sv` writes an increasing sequence and
asserts that every `rd_valid` returns the next expected value. That single
check catches underflow data, stale reset data, duplicated data, lost data, and
reordering.

## How to run

Activate the checked-in Conda environment, or prefix commands with
`conda run -n async_fifo`:

```sh
conda activate async_fifo
```

The full suite is:

```sh
make formal
```

When studying the project, start with this smaller ladder:

```sh
sby -f -d build/formal-pointer formal/pointer.sby
sby -f -d build/formal-core-bmc formal/core.sby bmc
sby -f -d build/formal-core-cover formal/core.sby cover
sby -f -d build/formal-fwft-bmc formal/fwft.sby bmc
sby -f -d build/formal-width-pack formal/width_conv.sby pack
sby -f -d build/formal-stream-pack formal/stream.sby pack
```

These commands move from local pointer rules, to the equal-width core contract,
to one wrapper path. On the reference `async_fifo` Conda environment, the first
four commands above have been run successfully from this repository:

| Command | Result | Why run it first |
|---|---|---|
| `formal/pointer.sby` | PASS | Smallest proof; checks Gray transitions and blocked pointers |
| `formal/core.sby bmc` | PASS | Checks bounded core ordering, status, occupancy, and `rd_valid` |
| `formal/core.sby cover` | PASS | Produces traces for full and post-depth read progress |
| `formal/fwft.sby bmc` | PASS | Checks FWFT pop ordering, stable stalls, reset clearing, and visible `empty` |
| `formal/width_conv.sby pack` | PASS | Checks one request-wrapper packing path |

The Makefile also runs `make formal-matrix`, which sweeps representative
request and stream wrapper widths, ratios, and address sizes.

## How to read a harness

Start with [`formal/pointer_formal.sv`](../formal/pointer_formal.sv). It is the
smallest proof and mirrors the Cummings-style pointer rules:

- Gray pointers may stay the same or change one bit;
- blocked writes do not move the write pointer;
- blocked reads do not move the read pointer.

Then read [`formal/core_formal.sv`](../formal/core_formal.sv). It connects the
pointer mechanism to the FIFO contract:

- `wr_used` and `rd_used` never exceed the configured depth;
- `full` and `empty` agree with the local occupancy views;
- `rd_valid` follows an accepted read;
- returned data is exactly the next token in order.

After that, read the wrapper harnesses:

- [`formal/fwft_formal.sv`](../formal/fwft_formal.sv) proves that the FWFT
  wrapper presents visible data in order, holds it stable while stalled, and
  clears the visible output during read reset;
- [`formal/width_conv_formal.sv`](../formal/width_conv_formal.sv) proves
  little-slice-first request conversion in both directions;
- [`formal/stream_formal.sv`](../formal/stream_formal.sv) proves packet
  metadata and output stability during backpressure;
- [`formal/matrix_formal.sv`](../formal/matrix_formal.sv) repeats simpler
  wrapper checks across a parameter matrix.

## Covers

Cover tasks are not safety proofs. They demonstrate that important states are
reachable inside the bounded model:

- the FIFO can become full;
- reads can progress beyond one FIFO depth;
- FWFT can expose a first word, stall it, and pop beyond one FIFO depth;
- wrapper pack and split paths can produce repeated outputs;
- stream final and non-final packet transfers are reachable.

These covers make the proofs less vacuous and give useful traces when learning
how the design moves.

## Boundaries

These checks are strong regression tests, but they are intentionally bounded.
They do not prove every integer parameter, every possible continuous clock
waveform, every target FPGA implementation, or physical CDC timing. The CDC
and timing sign-off boundary remains in [CDC Constraints](cdc_constraints.md).

For this project, the right mental model is:

```text
simulation: concrete scenarios and scoreboards
formal: bounded exhaustive behavior inside selected harnesses
CDC/STA: physical implementation sign-off
```
