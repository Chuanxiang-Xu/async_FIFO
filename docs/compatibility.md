# Compatibility and Release Support

Current RTL release: `1.2.0`.

## Verified tool and target matrix

| Area | Tool/target | Status |
|---|---|---|
| Simulation | Icarus Verilog in the digest-pinned `hdlc/sim` CI image | Required CI |
| Lint | Verilator in the digest-pinned `hdlc/sim` CI image | Required CI |
| Generic synthesis | Yosys in the digest-pinned `hdlc/formal` CI image | Required CI |
| Formal | SymbiYosys and Z3 in the digest-pinned `hdlc/formal` CI image | Required CI |
| Xilinx synthesis/CDC collections | Vivado 2025.2, `xc7z020clg400-1` | Verified |
| Xilinx implementation | Vivado 2025.2, PYNQ-Z2 / Zynq-7000 | Verified |
| Intel Quartus | Constraint template only | Not implementation-verified |

The GitHub Xilinx job requires a self-hosted runner labelled
`self-hosted`, `linux`, `x64`, and `vivado-2025.2`, plus repository variable
`XILINX_CI_ENABLED=true`. A skipped vendor job means the runner has not been
enabled; it is not evidence of Vivado validation. For security, pull requests
from forks do not execute on the licensed self-hosted runner.
Registration and service-environment instructions are in
[Xilinx Self-Hosted Runner](xilinx_runner.md). The runner must pass
`make xilinx-runner-check` before `XILINX_CI_ENABLED` is enabled.

## Supported public RTL

- `async_fifo`
- `async_fifo_fwft`
- `async_bidir_fifo`
- `async_fifo_ramif` experimental external-RAM wrapper
- `async_bidir_ramif_fifo` experimental full-duplex external-RAM wrapper
- `async_fifo_width_conv`
- `async_fifo_stream`
- `async_reset_sync`

The FIFO modules require power-of-two core depth. Width conversion supports
integer power-of-two ratios. Reset is destructive and coordinated; unilateral
runtime reset with retained data is not supported.

Formal release coverage currently contains 53 tasks: fixed deep harnesses,
two symbolic clock-rate/phase core BMCs, a 20-task concrete wrapper matrix,
the FWFT, bidirectional, RAMIF, and bidirectional RAMIF wrapper BMC/cover pairs,
and associated cover tasks. Verilator `-Wall` is warning-free and warnings are
treated as CI failures.

## Xilinx integration requirements

For every synthesized `async_fifo_core` instance:

1. apply source-clock maximum-delay and bus-skew constraints to both Gray
   crossings;
2. identify one exact instance hierarchy and `ADDR_WIDTH + 1`;
3. run `check_async_fifo_cdc` after synthesis;
4. review timing, exception coverage, CDC, methodology, and DRC reports after
   implementation.

`make xilinx-cdc` validates default and multi-instance elaborations, including
negative tests for wrong width, missing hierarchy, and ambiguous hierarchy.

## Release policy

- Patch releases preserve ports, parameters, capacity semantics, and reset
  behavior.
- Minor releases may add backward-compatible modules, checks, or parameters.
- Major releases may change public interfaces or documented contracts.
- Every release must pass `make check`; Xilinx-qualified releases must also
  pass `make xilinx-cdc` and the PYNQ implementation flow.
- Release version updates must keep `VERSION`, `async_fifo.core`, and
  `CHANGELOG.md` aligned.
