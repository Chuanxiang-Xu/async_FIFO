# 波形图库

这个页面把本项目的波形学习路线集中起来。这里只引用仓库里已有的 SVG、testbench 和
可复现命令，不放编造截图。

## 如何重新生成

教程 VCD 用下面命令生成：

```bash
make tutorial
```

输出文件是：

```text
build/tutorial_async_fifo.vcd
```

建议在波形工具里重点看这些信号：

```text
wr_clk, wr_rstn, wr_en, wr_data, full
rd_clk, rd_rstn, rd_en, rd_data, rd_valid, empty
```

## 标准 async FIFO 时序

![Representative async FIFO waveform](assets/async_fifo_waveform.svg)

重点观察：

- 写时钟和读时钟互不相关；
- 只有 `wr_en && !full` 时写入才被接受；
- 读侧要等写 Gray pointer 同步过来后才看到可读数据；
- `rd_valid` 限定返回的 `rd_data`；
- `empty` 的撤销是保守的，不是写入发生后立刻变化。

继续读：

- [逐步教程](tutorial_CN.md)
- [接口与时序](interface.md#equal-width-interface-async_fifo)

## 教程里的写满再读出场景

![Tutorial async FIFO waveform](assets/tutorial_waveform.svg)

这张图来自 `test/tb_fifo_tutorial.sv`，场景是深度 4 的 FIFO：

| 片段 | 该看什么 |
|---|---|
| 写入 `A0`, `A1`, `A2`, `A3` | `full=0` 时写请求被接受。 |
| `empty` 延迟撤销 | 读侧等待同步后的写指针。 |
| `full` 置位 | 写侧预测下一次写会覆盖未读数据。 |
| `full=1` 时尝试写 `EE` | 被阻塞的写不会进入存储。 |
| 读出 `A0`、再读出 `A1` | 顺序通过 `rd_valid` 和 `rd_data` 可见。 |
| `full` 延迟撤销 | 读指针跨回写侧后，写侧才知道空间释放。 |

运行：

```bash
make tutorial
```

然后查看：

```text
build/tutorial_async_fifo.vcd
```

继续读：

- [逐拍解释这张 waveform](tutorial_CN.md#8-逐拍解释这张-waveform)
- [Wrong Full/Empty Assumptions](common_mistakes/wrong_full_empty_assumptions.md)

## Standard read 与 FWFT read

![Standard read versus FWFT read timing](assets/fwft_vs_standard_waveform.svg)

标准 FIFO 是 request/response：

```text
rd_en && !empty  请求读
rd_valid         标记返回的 rd_data 有效
```

FWFT wrapper 是 observe/consume：

```text
rd_valid == 1       rd_data 已经可见
rd_en && rd_valid   消费当前可见数据
empty == !rd_valid
```

继续读：

- [FWFT / Fallthrough 设计说明](fwft_design_CN.md)
- [接口与时序](interface.md#equal-width-fwft-interface-async_fifo_fwft)
- `test/tb_fifo_fwft.sv`

## 架构图

![Async FIFO core and wrapper architecture](assets/architecture.svg)

用这张图把波形反推回 RTL 责任边界：

- 等宽 core 负责 pointer、同步器、flag、RAM 和 `rd_valid`；
- FWFT、width conversion、stream、bidirectional、RAMIF 都是围绕 CDC core 或同一
  pointer-control 模式的 wrapper；
- payload 通过 RAM 跨域，不通过逐 bit 同步器跨域。

继续读：

- [架构说明](architecture.md)
- [Cummings 风格 FIFO 映射](cummings_mapping_CN.md)
- [CDC 和时序约束](cdc_constraints.md)

## 建议练习

| 练习 | 运行或查看 | 信号 |
|---|---|---|
| 从空到第一笔可读 | `make tutorial` | `wr_en`, `empty`, `rd_en`, `rd_valid` |
| 写到 full | `make tutorial` | `wr_en`, `full`, 被阻塞的写数据 |
| full 后读出释放空间 | `make tutorial` | `rd_en`, `rd_valid`, `full` 撤销 |
| FWFT 可见数据 | `test/tb_fifo_fwft.sv` | `rd_valid`, `rd_data`, `rd_en`, `empty` |
| 复位行为 | `test/tb_reset_sync.sv`, `formal/reset_skew_formal.sv` | 本地 reset, `empty`, `rd_valid` |

更完整的可复现命令见 [证据中心](evidence/README.md)。
