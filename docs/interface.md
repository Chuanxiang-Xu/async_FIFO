# Interface and Timing

This project exposes seven primary synthesizable top-level modules:

- `async_fifo`: equal-width asynchronous FIFO with an explicit read-valid
  output;
- `async_fifo_fwft`: equal-width asynchronous FIFO with first-word
  fallthrough read behavior;
- `async_bidir_fifo`: two independent equal-width asynchronous FIFO channels
  for full-duplex CDC;
- `async_fifo_ramif`: experimental equal-width asynchronous FIFO control with
  an external simple dual-port RAM interface;
- `async_bidir_ramif_fifo`: experimental full-duplex composition of two
  `async_fifo_ramif` channels with independent external RAM interfaces;
- `async_fifo_width_conv`: request-based width-converting asynchronous FIFO;
- `async_fifo_stream`: recommended packet-aware ready/valid interface.

All primary modules use separate active-low asynchronous reset inputs
for the write and read domains. Reset may assert asynchronously, but the
integrator must deassert each reset synchronously to its local clock. Do not
transfer data until both domains have completed initialization. Formal checks
cover either domain releasing first under this coordinated-startup rule at
both the equal-width core and packet-stream interfaces.

The repository provides `async_reset_sync` as the supported integration
helper. Instantiate one copy per unrelated clock domain:

```verilog
async_reset_sync #(.STAGES(2)) u_wr_reset_sync (
    .clk(wr_clk),
    .async_rstn(system_rstn),
    .sync_rstn(wr_rstn)
);
```

Assertion is asynchronous and release takes `STAGES` local rising edges.
`STAGES` must be at least two. This helper does not change the FIFO's
destructive coordinated-reset contract.

## Transfer qualification summary

For request-style modules, `wr_en` and `rd_en` are requests. A transfer occurs
only when the local reset is released and the local status flag allows it:

| Module | Write accepted on `wr_clk` when | Read accepted on `rd_clk` when |
|---|---|---|
| `async_fifo` | `wr_rstn && wr_en && !full` | `rd_rstn && rd_en && !empty` |
| `async_fifo_fwft` | `wr_rstn && wr_en && !full` | `rd_rstn && rd_en && rd_valid` pops visible data |
| `async_bidir_fifo` | `a_rstn && a_tx_en && !a_tx_full`; `b_rstn && b_tx_en && !b_tx_full` | `b_rstn && b_rx_en && !b_rx_empty`; `a_rstn && a_rx_en && !a_rx_empty` |
| `async_fifo_ramif` | `wr_rstn && wr_en && !full`; also asserts `ram_wr_en` | `rd_rstn && rd_en && !empty`; also asserts `ram_rd_en` |
| `async_bidir_ramif_fifo` | `a_rstn && a_tx_en && !a_tx_full`; `b_rstn && b_tx_en && !b_tx_full`; also asserts direction-local RAM write enables | `b_rstn && b_rx_en && !b_rx_empty`; `a_rstn && a_rx_en && !a_rx_empty`; also asserts direction-local RAM read enables |
| `async_fifo_width_conv` | `wr_rstn && wr_en && !full` | `rd_rstn && rd_en && !empty` |

