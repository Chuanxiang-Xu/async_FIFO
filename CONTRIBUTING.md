# Contributing

Thanks for taking the time to improve this asynchronous FIFO project.

## Before opening an issue

Please include:

- the affected top-level module (`async_fifo`, `async_fifo_fwft`,
  `async_fifo_width_conv`, or `async_fifo_stream`);
- parameter values and write/read clock periods;
- simulator, synthesis tool, or FPGA family and tool version;
- a minimal reproduction, waveform, or error log;
- whether the issue appears during simulation, synthesis, timing analysis, or
  hardware operation.

Security-sensitive reports should not include private project data or
proprietary netlists in a public issue.

## Development setup

The local checks require:

- GNU Make;
- Icarus Verilog;
- Verilator for linting.
- Yosys, SymbiYosys, and Z3 for synthesis and formal checks.
- Vivado 2025.2 for Xilinx-qualified changes.

Run the same checks used by continuous integration:

```bash
make check
```

CI runs these checks in digest-pinned `hdlc/sim` and `hdlc/formal` containers.
When intentionally updating a toolchain, update the image digest, record the
new tool versions from the workflow log, and rerun the complete check set.

Generated files belong under `build/` and must not be committed.

Changes to Xilinx hierarchy, synchronizers, or constraints must also pass:

```bash
make xilinx-cdc
```

The vendor CI job runs on a self-hosted runner when
`XILINX_CI_ENABLED=true`. Release-facing changes must update `CHANGELOG.md`
and `docs/compatibility.md`, then pass `make release-check`.

## Pull requests

Keep each pull request focused on one change. Before submitting:

1. add or update a self-checking test;
2. run `make test` and `make lint`;
3. update both `README.md` and `README-CN.md` when public behavior changes;
4. document any new parameter restriction, latency, reset assumption, or CDC
   requirement;
5. avoid unrelated formatting or generated tool output.

For RTL changes, explain how overflow, underflow, pointer wraparound, reset,
and independent clock behavior were considered.

## What to run

Use the smallest relevant set while iterating, then run the broader checks
before opening a PR.

| Change area | Minimum checks |
|---|---|
| Markdown only | `make docs-check` |
| Tutorial waveform or tutorial testbench | `make tutorial`, `make docs-check` |
| Equal-width FIFO RTL | `make tb_equal_width tb_fifo_random`, `make lint`, `make cdc`, `make synth`, relevant formal target |
| FWFT wrapper | `make tb_fwft_first_word tb_fwft_stall_and_stream tb_fwft_empty_pop_and_reset`, `sby -f -d build/formal-fwft-bmc formal/fwft.sby bmc`, `make lint`, `make synth` |
| Width-conversion wrapper | `make tb_pack_16_to_32 tb_split_32_to_16 tb_width_conv_pack_buffer`, `make formal` or relevant `width_conv.sby` task |
| Stream wrapper | stream simulation targets, `make lint`, relevant `stream.sby` task |
| Reset behavior | reset simulations, `formal/reset_skew.sby`, and stream reset checks if wrappers are affected |
| CDC constraints or synchronizers | `make cdc`, `make synth`, `make xilinx-cdc` when Vivado 2025.2 is available |
| Release metadata | `make release-check` |

When in doubt, run:

```bash
make check
```

`make check` does not run the licensed Vivado flow.

## RTL style

- Use the `async_fifo*` prefix for primary modules and files.
- Use `wr_*` and `rd_*` for write-domain and read-domain ports and signals.
- Use `wr_data` and `rd_data` instead of generic `din` and `dout` in new APIs.
- Use `*_rstn` for active-low asynchronous reset inputs.
- Keep all state changes in their owning clock domain.
- Do not synchronize the payload bus bit by bit.
- Cross only registered Gray-coded pointers through the synchronizer modules.
- Preserve the power-of-two depth requirement unless the full CDC algorithm
  and its verification are intentionally replaced.
- Use nonblocking assignments in sequential logic.
- Treat synthesis pragmas and timing constraints as tool-specific behavior
  that must be documented and tested.

## Tests

New tests should be deterministic, self-checking, and terminate with a
nonzero status on failure. Prefer scoreboards over visual waveform inspection.
Useful coverage includes:

- full, empty, overflow attempts, and underflow attempts;
- pointer wraparound;
- simultaneous traffic with unrelated clocks;
- reset assertion and release;
- supported width ratios and slice ordering;
- ready/valid stability under backpressure and keep/last propagation;
- randomized traffic with reproducible seeds.

## License

By contributing, you agree that your contribution is licensed under the
project's [MIT License](LICENSE).
