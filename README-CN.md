# 异步 FIFO：可复用 RTL、CDC 约束与验证指南

[English](README.md)

[接口与时序](docs/interface.md) ·
[CDC 约束](docs/cdc_constraints.md) ·
[PYNQ-Z2 Vivado 验证](docs/pynq_z2_vivado.md) ·
[Xilinx CI runner](docs/xilinx_runner.md) ·
[兼容性](docs/compatibility.md) ·
[变更记录](CHANGELOG.md) ·
[贡献指南](CONTRIBUTING.md) ·
[MIT 许可证](LICENSE)

## 使用前必读

这个仓库提供三个可综合 FIFO 入口，选择接口时应先确定事务语义：

- `async_fifo`：等宽、请求式读写；
- `async_fifo_width_conv`：整数 2 次幂比例的请求式位宽转换；
- `async_fifo_stream`：带 `ready/valid`、`keep` 和 `last` 的分包流接口，
  推荐用于新的流式集成。

仓库还提供 `async_reset_sync`，用于在单个时钟域中实现复位异步断言和
同步撤销。

集成前必须理解以下契约：

1. **传输判定**：请求式接口只在 `wr_rstn && wr_en && !full` 或
   `rd_rstn && rd_en && !empty` 的本地时钟沿接受请求，读取结果必须用 `rd_valid`
   限定；流式接口只在 `valid && ready` 时完成传输。
2. **复位语义**：`wr_rstn`、`rd_rstn` 为低有效异步复位输入。复位可以
   异步断言（拉低），但必须由集成方分别在本地时钟域同步撤销（拉高）。复位
   是破坏性的；两侧完成协调初始化前不得传输，运行中单侧复位并保留数据
   不在支持范围内。
3. **深度与位宽**：core（内核）深度必须是 2 的幂；变宽比例必须是整数 2 次幂，
   且 `ADDR_WIDTH` 必须足以产生至少 2 个内部宽字。
4. **容量单位**：`ADDR_WIDTH` 描述 core RAM 的窄字等效容量，不包含
   wrapper 的拼包、pending、拆包和预取槽。`wr_core_used/rd_core_used`
   只统计 core，不是整个模块的在途拍数。
5. **本地状态视图**：`full`、`empty`、`almost_full/almost_empty` 和占用量都在各自
   时钟域产生。远端指针同步延迟会使它们保守地延迟撤销；它们不是同一时刻
   的全局占用快照。almost 标志仅用于提前流控，不能替代正式传输条件。
6. **CDC 约束**：payload 保存在双口 RAM 中，只有寄存后的格雷码指针跨域。
   两级同步器不能替代 STA/CDC 签核；实现工程必须约束格雷码总线到第一级
   同步器的最大延迟或总线偏斜。
7. **验证边界**：仿真和 45 项形式验证任务结合了固定深层时钟调度、符号化
   时钟频率/相位 BMC 和具体参数矩阵，但不构成一个同时覆盖所有整数参数、
   连续变化时钟波形和所有目标器件的符号化证明。

本文中，“拍（beat）”表示一次接口传输，“core word”表示内部等宽 RAM
数据字，“payload”表示数据及其随附元数据。BMC 指有界模型检查，cover
用于证明目标状态在给定深度内可达。

## 1. 项目结构

