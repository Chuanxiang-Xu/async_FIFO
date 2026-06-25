# Bidirectional External-RAM FIFO Wrapper Design

`async_bidir_ramif_fifo` is the composition of the two optional wrapper ideas:

```text
A transmit -> async_fifo_ramif -> B receive
B transmit -> async_fifo_ramif -> A receive
```

It is a full-duplex convenience wrapper for integrations that need independent
A->B and B->A CDC channels while supplying external RAM for each direction.
It is not a new CDC algorithm and does not share RAM between directions.

## Boundary Decision

The wrapper must be built from two `async_fifo_ramif` instances:

- `u_a2b_fifo`: write/control side in domain A, read/control side in domain B;
- `u_b2a_fifo`: write/control side in domain B, read/control side in domain A.

Each direction has its own RAM interface:

```text
a2b_ram_wr_*  driven in domain A
a2b_ram_rd_*  driven in domain B
b2a_ram_wr_*  driven in domain B
b2a_ram_rd_*  driven in domain A
```

No RAM port, pointer, flag, or occupancy signal is shared between directions.

## Public Contract

The user-facing FIFO side follows `async_bidir_fifo`:

| Side | Signal group | Meaning |
|---|---|---|
| A | `a_tx_*` | Data written in domain A and received in domain B |
| A | `a_rx_*` | Data received in domain A from domain B |
| B | `b_tx_*` | Data written in domain B and received in domain A |
| B | `b_rx_*` | Data received in domain B from domain A |

The RAM side follows `async_fifo_ramif` twice. Each external RAM must implement
the fixed one-cycle synchronous-read simple dual-port contract described in
[External RAM Interface FIFO Design](ramif_design.md).

## Independence Rules

- A->B and B->A use independent FIFO control and independent RAM storage.
- A->B full/empty/almost/used signals do not describe B->A.
- A->B RAM behavior cannot backpressure or reorder B->A, and vice versa.
- The wrapper provides no cross-direction transaction atomicity.
- Reset clears each direction's pointer/control state, but not external RAM
  contents.

## Non-Goals

`async_bidir_ramif_fifo` does not implement:

- shared bidirectional RAM ports;
- runtime direction switching;
- `a_dir` / `b_dir` half-duplex controls;
- RAM wait states or variable latency;
- width conversion;
- FWFT behavior;
- packet stream semantics.

Those features need separate contracts and verification plans.

## Verification Plan

Directed simulation should use two independent one-cycle RAM models and cover:

- A->B transfer ordering;
- B->A transfer ordering;
- simultaneous traffic in both directions;
- full/backpressure in one direction not blocking the other direction;
- reset clearing pointer/control state without relying on RAM clearing.

Formal verification can be added later as a small composition harness combining
the bidirectional ordering checks with the RAMIF one-cycle RAM model.
