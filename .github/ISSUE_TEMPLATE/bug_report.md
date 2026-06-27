---
name: Bug report
about: Report a simulation, formal, synthesis, CDC, or hardware issue
title: "[bug]: "
labels: bug
assignees: ""
---

## Affected Area

- [ ] `async_fifo`
- [ ] `async_fifo_fwft`
- [ ] `async_bidir_fifo`
- [ ] `async_fifo_ramif`
- [ ] `async_bidir_ramif_fifo`
- [ ] `async_fifo_width_conv`
- [ ] `async_fifo_stream`
- [ ] `async_reset_sync`
- [ ] constraints / CDC
- [ ] formal / simulation
- [ ] documentation
- [ ] board flow / PYNQ-Z2
- [ ] release or project metadata

## Configuration

- Parameters:
- Width ratio or stream metadata, if applicable:
- Almost flag thresholds, if changed:
- Write clock period/frequency:
- Read clock period/frequency:
- Reset scheme:
- OS:
- Tool and version:
- Target FPGA/device, if applicable:
- Public module instantiated directly:
- Commit SHA or release version:

## What Happened?


## Expected Behavior


## Reproduction

Please include the smallest command, testbench, waveform, or log that shows the issue.

```sh

```

- Waveform/VCD/trace path:
- Log or report excerpt:
- Does the issue reproduce from a clean checkout?

## Checks Already Run

- [ ] `make smoke`
- [ ] `make test`
- [ ] `make lint`
- [ ] `make cdc`
- [ ] `make synth`
- [ ] `make formal`
- [ ] `make docs-check`
- [ ] `make xilinx-cdc`
- [ ] `make pynq-z2`
- [ ] vendor CDC/timing reports reviewed

## Sign-Off Context

- Is this simulation, formal, synthesis, implementation, timing, CDC, or hardware behavior?
- For CDC/timing issues, what clock definitions and constraints were used?
- Were reset recovery/removal and target CDC reports reviewed?
- Are any vendor RAM, reset, or CDC warnings waived? If yes, why?

## Additional Context

Do not attach proprietary netlists, private customer data, or confidential timing reports.
