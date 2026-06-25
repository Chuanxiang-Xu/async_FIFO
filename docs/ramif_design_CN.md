# 外部 RAM 接口 FIFO 设计

`async_fifo_ramif` 是一个实验 wrapper，面向希望复用本仓库 FIFO 控制、指针和
CDC 逻辑，但自行提供存储实现的用户。它不是默认 FIFO 入口，也不应该替代普通
集成中的 `async_fifo`。

第一版应匹配当前内部 [`fifo_mem`](../rtl/core/fifo_mem.v) 的时序模型：写时钟域
一个写端口，读时钟域一个同步读端口。

## 边界决定

`async_fifo_ramif` 只应该外置存储：

```text
async_fifo_ramif
    pointer / full / empty / CDC control
        |
        +-- external simple dual-port RAM interface
```

它不能改变 Cummings 风格指针算法，不能同步 payload bit，不能加入位宽转换、
FWFT 行为，也不能引入新的 full/empty 定义。standard `async_fifo` 和
`async_fifo_core` 仍然是带内部推断 RAM 的主教学实现。

## RAM 契约

第一版 RAMIF 契约刻意保持收窄：

| 主题 | 第一版契约 |
|---|---|
| RAM 形态 | simple dual-port memory：一个写端口、一个读端口 |
| 写时钟 | `wr_clk` |
| 读时钟 | `rd_clk` |
| 写操作 | 在 `wr_clk` 上升沿，如果 `ram_wr_en` 为高，将 `ram_wr_data` 写入 `ram_wr_addr` |
| 读操作 | 在 `rd_clk` 上升沿，如果 `ram_rd_en` 为高，捕获 `ram_rd_addr` 对应字，并在一个读时钟沿后从 `ram_rd_data` 返回 |
| 读延迟 | 固定一拍，与 `fifo_mem` 匹配 |
| 反压 | 不支持；RAM 必须接受每一次拉高的读/写 enable |
| 复位 | FIFO reset 只清指针和控制状态，不清外部 RAM 内容 |
| 碰撞行为 | 无关时钟下同地址读写属于目标 RAM 行为；FIFO 不承诺 data-during-collision 值有意义 |
| 数据有效 | FIFO 的 `rd_valid` 限定用户侧 `rd_data`；裸 `ram_rd_data` 不独立表示有效 |

wrapper 只能为已接受的 FIFO 传输产生 RAM 请求：

```text
ram_wr_en = wr_rstn && wr_en && !full
ram_rd_en = rd_rstn && rd_en && !empty
```

外部 RAM 不能 stall 或重排这些请求。如果未来需要 wait-state 或 ready/valid RAM，
应定义成单独接口，并配套新的证明策略。

## Vendor RAM 绑定和碰撞指导

RAMIF 刻意不在仓库内部推断或例化某家 vendor 的 memory primitive。外部 RAM
wrapper 由使用方工程拥有，并由该工程保证综合工具映射到预期资源。

推荐集成形态：

```text
async_fifo_ramif
    |
    +-- project-owned ram_wrapper
            |
            +-- inferred simple dual-port RAM, vendor macro, or ASIC SRAM
```

这个 wrapper 应尽量简单：在读时钟域打一拍返回数据，接受每一次拉高的 enable，
不要加入额外队列；如果确实需要额外队列，就已经改变了 FIFO 契约和证明形状。

| 主题 | 工程指导 |
|---|---|
| FPGA inference | 使用项目本地 RAM wrapper，并按目标 FPGA family 的综合风格指南书写。不要假设工具一定推断正确，必须检查综合报告。 |
| Vendor macro binding | 如果直接例化 block RAM、UltraRAM、MLAB/M10K/M20K 或 ASIC SRAM macro，只在项目 RAM wrapper 内绑定，不放进 `async_fifo_ramif`。 |
| 读延迟 | 配置或包一层 memory，使 `ram_rd_data` 在 `ram_rd_en` 后恰好一个 `ram_rd_clk` 边沿返回。额外输出寄存器需要新的 FIFO wrapper。 |
| Enable 语义 | `ram_wr_en` 和 `ram_rd_en` 是不可 stall 的命令。带 busy、ready、sleep wakeup 或 refresh 行为的 RAM macro，必须先用 adapter 保持可见一拍契约。 |
| 同地址碰撞 | 不依赖 vendor-specific read-during-write 返回值。FIFO 契约由已接受传输和 `rd_valid` 定义，而不是裸 `ram_rd_data` 上的碰撞值。 |
| Byte enable 和 ECC | 不放进第一版 RAMIF 契约。确实需要时，外部 wrapper 必须让 FIFO 仍观察到整字写入和整字读取结果。 |
| 初始化 | 有效 FIFO 读取前的 RAM 内容无意义。reset 正确性不能依赖 RAM 初始化。 |
| Attributes/pragmas | family-specific 属性放在项目 RAM wrapper 中，并在综合阶段审阅；不要写进通用教学 RTL。 |