```text
async_FIFO/
├── rtl/
│   ├── async_fifo.v             # 等宽可复用顶层
│   ├── async_fifo_width_conv.v  # 变宽可复用顶层
│   ├── async_fifo_stream.v      # 带包边界的 ready/valid 顶层
│   ├── async_reset_sync.v       # 异步断言、同步撤销复位模块
│   ├── files.f                  # RTL 文件清单
│   └── core/
│       ├── async_fifo_core.v    # 等宽异步 FIFO 顶层
│       ├── fifo_mem.v           # 双时钟 Simple Dual-Port RAM
│       ├── wptr_full.v          # 写指针和 full 产生
│       ├── rptr_empty.v         # 读指针和 empty 产生
│       ├── sync_w2r.v           # 写指针同步到读时钟域
│       └── sync_r2w.v           # 读指针同步到写时钟域
└── test/
    ├── tb_reset_sync.sv         # 复位同步模块行为测试
    ├── tb_fifo_basic.sv         # 基础功能和水位标志测试
    ├── tb_fifo_stream.sv        # 包边界、keep/last 和反压测试
    ├── tb_fifo_random.sv        # 边界、回绕和随机 scoreboard 测试
    ├── fifo_assertions.sv       # FIFO 指针断言
    ├── stream_assertions.sv     # ready/valid 稳定性断言
    └── xilinx/multi_fifo_top.v  # Vivado 多实例验证顶层

constraints/
├── xilinx/async_fifo.xdc        # 带实例作用域的 Vivado 约束模板
├── xilinx/check_async_fifo.tcl  # 综合后精确对象数量检查
└── intel/async_fifo.sdc         # Quartus/TimeQuest 约束模板

scripts/
├── check_cdc.py                 # 同步器源码结构检查
├── check_parameters.sh          # 非法参数诊断检查
├── check_release.py             # 发布版本一致性检查
├── validate_xilinx_template.tcl # Vivado 单实例验证
└── validate_xilinx_multi.tcl    # Vivado 多实例正向/负向验证

formal/
├── pointer_formal.sv            # 局部指针安全形式验证 harness
├── pointer.sby                  # 指针证明配置
├── core_formal.sv               # 异步时钟 core 与数据顺序 harness
├── core.sby                     # core BMC/cover 配置
├── anyclock_core_formal.sv      # 符号化时钟频率/相位 core harness
├── anyclock_core.sby            # 符号化时钟 BMC 配置
├── reset_skew_formal.sv         # 写域/读域先释放的复位错位 harness
├── reset_skew.sby               # 复位错位 BMC/cover 配置
├── stream_reset_skew_formal.sv  # 分包流式复位错位 harness
├── stream_reset_skew.sby        # 流式复位错位 BMC/cover 配置
├── matrix_formal.sv             # wrapper 参数矩阵 harness
├── matrix.sby                   # 20 项位宽/比例/地址 BMC
├── matrix_cover.sby             # 1:4 非空 cover
├── width_conv_formal.sv         # 变宽打包/拆包顺序 harness
├── width_conv.sby               # 变宽 wrapper BMC/cover 配置
├── stream_formal.sv             # 包元数据与反压 harness
└── stream.sby                   # 流式 wrapper BMC/cover 配置
```

项目提供三个可复用 FIFO 入口：

```text
async_fifo                   等宽接口，配置 DATA_WIDTH/ADDR_WIDTH
└── async_fifo_core

async_fifo_width_conv        变宽接口，配置 WDATA_WIDTH/RDATA_WIDTH/ADDR_WIDTH
└── async_fifo_core          标准等宽异步 FIFO 内核
    ├── fifo_mem
    ├── wptr_full
    ├── rptr_empty
    ├── sync_w2r
    └── sync_r2w

async_fifo_stream            推荐的新流式接口
└── async_fifo_core          将 {data, keep, last} 作为整体存储

async_reset_sync             可选的单时钟域复位集成辅助模块
```

简单等宽场景使用 `async_fifo`，请求式变宽场景使用
`async_fifo_width_conv`，新的分包流式接口使用 `async_fifo_stream`。

## 2. 参数如何设置

### 2.1 标准等宽 FIFO：`async_fifo`

| 参数 | 含义 | 设置方法 |
|---|---|---|
| `DATA_WIDTH` | 每个 FIFO 数据字的位宽 | 按总线数据宽度设置，例如 8、16、32、64 |
| `ADDR_WIDTH` | RAM 地址位宽 | FIFO 深度为 `2**ADDR_WIDTH` |
| `ALMOST_FULL_THRESHOLD` | 高水位阈值 | 默认为深度减一 |
| `ALMOST_EMPTY_THRESHOLD` | 低水位阈值 | 默认为一个数据字 |

容量计算：

```text
FIFO 深度 = 2**ADDR_WIDTH 个数据字
总容量    = DATA_WIDTH × 2**ADDR_WIDTH bit
指针宽度  = ADDR_WIDTH + 1 bit
```

例如设计一个 32 bit、深度 512 的等宽异步 FIFO：

```verilog
async_fifo #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(9)       // 2**9 = 512 words
) u_async_fifo (
    .wr_clk   (wr_clk),
    .wr_rstn  (wr_rstn),
    .wr_en    (wr_en),
    .wr_data (wr_data),
    .full     (full),
    .almost_full (almost_full),
    .wr_used  (wr_used),
    .rd_clk   (rd_clk),
    .rd_rstn  (rd_rstn),
    .rd_en    (rd_en),
    .rd_data (rd_data),
    .rd_valid (rd_valid),
    .empty    (empty),
    .almost_empty(almost_empty),
    .rd_used  (rd_used)
);
```

如果目标深度已知，可按下式选择：

```text
ADDR_WIDTH = log2(FIFO 深度)
```

当前格雷码指针实现要求深度为 2 的幂。例如深度 1024 使用
`ADDR_WIDTH=10`，不要设置成任意非 2 次幂深度。

