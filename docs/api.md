# Public Module API

This page is a short entry point for public synthesizable modules. The
authoritative timing, reset, flag, occupancy, and transfer contract remains
[Interface and Timing](interface.md).

Use this page to choose a module quickly; use `interface.md` before connecting
one into a real design.

## Module Tiers

| Tier | Module | Status | Use when |
|---|---|---|---|
| 1 | `async_fifo` | Stable | You need the main equal-width asynchronous FIFO. Start here. |
| 2 | `async_fifo_fwft` | Stable | You need first-word fallthrough read behavior. |
| 3 | `async_fifo_width_conv` | Stable | You need request-style power-of-two width conversion. |
| 3 | `async_fifo_stream` | Stable | You need packet-aware ready/valid CDC with `keep` and `last`. |
| 4 | `async_bidir_fifo` | Beta | You need two independent full-duplex equal-width CDC channels. |
| 4 | `async_fifo_ramif` | Experimental | You need to supply a custom external RAM backend. |
| 4 | `async_bidir_ramif_fifo` | Experimental | You need full-duplex CDC with external RAM in both directions. |
| Utility | `async_reset_sync` | Stable utility | You need async-assert, sync-release reset generation for one clock domain. |

Core implementation modules under `rtl/core/` are internal. Read them to learn
or maintain the design, but instantiate public modules from `rtl/` or
`rtl/wrappers/` for integration.

## Recommended Starting Point

Most users should instantiate:

```text
rtl/async_fifo.v
```

The standard equal-width contract is:

```text
write accepted: wr_rstn && wr_en && !full
read accepted:  rd_rstn && rd_en && !empty
read data:      rd_valid qualifies rd_data
```

For the complete port list and timing details, see
[Equal-width interface: async_fifo](interface.md#equal-width-interface-async_fifo).

## Optional Wrappers

Wrappers add interface behavior around the same teaching core or the same
pointer-control pattern. They must not be treated as new CDC algorithms.

| Wrapper | Adds | Does not add |
|---|---|---|
| `async_fifo_fwft` | Read-side prefetch and visible-data semantics | A different pointer crossing mechanism |
| `async_fifo_width_conv` | Request-style packing/splitting for power-of-two ratios | Arbitrary non-power-of-two ratios |
| `async_fifo_stream` | Ready/valid, `keep`, `last`, and backpressure behavior | AXI infrastructure or packet policy beyond documented beats |
| `async_bidir_fifo` | Two independent FIFO directions | Shared storage, runtime direction switching, transaction atomicity |
| `async_fifo_ramif` | External one-cycle RAM interface | RAM backpressure, variable latency, ECC, byte enables, RAM sign-off |
| `async_bidir_ramif_fifo` | Two independent RAMIF directions | Shared bidirectional RAM ports or half-duplex arbitration |

## API Rules of Thumb

- Use `!full` for request-style write acceptance.
- Use `!empty` for standard request-style read acceptance.
- Use `rd_valid` to sample `rd_data`.
- Use `rd_valid` as visible-data level only for FWFT.
- Use `valid && ready` for stream transfers.
- Treat almost flags and occupancy counts as local advisory views.
- Treat reset as destructive and coordinated across domains.
- Keep target STA, CDC, reset, and RAM sign-off outside this generic API page.

## Related Pages

- [Interface and Timing](interface.md): authoritative public contract.
- [Architecture](architecture.md): module layering.
- [Internal Design Map](internal_design.md): RTL reading order.
- [Experimental Modules](experimental.md): advanced/experimental boundaries.
- [CDC and Timing Constraints](cdc_constraints.md): physical sign-off guidance.
