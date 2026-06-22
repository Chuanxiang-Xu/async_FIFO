# Asynchronous FIFO: Reusable RTL, CDC Constraints, and Verification Guide

[中文](README-CN.md)

[Interface and timing](docs/interface.md) ·
[CDC constraints](docs/cdc_constraints.md) ·
[Architecture](docs/architecture.md) ·
[PYNQ-Z2 Vivado validation](docs/pynq_z2_vivado.md) ·
[Xilinx CI runner](docs/xilinx_runner.md) ·
[Compatibility](docs/compatibility.md) ·
[Changelog](CHANGELOG.md) ·
[Contributing](CONTRIBUTING.md) ·
[MIT License](LICENSE)

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
in [Architecture](docs/architecture.md).

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

## 3. What does an asynchronous FIFO solve?

The write and read interfaces run in independent clock domains. The FIFO provides:

1. safe data transfer between those domains;
2. buffering when the producer and consumer have different instantaneous rates;
3. integer width conversion in the wrapper.

The payload is stored in dual-port RAM rather than synchronized bit by bit.
Only compact, registered Gray-coded pointers cross the boundary; each
destination domain uses the synchronized remote pointer to make a conservative
RAM-access decision.

## 3.1 Recommended streaming interface

`async_fifo_stream` adds complete ready/valid handshakes and packet metadata:

```verilog
// Write domain
wr_valid, wr_ready, wr_data, wr_keep, wr_last

// Read domain
rd_valid, rd_ready, rd_data, rd_keep, rd_last
```

A transfer occurs only on:

```text
wr_valid && wr_ready
rd_valid && rd_ready
```

When `valid=1` and `ready=0`, the source must keep `valid` asserted and hold
`data`, `keep`, and `last` stable until the handshake. `{data, keep, last}` is
stored as one FIFO payload, so metadata cannot
become separated from its data across the clock boundary.

Data widths must be positive multiples of eight. `keep[0]` describes
`data[7:0]`. The intended packet convention is full `keep` on non-final beats
and a nonzero, contiguous low-order `keep` mask on the final beat.

## 3.2 Why the write-side elastic buffer improves throughput

`pending_payload` is a one-entry elastic buffer between the write interface
and `async_fifo_core`:

```text
write interface -> pack/direct path -> pending_payload -> async FIFO core
```

The core accepts the pending word when:

```verilog
pending_pop = pending_valid && !core_full;
```

The input is ready when the pending register is empty, or when its old word
will leave on the current edge:

```verilog
wr_ready = !pending_valid || !core_full;
```

This creates four relevant state transitions:

| Old pending word leaves | New complete word arrives | Result |
|---:|---:|---|
| 0 | 0 | Keep the current pending state |
| 0 | 1 | Store the new word |
| 1 | 0 | Clear the pending register |
| 1 | 1 | Send the old word and replace it with the new word |

The final case removes the former mandatory bubble. While the core has space,
the direct/equal-width write path can now accept one beat on every `wr_clk`
edge. In narrow-write mode, ordinary narrow slices continue filling
`pack_data`; if a slice completes a wide word on the same edge that the old
pending word leaves, the newly completed word replaces it immediately.

Backpressure remains safe: if `core_full` and `pending_valid` are both high,
`wr_ready` goes low and the source must hold `wr_data`, `wr_keep`, and
`wr_last` stable.

### How randomized width conversion is checked

The verification environment contains independent reference models for both
directions:

- 16-to-32: accepted 16-bit beats are packed little-slice-first; `wr_last`
  flushes an incomplete wide word and the model generates the expected
  32-bit `data/keep/last` tuple;
- 32-to-16: each accepted 32-bit tuple is split into valid low and high
  16-bit slices; a partial final `keep=0011` produces only the low slice.

Both tests randomize packet length, valid gaps, final `keep`, and read-side
backpressure. A scoreboard compares every accepted output tuple, not only the
payload data.

## 4. Why is the pointer one bit wider than the address?

A RAM with `DEPTH = 2^ADDR_WIDTH` needs `ADDR_WIDTH` address bits. Each FIFO pointer has `ADDR_WIDTH + 1` bits.

The low bits address RAM, while the additional MSB records wraparound:

- identical read and write pointers mean empty;
- a write pointer one full depth ahead of the read pointer means full.

For a depth of eight:

```text
RAM address width = 3 bits
FIFO pointer width = 4 bits
```

## 5. Why use Gray-coded pointers?

A binary increment can change several bits at once:

```text
0111 -> 1000
```

If another clock samples during that transition, unequal routing delays can create a mixed value that never existed in the source domain.

Adjacent reflected Gray-code values change only one bit:

```verilog
gray = (binary >> 1) ^ binary;
```

Gray coding limits a normal single-step pointer transition to one crossing bit
and reduces the risk of sampling an incoherent multi-bit transition. It does
not eliminate metastability, so each pointer still requires a dedicated
synchronizer chain.

