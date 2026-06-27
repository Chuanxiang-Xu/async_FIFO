# 异步 FIFO 面试指南

这份指南把本仓库整理成 FPGA 面试复习路线。目标不是背答案，而是能把每个问题讲成：

```text
直觉 -> 机制 -> RTL 位置 -> 验证/约束边界
```

如果只记一句话，记这个：

```text
数据通过双时钟 RAM 跨域；控制通过寄存后的 Gray pointer 跨域；
full/empty 在本地时钟域保守地产生。
```

建议先读 [逐步教程](tutorial_CN.md)，再用本指南查漏补缺。

## 一分钟总览

异步 FIFO 的难点不是 RAM，而是“两个时钟域如何安全判断对方指针”。本项目采用经典
Cummings/Sunburst 风格：

| 概念 | RTL 位置 | 面试时怎么说 |
|---|---|---|
| 本地二进制指针 | `rtl/core/wptr_full.v`, `rtl/core/rptr_empty.v` | 二进制方便加一、寻址、计算本地 occupancy。 |
| 额外 pointer bit | `rtl/core/async_fifo_core.v` | 低位寻址，高位区分 wrap，从而区分空和满。 |
| Gray pointer | `wptr_gray`, `rptr_gray` | 相邻计数只变一个 bit，降低多 bit 异步采样风险。 |
| 两级同步器 | `rtl/core/sync_w2r.v`, `rtl/core/sync_r2w.v` | 对侧 Gray pointer 先同步，再参与本地 `full`/`empty` 判断。 |
| `empty` 判断 | `rptr_empty.v` 的 `rempty_next` | next read Gray pointer 等于同步后的 write Gray pointer。 |
| `full` 判断 | `wptr_full.v` 的 `wfull_next` | next write Gray pointer 等于同步后 read Gray pointer 的高两位取反形式。 |
| `rd_valid` | `rtl/core/async_fifo_core.v` | 标准 FIFO 使用同步读 RAM，读请求后一拍用 `rd_valid` 限定 `rd_data`。 |
| CDC 约束 | `docs/cdc_constraints.md` | Gray code 不等于物理签核完成，仍要约束 Gray bus skew/max delay。 |

## 高频问题

### 1. 为什么不能直接同步二进制指针？

二进制指针一次加一可能多个 bit 同时变化，比如：

```text
011 -> 100
```

异步采样时，接收域可能看到一个混合值。这个值既不是旧指针，也不是新指针，会导致
空满判断或 occupancy 计算错误。

本项目的做法是：本地保留二进制指针做计算，跨域前转换成寄存后的 Gray pointer。
对应 RTL 是 `wptr_full.v`、`rptr_empty.v`、`sync_w2r.v`、`sync_r2w.v`。

延伸阅读：[Binary Pointer Crossing](common_mistakes/binary_pointer_crossing.md)。

### 2. Gray code 是不是就完全安全了？

不是。Gray code 解决的是逻辑编码问题：相邻状态只变一个 bit。但布局布线以后，各
bit 到达同步器第一级的时间可能不同。如果 skew 太大，接收域仍可能在一个采样窗口
里看到跨越多个源端变化的效果。

所以还需要：

- 两级同步器；
- Gray pointer 源寄存器到目标同步器第一级的 max-delay 或 bus-skew 约束；
- post-synthesis/post-route timing 和 CDC report review。

延伸阅读：[Missing Gray-Bus Constraints](common_mistakes/missing_gray_bus_constraints.md)、
[CDC 和时序约束](cdc_constraints.md)。

### 3. 为什么指针要多一位？

RAM 地址只有 `ADDR_WIDTH` 位，但 FIFO pointer 用 `ADDR_WIDTH + 1` 位。

低 `ADDR_WIDTH` 位用于 RAM 地址，高一位表示绕回状态。否则当写地址和读地址低位
相等时，你无法区分：

- FIFO 是空的；
- FIFO 刚好满了，写指针绕了一圈追上读地址。

延伸阅读：[Cummings 风格 FIFO 映射](cummings_mapping_CN.md)。

### 4. `empty` 怎么判断？

`empty` 在读时钟域产生。读侧把“如果本拍读被接受，下一拍读指针是多少”转换成
Gray pointer，然后和同步过来的写 Gray pointer 比较：

```text
next rptr_gray == synchronized wptr_gray
```

如果相等，说明从读侧视角看没有未读数据。注意“从读侧视角”很重要，因为写指针跨到
读侧有同步延迟。

### 5. `full` 怎么判断？

