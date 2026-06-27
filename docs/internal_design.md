# Internal Design Map

This page is an RTL reading map for maintainers and learners. It does not
replace [Cummings-style FIFO mapping](cummings_mapping.md) or
[Learning Async FIFO](learning_async_fifo.md); it points to the files that
implement each idea.

Integrators should instantiate the public modules described in
[Public Module API](api.md), not internal core files directly.

## Core Reading Path

Read the equal-width FIFO in this order:

| Step | File | What to inspect |
|---|---|---|
| 1 | `rtl/async_fifo.v` | Minimal public wrapper, parameters, and public signal names. |
| 2 | `rtl/core/async_fifo_core.v` | Accepted transfer gating, RAM instance, synchronizer wiring, and `rd_valid`. |
| 3 | `rtl/core/fifo_mem.v` | Dual-clock storage and synchronous read behavior. |
| 4 | `rtl/core/wptr_full.v` | Write binary pointer, write Gray pointer, `full`, `almost_full`, and `wr_used`. |
| 5 | `rtl/core/rptr_empty.v` | Read binary pointer, read Gray pointer, `empty`, `almost_empty`, and `rd_used`. |
| 6 | `rtl/core/sync_w2r.v` | Write Gray pointer synchronization into the read domain. |
| 7 | `rtl/core/sync_r2w.v` | Read Gray pointer synchronization into the write domain. |
| 8 | `rtl/util/async_reset_sync.v` | Optional reset helper for integration boundaries. |

The core invariant is:

```text
payload stays in RAM
binary pointers stay local
registered Gray pointers cross domains
full/empty are generated in local domains
```

## Signal Ownership

| Owner | Signals | Notes |
|---|---|---|
| Write domain | `wr_en`, `wr_data`, `full`, `almost_full`, `wr_used`, `wptr_bin`, `wptr_gray` | Write acceptance is local and blocked by `full`. |
| Read domain | `rd_en`, `rd_data`, `rd_valid`, `empty`, `almost_empty`, `rd_used`, `rptr_bin`, `rptr_gray` | Standard read data is qualified by `rd_valid`. |
| CDC crossing | `wptr_gray`, `rptr_gray` | Only registered Gray pointers cross through synchronizers. |
| Storage | `fifo_mem` | Payload data is not synchronized bit by bit. |

## Wrapper Reading Map

Read wrappers only after the equal-width core is clear:

| Wrapper | File | Reading goal |
|---|---|---|
| FWFT | `rtl/wrappers/async_fifo_fwft.v` | How read-side prefetch turns request/response timing into visible-data timing. |
| Width conversion | `rtl/wrappers/async_fifo_width_conv.v` | How packing and splitting stay outside the CDC pointer mechanism. |
| Stream | `rtl/wrappers/async_fifo_stream.v` | How ready/valid, `keep`, `last`, and output stability map onto FIFO transfers. |
| Bidirectional | `rtl/wrappers/async_bidir_fifo.v` | How two independent `async_fifo` channels form full-duplex CDC. |
| RAMIF | `rtl/wrappers/async_fifo_ramif.v` | How storage is externalized while pointer/control logic stays local. |
| Bidirectional RAMIF | `rtl/wrappers/async_bidir_ramif_fifo.v` | How two independent RAMIF channels compose. |

Wrappers should not move payload into synchronizers or redefine the core
`full`/`empty` reasoning. If a wrapper adds storage, latency, or protocol
state, the interface docs and verification harnesses should describe that
behavior explicitly.

## Verification Reading Map

| Behavior | Formal or test location |
|---|---|
| Pointer safety and Gray transitions | `formal/pointer_formal.sv` |
| Equal-width FIFO ordering and `rd_valid` | `formal/core_formal.sv`, `test/tb_fifo_basic.sv`, `test/tb_fifo_random.sv` |
| Reset release ordering | `formal/reset_skew_formal.sv`, `test/tb_reset_sync.sv` |
| FWFT behavior | `formal/fwft_formal.sv`, `test/tb_fifo_fwft.sv` |
| Width conversion | `formal/width_conv_formal.sv`, width-conversion tests in `test/tb_fifo_basic.sv` |
| Stream behavior | `formal/stream_formal.sv`, `test/tb_fifo_stream.sv`, stream tests in `test/tb_fifo_random.sv` |
| Bidirectional composition | `formal/bidir_formal.sv`, `test/tb_fifo_bidir.sv` |
| RAMIF behavior | `formal/ramif_formal.sv`, `test/tb_fifo_ramif.sv` |
| Bidirectional RAMIF behavior | `formal/bidir_ramif_formal.sv`, `test/tb_fifo_bidir_ramif.sv` |

For a proof-first explanation, read [Formal Verification Guide](formal_verification.md).
For reproducible command summaries, read [Evidence Center](evidence/README.md).

## Maintenance Boundaries

- Preserve `rtl/async_fifo.v` as the minimal public equal-width entry point.
- Keep the CDC core equal-width.
- Keep width conversion, stream protocol behavior, FWFT behavior, and
  bidirectional composition in wrappers.
- Keep RAMIF as an external-storage boundary, not a new CDC algorithm.
- Update [Interface and Timing](interface.md) before or alongside public
  behavior changes.
- Update tests or formal harnesses when changing accepted transfers, latency,
  reset behavior, capacity, or wrapper state.
