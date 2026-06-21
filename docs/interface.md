# Interface and Timing

This project exposes three primary synthesizable top-level modules:

- `async_fifo`: equal-width asynchronous FIFO with an explicit read-valid
  output;
- `async_fifo_width_conv`: request-based width-converting asynchronous FIFO;
- `async_fifo_stream`: recommended packet-aware ready/valid interface.

All three primary modules use separate active-low asynchronous reset inputs
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
after that clock edge.

`almost_full` and `almost_empty` are advisory registered flags. Their default
thresholds are depth minus one and one word, respectively. The threshold
comparison includes the local transfer accepted on the current clock edge.

`wr_used` and `rd_used` combine a local pointer with a synchronized remote
pointer. They are stable in their respective domains and use core-word units,
but synchronization latency prevents either from being an instantaneous
global occupancy value.

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
