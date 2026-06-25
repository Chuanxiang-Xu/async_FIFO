# External RAM Interface FIFO Design

`async_fifo_ramif` is an experimental wrapper for users who want the FIFO
control, pointer, and CDC logic from this repository while providing their own
storage implementation. It is not the default FIFO entry point and should not
replace `async_fifo` for ordinary integrations.

The first version should match the timing model of the current internal
[`fifo_mem`](../rtl/core/fifo_mem.v): one write port in the write clock domain
and one synchronous read port in the read clock domain.

## Boundary Decision

`async_fifo_ramif` should externalize storage only:

```text
async_fifo_ramif
    pointer / full / empty / CDC control
        |
        +-- external simple dual-port RAM interface
```

It must not change the Cummings-style pointer algorithm, synchronize payload
bits, add width conversion, add FWFT behavior, or introduce a new full/empty
definition. The standard `async_fifo` and `async_fifo_core` remain the main
teaching implementation with inferred internal RAM.

## RAM Contract

The first RAMIF contract is deliberately narrow:

| Topic | First-version contract |
|---|---|
| RAM shape | Simple dual-port memory: one write port, one read port |
| Write clock | `wr_clk` |
| Read clock | `rd_clk` |
| Write operation | On `wr_clk`, when `ram_wr_en` is high, store `ram_wr_data` at `ram_wr_addr` |
| Read operation | On `rd_clk`, when `ram_rd_en` is high, capture the word at `ram_rd_addr` and return it on `ram_rd_data` after one read-clock edge |
| Read latency | Fixed one cycle, matching `fifo_mem` |
| Backpressure | Not supported; the RAM must accept every asserted read or write enable |
| Reset | FIFO reset clears pointer/control state only; it does not clear external RAM contents |
| Collision behavior | Same-address read/write across unrelated clocks is target-RAM behavior; the FIFO does not promise a useful data-during-collision value |
| Data validity | `rd_valid` from the FIFO qualifies user `rd_data`; raw `ram_rd_data` is not independently valid |

The wrapper should generate RAM requests only for accepted FIFO transfers:

```text
ram_wr_en = wr_rstn && wr_en && !full
ram_rd_en = rd_rstn && rd_en && !empty
```

The external RAM must not stall or reorder those requests. If a future design
needs a wait-state or ready/valid RAM, it should be a separate interface with a
new proof strategy.

## Vendor RAM Binding and Collision Guidance

RAMIF deliberately does not infer or instantiate a vendor memory primitive.
The consuming design owns the external RAM wrapper and must make the target
tool map it to the intended resource.

Recommended integration pattern:

```text
async_fifo_ramif
    |
    +-- project-owned ram_wrapper
            |
            +-- inferred simple dual-port RAM, vendor macro, or ASIC SRAM
```

Keep the wrapper small and boring: register the read data once in the read
clock domain, accept every asserted enable, and avoid extra queues unless you
also change the FIFO contract and proofs.

| Topic | Engineering guidance |
|---|---|
| FPGA inference | Use a project-local RAM wrapper that follows the synthesis style guide for the selected FPGA family. Check the synthesis report instead of assuming the intended memory was inferred. |
| Vendor macro binding | If a block RAM, UltraRAM, MLAB/M10K/M20K, or ASIC SRAM macro is instantiated directly, bind only inside the project-owned RAM wrapper, not inside `async_fifo_ramif`. |
| Read latency | Configure or wrap the memory so `ram_rd_data` returns exactly one `ram_rd_clk` edge after `ram_rd_en`. Extra output registers require a different FIFO wrapper. |
| Enables | Treat `ram_wr_en` and `ram_rd_en` as non-stallable commands. A RAM macro with busy, ready, sleep wakeup, or refresh behavior is not compatible without an adapter that preserves the visible one-cycle contract. |
| Same-address collision | Do not rely on a vendor-specific read-during-write value. The FIFO contract is defined by accepted transfers and `rd_valid`, not by raw collision data on `ram_rd_data`. |
| Byte enables and ECC | Keep them outside the first RAMIF contract. If needed, wrap them so the FIFO still observes one whole-word write and one whole-word read result. |
| Initialization | RAM contents before a valid FIFO read are irrelevant. Do not depend on RAM initialization for reset correctness. |
| Attributes/pragmas | Put family-specific attributes in the project RAM wrapper and review them during synthesis. Do not bake them into the generic teaching RTL. |

