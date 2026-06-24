# Asynchronous FIFO

[中文](README-CN.md)

A compact, learning-oriented asynchronous FIFO RTL project with CDC
constraints, wrappers, simulation/formal checks, and a small PYNQ-Z2 board
demo.

[Use it](#which-module-should-i-use) ·
[Tutorial](docs/tutorial.md) ·
[Learn it](docs/learning_async_fifo.md) ·
[Formal](docs/formal_verification.md) ·
[XPM comparison](docs/xpm_fifo_async_comparison.md) ·
[Interface](docs/interface.md) ·
[Architecture](docs/architecture.md) ·
[CDC constraints](docs/cdc_constraints.md) ·
[Board demo](docs/pynq_z2_vivado.md) ·
[Limitations](#limitations--sign-off-status) ·
[中文](README-CN.md)

## Which module should I use?

| Need | Module | Role |
|---|---|---|
| A small, equal-width asynchronous FIFO | `async_fifo` | **Start here.** Minimal public entry point |
| Different write and read widths | `async_fifo_width_conv` | Optional width-conversion wrapper |
| Ready/valid streaming with `keep` and `last` | `async_fifo_stream` | Optional packet-stream wrapper |

Most users should instantiate `async_fifo`. See
[`examples/basic_fifo/`](examples/basic_fifo/) for the smallest complete
example. The other two modules live under `rtl/wrappers/` to make their role
explicit; they add protocol behavior around the same equal-width core.

Detailed timing, reset, almost-flag, and occupancy semantics are centralized in
[Interface and Timing](docs/interface.md). The implementation layers are shown
in [Architecture](docs/architecture.md). If you want to study the design rather
than only instantiate it, start with the [step-by-step tutorial](docs/tutorial.md),
then read
[Learning Async FIFO](docs/learning_async_fifo.md).

## Learning roadmap

| Reader | Start here | Then read |
|---|---|---|
| First-time async FIFO learner | [Step-by-step tutorial](docs/tutorial.md) | [Learning Async FIFO](docs/learning_async_fifo.md) |
| RTL integrator | [Which module should I use?](#which-module-should-i-use) | [Interface and Timing](docs/interface.md) |
| Verification reader | [Learning Async FIFO](docs/learning_async_fifo.md) | [Formal Verification Guide](docs/formal_verification.md) |
| Vendor-IP comparer | [Interface and Timing](docs/interface.md) | [XPM_FIFO_ASYNC Comparison](docs/xpm_fifo_async_comparison.md) |
| CDC/timing reviewer | [Architecture](docs/architecture.md) | [CDC Constraints](docs/cdc_constraints.md) |
| Board-flow user | [Simple board demo](#simple-board-demo) | [PYNQ-Z2 Vivado Validation](docs/pynq_z2_vivado.md) |

The core async FIFO structure follows the well-known Cummings/Sunburst
style: binary pointers for local arithmetic, Gray pointers for CDC, two-flop
pointer synchronizers, and local-domain full/empty generation. See
[Theory references](#theory-references) for the paper links.

## Architecture at a glance

![Async FIFO core and wrapper architecture](docs/assets/architecture.svg)

The core stays equal-width and owns the CDC mechanism. Width conversion and
stream packet handling are explicit wrappers around that same core.

## Waveform snapshot

![Representative async FIFO waveform](docs/assets/async_fifo_waveform.svg)

The write and read clocks are unrelated. Writes are accepted in the write
domain, the read domain sees availability after Gray-pointer synchronization,
and consumers qualify returned data with `rd_valid`.

## Simple board demo

The PYNQ-Z2 example builds a synthesizable smoke test for
`xc7z020clg400-1`: a 100 MHz write clock and 75 MHz read clock move a counter
sequence through the FIFO. LED0 is a sticky mismatch indicator, LED2 blinks
only after successful reads, and LED3 shows MMCM lock.

```bash
make pynq-z2
```

See [PYNQ-Z2 Vivado Validation](docs/pynq_z2_vivado.md) for the bitstream path,
report checklist, LED behavior, and the exact Vivado 2025.2 validation result.

## Limitations / sign-off status

This is a reusable and well-checked learning project, not a blanket production
sign-off package.

- FIFO depth is a power of two.
- Width conversion supports integer power-of-two ratios.
- Reset is destructive; data-preserving unilateral runtime reset is not
  supported.
- Almost flags and occupancy values are local-domain flow-control views, not
  simultaneous global snapshots.
- Open-source simulation/formal checks are bounded and parameter-sampled.
- Xilinx constraints are implementation-validated for the included Vivado
  flows; Intel constraints are provided as a template.
- Real products still need device-, clock-, and integration-specific STA, CDC,
  reset, DRC, and methodology review.

## Read before integration

The repository provides three synthesizable FIFO entry points. Select one
according to the transaction semantics:

- `async_fifo`: equal-width request interface;
- `async_fifo_width_conv`: request interface with an integer power-of-two
  width ratio;
- `async_fifo_stream`: packet-aware `ready/valid`, `keep`, and `last`
  interface, recommended for new streaming integrations.

It also provides `async_reset_sync`, a reusable integration helper for
asynchronous reset assertion and synchronous release in one clock domain.

The following contracts are mandatory:

1. **Transfer qualification:** request transfers occur only on local clock
   edges satisfying `wr_rstn && wr_en && !full` or
   `rd_rstn && rd_en && !empty`; qualify returned
   data with `rd_valid`. Stream transfers occur only on `valid && ready`.
2. **Reset semantics:** `wr_rstn` and `rd_rstn` are active-low asynchronous
   reset inputs. They may assert asynchronously, but the integrator must
   deassert each reset synchronously in its local domain. Reset is destructive;
   do not transfer until both domains complete coordinated initialization.
   Data-preserving unilateral runtime reset is unsupported.
3. **Depth and width:** core depth is a power of two. Width conversion requires
   an integer power-of-two ratio and enough `ADDR_WIDTH` for at least two
   internal wide words.
4. **Capacity units:** `ADDR_WIDTH` describes narrow-word-equivalent core RAM
   capacity, excluding wrapper pack, pending, split, and prefetch slots.
   `wr_core_used/rd_core_used` count only the core, not all in-flight beats.
5. **Local status views:** flags and occupancy are generated in their owning
   domains. Remote-pointer synchronization conservatively delays flag
   deassertion; these signals are not a simultaneous global occupancy snapshot.
   Almost flags are advisory flow-control hints, not transfer qualifiers.
6. **CDC constraints:** payload stays in dual-port RAM; only registered
   Gray-coded pointers cross domains. Two-flop synchronizers do not replace
   STA/CDC sign-off. Constrain maximum delay or bus skew from each Gray source
   bank to its first synchronizer stage.
7. **Verification scope:** simulation and 45 formal tasks combine deep fixed
   schedules, symbolic clock-rate/phase BMCs, and a concrete parameter matrix.
   They are not one symbolic proof over every integer parameter, continuously
   varying clock waveform, or target device.

In this documentation, a *beat* is one interface transfer, a *core word* is one
equal-width internal RAM item, and a *payload* includes data plus metadata. BMC
means bounded model checking; cover tasks establish bounded reachability.

## 1. Project structure

```text
async_FIFO/
├── rtl/
│   ├── async_fifo.v             # Minimal public equal-width entry point
│   ├── files.f                  # RTL file list
│   ├── core/
│   │   ├── async_fifo_core.v    # Equal-width asynchronous FIFO
│   │   ├── fifo_mem.v           # Dual-clock simple dual-port RAM
│   │   ├── wptr_full.v          # Write pointer and full flag
│   │   ├── rptr_empty.v         # Read pointer and empty flag
│   │   ├── sync_w2r.v           # Write pointer into read domain
│   │   └── sync_r2w.v           # Read pointer into write domain
│   ├── wrappers/
│   │   ├── async_fifo_width_conv.v # Optional width-conversion wrapper
│   │   └── async_fifo_stream.v     # Optional packet-stream wrapper
│   └── util/
│       └── async_reset_sync.v       # Async-assert/sync-release reset helper
├── examples/
│   ├── basic_fifo/              # Smallest equal-width integration
│   └── pynq_z2/                 # FPGA board validation design
└── test/
    ├── tb_reset_sync.sv         # Reset synchronizer behavior test
    ├── tb_fifo_basic.sv         # Basic and almost-flag tests
    ├── tb_fifo_stream.sv        # Packet, keep/last, and backpressure tests
    ├── tb_fifo_random.sv        # Boundary, wrap, and random scoreboard tests
    ├── fifo_assertions.sv       # FIFO pointer assertions
    ├── stream_assertions.sv     # Ready/valid stability assertions
    └── xilinx/multi_fifo_top.v  # Vivado multi-instance validation top

constraints/
├── xilinx/async_fifo.xdc        # Scoped Vivado constraint template
├── xilinx/check_async_fifo.tcl  # Exact post-synthesis object checks
└── intel/async_fifo.sdc         # Quartus/TimeQuest template

scripts/
├── check_cdc.py                 # Source-level synchronizer structure check
├── check_parameters.sh          # Invalid-parameter diagnostic checks
├── check_release.py             # Release-version consistency check
├── validate_xilinx_template.tcl # Single-instance Vivado validation
└── validate_xilinx_multi.tcl    # Multi-instance positive/negative validation

formal/
├── pointer_formal.sv            # Local pointer safety proof harness
├── pointer.sby                  # Pointer proof configuration
├── core_formal.sv               # Multiclock core/data-order harness
├── core.sby                     # Core BMC/cover configuration
├── anyclock_core_formal.sv      # Symbolic clock-rate/phase core harness
├── anyclock_core.sby            # Symbolic-clock BMC configurations
├── reset_skew_formal.sv         # Write-first/read-first reset-release harness
├── reset_skew.sby               # Reset-skew BMC/cover configuration
├── stream_reset_skew_formal.sv  # Packet-stream reset-release harness
├── stream_reset_skew.sby        # Stream reset-skew BMC/cover configuration
├── matrix_formal.sv             # Parameter-matrix wrapper harnesses
├── matrix.sby                   # 20 width/ratio/address BMC tasks
├── matrix_cover.sby             # Ratio-4 non-vacuity covers
├── width_conv_formal.sv         # Pack/split wrapper order harnesses
├── width_conv.sby               # Width-conversion BMC/cover configuration
├── stream_formal.sv             # Packet metadata/backpressure harnesses
└── stream.sby                   # Stream-wrapper BMC/cover configuration
```

The project provides three reusable FIFO entry points:

```text
async_fifo                   equal width: DATA_WIDTH/ADDR_WIDTH
└── async_fifo_core

async_fifo_width_conv        width conversion: WDATA_WIDTH/RDATA_WIDTH/ADDR_WIDTH
└── async_fifo_core          conventional equal-width async FIFO core
    ├── fifo_mem
    ├── wptr_full
    ├── rptr_empty
    ├── sync_w2r
    └── sync_r2w

async_fifo_stream            recommended packet-streaming interface
└── async_fifo_core          stores {data, keep, last} as one payload

async_reset_sync             optional per-domain reset integration helper
```

Use `async_fifo` for a simple equal-width FIFO,
`async_fifo_width_conv` for request-based width conversion, and
`async_fifo_stream` for packet-streaming integrations.

## 2. Parameter configuration

### 2.1 Equal-width FIFO: `async_fifo`

| Parameter | Meaning | How to set it |
|---|---|---|
| `DATA_WIDTH` | Bits in each FIFO word | Match the data-bus width, such as 8, 16, 32, or 64 |
| `ADDR_WIDTH` | RAM address width | FIFO depth is `2**ADDR_WIDTH` words |
| `ALMOST_FULL_THRESHOLD` | High occupancy watermark | Defaults to depth minus one |
| `ALMOST_EMPTY_THRESHOLD` | Low occupancy watermark | Defaults to one word |

```text
FIFO depth    = 2**ADDR_WIDTH words
total capacity = DATA_WIDTH × 2**ADDR_WIDTH bits
pointer width = ADDR_WIDTH + 1 bits
```

Example: a 32-bit, 512-word FIFO:

```verilog
async_fifo #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(9)       // 2**9 = 512 words
) u_async_fifo (
    .wr_clk   (wr_clk),
    .wr_rstn  (wr_rstn),
    .wr_en    (wr_en),
    .wr_data (wr_data),
    .full     (full),
    .almost_full (almost_full),
    .wr_used  (wr_used),
    .rd_clk   (rd_clk),
    .rd_rstn  (rd_rstn),
    .rd_en    (rd_en),
    .rd_data (rd_data),
    .rd_valid (rd_valid),
    .empty    (empty),
    .almost_empty(almost_empty),
    .rd_used  (rd_used)
);
```

For a known depth:

```text
ADDR_WIDTH = log2(FIFO depth)
```

The current Gray-pointer implementation requires a power-of-two depth.

### 2.2 Width-converting FIFO: `async_fifo_width_conv`

| Parameter | Meaning | How to set it |
|---|---|---|
| `WDATA_WIDTH` | Write-interface width | Match the producer bus |
| `RDATA_WIDTH` | Read-interface width | Match the consumer bus |
| `ADDR_WIDTH` | Address width measured in narrower words | Narrow-side depth is `2**ADDR_WIDTH` |
| `ALMOST_FULL_THRESHOLD` | High watermark | Measured in internal wide core words |
| `ALMOST_EMPTY_THRESHOLD` | Low watermark | Measured in internal wide core words |

Example: 16-bit writes, 32-bit reads, and 1024 narrow words:

```verilog
async_fifo_width_conv #(
    .WDATA_WIDTH(16),
    .RDATA_WIDTH(32),
    .ADDR_WIDTH (10)
) u_async_fifo_width_conv (
    // ports
);
```

```text
width ratio        = 2
narrow-side depth  = 2**10 = 1024
core data width    = 32 bits
core address width = 10 - log2(2) = 9
core depth         = 2**9 = 512
core RAM capacity  = 1024×16 = 512×32 bits
```

The width ratio must be a power of two, and
`ADDR_WIDTH > log2(width ratio)`.

`ADDR_WIDTH` specifies core RAM capacity, not the complete wrapper pipeline.
For a width ratio `R`, the request-based converter can hold one additional
wide-word equivalent in its local pack/pending or split buffer. The example
therefore has 1024 narrow-word equivalents in RAM and up to two additional
16-bit items in wrapper-local storage. `wr_core_used` and `rd_core_used`
intentionally count only the 512-word core.

Capacity contract:

```text
R = width ratio
N = 2**ADDR_WIDTH narrow-word equivalents in core RAM
C = N / R internal wide words

equal width             maximum in flight = N interface words
narrow write/wide read maximum in flight = N + R narrow words
wide write/narrow read maximum in flight = C + 1 wide writes
                                      = N + R narrow slices
```

The extra `R` narrow-word equivalents are one wrapper-local wide word, not
additional addressable RAM. See [Interface and Timing](docs/interface.md) for
the stream wrapper's separate write/read pipeline bound.

## 3. Theory references

The async FIFO core follows the recommended Cummings/Sunburst structure:

- binary counters are used locally for address arithmetic;
- binary pointers are converted to reflected Gray code before crossing domains;
- each Gray pointer is synchronized into the opposite clock domain;
- `empty` is generated in the read domain and `full` in the write domain;
- pointer/flag logic predicts the next pointer so registered flags describe
  whether the next local transfer is legal.

Primary references:

- Clifford E. Cummings, *Simulation and Synthesis Techniques for Asynchronous
  FIFO Design*, SNUG San Jose 2002, Sunburst Design
  ([technical-library entry](https://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf)).
  This is the closest paper match for this repository's synchronized-pointer
  comparison style.
- Clifford E. Cummings and Peter Alfke, *Simulation and Synthesis Techniques
  for Asynchronous FIFO Design with Asynchronous Pointer Comparisons*, SNUG San
  Jose 2002
  ([technical-library entry](https://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf)).
  This companion paper is useful context, but this repository does not
  implement its asynchronous pointer-comparison style.

The tutorial gives the waveform-first view. The learning guide gives the
mechanism in reading order. The interface document is authoritative for
`rd_valid`, almost flags, wrapper capacity, reset, and transfer acceptance.

## 4. Parameter restrictions

This implementation requires:

1. an integer relationship between `WDATA_WIDTH` and `RDATA_WIDTH`;
2. a power-of-two width ratio;
3. `ADDR_WIDTH` equal to the `log2` of the narrow-side depth;
4. a derived internal address width of at least one;
5. a power-of-two FIFO core depth.

Example:

```text
WDATA_WIDTH = 16
RDATA_WIDTH = 32
ADDR_WIDTH  = 10

CORE_WIDTH  = 32
WIDTH_RATIO = 2
CORE_ADDR_WIDTH = 9
CORE_DEPTH      = 512 wide words
```

The core RAM capacity remains:

```text
1024 × 16 bits = 512 × 32 bits
```

This value excludes wrapper-local elasticity. The request-based converter can
hold one additional wide-word equivalent. The stream wrapper can hold one
write-side payload and up to two prefetched read-side payloads in addition to
the core. These local slots affect total in-flight data but are intentionally
excluded from `*_core_used`.

## 5. Mapping eight core questions to this RTL

| Study question | Project implementation |
|---|---|
| Purpose of an asynchronous FIFO | `async_fifo_width_conv` and `async_fifo_core` |
| Understanding empty and full | extended read/write pointers |
| Why Gray code is used | `wptr_full` and `rptr_empty` |
| Pointer synchronization direction | `sync_w2r` and `sync_r2w` |
| Empty/full equations | `rempty_next` and `wfull_next` |
| Whether flags are instantaneous | conservative synchronizer latency |
| Non-power-of-two depth | intentionally unsupported |
| Large clock-frequency ratios | engineering notes below |

## 6. Engineering notes

### Conservative empty/full deassertion

Synchronization primarily delays flag deassertion: the FIFO can already contain data while the read domain still sees empty, or already have space while the write domain still sees full. This is safe conservatism.

The goal is not a zero-latency view of the remote pointer. The required guarantees are:

- reading when `empty == 0` must not underflow;
- writing when `full == 0` must not overflow.

### Non-power-of-two depths

Special Gray sequences or alternative encodings can be studied for non-power-of-two FIFO depths, but wrap behavior, full detection, and verification become more involved. This implementation explicitly supports only power-of-two core depths.

In production, using the next larger power-of-two physical depth or a verified vendor FIFO IP is often simpler.

### The protocol defines no universal fixed clock-ratio limit

Missing intermediate Gray states in a slower destination domain is not inherently an error. The destination may observe one legal pointer and later observe a newer legal pointer while its status remains conservative.

The practical concerns are:

- synchronizer MTBF;
- routing skew among Gray-bus bits into the first synchronizer stage;
- STA and CDC constraints;
- reset release behavior;
- device technology and the required reliability target.

Logical one-bit Gray transitions do not automatically guarantee the required
physical arrival relationship after place and route. A production design
should constrain maximum delay or bus skew on each Gray crossing and run STA
and CDC analysis. The usable clock ratio is ultimately limited by throughput,
synchronizer MTBF, physical implementation, and system-level flow control.

## 7. Reset considerations

The write and read sides use separate active-low asynchronous resets:

```text
wr_rstn -> write pointer, full flag, read-pointer synchronizer
rd_rstn -> read pointer, empty flag, write-pointer synchronizer
```

Recommended system-level practice:

- reset may assert asynchronously;
- each reset must deassert synchronously in its local clock domain;
- local reset gates each RAM port, so a request held high during reset cannot
  access memory;
- unilateral reset while the other side continues transferring is outside the
  supported contract.

The reusable `async_reset_sync` module implements asynchronous assertion and
configurable synchronous release, with `STAGES >= 2`. Instantiate one copy in
every unrelated clock domain and feed its output to that domain's FIFO reset
input. It synchronizes reset release only; it does not make unilateral runtime
reset data-preserving.

The current RTL assumes both domains initialize to a consistent empty state.
Reset is destructive: queued data is discarded, and RAM contents and read data
are invalid during reset. Vendor DRC warnings caused by asynchronously reset
pointers driving block-RAM addresses require a reviewed waiver under these
conditions; they do not justify data-preserving one-sided reset.

## 8. Interface behavior

A write is accepted only when:

```text
wr_rstn && wr_en && !full
```

A read is accepted only when:

```text
rd_rstn && rd_en && !empty
```

Both request-based FIFO modules expose `rd_valid` for synchronous read timing.
Packet-streaming integrations should prefer `async_fifo_stream`, which adds
complete ready/valid backpressure and packet metadata.

For the precise semantics of `full`, `empty`, the almost flags, and all
occupancy outputs, see [Interface and Timing](docs/interface.md). That document
is the single reference for advanced status signals and wrapper-local storage.

## 9. Simulation

Create and activate the reproducible Conda tool environment:

```bash
conda env create -f environment.yml
conda activate async_fifo
```

To update an existing environment after `environment.yml` changes:

```bash
conda env update -n async_fifo -f environment.yml --prune
```

Then run the checks below.

### Quick checks before a PR

| Change area | Start with |
|---|---|
| Markdown only | `make docs-check` |
| Tutorial waveform | `make tutorial` and `make docs-check` |
| Equal-width FIFO RTL | `make tb_equal_width tb_fifo_random` |
| Width-conversion wrapper | `make tb_pack_16_to_32 tb_split_32_to_16` |
| Stream wrapper | `make tb_fifo_random tb_stream_random` |
| CDC or constraints | `make cdc` and `make synth` |
| Formal harnesses | the matching `sby -f ...` task, then `make formal` |
| Release metadata | `make release-check` |

Before opening a broader PR, run `make check` in the `async_fifo` Conda
environment. See [Contributing](CONTRIBUTING.md) for the full contributor
checklist.

Run all tests:

```bash
make test
```

Check that invalid parameter combinations fail with clear diagnostics:

```bash
make params
```

Check that `VERSION`, the FuseSoC core, compatibility document, and changelog
describe the same release:

```bash
make release-check
```

Run Verilator lint:

```bash
make lint
```

Run source-level CDC structure and Yosys synthesis checks:

```bash
make cdc
make synth
```

With Vivado 2025.2 available, synthesize the default and multi-instance
elaborations and run exact scoped CDC collection checks:

```bash
make xilinx-cdc
```

The negative cases must reject a wrong pointer width, missing hierarchy, and
ambiguous hierarchy. The same post-synthesis checker is used by the PYNQ
implementation flow.

Run the SymbiYosys pointer/core proofs and wrapper BMC/cover checks:

```bash
make formal
```

Run the complete open-source CI check set:

```bash
make check
```

`make check` does not invoke proprietary Vivado. When enabled, the separate
self-hosted Xilinx CI job additionally runs `make xilinx-cdc`.

### PYNQ-Z2 Vivado implementation

A board-specific validation design is included for the PYNQ-Z2
(`xc7z020clg400-1`). It uses the 125 MHz PL clock, generates 100 MHz write and
75 MHz read clocks, continuously transfers a counter sequence, reports a
sticky mismatch on LED0, and shows successful read progress on LED2.

```bash
make pynq-z2
```

Vivado writes CDC, timing, exception-coverage, bus-skew, and utilization
reports under `examples/pynq_z2/reports/`. See
[PYNQ-Z2 Vivado Validation](docs/pynq_z2_vivado.md) for report interpretation
and LED behavior.

The design has been synthesized, placed, routed, DRC-checked, and written to
bitstream locally with Vivado 2025.2 for `xc7z020clg400-1`. Post-route WNS is
5.625 ns, WHS is 0.115 ns, both 10-bit Gray crossings have 100% exception
coverage, both bus-skew constraints pass, and the 512 x 32 memory maps to one
RAMB18E1. The batch build fails on incomplete Gray collections, negative
setup/hold slack, bus-skew violations, DRC errors, or a missing bitstream.

Examples of running individual simulation tops are:

```bash
iverilog -g2012 \
  -s tb_equal_width \
  -o /tmp/tb_equal.out \
  -f rtl/files.f \
  test/tb_fifo_basic.sv
vvp /tmp/tb_equal.out
```

```bash
iverilog -g2012 \
  -s tb_pack_16_to_32 \
  -o /tmp/tb_pack.out \
  -f rtl/files.f \
  test/tb_fifo_basic.sv
vvp /tmp/tb_pack.out
```

```bash
iverilog -g2012 \
  -s tb_split_32_to_16 \
  -o /tmp/tb_split.out \
  -f rtl/files.f \
  test/tb_fifo_basic.sv
vvp /tmp/tb_split.out
```

The complete `make test` output includes:

```text
PASS: async reset assertion and two-stage synchronous release
PASS: parameterized equal-width FIFO
PASS: programmable almost-full/almost-empty flags
PASS: 16-bit write to 32-bit read
PASS: 32-bit write to 16-bit read
PASS: width-converter completed-word buffer
PASS: stream 16-to-32 keep/last and backpressure
PASS: stream 32-to-16 keep/last
PASS: full, empty, blocked access, occupancy, and wraparound
PASS: reset blocks RAM access and normal transfer resumes
PASS: randomized 7ns/11ns clocks and scoreboard (... transfers)
PASS: randomized stream scoreboard and backpressure (1200 beats)
PASS: stream accepts one write beat per clock without bubbles
PASS: stream produces one equal-width read beat per clock
PASS: stream produces one split read beat per clock
PASS: randomized stream 16-to-32 width conversion (... outputs)
PASS: randomized stream 32-to-16 width conversion (... outputs)
```

## 10. Verification and engineering status

- [x] equal-width, full, empty, blocked-access, and repeated-wrap tests;
- [x] reset-time RAM access gating and post-reset recovery test;
- [x] reusable async-assert/sync-release reset integration module and test;
- [x] randomized 7 ns / 11 ns clock-ratio test with a data scoreboard;
- [x] randomized stream scoreboard with packet metadata and backpressure;
- [x] continuous one-write-beat-per-clock elastic-buffer test;
- [x] continuous one-read-beat-per-clock prefetch tests for equal-width and
  wide-to-narrow streams;
- [x] randomized 16-to-32 and 32-to-16 width-conversion scoreboards;
- [x] executable SystemVerilog assertions for blocked-pointer stability and
  one-bit-or-zero Gray transitions;
- [x] source-level CDC synchronizer structure checks in CI;
- [x] release-version consistency checks in CI;
- [x] implementation-validated Xilinx Vivado constraint flow;
- [x] Intel Quartus/TimeQuest constraint template, explicitly marked as not
  implementation-validated;
- [x] instance-scoped Xilinx CDC constraints with exact single- and
  multi-instance post-synthesis positive/negative validation;
- [x] local-domain `wr_used/rd_used` and explicit core-only
  `wr_core_used/rd_core_used` occupancy views;
- [x] explicit ready/valid packet-streaming top level;
- [x] local SymbiYosys pointer proofs for Gray transitions and blocked access;
- [x] 96-frame coprime-clock SymbiYosys core BMC for occupancy, flags,
  `rd_valid`, and end-to-end data ordering, plus full/post-depth covers;
- [x] symbolic write/read clock-rate and initial-phase core BMCs at
  `ADDR_WIDTH=1/2`, covering all independently selected phase increments
  from 2 through 7 within the stated bounds;
- [x] write-first and read-first synchronous reset-release BMCs, with covers
  demonstrating normal ordered transfers after both domains initialize;
- [x] matching packet-stream reset-release BMCs through the 8-to-16 pack path,
  with reachable final/non-final packet transfers and backpressure checks;
- [x] four 64-frame pack/split wrapper BMCs for width conversion, packet
  metadata, output ordering, and ready/valid stability under backpressure;
- [x] four wrapper cover tasks reaching full, repeated request-interface
  reads, stream final/non-final transfers, and both packing directions
  (160 frames for request conversion and 96 frames for packet streaming);
- [x] a 20-task, 64-frame wrapper parameter matrix spanning request and stream
  interfaces, `ADDR_WIDTH=2/3/4/5`, 8/16-bit equal-width cases, and
  bidirectional 1:2/1:4/1:8 conversion, plus four ratio-4 repeated-output
  covers;
- [x] warning-free Verilator `-Wall` lint, with warnings treated as errors;
- [x] automated invalid-parameter diagnostic checks.

The deep wrapper harnesses retain representative fixed parameters for packet
corner cases and reset skew. The parameter matrix adds concrete elaborations
across four address widths, two equal widths, and ratios 1/2/4/8 using the
coprime 2/3 schedule. A separate core layer symbolically selects independent
clock increments and read-clock initial phase. These are complementary
bounded checks, not one proof over every integer parameter or every possible
time-varying clock waveform.

Open-source CI uses separate simulation and formal tool containers pinned by
immutable sha256 image digests. The `actions/checkout` action is also pinned
to a full commit SHA; tool versions are printed at the start of each job.
Xilinx CDC validation is a third CI job on a licensed self-hosted Vivado
2025.2 runner when repository variable `XILINX_CI_ENABLED=true`; a skipped job
is not vendor sign-off.

The included CDC script catches source-level structural regressions. The
Vivado scripts additionally check synthesized object collections, but neither
mechanism replaces project-specific post-route timing, `report_cdc`,
methodology/DRC review, or an equivalent commercial sign-off flow. The Intel
file remains a Quartus/TimeQuest template and has not been implementation
validated.

> Before real-hardware use, complete post-synthesis/post-route CDC, Gray-bus
> skew, and timing checks for the selected device, clocks, and tool version.

## License

This project is licensed under the [MIT License](LICENSE).
