# FWFT / Fallthrough Design Notes

This document defines the implemented first-word-fall-through behavior of
`async_fifo_fwft`. The base `async_fifo` module remains a standard
synchronous-read FIFO; FWFT is provided as an equal-width read-side wrapper
around the unchanged Cummings-style CDC core.

## Status

| Item | Status |
|---|---|
| Standard synchronous read | Implemented |
| FWFT / fallthrough read mode | Implemented as an equal-width wrapper |
| RTL parameter or wrapper | `rtl/wrappers/async_fifo_fwft.v` |
| Directed tests | `test/tb_fifo_fwft.sv` |
| Formal properties | `formal/fwft_formal.sv` and `formal/fwft.sby` |

The wrapper adds FWFT behavior without disturbing the Cummings-style CDC core.
It implements the fallthrough behavior as read-side prefetch and output-slot
logic around the existing equal-width core.

## Baseline: Current Standard Read

The implemented request interface works like this:

```text
rd_rstn && rd_en && !empty  accepts a read request
rd_valid                   marks the cycle where rd_data is valid
```

`rd_en` is a request to fetch a word. Because the RAM read port is synchronous,
the design exposes `rd_valid` so consumers know when `rd_data` should be
sampled.

In this mode:

- `empty == 0` means a read request may be accepted;
- `rd_en` initiates movement from RAM to `rd_data`;
- `rd_valid` pulses for an accepted read response;
- if the consumer does not request a read, the FIFO does not automatically
  place the first word on `rd_data`.

This is the behavior documented in [Interface and Timing](interface.md).

## FWFT Read

FWFT changes the read-side user contract from "request then receive" to
"observe then consume".

In the implemented FWFT wrapper:

```text
rd_valid == 1             rd_data holds a readable word
rd_en && rd_valid         consumes the currently visible word
empty == !rd_valid        no word is currently visible to the user
```

The first readable word should appear on `rd_data` automatically after it has
crossed into the read-side view and has been fetched from the synchronous RAM.
The user does not need to pulse `rd_en` to make the first word visible. `rd_en`
acts like a consume or pop signal.

This makes the equal-width request interface closer to a simple valid/ready
sink:

| Concept | Standard mode | FWFT mode |
|---|---|---|
| `rd_en` means | Request a read | Consume visible data |
| `rd_valid` means | Response to an accepted read | Output slot contains valid data |
| `empty` means | No read request can be accepted | No output word is visible |
| First word latency | User must request, then observe `rd_valid` | Logic prefetches; user observes `rd_valid` |
| Backpressure | User withholds `rd_en` | User withholds `rd_en`, valid data remains stable |

## Internal Model

`async_fifo_fwft` keeps `async_fifo_core` in standard mode and adds a read-side
prefetch layer:

```text
async_fifo_core
    standard rd_en/empty/rd_valid/rd_data
        |
        v
read-side prefetch/output slot
        |
        v
FWFT user rd_data/rd_valid/empty
```

The implemented prefetch layer owns two read-side slots:

```text
slot0_valid / slot0_data  user-visible output slot
slot1_valid / slot1_data  spare prefetched word
```

It issues an internal core read when:

```text
rd_rstn && !core_empty && output slot can accept another word
```

The slots can accept another word when space exists, including space freed by a
user pop on the same edge. For a synchronous-read core, one pending fetch bit is
also used so the wrapper accounts for a word requested from the core but not
yet returned by core `rd_valid`.

## Equal-Width FWFT Contract

The equal-width FWFT wrapper defines the public read-side behavior as:

| Signal | FWFT meaning |
|---|---|
| `rd_data` | Stable user-visible word while `rd_valid` is high |
| `rd_valid` | Output slot contains a valid word |
| `rd_en` | Pop the visible word when `rd_valid` is high |
| `empty` | Equivalent to `!rd_valid` at the user interface |
| `almost_empty` | Advisory core/read-side occupancy hint, not a pop qualifier |
| `rd_used` | Local read-domain estimate; must document whether it includes the output slot |

