# 学习异步 FIFO

这份文档面向“想通过这个项目学习异步 FIFO 原理”的读者，而不仅仅是想把它当
可复用 IP 直接实例化。

如果你只想知道怎么接端口，先看[接口与时序](interface.md)。如果你想先看模块
层次，先看[架构说明](architecture.md)。然后再回到这里，从问题、机制一路读到
RTL。

## 本文术语约定

| 术语 | 在本项目中的含义 |
|---|---|
| core（内核） | 等宽 FIFO 实现层，负责 CDC、存储器、指针和本地状态 |
| wrapper（封装层） | 包在 core 外面的协议或位宽适配层，不改变核心 CDC 机制 |
| payload（载荷） | FIFO 存储的完整数据项；stream 模式下包含 `keep`、`last` 等元数据 |
| beat（拍） | 一次被接口接受的传输 |
| occupancy（占用量） | 某个本地时钟域看到的 used-count 视图，不是全局瞬时精确值 |
| Gray pointer（格雷码指针） | 跨时钟域前由二进制指针转换得到的格雷码形式 |

## 1. 异步 FIFO 解决什么问题？

异步 FIFO 用来在两个互不相关的时钟域之间安全传递数据：

```text
写时钟域                         读时钟域
--------                         --------
wr_en, wr_data  ---> FIFO RAM ---> rd_en, rd_data
wr_clk              CDC          rd_clk
```

两个时钟的频率、相位、抖动都可能不同，也可能独立暂停。所以写侧不能直接使用
读侧产生的多 bit 计数器，读侧也不能直接使用写侧产生的多 bit 计数器。

这个 FIFO 把问题拆成三件事：

- payload 数据留在双时钟 RAM 里；
- 每个时钟域维护自己的本地二进制指针；
- 只有寄存后的格雷码指针通过同步器跨时钟域。

在这个仓库里，这套机制主要放在 [`rtl/core/`](../rtl/core/)。
[`rtl/async_fifo.v`](../rtl/async_fifo.v) 刻意保持为一个很薄的用户入口。

## 2. 它没有一个完美的全局状态

异步 FIFO 通常没有一个“所有时钟域同时准确”的全局 occupancy 寄存器。每个时钟域
看到的是自己的本地视角：

| 时钟域 | 自己维护 | 通过 CDC 收到 | 产生 |
|---|---|---|---|
| 写时钟域 | 写指针 | 同步后的读指针 | `full`、`almost_full`、`wr_used` |
| 读时钟域 | 读指针 | 同步后的写指针 | `empty`、`almost_empty`、`rd_used` |

所以 `full` 属于写时钟域，`empty` 属于读时钟域。它们可以安全地用于本地流控，
但不是同一瞬间的全局快照。

这种设计是保守的。远端已经释放空间或写入数据后，本地可能要等几拍同步器延迟
才能知道。因此 `full` 或 `empty` 可能比真实 RAM 状态更晚撤销，但这是安全的。

## 3. 为什么不能直接同步二进制指针？

FIFO 指针本质上是一个二进制计数器：

```text
000 -> 001 -> 010 -> 011 -> 100 -> ...
```

问题是二进制计数器可能一次翻转多个 bit。例如 `011 -> 100` 会同时翻转三个 bit。
如果另一个时钟域刚好在翻转过程中采样，就可能看到一个混合值，这个值既不是旧
指针，也不是新指针。

异步 FIFO 的做法是：跨域之前先把二进制指针转换成格雷码：

```text
binary: 000 001 010 011 100 101 110 111
gray:   000 001 011 010 110 111 101 100
```

格雷码每次递增只变化一个 bit。同步之后，接收端看到的可能是旧值，也可能是新值，
但不容易变成完全无关的错误计数。当然，物理实现仍然需要时序约束，保证格雷码
总线到第一级同步触发器的偏斜受控。

相关 RTL：

- [`rtl/core/wptr_full.v`](../rtl/core/wptr_full.v)：写二进制指针与写格雷码指针
- [`rtl/core/rptr_empty.v`](../rtl/core/rptr_empty.v)：读二进制指针与读格雷码指针
- [`rtl/core/sync_w2r.v`](../rtl/core/sync_w2r.v)：写格雷码指针同步到读时钟域
- [`rtl/core/sync_r2w.v`](../rtl/core/sync_r2w.v)：读格雷码指针同步到写时钟域

## 4. 为什么指针要多一位？

如果 FIFO 深度是 `2**ADDR_WIDTH`，RAM 地址只需要 `ADDR_WIDTH` 位，但 FIFO 指针
通常使用 `ADDR_WIDTH + 1` 位。

低位用于访问 RAM，高位用于区分两种低位看起来相同的情况：

- 指针相等，因为 FIFO 是空的；
- 写指针绕了一圈，低地址位又回到了同一个位置。

这个额外的 wrap bit 让设计可以区分 empty 和 full。

```text
ADDR_WIDTH = 3
RAM 地址位 = pointer[2:0]
回绕位     = pointer[3]
```

