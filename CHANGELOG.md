# Changelog

All notable changes are recorded here. The project follows Semantic
Versioning.

## [Unreleased]

- Clarified RAMIF external-memory integration guidance, including vendor RAM
  inference or macro binding, fixed one-cycle read latency, same-address
  collision assumptions, and sign-off evidence for project-owned RAM wrappers.

## [1.1.0] - 2026-06-24

- Added `async_fifo_fwft`, an equal-width first-word-fall-through wrapper that
  keeps the Cummings-style CDC core unchanged and adds read-side prefetch
  storage.
- Added directed FWFT simulations covering first-word visibility, output
  stability under backpressure, continuous pop order, empty pop attempts, and
  read reset clearing.
- Added FWFT formal BMC/cover tasks for pop ordering, no duplication/loss,
  stalled-output stability, visible `empty`, and reset clearing.
- Added Cummings/Sunburst concept-to-RTL mapping documentation in English and
  Chinese.
- Added FWFT design notes, standard-vs-FWFT tutorial timing, and a
  documentation index.
- Updated interface, formal, XPM comparison, README, FuseSoC, and contributor
  documentation for the FWFT wrapper.
- Surfaced the GitHub Actions RTL checks badge in the README files.

## [1.0.0] - 2026-06-23

- Reorganized RTL into `core/`, `wrappers/`, and `util/` layers while keeping
  `rtl/async_fifo.v` as the minimal stable user entry point.
- Added the `examples/basic_fifo` minimal integration example and a top-level
  "Which module should I use?" guide.
- Added architecture, learning, and centralized advanced-status documentation.
- Added README architecture and waveform figures plus concise limitation and
  board-demo summaries.
- Added a reproducible Conda verification environment and Markdown link checks.
- Added symbolic clock-rate/phase core BMCs.
- Expanded the wrapper matrix to 20 BMC elaborations, including 16-bit equal
  width and bidirectional 1:8 conversion.
- Removed all Verilator `-Wall` width warnings and made lint warnings fatal.
- Added Xilinx self-hosted runner readiness checks and setup documentation.
- Replaced the incompatible SBY/ABC BMC combination with the pinned Z3 SMT
  engine used by CI.

- Added equal-width, width-converting, and packet-stream asynchronous FIFO
  interfaces.
- Added randomized simulation scoreboards, assertions, bounded formal checks,
  reset-skew checks, and a concrete parameter matrix.
- Added digest-pinned open-source CI toolchains.
- Added PYNQ-Z2 Vivado implementation, timing, CDC, DRC, and bitstream flow.
- Added instance-scoped Xilinx Gray-bus constraints with exact post-synthesis
  endpoint validation and multi-instance positive/negative tests.
- Added the reusable `async_reset_sync` integration module.