### 2.2 变宽 FIFO：`async_fifo_width_conv`

| 参数 | 含义 | 设置方法 |
|---|---|---|
| `WDATA_WIDTH` | 写接口数据位宽 | 按写端总线设置 |
| `RDATA_WIDTH` | 读接口数据位宽 | 按读端总线设置 |
| `ADDR_WIDTH` | 以较窄数据项为单位的地址位宽 | 较窄端深度为 `2**ADDR_WIDTH` |
| `ALMOST_FULL_THRESHOLD` | 高水位阈值 | 以内核宽字为单位 |
| `ALMOST_EMPTY_THRESHOLD` | 低水位阈值 | 以内核宽字为单位 |

例如 16 bit 写、32 bit 读，较窄端容量为 1024 个 16-bit 数据：

```verilog
async_fifo_width_conv #(
    .WDATA_WIDTH(16),
    .RDATA_WIDTH(32),
    .ADDR_WIDTH (10)     // narrow depth = 2**10 = 1024
) u_async_fifo_width_conv (
    // ports
);
```

此时：

```text
位宽比例        = 32 / 16 = 2
窄端逻辑深度    = 2**10 = 1024
内核数据位宽    = 32 bit
内核地址位宽    = 10 - log2(2) = 9
内核物理深度    = 2**9 = 512
内核 RAM 容量   = 1024×16 = 512×32 bit
```

位宽比例必须是 1、2、4、8 等 2 的幂，并且
`ADDR_WIDTH > log2(位宽比例)`。

`ADDR_WIDTH` 描述的是内核 RAM 容量，不是整个 wrapper 流水线的硬上限。
对于位宽比例 `R`，请求式变宽模块还可以在本地打包/暂存或拆包缓冲中保存
一个宽字等效的数据。因此上例的 RAM 容量是 1024 个 16-bit 数据，本地
wrapper 最多还可保存两个 16-bit 数据。`wr_core_used` 和 `rd_core_used`
仍只统计 512 个宽字的内核。

容量契约如下：

```text
R = 位宽比例
N = 2**ADDR_WIDTH 个窄字等效的内核 RAM 容量
C = N / R 个内部宽字

等宽模式              最大在途量 = N 个接口数据字
窄写宽读              最大在途量 = N + R 个窄字
宽写窄读              最大在途量 = C + 1 个宽写数据
                               = N + R 个窄切片
```

额外的 `R` 个窄字等效量来自一个 wrapper 本地宽字缓冲，并不是可寻址 RAM
容量。流式 wrapper 还包含独立的写侧和读侧流水槽，精确定义见
[接口与时序](docs/interface.md)。

## 3. 为什么需要异步 FIFO？

异步 FIFO 的写端和读端工作在不同的时钟域。它主要解决：

1. 不同时钟域之间的数据传输；
2. 上下游瞬时速率不一致时的数据缓冲；
3. 在包装层中完成整数倍位宽转换。

数据本身通过双口 RAM 存储，不对整条数据总线逐位同步。跨时钟域传输的是
位宽较小、已寄存的格雷码指针，接收时钟域根据同步后的远端指针保守地
判断能否安全访问 RAM。

## 3.1 推荐的流式接口

`async_fifo_stream` 提供完整的 ready/valid 握手和包元数据：

```verilog
// 写时钟域
wr_valid, wr_ready, wr_data, wr_keep, wr_last

// 读时钟域
rd_valid, rd_ready, rd_data, rd_keep, rd_last
```

仅在下列条件成立时完成一次传输：

```text
wr_valid && wr_ready
rd_valid && rd_ready
```

当 `valid=1` 且 `ready=0` 时，发送方必须保持 `valid` 为高，并保持
`data`、`keep` 和 `last` 稳定，直到握手完成。
代码将 `{data, keep, last}` 作为一个完整 payload 写入 FIFO，因此包边界
和字节有效信息不会在跨时钟域过程中与数据分离。

数据位宽必须是 8 的正整数倍，`keep[0]` 对应 `data[7:0]`。推荐协议约定：
非末拍的 `keep` 全为 1；末拍使用非零、从低位连续有效的 `keep` 掩码。

## 3.2 写端弹性缓冲为什么能提高吞吐率

`pending_payload` 是写接口和 `async_fifo_core` 之间的一级弹性缓冲：

```text
写接口 -> 直接/拼包路径 -> pending_payload -> 异步 FIFO 内核
```

旧 pending 宽字在以下条件成立时进入内核：

```verilog
pending_pop = pending_valid && !core_full;
```

当 pending 寄存器为空，或者旧数据会在当前时钟沿离开时，输入端都可以
继续接收：