## 5. empty 怎么判断？

读时钟域维护读指针，同时接收同步后的写指针。

当“下一拍读指针”会等于同步后的写指针时，FIFO 为空：

```text
next read Gray pointer == synchronized write Gray pointer
```

直观理解就是：从读侧视角看，接受这次读动作之后，就没有可读数据了。

对应 RTL 在 [`rtl/core/rptr_empty.v`](../rtl/core/rptr_empty.v)。

## 6. full 怎么判断？

写时钟域维护写指针，同时接收同步后的读指针。

对于这个项目使用的常见 Cummings 风格异步 FIFO，full 条件可以理解成：

```text
下一拍写指针刚好领先同步后的读指针一个 FIFO 深度
```

在格雷码比较里，表现为下一拍写格雷码指针与同步后的读格雷码指针相比，最高两位
取反，其余位相同。这个比较式看起来有点绕，是因为指针带了额外回绕位，而且已经
转换成格雷码。核心思想很简单：写侧必须在覆盖未读数据之前停下来。

对应 RTL 在 [`rtl/core/wptr_full.v`](../rtl/core/wptr_full.v)。

## 7. 数据到底在哪里？

payload 数据不会穿过两级指针同步器。真正的数据保存在双时钟 RAM 中：

- 写侧用写地址把 `wr_data` 写入 RAM；
- 读侧用读地址从 RAM 读出 `rd_data`。

指针决定哪些地址安全可用，RAM 承载真正的数据。

在这个仓库里，[`rtl/core/fifo_mem.v`](../rtl/core/fifo_mem.v) 描述存储器，让
综合工具可以推断 FPGA RAM 资源。

## 8. 复位要怎么理解？

FIFO 有两个低有效复位：

- `wr_rstn` 复位写时钟域状态；
- `rd_rstn` 复位读时钟域状态。

复位可以异步断言，但撤销必须同步到本地时钟。辅助模块
[`rtl/util/async_reset_sync.v`](../rtl/util/async_reset_sync.v) 就是为了实现这个模式。

复位是破坏性的。它应该被看成重新初始化 FIFO，而不是保留队列里的数据。启动时，
两侧应完成协调复位释放后再开始正常传输。

## 9. 为什么有同步器还要写约束？

两级同步器可以降低亚稳态风险，但不能替代 STA/CDC 签核。

这个设计期望的 CDC 结构是：

```text
binary pointer -> Gray register -> first sync flop -> second sync flop
```

物理实现必须控制从源端格雷码寄存器到第一级同步触发器之间的总线延迟或偏斜。
否则不同格雷码 bit 到达时间差过大，接收时钟沿附近仍然可能破坏“一次只变一位”
这个假设。

Vivado 约束可以看
[`constraints/xilinx/async_fifo.xdc`](../constraints/xilinx/async_fifo.xdc) 和
[CDC 约束](cdc_constraints.md)。

## 10. 为什么 width conversion 和 stream 是 wrapper？

core 有意保持等宽、轻协议。它负责真正的 CDC 问题：

```text
async_fifo_core
├── memory
├── write pointer and full
├── read pointer and empty
└── Gray pointer synchronizers
```

wrapper 负责在 core 外面适配接口：

- [`async_fifo_width_conv`](../rtl/wrappers/async_fifo_width_conv.v) 负责不同位宽之间的打包和拆包；
- [`async_fifo_stream`](../rtl/wrappers/async_fifo_stream.v) 把 `{data, keep, last}` 作为一个 payload 存入 core，并增加
  ready/valid 分包语义。

把 wrapper 放在 core 外面，学习路径会清楚很多：先理解等宽异步 FIFO，再看协议
适配如何复用这个 core。

## 推荐阅读顺序

1. 先看 [`examples/basic_fifo/`](../examples/basic_fifo/) 的最小集成例子。
2. 再看 [`rtl/async_fifo.v`](../rtl/async_fifo.v)，理解用户入口。
3. 看 [`rtl/core/async_fifo_core.v`](../rtl/core/async_fifo_core.v)，理解各个子模块怎么连起来。
4. 看 [`rtl/core/wptr_full.v`](../rtl/core/wptr_full.v) 和
   [`rtl/core/rptr_empty.v`](../rtl/core/rptr_empty.v)。
5. 看 [`rtl/core/sync_w2r.v`](../rtl/core/sync_w2r.v) 和
   [`rtl/core/sync_r2w.v`](../rtl/core/sync_r2w.v)。
6. 看 [CDC 约束](cdc_constraints.md)，把 RTL 思路和 FPGA 实现连接起来。
7. 等等宽 core 理解顺了，再看 wrappers。

读 RTL 时可以一直抓住这个心智模型：

```text
数据路径：RAM，由本地二进制指针寻址
控制路径：格雷码指针跨时钟域同步
状态路径：本地指针 + 同步后的远端指针，产生本地 full/empty 等状态
```
