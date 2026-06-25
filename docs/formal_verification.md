# Formal Verification Guide

This guide explains how the formal checks connect back to user-visible FIFO
requirements. It is a reading map, not a replacement for the harness source.

If you are new to the design, read the [step-by-step tutorial](tutorial.md)
and [Learning Async FIFO](learning_async_fifo.md) first. If you need the public
contract, read [Interface and Timing](interface.md).

The properties in this guide use the same public behavior described in
`interface.md`: standard request reads update `rd_data` with a pulsed
`rd_valid`, FWFT reads pop visible data with `rd_en && rd_valid`, stream
transfers use `valid && ready`, and reset is destructive coordinated startup.

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
| Bidirectional channels preserve order independently | [`formal/bidir_formal.sv`](../formal/bidir_formal.sv) | Full-duplex wrapper composition does not couple A->B and B->A data streams |
| External RAM interface preserves standard FIFO timing | [`formal/ramif_formal.sv`](../formal/ramif_formal.sv) | One-cycle RAM contract, ordering, and `rd_valid` alignment |
| Bidirectional RAMIF channels preserve order independently | [`formal/bidir_ramif_formal.sv`](../formal/bidir_ramif_formal.sv) | Full-duplex external-RAM composition keeps A->B and B->A RAMIF channels isolated |
| Request width conversion preserves slice order | [`formal/width_conv_formal.sv`](../formal/width_conv_formal.sv) | Pack/split data ordering |
| Stream metadata stays attached to data | [`formal/stream_formal.sv`](../formal/stream_formal.sv) | `keep`, `last`, and backpressure behavior |
| Wrapper parameters are sampled across ratios and depths | [`formal/matrix_formal.sv`](../formal/matrix_formal.sv) | Regression coverage over representative configurations |

## From requirement to property

Read each harness as a small translation exercise:

```text
user-visible rule -> local acceptance condition -> reference state -> assertion
```

The harnesses deliberately avoid proving internal implementation details first.
They start from public behavior: when a transfer is accepted, what must the
user observe later?

| Requirement | Reference model | Property shape |
|---|---|---|
| A blocked write must not overflow storage | The write pointer should not move when `wr_en && full` | Assert the Gray write pointer is unchanged after a blocked write in `pointer_formal.sv` |
| A blocked read must not consume data | The read pointer should not move when `rd_en && empty` | Assert the Gray read pointer is unchanged after a blocked read in `pointer_formal.sv` |
| Accepted reads return data in FIFO order | `write_sequence` creates tokens; `read_sequence` predicts the next token | On every `rd_valid`, assert `rd_data == read_sequence` in `core_formal.sv` |
| Synchronous read timing is visible to users | `previous_read_allow` records the last accepted read | Assert `rd_valid` matches the prior accepted read in `core_formal.sv` |
| FWFT data must stay visible while stalled | `stalled_data` captures the visible word when `rd_valid && !rd_en` | Assert `rd_valid` remains high and `rd_data` stays equal to `stalled_data` in `fwft_formal.sv` |
| Stream backpressure must not corrupt a packet beat | A saved payload records `{rd_data, rd_keep, rd_last}` while `rd_valid && !rd_ready` | Assert the payload remains stable until the beat is accepted in `stream_formal.sv` |

This is why the core and wrapper proofs use counters instead of a full shadow
memory. A monotonically increasing token stream is enough to make many failures
observable: if the FIFO drops data, duplicates data, reorders data, reads from
empty storage, or leaks stale reset contents, the next `rd_valid` or FWFT pop
will disagree with the expected token.

