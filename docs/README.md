# Documentation Index

This directory separates the project documentation by reader intent.

## Four Study Tracks

| Track | Start | Then read | What to check in RTL or verification |
|---|---|---|---|
| Cummings-style async FIFO theory | [Step-by-step tutorial](tutorial.md) | [Cummings-style FIFO mapping](cummings_mapping.md), then [Learning Async FIFO](learning_async_fifo.md) | `rtl/core/wptr_full.v`, `rtl/core/rptr_empty.v`, `rtl/core/sync_w2r.v`, `rtl/core/sync_r2w.v` |
| Formal verification | [Formal Verification Guide](formal_verification.md) | [Interface and Timing](interface.md) for the public contract | `formal/pointer_formal.sv`, `formal/core_formal.sv`, wrapper harnesses |
| Industrial interface expectations | [Interface and Timing](interface.md) | [XPM_FIFO_ASYNC Comparison](xpm_fifo_async_comparison.md) | Reset, status flags, almost flags, data counts, unsupported vendor-IP features |
| FWFT / fallthrough behavior | [FWFT / Fallthrough Design Notes](fwft_design.md) | [Interface and Timing](interface.md#equal-width-fwft-interface-async_fifo_fwft) | `rtl/wrappers/async_fifo_fwft.v`, `test/tb_fifo_fwft.sv`, `formal/fwft_formal.sv` |

## Learning Path

| Goal | Start here |
|---|---|
| Build the first async FIFO mental model | [Step-by-step tutorial](tutorial.md) |
| Map classic Cummings/Sunburst ideas to this RTL | [Cummings-style FIFO mapping](cummings_mapping.md) |
| Study the design in more depth | [Learning Async FIFO](learning_async_fifo.md) |
| Understand standard vs FWFT read behavior | [FWFT / Fallthrough Design Notes](fwft_design.md) |

## Integration Path

| Goal | Start here |
|---|---|
| Choose and instantiate a public module | [Interface and Timing](interface.md) |
| Understand module layering and ownership | [Architecture](architecture.md) |
| Review CDC and timing constraints | [CDC and Timing Constraints](cdc_constraints.md) |
| Check supported tools, targets, and releases | [Compatibility and Release Support](compatibility.md) |

## Verification and Comparison

| Goal | Start here |
|---|---|
| Read the formal proof strategy | [Formal Verification Guide](formal_verification.md) |
| Compare with AMD/Xilinx XPM expectations | [XPM_FIFO_ASYNC Comparison](xpm_fifo_async_comparison.md) |
| Run the PYNQ-Z2 validation flow | [PYNQ-Z2 Vivado Validation](pynq_z2_vivado.md) |
| Prepare a Xilinx self-hosted runner | [Xilinx Self-Hosted Runner](xilinx_runner.md) |

Chinese learning-path documents are paired where the page is intended for
first-time readers:

- [逐步教程](tutorial_CN.md)
- [Cummings 风格 FIFO 映射](cummings_mapping_CN.md)
- [学习异步 FIFO](learning_async_fifo_CN.md)
- [形式验证指南](formal_verification_CN.md)
- [FWFT / Fallthrough 设计说明](fwft_design_CN.md)
- [XPM_FIFO_ASYNC 对比](xpm_fifo_async_comparison_CN.md)
