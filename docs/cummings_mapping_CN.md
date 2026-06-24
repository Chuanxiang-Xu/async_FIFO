# Cummings 风格 FIFO 映射

本文把 Cummings/Sunburst 经典异步 FIFO 思路映射到本仓库的 RTL。它适合作为
逐步教程和更深入实现说明之间的一层：

```text
逐步教程 -> Cummings 映射 -> 原理深读 -> 形式验证指南
```

本仓库不是逐行复刻某一篇论文。它保留的是同一组核心思想：本地二进制指针、
跨域格雷码指针、额外一位回绕位、两级指针同步器，以及本地时钟域内产生
`full`/`empty`。

## 概念对应位置

| Cummings 风格概念 | 本仓库位置 | 作用 |
|---|---|---|
| 2 的幂深度环形存储 | `fifo_mem`，由 `waddr` 和 `raddr` 索引 | 指针低位选择 RAM 项，回绕由额外位跟踪。 |
| 额外指针位 | `async_fifo_core` 中的 `[ADDR_WIDTH:0]` 指针 | 当 RAM 地址位相等时，用来区分空和满。 |
| 本地二进制指针 | `wptr_full` 的 `wptr_bin`，`rptr_empty` 的 `rptr_bin` | 二进制形式便于自增、寻址和估算占用量。 |
| 二进制转格雷码 | `(ptr_bin_next >> 1) ^ ptr_bin_next` | 相邻指针值只改变一位，适合跨异步边界采样。 |
| 寄存后的格雷码源指针 | `wptr_gray`，`rptr_gray` | 跨域同步的是寄存指针，不是组合逻辑。 |
| 指针同步器 | `sync_w2r`，`sync_r2w` | 指针通过两级 `ASYNC_REG` 触发器跨域。 |
| 空判断 | `rptr_gray_next == wptr_gray_sync` | 读指针追上同步后的写指针时，读侧为空。 |
| 满判断 | `wptr_gray_next == (rptr_gray_sync ^ FULL_MASK)` | 写指针比同步后的读指针领先一整圈时，写侧为满。 |
| 保守标志 | 本地时钟域寄存的 `full` 和 `empty` | 同步延迟会让标志撤销变慢，但不能允许溢出或下溢。 |
| payload 不逐 bit 同步 | `fifo_mem` | 数据保存在双时钟 RAM 中，只有指针跨时钟域。 |

## 指针宽度和额外位

RAM 有 `2**ADDR_WIDTH` 项，所以 `waddr` 和 `raddr` 使用 `ADDR_WIDTH` 位：

```verilog
wire [ADDR_WIDTH-1:0] waddr;
wire [ADDR_WIDTH-1:0] raddr;
```

FIFO 指针多一位：

```verilog
wire [ADDR_WIDTH:0] wptr_gray;
wire [ADDR_WIDTH:0] rptr_gray;
```

低 `ADDR_WIDTH` 位选择 RAM 地址。额外一位表示当前处在环形缓冲区的哪一圈。
如果没有这一位，地址位相等时会产生歧义：FIFO 可能是空，也可能刚好满。

## 本地用二进制，跨域用格雷码

每个本地时钟域内部，指针保持二进制形式，便于算术运算：

```verilog
wptr_bin_next = wptr_bin + (winc && !wfull);
rptr_bin_next = rptr_bin + (rinc && !rempty);
```

输出到另一个时钟域前，指针转换成格雷码：

```verilog
wptr_gray_next = (wptr_bin_next >> 1) ^ wptr_bin_next;
rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;
```

这个分工是设计核心：二进制适合本地计算，格雷码更适合被异步采样，因为相邻值只
变化一位。

## 同步方向

写指针同步到读时钟域，这样读侧才能判断是否有数据：

```text
wptr_gray -> sync_w2r -> wptr_gray_sync -> rptr_empty
```

读指针同步到写时钟域，这样写侧才能判断是否有空间：

```text
rptr_gray -> sync_r2w -> rptr_gray_sync -> wptr_full
```

每条路径都是对格雷码指针向量做同步。因此物理约束仍然重要：格雷码总线必须被
约束到合理的延迟或偏斜范围内，避免目的时钟域看到由布线偏斜造成的多 bit 变化。
见 [CDC 约束](cdc_constraints.md)。

