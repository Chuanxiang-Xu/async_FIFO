# Basic FIFO example

[`basic_fifo.v`](basic_fifo.v) is the smallest recommended integration. It
instantiates the stable `async_fifo` entry point as a 32-bit, 16-word FIFO and
leaves the optional advanced status outputs unconnected.

A write is accepted on `wr_clk` when `wr_en && !full`. A read is requested on
`rd_clk` when `rd_en && !empty`; use `rd_data` only when `rd_valid` is high.
Both reset inputs must be synchronously released in their respective clock
domains. See [Interface and Timing](../../docs/interface.md) for the complete
contract.

Compile the example from the repository root with:

```sh
iverilog -g2012 -s basic_fifo -o /tmp/basic_fifo.out \
  -f rtl/files.f examples/basic_fifo/basic_fifo.v
```