Assumptions are kept close to the environment, not the design. In these
harnesses, clocks, resets, and request/ready signals provide the environment;
the DUT still has to decide whether a transfer is legal using `full`, `empty`,
`rd_valid`, or `ready`. Covers then ask whether interesting states are actually
reachable, such as full occupancy, FWFT stall-and-pop, or stream final beats.

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
sby -f -d build/formal-bidir-bmc formal/bidir.sby bmc
sby -f -d build/formal-ramif-bmc formal/ramif.sby bmc
sby -f -d build/formal-bidir-ramif-bmc formal/bidir_ramif.sby bmc
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
| `formal/bidir.sby bmc` | PASS | Checks independent A->B and B->A ordering and local backpressure |
| `formal/ramif.sby bmc` | PASS | Checks ordering and `rd_valid` alignment with a one-cycle external RAM model |
| `formal/bidir_ramif.sby bmc` | PASS | Checks independent A->B and B->A ordering through two one-cycle external RAM models |
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
- [`formal/bidir_formal.sv`](../formal/bidir_formal.sv) proves that the
  full-duplex wrapper preserves independent token streams in both directions
  and keeps backpressure local to the affected channel;
- [`formal/ramif_formal.sv`](../formal/ramif_formal.sv) proves that the
  external RAM-interface wrapper preserves standard FIFO ordering and
  `rd_valid` timing when connected to a one-cycle synchronous RAM model;
- [`formal/bidir_ramif_formal.sv`](../formal/bidir_ramif_formal.sv) proves
  that the bidirectional RAMIF wrapper keeps the two external-RAM channels
  independent, including ordering, `rd_valid` alignment, and local
  backpressure;
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
- both bidirectional and bidirectional RAMIF channels can fill and produce
  valid reads;
- the RAMIF wrapper can fill and return valid reads through the external RAM
  model;
- wrapper pack and split paths can produce repeated outputs;
- stream final and non-final packet transfers are reachable.

These covers make the proofs less vacuous and give useful traces when learning
how the design moves.

## Bounds and Coverage

The formal tasks are bounded because this repository is optimized for readable
teaching harnesses and routine CI runtime. A PASS means the solver explored all
states allowed by that harness, parameter set, assumptions, and depth; it does
not mean every possible FIFO parameter or physical implementation was proved.

The bounds are chosen to make the most important FIFO failure modes observable:

| Harness | Why the bound is useful | What it still does not prove |
|---|---|---|
| Pointer | Exercises reset, allowed pointer movement, blocked full/empty requests, and Gray one-bit transitions. | Every possible synchronizer physical implementation or routed delay. |
| Core BMC | Uses a tiny depth so full, empty, wraparound, and reads beyond one FIFO depth are reachable quickly. | One symbolic proof over every `DATA_WIDTH`, `ADDR_WIDTH`, or clock waveform. |
| Reset skew | Checks write-first and read-first coordinated startup with requests held off until initialization completes. | Data-preserving one-sided reset while traffic continues. |
| FWFT | Covers visible fallthrough data, stalled output stability, prefetch movement, reset clearing, and pops beyond one depth. | Every possible output-pipeline or vendor FWFT latency choice. |
| Bidir | Checks two independent token streams and local backpressure across the composed A->B and B->A channels. | Cross-direction transaction atomicity or shared-resource arbitration, which the wrapper intentionally does not provide. |
| RAMIF | Checks a one-cycle synchronous external RAM model, RAM enable alignment, ordering, and `rd_valid` timing. | Variable-latency RAMs, wait states, collision semantics, or target macro timing. |
| Width conversion | Checks representative pack and split ratios with token ordering through wrapper-local storage. | Arbitrary non-power-of-two ratios or every integer parameter combination. |
| Stream | Checks ready/valid backpressure, packet metadata stability, and pack/split stream paths. | Protocol behavior outside the documented ready/valid contract. |
| Matrix | Samples equal-width, pack, and split configurations across request and stream wrappers. | Exhaustive coverage of all legal widths and depths. |

When changing RTL, treat the current bounds as regression tripwires. If a new
feature adds storage, latency, or a new state machine, increase the relevant
depth or add a cover that demonstrates the new state can be reached before
trusting the proof.

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