```verilog
wr_ready = !pending_valid || !core_full;
```

对应四种状态组合：

| 旧 pending 出队 | 新完整宽字到达 | 处理结果 |
|---:|---:|---|
| 0 | 0 | 保持当前状态 |
| 0 | 1 | 保存新宽字 |
| 1 | 0 | 清空 pending 寄存器 |
| 1 | 1 | 旧宽字进入内核，新宽字原位补入 |

最后一种情况消除了原有的固定空拍。只要内核还有空间，等宽/直接写路径
现在可以在每个 `wr_clk` 上升沿接收一拍。窄写模式下，普通窄切片继续写入
`pack_data`；如果某个切片恰好在旧 pending 离开的同一时钟沿组成完整宽字，
新宽字会直接替换 pending，不需要额外等待一拍。

反压安全性不变：当 `core_full` 和 `pending_valid` 同时为高时，`wr_ready`
拉低，发送方必须保持 `wr_data`、`wr_keep` 和 `wr_last` 稳定。

### 变宽随机验证如何建立参考结果

验证环境为两个方向分别建立了独立参考模型：

- 16→32：将已握手的 16-bit 拍按低切片优先拼接；`wr_last` 会冲刷未填满
  的宽字，模型同时生成期望的 32-bit `data/keep/last`；
- 32→16：把每个已握手的 32-bit 数据拆成有效的低、高 16-bit 切片；末拍
  `keep=0011` 时只生成低切片，不生成无效高切片。

两个测试都会随机化包长、valid 间隔、末拍 `keep` 和读端反压。scoreboard
逐拍比较完整的 `{data, keep, last}`，而不只是比较数据值。

## 4. 为什么指针需要多一位？

深度为 `DEPTH = 2^ADDR_WIDTH` 的 RAM 地址只需要 `ADDR_WIDTH` 位，但 FIFO 指针使用 `ADDR_WIDTH + 1` 位。

低 `ADDR_WIDTH` 位用于访问 RAM，额外的最高位用于记录回环：

- 读写指针完全相同：FIFO 空；
- 写指针比读指针领先一个完整深度：FIFO 满。

例如深度为 8：

```text
RAM 地址宽度 = 3 bit
FIFO 指针宽度 = 4 bit
```

代码对应：

```verilog
wire [ADDR_WIDTH-1:0] waddr;
wire [ADDR_WIDTH:0]   wptr_gray;
```

## 5. 为什么跨时钟域使用格雷码指针？

二进制计数器递增时可能同时翻转多位，例如：

```text
0111 -> 1000
```

如果接收时钟恰好在翻转期间采样，不同位的路径延迟可能形成一个不存在的组合值。

二进制反射格雷码（Binary-Reflected Gray Code，BRGC，以下简称格雷码）
的相邻计数值只改变一位：

```verilog
gray = (binary >> 1) ^ binary;
```

因此一次合法的指针递增只产生一个跨域翻转位。格雷码只降低多位不一致
采样的风险，不能消除亚稳态；每个格雷码指针仍然需要专用同步器链。

本项目中：

- `sync_w2r`：将写格雷码指针同步到读时钟域；
- `sync_r2w`：将读格雷码指针同步到写时钟域；
- `(* ASYNC_REG = "TRUE" *)`：向 FPGA 工具标记同步寄存器。

## 6. 指针应该同步到哪个时钟域？

原则是：标志必须在使用它的本地时钟域产生。

| 标志 | 本地时钟域 | 需要同步过来的远端指针 |
|---|---|---|
| `empty` | 读时钟域 | 写指针 |
| `full` | 写时钟域 | 读指针 |

所以本项目的数据流为：

```text
wptr_gray --sync_w2r--> wptr_gray_sync --rptr_empty--> empty
rptr_gray --sync_r2w--> rptr_gray_sync --wptr_full --> full
```

同步有延迟，因此标志可能保守：

- 新数据写入后，`empty` 可能晚几个读时钟周期撤销；
- 数据读出后，`full` 可能晚几个写时钟周期撤销。

这种延迟降低了瞬时可用容量，但不会允许下溢或上溢。

## 7. 空和满如何判断？

### 7.1 空判断

读时钟域计算下一读指针：

```verilog
rptr_bin_next  = rptr_bin + (rinc && !rempty);
rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;
rempty_next    = (rptr_gray_next == wptr_gray_sync);
```

当“下一读格雷码指针”等于同步后的写格雷码指针时，说明执行本次合法读取后没有剩余数据。

### 7.2 满判断

对于采用二进制反射格雷码、深度为 2 的幂的 FIFO，满状态满足：

- 写指针与同步后的读指针低位相同；
- 两个最高位相反。

