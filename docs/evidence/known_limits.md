# Known Limits

This page collects the boundaries that should remain visible in integration
notes, release claims, and reviews. The project is a teaching reference with
strong regression checks, not a drop-in vendor FIFO IP replacement or a
complete CDC sign-off package.

## Design Limits

- FIFO depth is a power of two.
- The CDC core is equal-width; width conversion is implemented in wrappers.
- Width conversion supports integer power-of-two ratios.
- Reset is destructive and coordinated. Data-preserving one-sided runtime
  reset is not supported.
- `full`, `empty`, almost flags, and occupancy values are local-domain views
  and include conservative remote-pointer synchronization latency.
- `async_fifo_ramif` and `async_bidir_ramif_fifo` assume the documented
  external RAM contract, including one read-clock latency and no RAM
  backpressure.
- `async_bidir_fifo` and `async_bidir_ramif_fifo` compose independent A->B and
  B->A channels; they do not provide cross-direction transaction atomicity.

## Verification Limits

- Simulation covers selected deterministic and randomized scenarios, not every
  possible environment.
- Formal checks are bounded and parameter-sampled.
- Cover tasks show reachability inside the selected formal bounds; they are
  not safety proofs by themselves.
- Open-source checks do not run the licensed Vivado implementation flow.
- `make check` does not include `make xilinx-cdc` or `make pynq-z2`.
- `make check` requires the open-source simulator, lint, synthesis, and formal
  tools reported by `make tools-check`; a missing tool is an environment issue,
  not RTL evidence.

## Physical Sign-Off Limits

- RTL attributes and constraint templates do not close timing in a user's
  final FPGA project.
- Every integration needs target-specific STA, CDC, reset, DRC, methodology,
  and waiver review.
- Gray-pointer paths require appropriate max-delay or bus-skew constraints
  from source pointer registers to first-stage synchronizer registers.
- Broad false-path or asynchronous-clock-group constraints can hide real
  timing problems if they override the intended Gray-path constraints.
- Intel constraints are provided as a template and are not implementation-
  verified in this repository.
- Vendor-specific features such as ECC, programmable thresholds, advanced
  sleep modes, and complete commercial CDC sign-off behavior are out of scope.

## Good Release Language

Prefer claims like:

- teaching RTL reference;
- bounded formal checks;
- source-level CDC structure checks;
- Xilinx template validation;
- requires target-specific STA/CDC/reset review.

Avoid claims like:

- production IP replacement;
- universally proved for all parameters;
- CDC sign-off complete for all targets;
- vendor FIFO equivalent.

## Where to Look Next

- [Interface and Timing](../interface.md) defines the public behavior.
- [CDC and Timing Constraints](../cdc_constraints.md) defines the integration
  sign-off responsibilities.
- [XPM_FIFO_ASYNC Comparison](../xpm_fifo_async_comparison.md) explains the
  gap between this teaching RTL and industrial FIFO expectations.
