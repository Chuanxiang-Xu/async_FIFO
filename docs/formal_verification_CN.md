# 形式验证指南

这份文档解释 formal 检查如何对应到用户可见的 FIFO 需求。它是阅读路线图，
不是 harness 源码的替代品。

如果你刚开始看这个设计，建议先读[逐步教程](tutorial_CN.md)和
[学习异步 FIFO](learning_async_fifo_CN.md)。如果你需要公开接口契约，读
[接口与时序](interface.md)。

本文中的 properties 使用与 `interface.md` 相同的公开行为：标准请求式读取用
脉冲式 `rd_valid` 标记 `rd_data` 更新，FWFT 读取通过 `rd_en && rd_valid`
pop 可见数据，stream 传输使用 `valid && ready`，复位是破坏性的协调启动。

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
| 双向通道各自保持顺序 | [`formal/bidir_formal.sv`](../formal/bidir_formal.sv) | full-duplex wrapper 组合不会耦合 A->B 和 B->A 数据流 |
| 外部 RAM 接口保持 standard FIFO 时序 | [`formal/ramif_formal.sv`](../formal/ramif_formal.sv) | 一拍 RAM 契约、顺序和 `rd_valid` 对齐 |
| 双向 RAMIF 通道各自保持顺序 | [`formal/bidir_ramif_formal.sv`](../formal/bidir_ramif_formal.sv) | full-duplex 外部 RAM 组合保持 A->B 和 B->A RAMIF 通道隔离 |
| 请求式变宽保持切片顺序 | [`formal/width_conv_formal.sv`](../formal/width_conv_formal.sv) | pack/split 数据顺序 |
| stream 元数据不脱离数据 | [`formal/stream_formal.sv`](../formal/stream_formal.sv) | `keep`、`last` 和反压行为 |
| wrapper 参数覆盖多个比例和深度 | [`formal/matrix_formal.sv`](../formal/matrix_formal.sv) | 代表性配置的回归覆盖 |

## 从用户需求到 property

阅读每个 harness 时，可以把它看成一个小翻译过程：

```text
用户可见规则 -> 本地传输接受条件 -> 参考状态 -> assertion
```

harness 不会先从内部实现细节开始证明。它们先抓住公开行为：某次传输被接受后，
用户之后必须观察到什么？

| 需求 | 参考模型 | property 形状 |
|---|---|---|
| 被 `full` 阻塞的写请求不能导致 overflow | `wr_en && full` 时写指针不应移动 | 在 `pointer_formal.sv` 中断言 blocked write 后 Gray 写指针保持不变 |
| 被 `empty` 阻塞的读请求不能消费数据 | `rd_en && empty` 时读指针不应移动 | 在 `pointer_formal.sv` 中断言 blocked read 后 Gray 读指针保持不变 |
| 已接受读取必须按 FIFO 顺序返回数据 | `write_sequence` 产生 token，`read_sequence` 预测下一个 token | 在 `core_formal.sv` 中对每个 `rd_valid` 断言 `rd_data == read_sequence` |
| 同步读时序必须对用户可见 | `previous_read_allow` 记录上一个已接受读请求 | 在 `core_formal.sv` 中断言 `rd_valid` 对齐上一拍已接受读请求 |
| FWFT stall 时可见数据必须保持 | `stalled_data` 在 `rd_valid && !rd_en` 时捕获可见字 | 在 `fwft_formal.sv` 中断言 `rd_valid` 保持为高且 `rd_data` 等于 `stalled_data` |
| stream 反压不能破坏一个 packet beat | 保存 `rd_valid && !rd_ready` 时的 `{rd_data, rd_keep, rd_last}` | 在 `stream_formal.sv` 中断言该 payload 在被接受前保持稳定 |

这也是 core 和 wrapper 证明使用计数 token 而不是完整 shadow memory 的原因。
单调递增 token 流足以让很多错误变得可观察：如果 FIFO 丢数据、重复数据、
乱序、从空存储读取，或者泄漏复位前旧数据，下一个 `rd_valid` 或 FWFT pop
就会和期望 token 不一致。