本项目用掩码表达：

```verilog
FULL_MASK  = {2'b11, {(PTR_WIDTH-2){1'b0}}};
wfull_next = (wptr_gray_next == (rptr_gray_sync ^ FULL_MASK));
```

这里必须反转两个最高位，而不是只反转二进制指针意义上的回环位。

## 8. 为什么使用“下一指针”计算标志？

`wptr_full` 和 `rptr_empty` 先计算当前周期请求被接受后的指针，再计算下一状态的 `full/empty`，最后在本地时钟沿寄存。

这样标志与本地指针状态一致：

```text
当前请求是否合法
        ↓
计算 binary_next
        ↓
转换 gray_next
        ↓
比较远端同步指针
        ↓
寄存 pointer 和 flag
```

写满时写请求不会推进写指针，读空时读请求不会推进读指针：

```verilog
winc && !wfull
rinc && !rempty
```

## 9. 双口 RAM 的设计

`fifo_mem` 只负责存储，不参与 CDC 和空满判断。它采用标准双时钟 Simple Dual-Port RAM 模板：

```verilog
always @(posedge wclk)
    if (wclken)
        mem[waddr] <= wdata;

always @(posedge rclk)
    if (rclken)
        rdata <= mem[raddr];
```

特点：

- 写端和读端分别使用自己的时钟；
- 同步写、同步读；
- RAM 数组不复位，有利于推断 FPGA Block RAM；
- RAM 中的未知初始内容由 `empty` 和指针状态隔离。

同步读意味着读请求在读时钟沿被接受，`rdata` 在该时钟沿后更新。`async_fifo_core` 提供 `rd_valid` 与这次更新对应。

## 10. 位宽转换如何实现？

经典异步 FIFO 内核保持等宽，使跨域指针每次只增加 1。位宽转换全部放在 CDC 内核外部。

### 10.1 窄写、宽读

在写时钟域打包，然后向内核写入一个宽字。

例如 16→32：

```text
依次写入 16'h0001、16'h0002
内核存储 32'h0002_0001
```

低位切片优先。

#### 10.1.1 原有半包阻塞问题及解决方案

旧版 `async_fifo_width_conv` 将拼好的宽字直接写入异步 FIFO 内核。如果内核在一个
宽字尚未拼完时变满，最后一个窄字必须等待读端释放空间后才能被接受。
FIFO 本身最终可以恢复，但如果系统规定“写端完成当前事务后读端才启动”，
这种等待可能参与形成系统级循环等待。

现在写端增加了一个完整宽字暂存槽：

```text
窄数据输入 -> 拼包寄存器 -> 完整宽字暂存寄存器
                              -> 异步 FIFO 内核
```

即使内核已经满，当前宽字仍可以接收最后一个窄切片并进入暂存槽。只有
暂存槽被占用时，旧接口的 `full` 才会阻止继续接收新窄字。

对于新设计，更推荐使用 `async_fifo_stream`：

- `wr_ready` 明确表示当前输入拍能否被接受；
- `wr_last` 可以立即冲刷未填满的宽字；
- `wr_keep` 记录末拍中哪些字节有效；
- 读端通过 `rd_valid/rd_ready` 安全处理反压。

### 10.2 宽写、窄读

内核读取一个宽字后，在读时钟域缓存并逐片输出。

例如 32→16：

```text
写入 32'h1122_3344
依次读出 16'h3344、16'h1122
```

`fetch_pending` 用于记录同步 RAM 的在途读取。流式顶层另外提供 current/next
两个读侧 payload 槽：当前宽字输出时预取下一个宽字；返回数据还可以在当前
输出恰好被消费的同一时钟沿完成替换。因此初始填充后，等宽和宽写窄读模式
都可以在数据持续可用时达到每个 `rd_clk` 一拍。

### 10.3 为什么不让格雷码指针一次增加多个地址？

如果为了位宽转换让跨域指针一次增加 2、4 等步长，连续传输的格雷码值不再
保证只变化一位，这会破坏采用格雷码进行 CDC 的基本前提。

本设计让等宽内核的指针每次只增加 1，并在单一时钟域中完成打包或拆包。

## 11. 参数限制

当前实现要求：

1. `WDATA_WIDTH` 和 `RDATA_WIDTH` 具有整数倍关系；
2. 位宽比例是 2 的幂；
3. `ADDR_WIDTH` 表示较窄端深度的 `log2`；
4. 推导出的内部地址宽度至少为 1；
5. FIFO 内核深度始终为 2 的幂。

例如：