`full` 在写时钟域产生。写侧预测下一拍写指针，如果它正好比同步后的读指针领先一个
FIFO 深度，则不能继续写。

在本项目使用的 reflected Gray code 中，常见表达是：

```text
next wptr_gray == synchronized rptr_gray with two MSBs inverted
```

常见错误是只取反一个 MSB。这个项目在 `wptr_full.v` 里使用 `FULL_MASK` 取反高两位。

### 6. 为什么 `full` 和 `empty` 会“慢半拍”或“保守”？

因为每个时钟域只能看到同步后的对侧指针。读侧已经读走数据以后，写侧要等读指针
跨回来才知道空间释放；写侧已经写入数据以后，读侧要等写指针跨过去才知道数据可读。

这叫保守撤销：可能晚一点允许传输，但不能错误允许上溢或下溢。

延伸阅读：[Wrong Full/Empty Assumptions](common_mistakes/wrong_full_empty_assumptions.md)。

### 7. 标准 FIFO 的 `rd_valid` 是什么？

标准 `async_fifo` 的读接口是 request/response：

```text
rd_en && !empty  接受读请求
rd_valid         标记 rd_data 有效
```

因为内部 RAM 是同步读，`rd_en` 不是数据有效信号。用户必须用 `rd_valid` 采样
`rd_data`。

FWFT wrapper 不同：`rd_valid` 是“当前已经有可见数据”的 level 信号，
`rd_en && rd_valid` 才 pop 当前数据。

波形对比见 [Waveform Gallery](waveform_gallery_CN.md)。

### 8. 复位怎么讲？

本项目使用低有效异步复位输入。复位可以异步断言，但撤销必须在各自本地时钟域同步。
复位是破坏性的：FIFO 里已有数据被丢弃，运行中单侧复位并保留数据不属于支持契约。

对应检查包括：

- `async_reset_sync` 辅助模块；
- `formal/reset_skew_formal.sv`；
- `formal/stream_reset_skew_formal.sv`；
- `test/tb_reset_sync.sv`。

延伸阅读：[Unsafe Reset Release](common_mistakes/unsafe_reset_release.md)。

### 9. 为什么深度必须是 2 的幂？

本项目使用常规 reflected-Gray pointer 序列和高两位取反的 full 判断。这个结构依赖
2 的幂环形计数。任意深度会让 wrap、Gray 相邻性、full 判断和 formal harness 都变
复杂。

工程上通常选择下一个更大的 2 的幂深度，或者使用明确支持该深度的 vendor FIFO。

延伸阅读：[Non-Power-of-Two Depths](common_mistakes/non_power_of_two_depths.md)。

### 10. formal 证明了什么，没有证明什么？

本仓库 formal 检查的是有界、参数抽样的行为：

- Gray pointer 单 bit 变化；
- 满时写指针不动；
- 空时读指针不动；
- 数据顺序；
- `rd_valid` 对齐；
- reset release；
- FWFT、width conversion、stream、bidir、RAMIF wrapper 行为。

它不是对所有参数、所有器件、所有布局布线的数学签核，也不能替代 STA/CDC report。

延伸阅读：[形式验证指南](formal_verification_CN.md)、[证据中心](evidence/README.md)。

## 面试回答模板

可以按这个结构回答：

```text
1. 先说问题：两个时钟域不能直接比较未同步指针。
2. 再说机制：本地 binary，跨域 Gray，两级同步。
3. 再说空满：read domain 产生 empty，write domain 产生 full。
4. 再说保守性：同步延迟导致 flag deassertion 保守，但安全。
5. 最后说工程边界：Gray bus 仍需约束，formal 是 bounded，不替代 STA/CDC。
```

## 30 分钟复习路线

1. 看 [Waveform Gallery](waveform_gallery_CN.md)。
2. 读 [Cummings 风格 FIFO 映射](cummings_mapping_CN.md) 到 full/empty 部分。
3. 读 [常见异步 FIFO 错误](common_mistakes/README_CN.md)。
4. 打开 `rtl/core/wptr_full.v` 和 `rtl/core/rptr_empty.v`。
5. 跑 `make smoke`。

## 深度复习路线

1. 跑 `make tutorial`，打开 `build/tutorial_async_fifo.vcd`。
2. 读 [接口与时序](interface.md)。
3. 读 [形式验证指南](formal_verification_CN.md)。
4. 读 [CDC 和时序约束](cdc_constraints.md)。
5. 根据 [证据中心](evidence/README.md) 跑相关仿真或 formal target。