In this project:

- `sync_w2r` synchronizes the write pointer into the read domain;
- `sync_r2w` synchronizes the read pointer into the write domain;
- `(* ASYNC_REG = "TRUE" *)` identifies the synchronizer registers to FPGA tools.

## 6. Which pointer crosses into which domain?

Flags are generated in the clock domain where they are consumed.

| Flag | Local domain | Remote pointer required |
|---|---|---|
| `empty` | read clock | write pointer |
| `full` | write clock | read pointer |

```text
wptr_gray --sync_w2r--> wptr_gray_sync --rptr_empty--> empty
rptr_gray --sync_r2w--> rptr_gray_sync --wptr_full --> full
```

Synchronization latency makes the flags conservative:

- after a write, `empty` may take several read clocks to deassert;
- after a read, `full` may take several write clocks to deassert.

This can temporarily reduce usable capacity, but it must not permit underflow or overflow.

## 7. Empty and full detection

### Empty

The read domain predicts its pointer after the current accepted read:

```verilog
rptr_bin_next  = rptr_bin + (rinc && !rempty);
rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;
rempty_next    = (rptr_gray_next == wptr_gray_sync);
```

Equality means no unread words remain after that operation.

### Full

For a power-of-two reflected-Gray FIFO, a full write pointer matches the synchronized read pointer with its two most significant bits inverted:

```verilog
FULL_MASK  = {2'b11, {(PTR_WIDTH-2){1'b0}}};
wfull_next = (wptr_gray_next == (rptr_gray_sync ^ FULL_MASK));
```

The two-MSB inversion is specific to this Gray-pointer construction; simply inverting the binary wrap bit is not equivalent.

## 8. Why calculate flags from the next pointer?

Each pointer module determines whether the local request is accepted, calculates the next binary pointer, converts it to Gray code, and computes the next registered flag:

```text
accepted local request
        ↓
binary_next
        ↓
gray_next
        ↓
compare synchronized remote pointer
        ↓
register pointer and flag
```

A write while full and a read while empty do not advance their pointers:

```verilog
winc && !wfull
rinc && !rempty
```

## 9. Dual-port RAM

`fifo_mem` is storage-only. It uses a standard dual-clock simple dual-port RAM inference template:

```verilog
always @(posedge wclk)
    if (wclken)
        mem[waddr] <= wdata;

always @(posedge rclk)
    if (rclken)
        rdata <= mem[raddr];
```

The memory array is intentionally not reset, improving block-RAM inference. Reset pointers and flags prevent stale or unknown locations from being read.

The read port is synchronous. An accepted request updates `rdata` after the read-clock edge, and `async_fifo_core` provides the corresponding `rd_valid` pulse.

## 10. Width conversion

The asynchronous core remains equal-width so every crossing pointer advances by exactly one. Width conversion occurs outside the CDC machinery.

### Narrow write, wide read

Narrow words are packed in the write domain before one wide core write.

For 16-to-32 conversion:

```text
write 16'h0001, then 16'h0002
stored core word = 32'h0002_0001
```

#### Legacy half-pack blocking and its solution

The original `async_fifo_width_conv` wrapper wrote a completed packed word directly into
the core. If the core became full while a word was partially packed, the last
narrow slice could not be accepted until the read side released space. This
was recoverable, but it could participate in a system-level circular wait.

The wrapper now has a one-word completed-data holding register:

```text
narrow inputs -> packing register -> completed-word holding register
                                      -> asynchronous FIFO core
```

Therefore, one complete packed word can be finished even while the core is
full. Backpressure is asserted only when that holding register is occupied.

`async_fifo_stream` is the preferred solution for new designs. `wr_ready`
states exactly whether the current input beat can be accepted, `wr_last`
flushes a partial packed word, and `wr_keep` records which bytes are valid.

### Wide write, narrow read

A wide core word is fetched and buffered in the read domain, then returned one narrow slice at a time.

For 32-to-16 conversion:

```text
write 32'h1122_3344
read 16'h3344, then 16'h1122
```

`fetch_pending` records an outstanding synchronous RAM read. The stream top
also has current and next read-side payload slots. It prefetches the next core
word while presenting the current one and can replace a consumed word on the
same edge that a RAM response returns. After initial fill, equal-width and
wide-to-narrow streams can sustain one output beat per `rd_clk` while data is
available.

### Why not advance a crossing pointer by two or four?

Skipping binary addresses can make consecutive transmitted Gray values differ in multiple bits, defeating the single-transition property relied upon by the CDC scheme. Packing and splitting in one local domain avoids that problem.

## 11. Parameter restrictions

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

## 12. Mapping eight core questions to this RTL

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

## 13. Engineering notes

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

## 14. Reset considerations

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

## 15. Interface behavior

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

## 16. Simulation

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

## 17. Verification and engineering status

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