```text
WDATA_WIDTH = 16
RDATA_WIDTH = 32
ADDR_WIDTH  = 10

CORE_WIDTH  = 32
WIDTH_RATIO = 2
CORE_ADDR_WIDTH = 9
CORE_DEPTH      = 512 个 32-bit 字
```

内核 RAM 容量仍为：

```text
1024 × 16 bit = 512 × 32 bit
```

这个数值不包含 wrapper 的本地弹性缓冲。请求式变宽模块可额外保存一个
宽字等效的数据；流式 wrapper 除内核外，还可能同时保存一个写侧 payload
和最多两个预取的读侧 payload。这些本地槽会增加总在途数据，但明确不计入
`*_core_used`。

## 12. 八个核心问题的实现映射

| PDF 学习问题 | 本项目对应 |
|---|---|
| 异步 FIFO 的作用 | `async_fifo_width_conv` + `async_fifo_core` |
| 如何理解空满 | 扩展一位的读写指针 |
| 为什么使用格雷码 | `wptr_full`、`rptr_empty` |
| 指针同步方向 | `sync_w2r`、`sync_r2w` |
| 如何判断空满 | `rempty_next`、`wfull_next` |
| 空满是否绝对实时 | 两级同步导致保守延迟 |
| 非 2 次幂深度 | 当前实现不支持 |
| 时钟频差问题 | 见下一节的工程化说明 |

## 13. 工程实现中需要注意的问题

### 13.1 空满标志的保守撤销延迟

同步延迟主要使标志的撤销变慢，即 FIFO 已经不空但读域仍短暂看到空，或者 FIFO 已经不满但写域仍短暂看到满。这是安全的保守判断。

设计目标不是让标志反映远端的瞬时真实指针，而是保证：

- `empty == 0` 时允许读取不会下溢；
- `full == 0` 时允许写入不会上溢。

### 13.2 非 2 次幂深度

可以研究特殊格雷码序列或其他编码来实现非 2 次幂异步 FIFO，但满判断、
回环和形式验证都会更复杂。当前代码不采用改变起点的方案，而是明确限制
内部深度为 2 的幂。

对于工程项目，更常见的选择是使用下一个更大的 2 的幂物理深度，或者采用经过充分验证的厂商 FIFO IP。

### 13.3 协议没有规定通用的固定时钟频率比上限

接收域漏采某些格雷码状态本身通常不是错误；接收端可以从一个合法格雷码值
跳到更晚的合法格雷码值，空满结果仍然趋于保守。

真正需要关注的是：

- 两级同步器的 MTBF；
- 格雷码总线各位从源寄存器到第一级同步器的路径偏斜；
- STA/CDC 工具约束；
- 复位释放和跨域时序；
- 所用 FPGA/ASIC 工艺和目标可靠性。

格雷码“逻辑上一次只变一位”并不自动保证布局布线后各位满足所需的
到达时间关系。实际工程中应对格雷码总线添加最大延迟或 bus-skew
（总线偏斜）约束，并运行 STA 与 CDC 检查。允许的频率比最终受吞吐需求、
同步器 MTBF、物理实现和系统级流量控制共同限制。

## 14. 复位注意事项

写域和读域分别使用低有效异步复位：

```text
wr_rstn -> 写指针、full、rptr 同步器
rd_rstn -> 读指针、empty、wptr 同步器
```

工程上建议：

- 复位可以异步断言（拉低）；
- 每个时钟域内必须同步撤销（拉高）；
- core 会使用本地复位门控 RAM 读写，即使请求在复位期间保持为高也不会访问存储器；
- 运行中只复位一侧而另一侧继续传输不属于当前支持契约。

仓库提供公共 `async_reset_sync` 模块，实现异步断言和可配置的本地时钟
同步撤销，其中 `STAGES >= 2`。每个无关时钟域应各实例化一份，并将输出
连接到该域的 FIFO 复位输入。该模块只同步复位撤销，不会让运行中单侧复位
具备数据保留能力。

当前 RTL 假设两个时钟域会被初始化到一致的空 FIFO 状态。复位属于破坏性
操作：复位前缓存的数据全部丢弃，复位期间 RAM 内容和读数据不具有有效
语义。由异步复位指针驱动 BRAM 地址产生的厂商 DRC 警告，需要按照这个
前提检查综合后网表并记录 waiver，不能用于支持单侧数据保留复位。

## 15. 当前接口行为

写请求仅在以下条件成立时被接受：

```text
wr_rstn && wr_en && !full
```

读请求仅在以下条件成立时被接受：

```text
rd_rstn && rd_en && !empty
```

两个请求式 FIFO 主模块都导出 `rd_valid`，用于标记同步读数据有效。
分包流式集成建议使用 `async_fifo_stream`，因为它进一步提供完整
ready/valid 反压和包元数据。

