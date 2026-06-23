# Architecture

The repository separates the smallest user-facing FIFO from optional protocol
wrappers and CDC implementation details:

![Async FIFO core and wrapper architecture](assets/architecture.svg)

```mermaid
flowchart TD
    A[async_fifo<br/>minimal public entry] --> C[async_fifo_core]
    W[async_fifo_width_conv<br/>optional wrapper] --> C
    S[async_fifo_stream<br/>optional wrapper] --> C
    C --> M[fifo_mem<br/>dual-clock storage]
    C --> WP[wptr_full]
    C --> RP[rptr_empty]
    C --> SW[sync_w2r]
    C --> SR[sync_r2w]
    U[async_reset_sync<br/>optional integration utility] -. local resets .-> A
    U -. local resets .-> W
    U -. local resets .-> S
```

## Directory ownership

| Directory | Responsibility |
|---|---|
| [`rtl/async_fifo.v`](../rtl/async_fifo.v) | Stable, minimal equal-width user entry point |
| [`rtl/core/`](../rtl/core/) | Storage, pointers, Gray-code synchronization, and local status generation |
| [`rtl/wrappers/`](../rtl/wrappers/) | Width conversion and packet-stream protocol behavior |
| [`rtl/util/`](../rtl/util/) | Optional integration helpers that are not part of FIFO data movement |

`async_fifo.v` deliberately contains no CDC algorithm of its own: it preserves
a simple public module name while delegating implementation to
`async_fifo_core`. Both wrappers also instantiate the same equal-width core;
packing, splitting, ready/valid buffering, and packet metadata remain outside
the CDC mechanism.

Only Gray-coded pointers cross through synchronizer chains. Payload data stays
in the dual-clock memory. See [Interface and Timing](interface.md) for port and
status contracts, [Learning Async FIFO](learning_async_fifo.md) for the
step-by-step mechanism, and [CDC Constraints](cdc_constraints.md) for physical
timing requirements.