The standard request-style modules expose `rd_valid`; consumers must qualify `rd_data`
with `rd_valid`, not with `rd_en` alone. The FWFT wrapper uses `rd_valid` as a
level signal: while high, `rd_data` contains a visible word, and `rd_en` pops it.
The tutorial waveform shows the standard timing in a small depth-4 FIFO: see
[Async FIFO Step-by-Step Tutorial](tutorial.md#a-real-waveform).

For `async_fifo_stream`, the status flags are secondary. Data movement is
defined by ready/valid handshakes: `wr_valid && wr_ready` in the write domain
and `rd_valid && rd_ready` in the read domain.

## Advanced status signals

This section is the single reference for status outputs beyond the basic
transfer qualifiers. Logic that moves data must use the module's documented
transfer condition: `!full`/`!empty` for standard request interfaces,
`rd_valid` for FWFT pops, or `ready && valid` for the stream interface. The
signals below are for monitoring and early flow control.

| Signal | Clock domain | Meaning |
|---|---|---|
| `almost_full` | write | Local, registered core occupancy is at or above the configured high threshold |
| `almost_empty` | read | Local, registered core occupancy is at or below the configured low threshold |
| `wr_used` | write | Equal-width FIFO occupancy derived from the local write pointer and synchronized read pointer |
| `rd_used` | read | Equal-width FIFO readable count derived from the local read pointer and synchronized write pointer |
| `wr_core_used` | write | Wrapper view of core occupancy only; excludes local pack/pending/output storage |
| `rd_core_used` | read | Wrapper view of core occupancy only; excludes local pack/pending/output storage |

Every value is a local clock-domain view. Remote-pointer synchronization means
none is an instantaneous global snapshot, and flag deassertion is deliberately
conservative. Wrapper occupancy is measured in internal core words, not
interface beats. In particular, `almost_empty` may be high while a wrapper
still holds readable split or prefetched data. Thresholds likewise use core
word units. Wrapper-specific storage bounds are documented in the capacity
sections below.

## Equal-width interface: `async_fifo`

### Parameters

| Parameter | Description |
|---|---|
| `DATA_WIDTH` | Width of each stored word |
| `ADDR_WIDTH` | RAM address width; depth is `2**ADDR_WIDTH` words |
| `ALMOST_FULL_THRESHOLD` | Assert at or above this occupied-word count |
| `ALMOST_EMPTY_THRESHOLD` | Assert at or below this occupied-word count |

### Ports

| Port | Domain | Direction | Description |
|---|---|---|---|
| `wr_clk` | write | input | Write clock |
| `wr_rstn` | write | input | Active-low reset; asynchronous assertion, locally synchronized deassertion required |
| `wr_en` | write | input | Write request |
| `wr_data` | write | input | Write data |
| `full` | write | output | No write can be accepted while high |
| `almost_full` | write | output | Occupancy has reached the configured high threshold |
| `wr_used` | write | output | Conservative write-domain occupied-word view |
| `rd_clk` | read | input | Read clock |
| `rd_rstn` | read | input | Active-low reset; asynchronous assertion, locally synchronized deassertion required |
| `rd_en` | read | input | Read request |
| `rd_data` | read | output | Registered read data |
| `rd_valid` | read | output | `rd_data` was updated by an accepted read |
| `empty` | read | output | No read can be accepted while high |
| `almost_empty` | read | output | Occupancy is at or below the configured low threshold |
| `rd_used` | read | output | Conservative read-domain readable-word view |

A write is accepted on a rising `wr_clk` edge when:

```text
wr_rstn && wr_en && !full
```

A read is accepted on a rising `rd_clk` edge when:

```text
rd_rstn && rd_en && !empty
```

The reset terms are also used to gate the inferred RAM ports. Requests held
high during reset cannot read or write memory. Reset is destructive: queued
data is discarded, and `rd_data` is not meaningful until a new `rd_valid`
appears after coordinated reset release.

The RAM has a synchronous read port. `rd_valid` is asserted for the cycle
corresponding to an accepted read, and `rd_data` contains the newly read word
after that clock edge. In other words, `rd_valid` marks the cycle in which
`rd_data` should be sampled. For a concrete timing example, run `make tutorial`
and compare the accepted reads with the `rd_valid` pulses in
[the tutorial waveform](tutorial.md#a-real-waveform).

`almost_full` and `almost_empty` are advisory registered flags. Their default
thresholds are depth minus one and one word, respectively. The threshold
comparison includes the local transfer accepted on the current clock edge.

`wr_used` and `rd_used` combine a local pointer with a synchronized remote
pointer. They are stable in their respective domains and use core-word units,
but synchronization latency prevents either from being an instantaneous
global occupancy value.

## Equal-width FWFT interface: `async_fifo_fwft`

`async_fifo_fwft` wraps the same equal-width core with read-side prefetch
storage. It is intended for users who want the first readable word to appear on
`rd_data` automatically after pointer synchronization and the internal
synchronous RAM fetch.

The write-side contract is identical to `async_fifo`:

```text
wr_rstn && wr_en && !full
```

The read side is observe-then-consume:

```text
rd_valid == 1             rd_data holds a visible word
rd_rstn && rd_en && rd_valid  consumes that visible word
empty == !rd_valid        no word is currently visible to the user
```

While `rd_valid && !rd_en`, `rd_data` remains stable. A pop when `rd_valid` is
low is non-destructive. The wrapper contains two read-side prefetch slots so it
can keep data available during continuous reads once the initial fallthrough
pipeline has filled.

`rd_used` is a read-domain user-facing estimate: the core read-domain count
plus the wrapper's visible slot, spare slot, and pending internal fetch. Like
all occupancy views in this project, it is local and conservative rather than a
global instantaneous count. `almost_empty` is derived from this FWFT read-side
view and remains advisory; the pop qualifier is `rd_en && rd_valid`.

For the design rationale and test plan, see
[FWFT / Fallthrough Design Notes](fwft_design.md).

## Bidirectional equal-width interface: `async_bidir_fifo`

`async_bidir_fifo` is a full-duplex composition wrapper. It contains two
independent standard `async_fifo` instances:

```text
a_tx_* in domain A -> b_rx_* in domain B
b_tx_* in domain B -> a_rx_* in domain A
```

It does not share RAM, flags, or pointer state between directions. It does not
provide runtime direction switching or cross-direction transaction atomicity.

### Parameters

| Parameter | Description |
|---|---|
| `DATA_WIDTH` | Width of each stored word in both directions |
| `ADDR_WIDTH` | RAM address width for each internal FIFO; each direction has `2**ADDR_WIDTH` words |
| `ALMOST_FULL_THRESHOLD` | Assert each transmit almost-full flag at or above this occupied-word count |
| `ALMOST_EMPTY_THRESHOLD` | Assert each receive almost-empty flag at or below this readable-word count |

### Ports

| Port group | Domain | Description |
|---|---|---|
| `a_clk`, `a_rstn` | A | A-domain clock and active-low reset |
| `b_clk`, `b_rstn` | B | B-domain clock and active-low reset |
| `a_tx_en`, `a_tx_data`, `a_tx_full`, `a_tx_almost_full`, `a_tx_used` | A | A-to-B write request, data, and A-domain status |
| `b_rx_en`, `b_rx_data`, `b_rx_valid`, `b_rx_empty`, `b_rx_almost_empty`, `b_rx_used` | B | A-to-B read request, data, and B-domain status |
| `b_tx_en`, `b_tx_data`, `b_tx_full`, `b_tx_almost_full`, `b_tx_used` | B | B-to-A write request, data, and B-domain status |
| `a_rx_en`, `a_rx_data`, `a_rx_valid`, `a_rx_empty`, `a_rx_almost_empty`, `a_rx_used` | A | B-to-A read request, data, and A-domain status |

A-to-B writes are accepted on `a_clk` when:

```text
a_rstn && a_tx_en && !a_tx_full
```

A-to-B reads are accepted on `b_clk` when:

```text
b_rstn && b_rx_en && !b_rx_empty
```

The B-to-A direction uses the symmetric conditions:

```text
b_rstn && b_tx_en && !b_tx_full
a_rstn && a_rx_en && !a_rx_empty
```

`b_rx_valid` qualifies `b_rx_data`, and `a_rx_valid` qualifies `a_rx_data`.
Almost flags and occupancy values are local-domain views for their own
direction only. For example, `a_tx_full` describes A-to-B storage and does not
imply anything about `b_tx_full`.

For the design rationale, see
[Bidirectional FIFO Wrapper Design](bidir_fifo_design.md).

## External RAM interface: `async_fifo_ramif`

`async_fifo_ramif` exposes the same standard equal-width FIFO contract as
`async_fifo`, but the storage array is provided by the integrating design. The
wrapper still owns pointer arithmetic, Gray-pointer synchronization,
`full`/`empty`, almost flags, occupancy, and `rd_valid`.

The external RAM must implement the fixed contract documented in
[External RAM Interface FIFO Design](ramif_design.md): simple dual-port memory,
synchronous write, synchronous read, one read-clock latency, and no RAM
backpressure.

### Parameters

| Parameter | Description |
|---|---|
| `DATA_WIDTH` | Width of each stored word |
| `ADDR_WIDTH` | RAM address width; external RAM depth must be `2**ADDR_WIDTH` words |
| `ALMOST_FULL_THRESHOLD` | Assert at or above this occupied-word count |
| `ALMOST_EMPTY_THRESHOLD` | Assert at or below this readable-word count |

### FIFO-side ports

The user-facing FIFO ports match `async_fifo`:

| Port group | Domain | Description |
|---|---|---|
| `wr_clk`, `wr_rstn`, `wr_en`, `wr_data`, `full`, `almost_full`, `wr_used` | write | Standard write request and local write-domain status |
| `rd_clk`, `rd_rstn`, `rd_en`, `rd_data`, `rd_valid`, `empty`, `almost_empty`, `rd_used` | read | Standard read request, returned data, and local read-domain status |

### RAM-side ports

| Port | Direction | Description |
|---|---|---|
| `ram_wr_clk` | output | Forwarded `wr_clk` |
| `ram_wr_en` | output | External RAM write enable for an accepted FIFO write |
| `ram_wr_addr` | output | External RAM write address |
| `ram_wr_data` | output | External RAM write data |
| `ram_rd_clk` | output | Forwarded `rd_clk` |
| `ram_rd_en` | output | External RAM read enable for an accepted FIFO read |
| `ram_rd_addr` | output | External RAM read address |
| `ram_rd_data` | input | External RAM read data returned after one `rd_clk` edge |

The wrapper generates RAM enables only for accepted FIFO transfers:

```text
ram_wr_en = wr_rstn && wr_en && !full
ram_rd_en = rd_rstn && rd_en && !empty
```

`rd_valid` is generated by the FIFO wrapper and qualifies `rd_data`, which is
the returned `ram_rd_data`. Reset clears FIFO pointer/control state only; it
does not clear or initialize the external RAM contents.

## Bidirectional external RAM interface: `async_bidir_ramif_fifo`

`async_bidir_ramif_fifo` composes two independent `async_fifo_ramif`
instances:

```text
a_tx_* in domain A -> a2b_ram_* storage -> b_rx_* in domain B
b_tx_* in domain B -> b2a_ram_* storage -> a_rx_* in domain A
```

It is the RAMIF counterpart of `async_bidir_fifo`: the CDC channels are
full-duplex, but there is no shared RAM, shared pointer state, runtime
direction switching, or cross-direction transaction atomicity. Each direction
must connect to a separate simple dual-port RAM that satisfies the same
one-read-clock-latency contract as `async_fifo_ramif`.

### Parameters

| Parameter | Description |
|---|---|
| `DATA_WIDTH` | Width of each stored word in both directions |
| `ADDR_WIDTH` | RAM address width for each external RAM; each direction has `2**ADDR_WIDTH` words |
| `ALMOST_FULL_THRESHOLD` | Assert each transmit almost-full flag at or above this occupied-word count |
| `ALMOST_EMPTY_THRESHOLD` | Assert each receive almost-empty flag at or below this readable-word count |

### FIFO-side ports

| Port group | Domain | Description |
|---|---|---|
| `a_clk`, `a_rstn` | A | A-domain clock and active-low reset |
| `b_clk`, `b_rstn` | B | B-domain clock and active-low reset |
| `a_tx_en`, `a_tx_data`, `a_tx_full`, `a_tx_almost_full`, `a_tx_used` | A | A-to-B write request, data, and A-domain status |
| `b_rx_en`, `b_rx_data`, `b_rx_valid`, `b_rx_empty`, `b_rx_almost_empty`, `b_rx_used` | B | A-to-B read request, data, and B-domain status |
| `b_tx_en`, `b_tx_data`, `b_tx_full`, `b_tx_almost_full`, `b_tx_used` | B | B-to-A write request, data, and B-domain status |
| `a_rx_en`, `a_rx_data`, `a_rx_valid`, `a_rx_empty`, `a_rx_almost_empty`, `a_rx_used` | A | B-to-A read request, data, and A-domain status |

### RAM-side ports

| Port group | Direction | Description |
|---|---|---|
| `a2b_ram_wr_*`, `a2b_ram_rd_*` | output/input | External RAM interface for the A-to-B channel |
| `b2a_ram_wr_*`, `b2a_ram_rd_*` | output/input | External RAM interface for the B-to-A channel |

The per-direction RAM ports have the same meaning as `async_fifo_ramif`:
`*_ram_wr_clk`, `*_ram_wr_en`, `*_ram_wr_addr`, `*_ram_wr_data`,
`*_ram_rd_clk`, `*_ram_rd_en`, `*_ram_rd_addr`, and `*_ram_rd_data`.

For the design rationale, see
[Bidirectional RAMIF FIFO Design](bidir_ramif_fifo_design.md).

## Width-converting interface: `async_fifo_width_conv`

### Parameters

| Parameter | Description |
|---|---|
| `WDATA_WIDTH` | Write-side data width |
| `RDATA_WIDTH` | Read-side data width |
| `ADDR_WIDTH` | Narrow-side address width |
| `ALMOST_FULL_THRESHOLD` | High threshold in internal `CORE_WIDTH` words |
| `ALMOST_EMPTY_THRESHOLD` | Low threshold in internal `CORE_WIDTH` words |

The width ratio must be an integer power of two. `ADDR_WIDTH` defines the
equal-width core RAM capacity, measured in units of the narrower interface.
It does not include wrapper-local packing, pending, or splitting storage.

### Ports

| Port | Domain | Direction | Description |
|---|---|---|---|
| `wr_clk` | write | input | Write clock |
| `wr_rstn` | write | input | Active-low reset; asynchronous assertion, locally synchronized deassertion required |
| `wr_en` | write | input | Write request |
| `wr_data` | write | input | Write data |
| `full` | write | output | Current wrapper-level backpressure |
| `almost_full` | write | output | Internal core occupancy reached the high threshold |
| `wr_core_used` | write | output | Write-domain core-word occupancy view |
| `rd_clk` | read | input | Read clock |
| `rd_rstn` | read | input | Active-low reset; asynchronous assertion, locally synchronized deassertion required |
| `rd_en` | read | input | Read request |
| `rd_data` | read | output | Read data |
| `rd_valid` | read | output | `rd_data` was updated by an accepted read |
| `empty` | read | output | Current wrapper-level empty indication |
| `almost_empty` | read | output | Internal core occupancy is at or below the low threshold |
| `rd_core_used` | read | output | Read-domain core-word occupancy view |

The width-converting threshold parameters use internal `CORE_WIDTH` words,
not narrow-side entries. Their default value of `-1` selects depth minus one
for `almost_full` and one for `almost_empty`.

Like the equal-width request interface, a write-side input beat is accepted
only on a rising `wr_clk` edge with `wr_rstn && wr_en && !full`, and a
read-side output beat is accepted only on a rising `rd_clk` edge with
`rd_rstn && rd_en && !empty`. The wrapper-level `full` and `empty` signals
already include the local pack, pending, fetch, and split-buffer state needed
to decide whether the next interface beat can move.

`wr_core_used` and `rd_core_used` deliberately describe only the equal-width
FIFO core. They do not include partially packed input slices, a completed
pending word, or slices already buffered in the read wrapper. The explicit
`core` name prevents these values from being mistaken for exact interface-beat
occupancy.

### Capacity contract

Define:

```text
R = max(WDATA_WIDTH, RDATA_WIDTH) / min(WDATA_WIDTH, RDATA_WIDTH)
N = 2**ADDR_WIDTH                  # narrow-word equivalent core capacity
C = N / R                         # internal CORE_WIDTH words
```

The wrapper has the following structural storage:

| Mode | Core RAM | Wrapper-local storage | Maximum accepted but not fully returned |
|---|---:|---:|---:|
| Equal width | `N` words | none | `N` interface words |
| Narrow write, wide read | `C` core words | one pending or partial core-word equivalent | `N + R` narrow words |
| Wide write, narrow read | `C` core words | one fetched/splitting core word | `C + 1` wide writes, equivalent to `N + R` narrow slices |

The extra local word is pipeline elasticity, not additional addressable RAM.
In narrow-write mode, `full` describes whether another narrow write can be
accepted by the pack/pending path. In wide-write/narrow-read mode, a core word
may move into the read-side split buffer and free a RAM entry, so total
accepted-but-not-fully-returned data can exceed the core RAM capacity by one
wide word.

The table is a storage bound, not a promise that a partial narrow-write group
will become readable. Without packet metadata, the producer must still provide
complete groups of `R` narrow writes.

In wide-write/narrow-read mode, a wide word already fetched into the local
split buffer is no longer included in the core occupancy. Consequently,
`almost_empty` may assert while unread narrow slices remain buffered. Treat
the almost flags as early-warning flow-control hints, not transfer-valid
signals.

### Slice ordering

Conversion is little-slice-first:

```text
16-bit writes 0001, 0002 -> one 32-bit word 0002_0001
32-bit write 1122_3344   -> 16-bit reads 3344, 1122
```

### Read-valid behavior

`rd_valid` pulses whenever `rd_data` is updated. In wide-write/narrow-read mode,
the first pulse follows the internal synchronous RAM fetch; subsequent pulses
correspond to accepted buffered-slice reads. Consumers must qualify `rd_data`
with `rd_valid`.

### Partial packed words

In narrow-write/wide-read mode, narrow writes are accumulated locally until a
complete core word has been assembled. A partial word:

- is not visible to the read domain;
- does not make `empty` deassert;
- is discarded if the write domain is reset.

The producer must therefore send complete groups of `WIDTH_RATIO` narrow
items.

## Flag latency

`full` and `empty` are generated in their local clock domains from synchronized
remote Gray pointers. Their deassertion is intentionally conservative:

- `empty` may remain high for several `rd_clk` cycles after a write;
- `full` may remain high for several `wr_clk` cycles after space is freed.

This latency reduces instantaneous throughput but prevents unsafe reads and
writes.

The almost flags inherit the same synchronization latency. `almost_full` is
generated in the write domain; `almost_empty` is generated in the read domain.

## Packet streaming interface: `async_fifo_stream`

### Handshake

The write beat is accepted when `wr_valid && wr_ready`. The read beat is
accepted when `rd_valid && rd_ready`. While valid is high and ready is low,
the corresponding data, keep, and last outputs must remain stable.

Unlike the request-style interfaces, `rd_valid` is not a one-cycle pulse that
merely marks a returned RAM word. It is the stream valid signal: while it is
high, `rd_data`, `rd_keep`, and `rd_last` describe the current output beat and
must remain stable until `rd_ready` accepts it.

### Ports

| Port group | Signals |
|---|---|
| Write input | `wr_valid`, `wr_ready`, `wr_data`, `wr_keep`, `wr_last` |
| Read output | `rd_valid`, `rd_ready`, `rd_data`, `rd_keep`, `rd_last` |
| Status | `full`, `empty`, `almost_full`, `almost_empty`, `wr_core_used`, `rd_core_used` |

`full` is the inverse of `wr_ready`. `empty` indicates that no output beat is
currently available and no immediately visible core word can be fetched.
Normal data movement should use ready/valid rather than status flags.

The stream module's `wr_core_used` and `rd_core_used` have the same core-only
meaning as the width-converting request interface. Packet metadata and local
elastic/read buffers make an exact interface-beat count a different, more
expensive feature; these outputs do not claim to provide it.

### Stream capacity contract

Using the same `R`, `N`, and `C` definitions above, the stream wrapper contains:

```text
C core payload words
+ 1 write-side pending/pack payload
+ up to 2 read-side current/next payloads
```

With no read-side movement, write backpressure can therefore occur after the
core plus one write-side payload has been accepted. If the read side has
prefetched data but is stalled, those payloads have left the core and allow
additional writes; the whole module can then contain up to `C + 3` core-word
equivalents, or `N + 3R` narrower-beat equivalents.

This is a structural upper bound. Partial final packets may use fewer valid
bytes, and `wr_core_used`/`rd_core_used` continue to report only the `C`-word
core. `full`, `empty`, and the almost flags are local flow-control views, not
exact total-pipeline occupancy counters.

### Metadata rules

- Both data widths must be positive multiples of eight.
- `keep[i]` corresponds to `data[8*i +: 8]`.
- Use all-one `keep` values on non-final packet beats.
- Use a nonzero, low-order contiguous `keep` mask on the final beat.
- `last` and `keep` are stored in the same dual-port RAM word as data.

### Width conversion

For narrow writes, the wrapper packs accepted beats until the wide word is
full or an accepted `wr_last` flushes it. A completed word can wait in a local
holding register while the core is full.

The write-side holding register is elastic. If its current word is accepted by
the core, a new complete word may replace it on the same edge. Therefore, while
the core has space, the direct write path can sustain one accepted beat per
write clock without an artificial every-other-cycle bubble.

For narrow reads, the wrapper holds a fetched wide payload in the read domain
and presents one slice at a time. All outputs remain stable under read-side
backpressure. A partial final word stops after the last slice containing valid
bytes.

The read side has current and next payload slots. While the current payload is
being consumed, a core read can fill the next slot; a returning payload can
also replace a word consumed on the same edge. After initial fill latency, an
equal-width stream and a wide-to-narrow split stream can therefore sustain one
accepted output beat per `rd_clk` while data remains available. Backpressure
stops consumption and both slots preserve their payloads. Ready/valid
semantics remain authoritative.