对于等宽 `async_fifo`，`wr_used` 和 `rd_used` 是各自本地时钟域中的
占用量视图。变宽和流式包装层使用更明确的 `wr_core_used` 与
`rd_core_used`：它们只统计内部宽字 core，不包含本地拼包、pending 和
输出缓冲。由于远端指针存在同步延迟，这些信号都不是跨时钟域的瞬时
全局计数。

## 16. 仿真

需要 Icarus Verilog：

运行全部测试：

```bash
make test
```

检查非法参数组合是否给出清晰错误：

```bash
make params
```

检查 `VERSION`、FuseSoC core、兼容性文档和变更记录是否描述同一发布版本：

```bash
make release-check
```

运行 Verilator lint：

```bash
make lint
```

运行同步器结构检查和 Yosys 综合检查：

```bash
make cdc
make synth
```

本机安装 Vivado 2025.2 后，可综合默认及多实例设计并执行实例作用域和
精确对象数量检查：

```bash
make xilinx-cdc
```

负向测试会确认错误指针宽度、缺失层次和模糊层次必定失败。PYNQ 实现流程
复用同一份综合后检查脚本。

运行 SymbiYosys 指针/core 证明与 wrapper BMC/cover 检查：

```bash
make formal
```

运行开源 CI 使用的全部检查：

```bash
make check
```

`make check` 不调用闭源 Vivado。启用自托管 Xilinx CI 后，独立的厂商 job
还会执行 `make xilinx-cdc`。

### PYNQ-Z2 Vivado 实现验证

仓库提供了面向 PYNQ-Z2（`xc7z020clg400-1`）的板级验证工程。它使用
125 MHz PL 时钟，经 MMCM 产生 100 MHz 写时钟和 75 MHz 读时钟，持续
传输递增数据，用 LED0 粘滞显示数据顺序错误，并用 LED2 显示成功读取
进度。

```bash
make pynq-z2
```

Vivado 会在 `examples/pynq_z2/reports/` 下生成 CDC、时序、exception
覆盖、格雷码总线偏斜和资源报告。

本仓库已使用本机 Vivado 2025.2 对 `xc7z020clg400-1` 完成综合、布局布线、
DRC 和 bitstream 生成。最新布局布线后 WNS 为 5.625 ns、WHS 为 0.115 ns，
两组 10 位格雷码跨域约束覆盖率均为 100%，总线偏斜约束均通过，512×32
FIFO 存储器被推断为 1 个 RAMB18E1。若格雷码对象数量不完整、setup/hold
slack 为负、bus-skew 违规、存在 DRC error 或 bitstream 缺失，批处理构建
会直接失败。

| LED | 含义 | 正常状态 |
|---|---|---|
| LED0 | 数据顺序错误，粘滞置位 | 熄灭 |
| LED1 | FIFO full | 可能变化 |
| LED2 | 成功读取 heartbeat（约 2.2 Hz） | 持续闪烁 |
| LED3 | MMCM locked | 点亮 |

详细流程和报告检查方法见
[PYNQ-Z2 Vivado 验证](docs/pynq_z2_vivado.md)。

以下是单独运行部分仿真顶层的示例：

```bash
iverilog -g2012 \
  -s tb_equal_width \
  -o /tmp/tb_equal.out \
  -f rtl/files.f \
  test/tb_fifo_basic.sv
vvp /tmp/tb_equal.out
```

```bash
iverilog -g2012 \
  -s tb_pack_16_to_32 \
  -o /tmp/tb_pack.out \
  -f rtl/files.f \
  test/tb_fifo_basic.sv
vvp /tmp/tb_pack.out
```

```bash
iverilog -g2012 \
  -s tb_split_32_to_16 \
  -o /tmp/tb_split.out \
  -f rtl/files.f \
  test/tb_fifo_basic.sv
vvp /tmp/tb_split.out
```

完整执行 `make test` 时会包含以下输出：

```text
PASS: async reset assertion and two-stage synchronous release
PASS: parameterized equal-width FIFO
PASS: programmable almost-full/almost-empty flags
PASS: 16-bit write to 32-bit read
PASS: 32-bit write to 16-bit read
PASS: width-converter completed-word buffer
PASS: stream 16-to-32 keep/last and backpressure
PASS: stream 32-to-16 keep/last
PASS: full, empty, blocked access, occupancy, and wraparound
PASS: reset blocks RAM access and normal transfer resumes
PASS: randomized 7ns/11ns clocks and scoreboard (... transfers)
PASS: randomized stream scoreboard and backpressure (1200 beats)
PASS: stream accepts one write beat per clock without bubbles
PASS: stream produces one equal-width read beat per clock
PASS: stream produces one split read beat per clock
PASS: randomized stream 16-to-32 width conversion (... outputs)
PASS: randomized stream 32-to-16 width conversion (... outputs)
```

