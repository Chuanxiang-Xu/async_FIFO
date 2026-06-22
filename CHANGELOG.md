# Changelog

All notable changes are recorded here. The project follows Semantic
Versioning.

## [Unreleased]

- Reorganized RTL into `core/`, `wrappers/`, and `util/` layers while keeping
  `rtl/async_fifo.v` as the minimal stable user entry point.
- Added the `examples/basic_fifo` minimal integration example and a top-level
  "Which module should I use?" guide.
- Added architecture and centralized advanced-status documentation.
- Added a reproducible Conda verification environment and Markdown link checks.
- Added symbolic clock-rate/phase core BMCs.
- Expanded the wrapper matrix to 20 BMC elaborations, including 16-bit equal
  width and bidirectional 1:8 conversion.
- Removed all Verilator `-Wall` width warnings and made lint warnings fatal.
- Added Xilinx self-hosted runner readiness checks and setup documentation.
- Replaced the incompatible SBY/ABC BMC combination with the pinned Z3 SMT
  engine used by CI.

## [1.0.0] - 2026-06-21

- Added equal-width, width-converting, and packet-stream asynchronous FIFO
  interfaces.
- Added randomized simulation scoreboards, assertions, bounded formal checks,
  reset-skew checks, and a concrete parameter matrix.
- Added digest-pinned open-source CI toolchains.
- Added PYNQ-Z2 Vivado implementation, timing, CDC, DRC, and bitstream flow.
- Added instance-scoped Xilinx Gray-bus constraints with exact post-synthesis
  endpoint validation and multi-instance positive/negative tests.
- Added the reusable `async_reset_sync` integration module.
