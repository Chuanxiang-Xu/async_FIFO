# XPM_FIFO_ASYNC Comparison

This document compares this teaching RTL project with AMD/Xilinx
`XPM_FIFO_ASYNC`. It is not a replacement for AMD documentation, and this
repository is not a vendor-IP clone. The goal is to show which industrial FIFO
expectations this project intentionally follows, where it differs, and what
remains out of scope.

The reference point is AMD UG974, `XPM_FIFO_ASYNC`, version 2026.1:

- <https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/XPM_FIFO_ASYNC>

## Summary

| Topic | `XPM_FIFO_ASYNC` expectation | This repository |
|---|---|---|
| Purpose | Vendor macro for production AMD/Xilinx FPGA designs | Readable, runnable, verifiable teaching RTL |
| Main request interface | `wr_en/full`, `rd_en/empty`, `din/dout`, `data_valid` | `wr_en/full`, `rd_en/empty`, `wr_data/rd_data`, `rd_valid` |
| Read modes | Standard and FWFT via `READ_MODE` | Standard synchronous read plus an equal-width FWFT wrapper; no XPM-compatible `READ_MODE` parameter |
| Read latency | Configurable with `FIFO_READ_LATENCY` in standard mode | One synchronous RAM read response marked by `rd_valid` |
| Reset | Single `rst`, synchronous to `wr_clk`, plus `wr_rst_busy` and `rd_rst_busy` | Separate active-low domain resets; async assert, local sync release required |
| CDC stages | `CDC_SYNC_STAGES` parameter | Fixed two-flop pointer synchronizers in the core |
| Width conversion | Supported by `WRITE_DATA_WIDTH`/`READ_DATA_WIDTH` with documented ratios | Kept outside the equal-width CDC core in wrappers |
| Counts | `wr_data_count`, `rd_data_count` with configurable widths | `wr_used/rd_used` for equal-width; `*_core_used` for wrappers |
| Almost/prog flags | `almost_*` plus `prog_*` thresholds/features | Static `almost_*` thresholds; no separate `prog_*` ports |
| Error/status features | `wr_ack`, `overflow`, `underflow`, ECC error/injection, sleep | Not implemented; tests/formal prove blocked operations are non-destructive |
| Memory selection | `FIFO_MEMORY_TYPE`, ECC, cascade-related attributes | Portable inferred RAM, no RAM-type selection parameter |
| Sign-off model | Vendor macro plus AMD tool/report expectations | Open RTL plus documented CDC constraints, tests, and bounded formal checks |

## From Industrial Expectation to Teaching RTL Contract

Use this table when reading XPM-style requirements as an integrator. The
project often supports the underlying FIFO behavior, but exposes it through a
smaller teaching contract instead of an AMD-compatible macro interface.

