# 双向 FIFO Wrapper 设计

`async_bidir_fifo` 是一个 full-duplex CDC 组合 wrapper。它不是新的 FIFO 算法，
而是组合两个独立的等宽异步 FIFO：

```text
A transmit -> async_fifo -> B receive
B transmit -> async_fifo -> A receive
```

它的目标是给集成者一个清楚的 TX/RX 风格双向通信模块，同时不改变
Cummings 风格 CDC core。

## 公开契约

| 侧 | 信号组 | 含义 |
|---|---|---|
| A | `a_tx_*` | A 时钟域写入、B 时钟域接收的数据 |
| A | `a_rx_*` | A 时钟域从 B 接收的数据 |
| B | `b_tx_*` | B 时钟域写入、A 时钟域接收的数据 |
| B | `b_rx_*` | B 时钟域从 A 接收的数据 |

每个方向都沿用 standard `async_fifo` 请求式契约：

```text
tx_rstn && tx_en && !tx_full  接受一次写入
rx_rstn && rx_en && !rx_empty 接受一次读取
rx_valid                     限定 rx_data
```

wrapper 使用 `a_rstn` 复位所有 A 时钟域状态，使用 `b_rstn` 复位所有 B 时钟域
状态。两个方向的复位都是破坏性的，与底层 FIFO 实例一致。

## 独立性规则

两个方向有意保持独立：

- A->B 和 B->A 使用独立存储。
- A->B 和 B->A 使用独立 pointer synchronizer。
- A->B 的 `full`、`empty`、almost 标志和 occupancy 不描述 B->A。
- 一个方向 full 不会阻止另一个方向写入。
- wrapper 不提供跨方向事务原子性或排序关系。

如果上层协议要求 request 和 response 一起提交，这个协议逻辑必须放在 FIFO
wrapper 之上。

## 非目标

`async_bidir_fifo` 明确不实现：

- 运行时方向切换；
- 两个方向共享 RAM；
- `a_dir` / `b_dir` half-duplex 控制；
- 位宽转换；
- FWFT 读行为；
- packet metadata 或 ready/valid stream 语义。

这些功能要么属于已有 wrapper，要么应作为未来实验模块单独定义契约。full-duplex
教学 wrapper 应保持为两个 standard asynchronous FIFO 的可读组合。

## 验证计划

directed simulation 应覆盖：

- A->B 传输顺序；
- B->A 传输顺序；
- 两个方向同时传输；
- 一个方向 full 或反压不阻塞另一个方向；
- reset 清空两个方向。

因为这个 wrapper 不包含新的 CDC 算法，第一步 formal 可以很小：证明每个方向
保持底层 FIFO 传输契约，并证明反方向请求保持独立。