## 17. 验证与工程化状态

- [x] 等宽、满、空、非法访问阻塞和多次回绕测试；
- [x] 复位期间 RAM 访问门控及复位后恢复传输测试；
- [x] 可复用的异步断言/同步撤销复位模块及测试；
- [x] 7 ns / 11 ns 随机时钟比和数据 scoreboard；
- [x] 包元数据与随机反压的流式 scoreboard；
- [x] 写端弹性缓冲连续每周期一拍测试；
- [x] 等宽及宽写窄读的读侧预取连续每周期一拍测试；
- [x] 16→32 与 32→16 双向变宽随机 scoreboard；
- [x] 满时写指针稳定、空时读指针稳定和格雷码单比特变化断言；
- [x] CI 中执行同步器源码结构检查；
- [x] CI 中执行发布版本一致性检查；
- [x] 经过实际实现验证的 Xilinx Vivado 约束流程；
- [x] Intel Quartus/TimeQuest 约束模板，并明确标注为尚未经过实际实现验证；
- [x] Xilinx 实例作用域约束，以及单实例/多实例综合后精确数量正负向验证；
- [x] 等宽 `wr_used/rd_used` 及变宽模块明确的 core-only
  `wr_core_used/rd_core_used` 占用量；
- [x] 显式 ready/valid 的分包流式顶层；
- [x] 格雷码变化和阻塞指针稳定性的局部指针证明；
- [x] 互质周期异步时钟下 core 占用量、状态标志、`rd_valid` 与端到端数据顺序
  的 96 帧 SymbiYosys BMC，以及 full 和跨深度读取 cover；
- [x] `ADDR_WIDTH=1/2` 下写/读时钟频率和读时钟初相位符号化的 core BMC，
  在约束范围内分别覆盖 2～7 的独立相位增量；
- [x] 写域先释放、读域先释放两种同步复位释放顺序的 BMC，并用 cover 实际
  到达两个域完成初始化后的有序传输；
- [x] 分包流式顶层的对应复位释放 BMC，覆盖 8→16 打包路径、
  final/non-final 包传输及反压稳定性；
- [x] 变宽打包/拆包、包元数据、输出顺序及反压稳定性的四项 64 帧 wrapper BMC；
- [x] 四项 wrapper cover：实际到达 full、request 接口多次读取、流式 final/
  non-final 传输及双向打包场景（request 变宽为 160 帧，分包流式为 96 帧）；
- [x] 20 项、64 帧 wrapper 参数矩阵：覆盖 request/stream 接口、
  `ADDR_WIDTH=2/3/4/5`、8/16-bit 等宽及双向 1:2/1:4/1:8 变宽，并配套
  四项 1:4 重复输出 cover；
- [x] Verilator `-Wall` 零告警 lint，任何告警都会导致检查失败；
- [x] 非法参数组合的自动诊断测试。

深层 wrapper harness 仍使用固定代表参数检查包边界和复位错位；参数矩阵
增加四种地址宽度、两种等宽位宽和 1/2/4/8 比例的具体 elaboration，并采用
互质的 2/3 时钟调度。另有一层 core BMC 会符号化选择独立时钟增量和读时钟
初相位。它们是互补的有界检查，并不等价于一个覆盖所有整数参数或所有连续
变化时钟波形的证明。

开源 CI 分别使用仿真和 formal 工具容器，两个镜像都以不可变 sha256
digest 锁定。`actions/checkout` 也固定到完整 commit SHA，每个 job
开始时会输出实际工具版本。仓库变量 `XILINX_CI_ENABLED=true` 时，还会在
带许可的自托管 Vivado 2025.2 runner 上运行第三个 Xilinx CDC job；该 job
被跳过不代表完成了厂商签核。

仓库中的 CDC 脚本用于发现源码层面的同步器结构回归；Vivado 脚本还会
检查综合网表对象集合。两者都不能替代具体工程的布局布线后时序、
`report_cdc`、methodology/DRC 审查或同等级商业签核流程。Intel 文件目前
仍是 Quartus/TimeQuest 模板，尚未经过实际实现验证。

> 用于真实硬件前，请根据目标器件、时钟配置和工具版本完成综合后及布局
> 布线后的 CDC、格雷码总线偏斜和时序检查。

## 许可证

本项目采用 [MIT License](LICENSE)。
