# Documentation Index

This directory separates the project documentation by reader intent.

## Reading Route at a Glance

```text
Cummings theory -> RTL core -> Formal proofs -> XPM expectations -> FWFT option
        |              |              |                 |                |
 tutorial/map     core modules    proof guide      interface gap     read mode
```

## Study Tracks

| Track | Start | Then read | What to check in RTL or verification |
|---|---|---|---|
| Cummings-style async FIFO theory | [Step-by-step tutorial](tutorial.md) | [Cummings-style FIFO mapping](cummings_mapping.md), then [Learning Async FIFO](learning_async_fifo.md) | `rtl/core/wptr_full.v`, `rtl/core/rptr_empty.v`, `rtl/core/sync_w2r.v`, `rtl/core/sync_r2w.v` |
| Formal verification | [Formal Verification Guide](formal_verification.md) | [Interface and Timing](interface.md) for the public contract | `formal/pointer_formal.sv`, `formal/core_formal.sv`, wrapper harnesses |
| Reproducible evidence | [Evidence Center](evidence/README.md) | [CDC and Timing Constraints](cdc_constraints.md) for sign-off boundaries | `make smoke`, `make test`, `make formal`, `make cdc`, optional Vivado flows |
| Common mistakes | [Common Async FIFO Mistakes](common_mistakes/README.md) | [Cummings-style FIFO mapping](cummings_mapping.md) for the correct structure | Binary pointer crossing, Gray-bus constraints, flags, reset, depth assumptions |
| Interview prep | [Async FIFO Interview Guide](interview_guide.md) | [Waveform Gallery](waveform_gallery.md) | Explain the design, then point to RTL, proofs, and constraints |
| Waveform-led learning | [Waveform Gallery](waveform_gallery.md) | [Step-by-step tutorial](tutorial.md) for the detailed timing walk | Tutorial VCD, standard read timing, FWFT comparison |
| Industrial interface expectations | [Interface and Timing](interface.md) | [XPM_FIFO_ASYNC Comparison](xpm_fifo_async_comparison.md) | Reset, status flags, almost flags, data counts, unsupported vendor-IP features |
| FWFT / fallthrough behavior | [FWFT / Fallthrough Design Notes](fwft_design.md) | [Interface and Timing](interface.md#equal-width-fwft-interface-async_fifo_fwft) | `rtl/wrappers/async_fifo_fwft.v`, `test/tb_fifo_fwft.sv`, `formal/fwft_formal.sv` |
| Bidirectional full-duplex CDC | [Bidirectional FIFO Wrapper Design](bidir_fifo_design.md) | [Interface and Timing](interface.md#bidirectional-equal-width-interface-async_bidir_fifo) | `rtl/wrappers/async_bidir_fifo.v`, `test/tb_fifo_bidir.sv` |
| External/custom RAM backend | [External RAM Interface FIFO Design](ramif_design.md) | [Interface and Timing](interface.md#external-ram-interface-async_fifo_ramif) | `rtl/wrappers/async_fifo_ramif.v`, `test/tb_fifo_ramif.sv` |
| Bidirectional external RAM composition | [Bidirectional RAMIF FIFO Design](bidir_ramif_fifo_design.md) | [Interface and Timing](interface.md#bidirectional-external-ram-interface-async_bidir_ramif_fifo) | `rtl/wrappers/async_bidir_ramif_fifo.v`, `test/tb_fifo_bidir_ramif.sv` |

## Learning Path

| Goal | Start here |
|---|---|
| Build the first async FIFO mental model | [Step-by-step tutorial](tutorial.md) |
| Map classic Cummings/Sunburst ideas to this RTL | [Cummings-style FIFO mapping](cummings_mapping.md) |
| Study the design in more depth | [Learning Async FIFO](learning_async_fifo.md) |
| Understand standard vs FWFT read behavior | [FWFT / Fallthrough Design Notes](fwft_design.md) |
| Understand full-duplex CDC composition | [Bidirectional FIFO Wrapper Design](bidir_fifo_design.md) |
| Understand the experimental external RAM backend | [External RAM Interface FIFO Design](ramif_design.md) |
| Understand full-duplex CDC with external RAM | [Bidirectional RAMIF FIFO Design](bidir_ramif_fifo_design.md) |
| Prepare for async FIFO interview questions | [Async FIFO Interview Guide](interview_guide.md) |
| Learn from reproducible waveforms | [Waveform Gallery](waveform_gallery.md) |

## Integration Path

| Goal | Start here |
|---|---|
| Choose and instantiate a public module | [Interface and Timing](interface.md) |
| Scan the public module boundary | [Public Module API](api.md) |
| Understand module layering and ownership | [Architecture](architecture.md) |
| Read the internal RTL implementation | [Internal Design Map](internal_design.md) |
| Review experimental and advanced wrapper boundaries | [Experimental and Advanced Modules](experimental.md) |
| Use layered RTL filelists | [RTL Filelists](filelists.md) |
| Review CDC and timing constraints | [CDC and Timing Constraints](cdc_constraints.md) |
| Check supported tools, targets, and releases | [Compatibility and Release Support](compatibility.md) |

## Verification and Comparison

| Goal | Start here |
|---|---|
| Read the formal proof strategy | [Formal Verification Guide](formal_verification.md) |
| Check reproducible evidence and known limits | [Evidence Center](evidence/README.md) |
| Learn common async FIFO and CDC mistakes | [Common Async FIFO Mistakes](common_mistakes/README.md) |
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
- [双向 FIFO Wrapper 设计](bidir_fifo_design_CN.md)
- [外部 RAM 接口 FIFO 设计](ramif_design_CN.md)
- [双向 RAMIF FIFO 设计](bidir_ramif_fifo_design_CN.md)
- [XPM_FIFO_ASYNC 对比](xpm_fifo_async_comparison_CN.md)
- [常见异步 FIFO 错误](common_mistakes/README_CN.md)
- [异步 FIFO 面试指南](interview_guide_CN.md)
- [波形图库](waveform_gallery_CN.md)