The wrapper exposes `empty = !rd_valid` for user behavior. It defines `rd_used`
as the core read-domain view plus the visible slot, spare slot, and pending
internal fetch.

## Stability Rules

FWFT must obey ready/valid-style output stability:

- When `rd_valid && !rd_en`, `rd_data` must remain stable.
- A held word may stay visible across any number of read-clock cycles.
- `rd_valid` may remain high across a consume if the next word is already
  available or arrives into the output slot on that edge.
- A consume when `rd_valid == 0` must be non-destructive.
- Reset clears the visible slot, any pending fetch bit, and `rd_valid`.

These rules are the main reason FWFT should be implemented as a read-side
prefetch/output layer instead of changing the Gray-pointer CDC mechanism.

## Empty and Almost-Empty Semantics

The most important naming decision is `empty`.

For FWFT, user-facing `empty` should mean:

```text
empty == !rd_valid
```

That is, the user should treat `empty` as "there is no currently visible word."
This differs from the core's internal `empty`, which means "the core cannot
accept another internal read request right now."

`almost_empty` should stay advisory. It may be derived from the core occupancy,
from visible-slot-aware read-side occupancy, or from a documented combination.
It must not replace the pop condition:

```text
FWFT pop = rd_rstn && rd_en && rd_valid
```

## Relationship to XPM

AMD/Xilinx `XPM_FIFO_ASYNC` exposes standard and FWFT behavior through
`READ_MODE`. This repository should not try to clone every XPM detail. The
useful alignment is at the interface expectation level:

- standard mode: request read, then qualify response;
- FWFT mode: first word becomes visible automatically, then the user consumes
  visible words.

Vendor-specific details such as exact effective depth, read latency parameters,
busy ports, ECC, and programmable flags remain out of scope unless they serve
the teaching path.

## Implemented Structure

The 1.1.0 implementation follows this structure:

1. `async_fifo_core` stays standard and unchanged.
2. The read-side prefetch layer includes:
   - one visible output slot;
   - one spare prefetched slot;
   - one pending internal-read bit;
   - stable `rd_data` while stalled;
   - user `empty = !rd_valid`.
3. Directed tests cover first-word visibility, backpressure stability,
   continuous reads, reset clearing, and blocked empty pops.
4. Formal properties cover ordering, no duplicate fetch, no dropped word,
   output stability while stalled, and reset clearing.
5. The tutorial waveform compares standard and FWFT read timing.
6. `async_fifo` keeps its standard read contract; `async_fifo_fwft` is the
   public equal-width FWFT entry point.

## Verification Coverage

Directed simulations cover these scenarios:

| Scenario | Expected behavior |
|---|---|
| One write, no `rd_en` | After pointer sync and RAM fetch, `rd_valid` rises and `rd_data` shows the word. |
| Hold output stalled | While `rd_valid && !rd_en`, `rd_data` is stable. |
| Consume one word | `rd_en && rd_valid` pops exactly one word. |
| Continuous stream | With `rd_en` held high, words emerge in order without duplicates. |
| Empty pop attempt | `rd_en` while `rd_valid == 0` is non-destructive. |
| Reset during visible word | Reset clears `rd_valid`; old `rd_data` is not meaningful. |

Formal properties mirror the same contract:

- accepted writes increase the expected sequence;
- FWFT pops return the oldest expected word;
- a core read is not issued if a previous fetch is still pending and no slot is
  available;
- stalled output data is stable;
- no `rd_valid` is asserted during read reset.

## Open Decisions

- Should FWFT stay permanently as a separate module, `async_fifo_fwft`, or
  eventually become a parameter on `async_fifo`?
- Is the current `rd_used` definition, including both slots and pending fetch,
  the right long-term public contract?
- Should FWFT support width-conversion wrappers later, or stay equal-width only?
- Should stream mode reuse the same prefetch layer, or remain its own
  ready/valid implementation?

Conservative recommendation: keep the equal-width FWFT wrapper separate. Keep
the current `async_fifo` contract unchanged unless a later release has a clear
reason to add a `READ_MODE` parameter.
