# XPM_FIFO_ASYNC 对比

这份文档把本教学 RTL 项目与 AMD/Xilinx `XPM_FIFO_ASYNC` 做对比。它不是 AMD
官方文档的替代品，本仓库也不是 vendor IP 克隆。目标是说明本项目跟随了哪些工业
FIFO 接口预期，哪些地方有意不同，哪些功能明确不支持。

本文参考 AMD UG974 里的 `XPM_FIFO_ASYNC`，版本为 2026.1：

- <https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/XPM_FIFO_ASYNC>

## 总览

| 主题 | `XPM_FIFO_ASYNC` 预期 | 本仓库 |
|---|---|---|
| 定位 | 面向 AMD/Xilinx FPGA 产品设计的 vendor macro | 可读、可跑、可验证的教学 RTL |
| 主要请求接口 | `wr_en/full`、`rd_en/empty`、`din/dout`、`data_valid` | `wr_en/full`、`rd_en/empty`、`wr_data/rd_data`、`rd_valid` |
| 读模式 | 通过 `READ_MODE` 支持 standard 和 FWFT | 当前只有同步读 standard 行为；FWFT 是未来路线 |
| 读延迟 | standard 模式下由 `FIFO_READ_LATENCY` 配置 | 固定同步 RAM 读响应，用 `rd_valid` 标记 |
| 复位 | 单个 `rst`，同步到 `wr_clk`，并提供 `wr_rst_busy/rd_rst_busy` | 写读域独立低有效复位；异步断言，本地同步撤销 |
| CDC 级数 | `CDC_SYNC_STAGES` 参数 | core 固定两级指针同步器 |
| 位宽转换 | 通过 `WRITE_DATA_WIDTH/READ_DATA_WIDTH` 和规定比例支持 | 保持等宽 CDC core，把变宽放在 wrapper |
| 计数 | `wr_data_count`、`rd_data_count`，位宽可配置 | 等宽用 `wr_used/rd_used`；wrapper 用 `*_core_used` |
| almost/prog 标志 | `almost_*` 加 `prog_*` 阈值/功能 | 静态 `almost_*` 阈值；没有单独 `prog_*` 端口 |
| 错误/状态功能 | `wr_ack`、`overflow`、`underflow`、ECC、sleep | 不实现；用测试和 formal 证明 blocked 操作非破坏 |
| 存储资源选择 | `FIFO_MEMORY_TYPE`、ECC、cascade 相关属性 | 可移植 RAM 推断，没有 RAM 类型选择参数 |
| 签核模型 | vendor macro 加 AMD 工具/报告预期 | 开放 RTL 加 CDC 约束、测试和有界 formal |

## 接口对齐

两个设计采用相同的基本请求思想：写请求只有在非满时被接受，读请求只有在非空时
被接受。本项目的数据端口叫 `wr_data/rd_data`，读有效叫 `rd_valid`；XPM 对应端口
叫 `din/dout` 和 `data_valid`。

本项目公开的接口契约更小：

```text
wr_rstn && wr_en && !full   接受一次写
rd_rstn && rd_en && !empty  接受一次读
rd_valid                   限定 rd_data 有效
```

XPM 还提供更多工业状态和诊断端口，例如 `wr_ack`、`overflow`、`underflow`、
`wr_data_count`、`rd_data_count`、`wr_rst_busy`、`rd_rst_busy`、ECC 错误标志和
sleep 支持。本仓库只保留服务教学路径的功能。

## 参数对比

| XPM 参数区域 | 本项目最接近的概念 | 说明 |
|---|---|---|
| `FIFO_WRITE_DEPTH` | `2**ADDR_WIDTH` | 都使用 2 的幂深度。XPM 会按读模式说明 effective depth；本项目分开说明 core 和 wrapper 容量。 |
| `WRITE_DATA_WIDTH`, `READ_DATA_WIDTH` | `DATA_WIDTH` 或 wrapper 的 `WDATA_WIDTH/RDATA_WIDTH` | core 保持等宽；位宽转换在 core 外部实现。 |
| `READ_MODE` | 暂无对应参数 | 当前是 standard 同步读 + `rd_valid`；FWFT 属于路线图。 |
| `FIFO_READ_LATENCY` | 固定同步 RAM 响应 | 本项目不提供可配置输出流水。 |
| `CDC_SYNC_STAGES` | 两级同步器 | core 为了教学清晰固定为两级。 |
| `PROG_FULL_THRESH`, `PROG_EMPTY_THRESH` | `ALMOST_FULL_THRESHOLD`, `ALMOST_EMPTY_THRESHOLD` | 本项目阈值是静态参数，只导出 `almost_*`，没有单独 `prog_*` 端口。 |
| `FIFO_MEMORY_TYPE`, `ECC_MODE`, `CASCADE_HEIGHT`, `WAKEUP_TIME` | 无对应功能 | vendor 资源/实现特性不在本项目范围内。 |