For FPGA sign-off, keep the synthesis utilization report, RAM inference or
macro binding evidence, timing report for the RAM ports, and any documented
read-during-write or reset-related waiver. For ASIC sign-off, replace those
with the SRAM compiler instance documentation, timing views, CDC/timing review,
and any macro-specific collision assumptions.

### Minimal RAM wrapper skeleton

The RAM connected to RAMIF can be inferred or macro-backed, but its visible
behavior should look like this one-cycle simple dual-port model:

```verilog
module project_simple_dpram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 9
) (
    input                         wr_clk,
    input                         wr_en,
    input      [ADDR_WIDTH-1:0]   wr_addr,
    input      [DATA_WIDTH-1:0]   wr_data,

    input                         rd_clk,
    input                         rd_en,
    input      [ADDR_WIDTH-1:0]   rd_addr,
    output reg [DATA_WIDTH-1:0]   rd_data
);
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end
endmodule
```

Connect it directly to the RAMIF side:

```verilog
project_simple_dpram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_fifo_storage (
    .wr_clk (ram_wr_clk),
    .wr_en  (ram_wr_en),
    .wr_addr(ram_wr_addr),
    .wr_data(ram_wr_data),
    .rd_clk (ram_rd_clk),
    .rd_en  (ram_rd_en),
    .rd_addr(ram_rd_addr),
    .rd_data(ram_rd_data)
);
```

In a production project, this wrapper is the right place for vendor attributes
or a macro instance. Do not add ready/busy behavior, extra output latency, or
collision-dependent control without changing the documented RAMIF contract.

## Proposed Public FIFO Ports

The user-facing FIFO side should mirror `async_fifo`:

```text
wr_clk, wr_rstn, wr_en, wr_data, full, almost_full, wr_used
rd_clk, rd_rstn, rd_en, rd_data, rd_valid, empty, almost_empty, rd_used
```

The RAM side should expose the storage transaction:

```text
ram_wr_clk
ram_wr_en
ram_wr_addr
ram_wr_data

ram_rd_clk
ram_rd_en
ram_rd_addr
ram_rd_data
```

`ram_wr_clk` and `ram_rd_clk` are forwarded from `wr_clk` and `rd_clk` so an
external RAM wrapper can connect them directly. `rd_data` should be a wrapper
alias of the returned synchronous RAM data, qualified by FIFO `rd_valid`.

## Non-Goals

The first RAMIF wrapper should not implement:

- RAM backpressure or wait states;
- variable read latency;
- asynchronous combinational read;
- byte enables;
- ECC;
- RAM initialization or clearing;
- width conversion;
- FWFT behavior;
- packet metadata;
- shared bidirectional RAM ports.

These features may be studied later, but each one changes either the public
contract, the proof shape, or the target sign-off responsibility.

## Verification Plan

The first implementation should include:

- a testbench RAM model with the exact one-cycle read contract;
- directed A/B clock tests matching `async_fifo` behavior;
- reset tests showing pointer/control reset does not rely on RAM clearing;
- a wrapper equivalence-style simulation comparing `async_fifo_ramif` against
  `async_fifo` for the same accepted transfer sequence;
- a small formal harness proving ordering and `rd_valid` alignment with the
  RAM model.

Because RAMIF externalizes storage, documentation and tests should emphasize
that the consuming project owns RAM inference, macro instantiation, timing,
collision semantics, and any RAM-specific sign-off.