FPGA sign-off 时应保留综合 utilization、RAM inference 或 macro binding 证据、
RAM 端口 timing report，以及任何 read-during-write 或 reset 相关 waiver。
ASIC sign-off 则替换为 SRAM compiler 实例文档、timing views、CDC/timing review
和 macro-specific collision assumption。

### 最小 RAM wrapper 骨架

接到 RAMIF 的 RAM 可以由综合推断，也可以在项目里绑定 macro，但对 FIFO 可见的
行为应像下面这个一拍 simple dual-port model：

```verilog
module project_simple_dpram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 9
) (
    input                         wr_clk,
    input                         wr_en,
    input      [ADDR_WIDTH-1:0]   wr_addr,
    input      [DATA_WIDTH-1:0]   wr_data,

    input                         rd_clk,
    input                         rd_en,
    input      [ADDR_WIDTH-1:0]   rd_addr,
    output reg [DATA_WIDTH-1:0]   rd_data
);
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end
endmodule
```

RAMIF 侧可以直接这样连接：

```verilog
project_simple_dpram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_fifo_storage (
    .wr_clk (ram_wr_clk),
    .wr_en  (ram_wr_en),
    .wr_addr(ram_wr_addr),
    .wr_data(ram_wr_data),
    .rd_clk (ram_rd_clk),
    .rd_en  (ram_rd_en),
    .rd_addr(ram_rd_addr),
    .rd_data(ram_rd_data)
);
```

实际 production 工程中，vendor attributes 或 macro instance 应放在这个 wrapper
里。不要在不改变 RAMIF 契约的情况下加入 ready/busy、额外输出延迟，或依赖
碰撞返回值的控制逻辑。

## 建议公开 FIFO 端口

用户侧 FIFO 端口应镜像 `async_fifo`：

```text
wr_clk, wr_rstn, wr_en, wr_data, full, almost_full, wr_used
rd_clk, rd_rstn, rd_en, rd_data, rd_valid, empty, almost_empty, rd_used
```

RAM 侧暴露存储事务：

```text
ram_wr_clk
ram_wr_en
ram_wr_addr
ram_wr_data

ram_rd_clk
ram_rd_en
ram_rd_addr
ram_rd_data
```

`ram_wr_clk` 和 `ram_rd_clk` 分别由 `wr_clk`、`rd_clk` 转发，方便外部 RAM wrapper
直接连接。`rd_data` 应是同步 RAM 返回数据的 wrapper 别名，并由 FIFO `rd_valid`
限定。

## 非目标

第一版 RAMIF wrapper 不应实现：

- RAM 反压或 wait state；
- 可变读延迟；
- 异步组合读；
- byte enable；
- ECC；
- RAM 初始化或清零；
- 位宽转换；
- FWFT 行为；
- packet metadata；
- 共享双向 RAM 端口。

这些功能以后可以研究，但每一项都会改变公开契约、证明形状或目标工程签核责任。

## 验证计划

第一版实现应包含：

- 严格符合一拍读契约的 testbench RAM model；
- 与 `async_fifo` 行为匹配的异步 A/B 时钟 directed tests；
- 证明 pointer/control reset 不依赖 RAM 清零的 reset tests；
- 将 `async_fifo_ramif` 与 `async_fifo` 在同一 accepted transfer 序列下比较的
  wrapper equivalence-style simulation；
- 小型 formal harness，证明顺序和 `rd_valid` 与 RAM model 对齐。

因为 RAMIF 把存储外置，文档和测试应强调：使用方负责 RAM inference、macro
例化、时序、碰撞语义，以及任何 RAM 相关签核。
