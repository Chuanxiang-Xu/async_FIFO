# 形式验证指南

这份文档解释 formal 检查如何对应到用户可见的 FIFO 需求。它是阅读路线图，
不是 harness 源码的替代品。

如果你刚开始看这个设计，建议先读[逐步教程](tutorial_CN.md)和
[学习异步 FIFO](learning_async_fifo_CN.md)。如果你需要公开接口契约，读
[接口与时序](interface.md)。

## 证明策略

formal 检查被拆成几个小 harness，每个 harness 只负责一类明确行为：

| 用户可见需求 | formal 位置 | 保护什么 |
|---|---|---|
| Gray pointer 每次本地前进最多只变一位 | [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) | CDC 指针纪律 |
| 满时写请求不能推进写指针 | [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) | 阻止 blocked write 导致 overflow |
| 空时读请求不能推进读指针 | [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) | 阻止 blocked read 导致 underflow |
| 等宽 FIFO 保持数据顺序 | [`formal/core_formal.sv`](../formal/core_formal.sv) | 不丢失、不重复、不乱序 |
| `rd_valid` 对齐已接受读请求 | [`formal/core_formal.sv`](../formal/core_formal.sv) | 同步读时序正确 |
| 本地状态计数不越界 | [`formal/core_formal.sv`](../formal/core_formal.sv) | 保守的 `full`、`empty` 和 occupancy 视图 |
| 写域先释放或读域先释放都能启动 | [`formal/reset_skew_formal.sv`](../formal/reset_skew_formal.sv) | 复位错位后的协调启动 |
| FWFT 可见 pop 保持顺序 | [`formal/fwft_formal.sv`](../formal/fwft_formal.sv) | 预取槽不丢失、不重复、不乱序 |
| FWFT stall 时输出稳定 | [`formal/fwft_formal.sv`](../formal/fwft_formal.sv) | fallthrough 反压行为正确 |
| 请求式变宽保持切片顺序 | [`formal/width_conv_formal.sv`](../formal/width_conv_formal.sv) | pack/split 数据顺序 |
| stream 元数据不脱离数据 | [`formal/stream_formal.sv`](../formal/stream_formal.sv) | `keep`、`last` 和反压行为 |
| wrapper 参数覆盖多个比例和深度 | [`formal/matrix_formal.sv`](../formal/matrix_formal.sv) | 代表性配置的回归覆盖 |

harness 尽量使用确定性的 token 流，而不是大型 shadow RAM。例如
`core_formal.sv` 写入递增序列，并断言每个 `rd_valid` 都返回下一个期望值。
这个检查同时能抓到 underflow 数据、复位后的旧数据、重复、丢失和乱序。

## 如何运行

先激活仓库对应的 Conda 环境，或者在命令前加 `conda run -n async_fifo`：

```sh
conda activate async_fifo
```

完整 formal 套件：

```sh
make formal
```

学习时建议先跑下面这组小阶梯：

```sh
sby -f -d build/formal-pointer formal/pointer.sby
sby -f -d build/formal-core-bmc formal/core.sby bmc
sby -f -d build/formal-core-cover formal/core.sby cover
sby -f -d build/formal-fwft-bmc formal/fwft.sby bmc
sby -f -d build/formal-width-pack formal/width_conv.sby pack
sby -f -d build/formal-stream-pack formal/stream.sby pack
```

这些命令从局部指针规则开始，再到等宽 core 契约，最后进入一个 wrapper 路径。
在本仓库的 `async_fifo` Conda 环境中，上面前四个命令已经成功跑过：

| 命令 | 结果 | 为什么先跑它 |
|---|---|---|
| `formal/pointer.sby` | PASS | 最小证明；检查 Gray 变化和 blocked pointer |
| `formal/core.sby bmc` | PASS | 检查有界 core 顺序、状态、occupancy 和 `rd_valid` |
| `formal/core.sby cover` | PASS | 生成 full 和跨深度读取进展的 trace |
| `formal/fwft.sby bmc` | PASS | 检查 FWFT pop 顺序、stall 稳定、复位清空和可见 `empty` |
| `formal/width_conv.sby pack` | PASS | 检查一条请求式 wrapper 打包路径 |

Makefile 还会运行 `make formal-matrix`，覆盖一组代表性的 request/stream
wrapper 位宽、比例和地址宽度组合。

## 如何读 harness

先从 [`formal/pointer_formal.sv`](../formal/pointer_formal.sv) 开始。它是最小
证明，直接对应 Cummings 风格指针规则：

- Gray pointer 可以不变，或者只变化一个 bit；
- 满时写请求不会移动写指针；
- 空时读请求不会移动读指针。

然后读 [`formal/core_formal.sv`](../formal/core_formal.sv)。它把指针机制连接到
FIFO 契约：

- `wr_used` 和 `rd_used` 不超过配置深度；
- `full`、`empty` 与本地 occupancy 视图一致；
- `rd_valid` 跟随已接受读请求；
- 读出的数据严格等于下一个期望 token。

再看 wrapper harness：

- [`formal/fwft_formal.sv`](../formal/fwft_formal.sv) 证明 FWFT wrapper 按顺序
  呈现可见数据，stall 时保持稳定，并在读复位期间清空可见输出；
- [`formal/width_conv_formal.sv`](../formal/width_conv_formal.sv) 证明请求式
  双向变宽的 little-slice-first 顺序；
- [`formal/stream_formal.sv`](../formal/stream_formal.sv) 证明包元数据和反压
  时输出稳定；
- [`formal/matrix_formal.sv`](../formal/matrix_formal.sv) 在参数矩阵上重复较小
  的 wrapper 检查。

## Cover 的作用

cover 任务不是安全证明。它们用于证明重要状态在有界模型内确实可达：

- FIFO 能到达 full；
- 读取能跨过一个 FIFO 深度；
- FWFT 能暴露第一个字、stall 该字，并 pop 超过一个 FIFO 深度；
- wrapper pack 和 split 路径能产生重复输出；
- stream 的 final 和 non-final 包传输都可达。

这些 cover 可以减少 vacuous proof，也能在学习设计行为时提供有用 trace。

## 边界

这些检查是很强的回归测试，但它们仍然是有界的。它们不等价于证明所有整数参数、
所有连续变化时钟波形、所有目标 FPGA 实现或物理 CDC 时序。CDC 和时序签核边界
仍然见 [CDC 约束](cdc_constraints.md)。

本项目里可以这样理解三类检查：

```text
simulation: 具体场景和 scoreboard
formal:     选定 harness 内的有界穷举行为
CDC/STA:    物理实现签核
```