## 复位差异

XPM 使用 `rst`，并导出 `wr_rst_busy` 和 `rd_rst_busy`。AMD 文档要求用户逻辑在 reset
或 busy 有效时不要切换 enable。

本项目使用两个独立复位：

```text
wr_rstn  写时钟域复位
rd_rstn  读时钟域复位
```

它们可以异步断言，但撤销必须由集成系统在本地时钟域同步。
[`rtl/util/async_reset_sync.v`](../rtl/util/async_reset_sync.v) 实现了这个模式。
复位是破坏性的，不支持运行中单侧复位并保留数据。

## 读模式和 `rd_valid`

XPM 支持 standard 和 FWFT 模式。standard 模式下，`data_valid` 与配置的读延迟相关；
FWFT 模式下，第一个数据可以用 fall-through 方式提前出现在输出端。

本项目当前实现 standard 同步读行为：

- `rd_en && !empty` 接受读请求；
- RAM 在读时钟沿更新 `rd_data`；
- `rd_valid` 标记应该采样 `rd_data` 的周期。

具体波形见[逐步教程](tutorial_CN.md#7-一张真实-waveform)。FWFT/fallthrough 行为
有意留作未来模式或 wrapper 级扩展。

## 位宽转换

XPM 把非对称写读位宽作为 macro 参数的一部分。AMD 文档对 `WRITE_DATA_WIDTH` 和
`READ_DATA_WIDTH` 支持的比例有明确限制。

本项目保持 CDC core 等宽：

```text
async_fifo_core: 等宽 RAM、指针、full/empty、同步器
wrappers:       打包/拆包或 ready/valid 分包语义
```

这是教学选择：让 Gray pointer CDC 推理不和位宽转换纠缠在一起。wrapper 容量和
`*_core_used` 语义见[接口与时序](interface.md)。

## 状态标志和计数

XPM 的状态面更丰富：

- `full`、`empty`、`almost_full`、`almost_empty`；
- `prog_full`、`prog_empty`；
- `wr_data_count`、`rd_data_count`；
- `wr_ack`、`overflow`、`underflow`；
- 启用 ECC 时的错误标志。

本仓库只导出教学契约需要的状态：

- `full` 和 `empty` 是传输资格判断；
- `almost_full` 和 `almost_empty` 是提前流控提示；
- `wr_used/rd_used` 是等宽 FIFO 的本地 core 视图；
- `wr_core_used/rd_core_used` 明确不包含 wrapper 本地存储。

满时写、空时读都是非破坏性的，但本项目不输出 `overflow` 或 `underflow` 脉冲；
这个行为由仿真和 formal properties 检查。

## CDC 与签核

XPM 是 vendor macro，目标是配合 AMD 实现流程使用。本仓库提供开放 RTL、源码级
CDC 检查、Xilinx/Intel 约束模板、仿真和有界 formal。它们适合学习和回归，但不能
替代目标工程的综合后和布局布线后 CDC/时序签核。

本项目的物理实现边界见 [CDC 与时序约束](cdc_constraints.md)。

## 暂不支持的 XPM 功能

本项目有意不实现：

- FWFT 读模式；
- 可配置 `FIFO_READ_LATENCY`；
- `wr_rst_busy` / `rd_rst_busy`；
- `wr_ack`、`overflow`、`underflow` 输出端口；
- 动态 programmable flag 端口；
- ECC 编解码和错误注入；
- sleep/低功耗控制；
- RAM primitive 选择或 cascade 控制；
- 完整 vendor macro 兼容 wrapper。

这些都是合理的工业 FIFO 功能。本仓库暂不实现它们，是为了保持核心学习路径清楚：
Cummings 风格 CDC、可读 RTL、可运行测试、formal properties，以及明确的签核边界。
