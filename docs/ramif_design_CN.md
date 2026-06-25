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
