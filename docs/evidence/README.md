# Evidence Center

This directory collects the repository's reproducible verification and
sign-off evidence in one place. It is intentionally conservative: a page may
summarize only checks that are present in this repository or reproducible from
checked-in commands.

The evidence center does not replace the learning documents. Use it when you
want to answer:

- what has been checked;
- how to reproduce the check;
- what the check does not prove;
- where to read the detailed design or verification explanation.

## Evidence Map

| Area | Summary | Reproduce |
|---|---|---|
| Simulation | [Simulation Summary](simulation_summary.md) | `make test` |
| Formal | [Formal Summary](formal_summary.md) | `make formal` |
| CDC and constraints | [CDC Summary](cdc_summary.md) | `make cdc`, `make synth`, optional `make xilinx-cdc` |
| PYNQ-Z2 Vivado flow | [PYNQ-Z2 Summary](fpga_pynq_z2_summary.md) | `make pynq-z2` with Vivado 2025.2 |
| Boundaries | [Known Limits](known_limits.md) | Read before integration or release claims |

For quick local confidence while editing documentation or studying the core,
run:

```bash
make smoke
```

For broad open-source regression confidence before handoff, run:

```bash
make tools-check
make check
```

`make check` does not run the licensed Vivado flow. Xilinx-qualified changes
also need `make tools-check-vivado` and `make xilinx-cdc`, and board-flow
updates need `make pynq-z2` on a machine with the supported Vivado
installation.

## How to Read PASS Claims

A PASS in these pages means the named command or report has checked a specific
scope. It does not mean this repository is a complete vendor FIFO IP
replacement, a commercial CDC sign-off package, or proof of every legal
parameter on every FPGA target.

The intended confidence model is:

```text
simulation: concrete scenarios and scoreboards
formal: bounded exhaustive behavior inside selected harnesses
CDC/STA: physical implementation sign-off for a target project
```

## Detailed References

- [Interface and Timing](../interface.md) is the public FIFO contract.
- [Formal Verification Guide](../formal_verification.md) explains the proof
  strategy and bounds.
- [CDC and Timing Constraints](../cdc_constraints.md) explains physical
  implementation responsibilities.
- [PYNQ-Z2 Vivado Validation](../pynq_z2_vivado.md) records the board-flow
  target, reports, and limitations.
- [Compatibility and Release Support](../compatibility.md) records supported
  tools, public RTL, and release policy.