Assumption 尽量只贴近环境，而不是替 DUT 证明设计本身。这里的环境包括时钟、
复位以及 request/ready 信号；DUT 仍然必须根据 `full`、`empty`、`rd_valid`
或 `ready` 自己决定传输是否合法。Cover 则用来确认有意思的状态确实可达，
例如 full occupancy、FWFT stall 后 pop、stream final beat 等。

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
sby -f -d build/formal-bidir-bmc formal/bidir.sby bmc
sby -f -d build/formal-ramif-bmc formal/ramif.sby bmc
sby -f -d build/formal-bidir-ramif-bmc formal/bidir_ramif.sby bmc
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
| `formal/bidir.sby bmc` | PASS | 检查 A->B 和 B->A 独立顺序及本地反压 |
| `formal/ramif.sby bmc` | PASS | 用一拍外部 RAM model 检查顺序和 `rd_valid` 对齐 |
| `formal/bidir_ramif.sby bmc` | PASS | 用两套一拍外部 RAM model 检查 A->B 和 B->A 独立顺序 |
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
- [`formal/bidir_formal.sv`](../formal/bidir_formal.sv) 证明 full-duplex
  wrapper 在两个方向上保持独立 token 流，并让反压只影响对应通道；
- [`formal/ramif_formal.sv`](../formal/ramif_formal.sv) 证明外部 RAM 接口
  wrapper 在连接一拍同步 RAM model 时保持 standard FIFO 顺序和 `rd_valid` 时序；
- [`formal/bidir_ramif_formal.sv`](../formal/bidir_ramif_formal.sv) 证明双向
  RAMIF wrapper 保持两条外部 RAM 通道独立，包括顺序、`rd_valid` 对齐和本地反压；
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
- 双向和双向 RAMIF 通道都能到达 full，并产生有效读取；
- RAMIF wrapper 能到达 full，并通过外部 RAM model 返回有效读取；
- wrapper pack 和 split 路径能产生重复输出；
- stream 的 final 和 non-final 包传输都可达。

这些 cover 可以减少 vacuous proof，也能在学习设计行为时提供有用 trace。

## Bound 和覆盖范围

formal 任务保持有界，是因为这个仓库优先追求可读的教学 harness 和适合 CI 的
运行时间。PASS 表示 solver 已经穷举了该 harness、参数集合、assumption 和深度
允许的所有状态；它不表示已经证明了所有 FIFO 参数或所有物理实现。

这些 bound 的选择目标，是让最重要的 FIFO 失效模式变得可观察：

| Harness | 为什么这个 bound 有用 | 仍然不证明什么 |
|---|---|---|
| Pointer | 覆盖复位、允许的指针移动、被 full/empty 阻塞的请求，以及 Gray one-bit 变化。 | 所有同步器物理实现或布线延迟。 |
| Core BMC | 使用很小深度，让 full、empty、回绕和跨过一个 FIFO 深度的读取很快可达。 | 覆盖所有 `DATA_WIDTH`、`ADDR_WIDTH` 或所有时钟波形的单个符号化证明。 |
| Reset skew | 检查写域先释放和读域先释放的协调启动，请求在初始化完成前保持关闭。 | 运行中单侧复位并保留数据。 |
| FWFT | 覆盖可见 fallthrough 数据、stall 输出稳定、预取移动、复位清空，以及跨深度 pop。 | 所有输出流水线选择或 vendor FWFT 延迟选择。 |
| Bidir | 检查组合后的 A->B 和 B->A 通道中两个独立 token 流及本地反压。 | 跨方向事务原子性或共享资源仲裁；该 wrapper 有意不提供这些行为。 |
| RAMIF | 检查一拍同步外部 RAM model、RAM enable 对齐、顺序和 `rd_valid` 时序。 | 可变延迟 RAM、wait state、碰撞语义或目标 macro 时序。 |
| Width conversion | 用代表性 pack/split 比例检查 wrapper 本地存储中的 token 顺序。 | 任意非 2 次幂比例或所有合法参数组合。 |
| Stream | 检查 ready/valid 反压、包元数据稳定，以及 pack/split stream 路径。 | 文档化 ready/valid 契约之外的协议行为。 |
| Matrix | 在 request 和 stream wrapper 上抽样等宽、pack、split 配置。 | 穷举所有合法位宽和深度。 |

修改 RTL 时，应把当前 bound 当成回归触发器。如果新功能增加了存储、延迟或新的
状态机，应提高相关深度，或者增加一个 cover 证明新状态可达，再信任证明结果。

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