## Empty 产生

读时钟域先预测下一个读指针，再和同步后的写指针比较：

```verilog
assign rptr_bin_next =
    rptr_bin + {{(PTR_WIDTH-1){1'b0}}, (rinc && !rempty)};
assign rptr_gray_next =
    (rptr_bin_next >> 1) ^ rptr_bin_next;
assign rempty_next = (rptr_gray_next == wptr_gray_sync);
```

使用 next pointer 的好处是，寄存后的 `empty` 描述下一次读请求是否可以被接受。
如果 `empty` 为高，读请求不会推动指针，也不会产生有效数据。

## Full 产生

写时钟域先预测下一个写指针，再检查它是否比同步后的读指针领先一整圈：

```verilog
localparam [PTR_WIDTH-1:0] FULL_MASK =
    {2'b11, {(PTR_WIDTH-2){1'b0}}};

assign wptr_gray_next =
    (wptr_bin_next >> 1) ^ wptr_bin_next;
assign wfull_next =
    (wptr_gray_next == (rptr_gray_sync ^ FULL_MASK));
```

在反射格雷码中，满判断需要翻转同步后对侧指针的两个最高位，低位保持不变。
只翻转一个最高位是很常见的错误。

## 本仓库的有意差异

项目遵循 Cummings 风格模型，但为了 FPGA 可移植性和教学清晰度，做了几处明确的
实现选择。

| 选择 | 影响 |
|---|---|
| 同步后指针比较 | `full` 和 `empty` 都在对侧指针通过两级同步器后产生。 |
| 同步读 RAM | `fifo_mem` 使用简单双时钟 RAM 模板，读数据被寄存。 |
| 显式 `rd_valid` | 使用者必须用 `rd_valid` 限定 `rd_data`，而不是假设数据立即 fallthrough。 |
| 等宽 CDC core | 位宽转换和 stream 分包语义都放在 wrapper 中，不进入跨域指针机制。 |
| 固定两级指针同步器 | 结构易读，并符合常见 FPGA CDC 实践；更深同步器可作为未来参数化扩展。 |
| 静态 almost 阈值 | `almost_full` 和 `almost_empty` 是简单的本地时钟域流控提示。 |

对使用者最明显的差异是 `rd_valid`。很多教材图重点解释指针安全，会把数据表现得
像是立即可见。本仓库使用同步读 RAM 模板，因此一次被接受的读请求会在读时钟沿
产生对应的寄存 `rd_data`，并由 `rd_valid` 标记。

## 常见错误实现

这些是本仓库希望帮助读者尽早识别的问题：

- 直接同步二进制指针。
- 在本地控制逻辑中比较未同步的对侧指针。
- 只使用 RAM 地址位，省略额外回绕位。
- 认为地址位相等就足以区分空和满。
- full 比较时只翻转一个格雷码最高位。
- 用组合跨域逻辑更新 `full` 或 `empty`。
- 把 payload 位逐个用同步器跨域，而不是放入双时钟 RAM。
- 把 `wr_used` 和 `rd_used` 当作同一个精确全局占用量。
- 用 `almost_full` 或 `almost_empty` 替代 `!full` 或 `!empty` 作为传输条件。
- 忘记给格雷码指针总线做物理时序约束。
- 假设复位会保留 FIFO 中的数据。

## 建议 RTL 阅读顺序

推荐按下面顺序读：

1. `rtl/async_fifo.v`：公开的等宽 FIFO 入口。
2. `rtl/core/async_fifo_core.v`：接受传输、RAM 实例、同步器连接和 `rd_valid`。
3. `rtl/core/wptr_full.v`：写侧二进制指针、格雷码指针、`full`、
   `almost_full` 和写侧占用量估计。
4. `rtl/core/rptr_empty.v`：读侧二进制指针、格雷码指针、`empty`、
   `almost_empty` 和读侧占用量估计。
5. `rtl/core/sync_w2r.v` 与 `rtl/core/sync_r2w.v`：格雷码指针跨域。
6. `rtl/core/fifo_mem.v`：payload 存储。

读完后，再看[形式验证指南](formal_verification_CN.md)，理解这些行为如何被检查。
