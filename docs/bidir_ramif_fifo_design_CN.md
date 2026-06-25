# 双向外部 RAM FIFO Wrapper 设计

`async_bidir_ramif_fifo` 是两个 optional wrapper 思路的组合：

```text
A transmit -> async_fifo_ramif -> B receive
B transmit -> async_fifo_ramif -> A receive
```

它面向需要独立 A->B 和 B->A CDC 通道，同时每个方向都由外部提供 RAM 的集成场景。
它不是新的 CDC 算法，也不在两个方向之间共享 RAM。

## 边界决定

该 wrapper 必须由两个 `async_fifo_ramif` 实例组成：

- `u_a2b_fifo`：写/控制侧在 A 时钟域，读/控制侧在 B 时钟域；
- `u_b2a_fifo`：写/控制侧在 B 时钟域，读/控制侧在 A 时钟域。

每个方向都有自己的 RAM 接口：

```text
a2b_ram_wr_*  由 A 时钟域驱动
a2b_ram_rd_*  由 B 时钟域驱动
b2a_ram_wr_*  由 B 时钟域驱动
b2a_ram_rd_*  由 A 时钟域驱动
```

两个方向不共享 RAM 端口、指针、标志或 occupancy 信号。

## 公开契约

用户侧 FIFO 接口沿用 `async_bidir_fifo`：

| 侧 | 信号组 | 含义 |
|---|---|---|
| A | `a_tx_*` | A 时钟域写入、B 时钟域接收的数据 |
| A | `a_rx_*` | A 时钟域从 B 接收的数据 |
| B | `b_tx_*` | B 时钟域写入、A 时钟域接收的数据 |
| B | `b_rx_*` | B 时钟域从 A 接收的数据 |

RAM 侧相当于使用两次 `async_fifo_ramif`。每个外部 RAM 都必须满足
[外部 RAM 接口 FIFO 设计](ramif_design_CN.md) 中定义的固定一拍同步读
simple dual-port 契约。

## 独立性规则

- A->B 和 B->A 使用独立 FIFO 控制与独立 RAM 存储。
- A->B 的 full/empty/almost/used 信号不描述 B->A。
- A->B RAM 行为不能反压或重排 B->A，反之亦然。
- wrapper 不提供跨方向事务原子性。
- reset 清除每个方向的 pointer/control 状态，但不清外部 RAM 内容。

## 非目标

`async_bidir_ramif_fifo` 不实现：

- 共享双向 RAM 端口；
- 运行时方向切换；
- `a_dir` / `b_dir` half-duplex 控制；
- RAM wait state 或可变延迟；
- 位宽转换；
- FWFT 行为；
- packet stream 语义。

这些功能需要单独契约和验证计划。

## 验证计划

directed simulation 应使用两个独立的一拍 RAM model，并覆盖：

- A->B 传输顺序；
- B->A 传输顺序；
- 两个方向同时传输；
- 一个方向 full/反压不阻塞另一个方向；
- reset 清 pointer/control 状态，且不依赖 RAM 清零。

formal verification 可后续增加成小型组合 harness，把双向顺序检查和 RAMIF 一拍
RAM model 组合起来。
