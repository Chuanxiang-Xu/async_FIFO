# Bidirectional FIFO Wrapper Design

`async_bidir_fifo` is a full-duplex CDC convenience wrapper. It is not a new
FIFO algorithm. It composes two independent equal-width asynchronous FIFOs:

```text
A transmit -> async_fifo -> B receive
B transmit -> async_fifo -> A receive
```

The purpose is to give integrators a clear TX/RX-style module for two-way
communication without changing the Cummings-style CDC core.

## Public Contract

| Side | Signal group | Meaning |
|---|---|---|
| A | `a_tx_*` | Data written in domain A and received in domain B |
| A | `a_rx_*` | Data received in domain A from domain B |
| B | `b_tx_*` | Data written in domain B and received in domain A |
| B | `b_rx_*` | Data received in domain B from domain A |

Each direction follows the standard `async_fifo` request contract:

```text
tx_rstn && tx_en && !tx_full  accepts a write
rx_rstn && rx_en && !rx_empty accepts a read
rx_valid                     qualifies rx_data
```

The wrapper uses `a_rstn` for all A-domain state and `b_rstn` for all B-domain
state. Reset is destructive in both directions, exactly like the underlying
FIFO instances.

## Independence Rules

The two directions are intentionally independent:

- A->B and B->A have separate storage.
- A->B and B->A have separate pointer synchronizers.
- A->B `full`, `empty`, almost flags, and occupancy do not describe B->A.
- One direction becoming full does not block writes in the other direction.
- The wrapper provides no cross-direction transaction atomicity or ordering.

If a protocol requires a request and response to commit together, that protocol
logic must sit above the FIFO wrapper.

## Non-Goals

`async_bidir_fifo` deliberately does not implement:

- runtime direction switching;
- shared RAM between directions;
- `a_dir` / `b_dir` half-duplex controls;
- width conversion;
- FWFT read behavior;
- packet metadata or ready/valid stream semantics.

Those features either belong in existing wrappers or in future experimental
modules with their own contracts. The full-duplex teaching wrapper should
remain a readable composition of two standard asynchronous FIFOs.

## Verification Plan

Directed simulation should cover:

- A->B transfer ordering;
- B->A transfer ordering;
- simultaneous traffic in both directions;
- full or backpressure in one direction not blocking the other direction;
- reset clearing both directions.

Because the wrapper contains no new CDC algorithm, the first formal step can be
small: prove that each direction preserves the underlying FIFO transfer
contract and that opposite-direction requests remain independent.