| XPM-style expectation | This repository's contract | Where to read next |
|---|---|---|
| Independent write and read clocks | Supported. The equal-width core crosses only registered Gray pointers; payload stays in dual-port RAM. | [Architecture](architecture.md), [CDC and Timing Constraints](cdc_constraints.md) |
| Request-based write/read enables | Supported for `async_fifo`, `async_fifo_fwft`, and `async_fifo_width_conv`; stream users should use ready/valid instead. | [Interface and Timing](interface.md#transfer-qualification-summary) |
| Standard synchronous read mode | Supported by `async_fifo`; `rd_valid` marks the cycle where the returned `rd_data` should be sampled. | [Interface and Timing](interface.md#equal-width-interface-async_fifo), [tutorial waveform](tutorial.md#a-real-waveform) |
| First-word fallthrough read mode | Supported as the separate `async_fifo_fwft` wrapper; `rd_valid` is a visible-data level signal and `rd_en && rd_valid` pops the word. | [FWFT / Fallthrough Design Notes](fwft_design.md), [Interface and Timing](interface.md#equal-width-fwft-interface-async_fifo_fwft) |
| Reset and reset-busy integration | Reset is destructive with separate active-low domain resets; assertion may be asynchronous, but release must be synchronized locally. No `*_rst_busy` ports are exposed. | [Interface and Timing](interface.md), [`async_reset_sync`](../rtl/util/async_reset_sync.v) |
| Almost and programmable flags | Static `almost_full` and `almost_empty` thresholds are supported as advisory local-domain flow-control hints. Separate dynamic `prog_*` ports are not supported. | [Interface and Timing](interface.md#advanced-status-signals) |
| Data count visibility | Equal-width `wr_used/rd_used` and wrapper `*_core_used` are conservative local views, not global snapshots or exact wrapper-pipeline occupancy. | [Interface and Timing](interface.md#advanced-status-signals) |
| Width conversion | Supported in wrappers while preserving an equal-width CDC core. Capacity is documented in core-word and wrapper-local storage terms. | [Interface and Timing](interface.md#width-converting-interface-async_fifo_width_conv) |
| Overflow and underflow reporting | Blocked writes and reads are non-destructive, but no `overflow` or `underflow` pulse ports are provided. | [Formal Verification Guide](formal_verification.md#from-requirement-to-property) |
| ECC, sleep, memory primitive selection, cascade controls | Not supported. These are vendor implementation features outside this teaching RTL boundary. | [Unsupported XPM Features](#unsupported-xpm-features), [Limitations in README](../README.md#limitations--sign-off-status) |

## Interface Alignment

Both designs use the same basic request idea: a write occurs only when the
write request is made while not full, and a read occurs only when the read
request is made while not empty. This project names the data ports
`wr_data/rd_data` and names the read-valid pulse `rd_valid`; XPM names the
corresponding ports `din/dout` and `data_valid`.

This project deliberately exposes a smaller public contract:

```text
wr_rstn && wr_en && !full   accepts a write
rd_rstn && rd_en && !empty  accepts a read
rd_valid                   qualifies rd_data
```

XPM also provides industrial status and diagnostic ports such as `wr_ack`,
`overflow`, `underflow`, `wr_data_count`, `rd_data_count`, `wr_rst_busy`,
`rd_rst_busy`, ECC error flags, and sleep support. This repository omits those
features unless they directly serve the teaching path.

## Parameters

| XPM parameter area | Closest project concept | Notes |
|---|---|---|
| `FIFO_WRITE_DEPTH` | `2**ADDR_WIDTH` | Both use power-of-two depth. XPM documents effective depth details by read mode; this project documents core and wrapper capacity separately. |
| `WRITE_DATA_WIDTH`, `READ_DATA_WIDTH` | `DATA_WIDTH` or wrapper `WDATA_WIDTH/RDATA_WIDTH` | The core stays equal-width. Width conversion is wrapper logic around the core. |
| `READ_MODE` | Not supported as an XPM-compatible parameter | `async_fifo` remains standard synchronous read; `async_fifo_fwft` provides a separate equal-width FWFT wrapper. |
| `FIFO_READ_LATENCY` | Fixed synchronous RAM response | This project does not expose a configurable output pipeline. |
| `CDC_SYNC_STAGES` | Two-flop synchronizers | The core is intentionally simple and fixed for teaching. |
| `PROG_FULL_THRESH`, `PROG_EMPTY_THRESH` | `ALMOST_FULL_THRESHOLD`, `ALMOST_EMPTY_THRESHOLD` | Project thresholds are static parameters and expose only `almost_*`, not separate `prog_*` ports. |
| `FIFO_MEMORY_TYPE`, `ECC_MODE`, `CASCADE_HEIGHT`, `WAKEUP_TIME` | No equivalent | Vendor implementation/resource features are intentionally out of scope. |

## Reset Differences

XPM uses `rst` with `wr_rst_busy` and `rd_rst_busy` outputs, and AMD documents
that user logic should not toggle enables while reset or busy signals are
active.

This repository instead has separate resets:

```text
wr_rstn  write-domain reset
rd_rstn  read-domain reset
```

They may assert asynchronously, but release must be synchronized in the local
domain by the integrating system. The helper
[`rtl/util/async_reset_sync.v`](../rtl/util/async_reset_sync.v) implements that
pattern. Reset is destructive, and data-preserving one-sided runtime reset is
not supported.

## Read Mode and `rd_valid`

XPM supports standard mode and FWFT mode. In standard mode, `data_valid`
depends on the configured read latency. In FWFT mode, the first word can appear
without a normal read-request latency.

The main `async_fifo` entry point implements standard synchronous-read behavior:

- `rd_en && !empty` accepts a read request;
- the RAM updates `rd_data` on the read clock edge;
- `rd_valid` marks the cycle where `rd_data` should be sampled.

For a concrete waveform, see the
[step-by-step tutorial](tutorial.md#a-real-waveform). The separate
`async_fifo_fwft` wrapper implements the teaching-project FWFT contract
described in [FWFT / Fallthrough Design Notes](fwft_design.md); it is not an
attempt to clone every XPM `READ_MODE="fwft"` detail.

## Width Conversion

XPM treats asymmetric write/read widths as part of the macro parameter set.
AMD documents supported ratios around `WRITE_DATA_WIDTH` and `READ_DATA_WIDTH`.

This project keeps the CDC core equal-width:

```text
async_fifo_core: equal-width RAM, pointers, full/empty, synchronizers
wrappers:       pack/split or ready/valid packet behavior
```

That split is a teaching choice. It keeps Gray-pointer CDC reasoning independent
from width conversion. See [Interface and Timing](interface.md) for wrapper
capacity and `*_core_used` semantics.

## Status Flags and Counts

XPM has a richer status surface:

- `full`, `empty`, `almost_full`, `almost_empty`;
- `prog_full`, `prog_empty`;
- `wr_data_count`, `rd_data_count`;
- `wr_ack`, `overflow`, `underflow`;
- ECC flags when ECC is enabled.

This repository exposes only the status needed for the teaching contract:

- `full` and `empty` are transfer qualifiers;
- `almost_full` and `almost_empty` are advisory flow-control hints;
- `wr_used/rd_used` are local-domain core views for equal-width FIFOs;
- `wr_core_used/rd_core_used` intentionally exclude wrapper-local storage.

Blocked writes and reads are non-destructive, but there are no `overflow` or
`underflow` output pulses. That behavior is checked by simulation and formal
properties rather than exposed as ports.

## CDC and Sign-Off

XPM is a vendor macro intended to integrate with AMD implementation flows. This
repository provides open RTL, source-level CDC checks, Xilinx/Intel constraint
templates, simulation, and bounded formal verification. Those checks are useful
for learning and regression, but they do not replace target-specific
post-synthesis and post-route CDC/timing sign-off.

See [CDC and Timing Constraints](cdc_constraints.md) for this repository's
physical implementation boundary.

## Unsupported XPM Features

This project intentionally does not implement:

- an XPM-compatible `READ_MODE` parameter;
- configurable `FIFO_READ_LATENCY`;
- `wr_rst_busy` / `rd_rst_busy`;
- `wr_ack`, `overflow`, and `underflow` output ports;
- dynamic programmable flag ports;
- ECC encode/decode and error injection;
- sleep/power-saving controls;
- RAM primitive selection or cascade controls;
- a complete vendor-macro compatibility wrapper.

These are valid industrial FIFO features. They are omitted here to preserve the
core learning path: Cummings-style CDC, readable RTL, runnable tests, formal
properties, and explicit sign-off boundaries.
