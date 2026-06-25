# FWFT / Fallthrough 设计说明

本文定义 `async_fifo_fwft` 已实现的 first-word-fall-through 行为。基础
`async_fifo` 模块仍然保持 standard 同步读 FIFO；FWFT 作为等宽读侧 wrapper
提供，包在未改动的 Cummings 风格 CDC core 外面。

## 当前状态

| 项目 | 状态 |
|---|---|
| standard 同步读 | 已实现 |
| FWFT / fallthrough 读模式 | 已实现等宽 wrapper |
| 公开边界 | 独立 `async_fifo_fwft` wrapper，不作为 `async_fifo` 参数 |
| RTL 实现 | `rtl/wrappers/async_fifo_fwft.v` |
| directed tests | `test/tb_fifo_fwft.sv` |
| formal properties | `formal/fwft_formal.sv` 和 `formal/fwft.sby` |

这个 wrapper 在不扰动 Cummings 风格 CDC core 的前提下加入 FWFT 行为。实现方式
是在现有等宽 core 外面增加读侧 prefetch 和输出槽逻辑。

## 边界决定

FWFT 会作为独立公开模块暴露：

```text
async_fifo       standard 同步读 FIFO
async_fifo_fwft  等宽 FWFT 读侧 wrapper
```

教学接口里的基础 `async_fifo` 不增加 `READ_MODE` 或 `FWFT` 参数。这样同一个模块名
不会因为参数不同而改变 `rd_en`、`rd_valid` 和 `empty` 的含义，也能把
Cummings 风格 CDC core 和 fallthrough prefetch 行为作为两个独立概念讲清楚。

如果未来 release 增加 XPM 风格兼容层，那一层可以暴露类似 `READ_MODE` 的参数。
但它应该在内部转换到 `async_fifo` 或 `async_fifo_fwft`，而不是改变教学主入口。

## 基线：当前 Standard Read

已经实现的请求式读接口如下：

```text
rd_rstn && rd_en && !empty  接受一次读请求
rd_valid                   标记 rd_data 有效的周期
```

`rd_en` 是一次取数请求。因为 RAM 读端口是同步读，所以设计导出 `rd_valid`，让
使用者知道什么时候应该采样 `rd_data`。

在当前模式下：

- `empty == 0` 表示可以接受读请求；
- `rd_en` 发起一次从 RAM 到 `rd_data` 的移动；
- `rd_valid` 对一次被接受的读响应打脉冲；
- 如果消费者不发起读请求，FIFO 不会自动把第一个数据放到 `rd_data` 上。

这个行为的权威定义见[接口与时序](interface.md)。

## FWFT Read

FWFT 把读侧用户契约从“请求然后收到数据”改成“先看到数据，然后消费数据”。

已实现 FWFT wrapper 的语义是：

```text
rd_valid == 1             rd_data 上有一个可读数据字
rd_en && rd_valid         消费当前可见的数据字
empty == !rd_valid        用户当前看不到可读数据
```

第一个可读数据在经过读侧指针同步、并从同步 RAM 取出后，应自动出现在
`rd_data` 上。用户不需要先打一拍 `rd_en` 才能看到第一个字。此时 `rd_en` 的角色
更像 consume/pop 信号。

这样等宽请求接口在读侧更接近简单的 valid/ready sink：

| 概念 | Standard 模式 | FWFT 模式 |
|---|---|---|
| `rd_en` 含义 | 发起读请求 | 消费可见数据 |
| `rd_valid` 含义 | 对已接受读请求的响应 | 输出槽里有有效数据 |
| `empty` 含义 | 不能接受读请求 | 没有用户可见数据 |
| 第一个数据延迟 | 用户先请求，再等 `rd_valid` | 逻辑预取，用户等待 `rd_valid` |
| 反压 | 用户不拉 `rd_en` | 用户不拉 `rd_en`，有效数据保持稳定 |

## 内部模型

`async_fifo_fwft` 保持 `async_fifo_core` 为 standard 模式，并在读侧增加预取层：

```text
async_fifo_core
    standard rd_en/empty/rd_valid/rd_data
        |
        v
读侧 prefetch/output slot
        |
        v
FWFT 用户 rd_data/rd_valid/empty
```

已实现的预取层拥有两个读侧槽：

```text
slot0_valid / slot0_data  用户可见输出槽
slot1_valid / slot1_data  备用预取数据字
```

当满足下面条件时，预取层向 core 发起内部读：

```text
rd_rstn && !core_empty && 输出槽可以接收新数据
```

读侧槽在有空间时可以接收新数据，也包括同一个时钟沿因用户 pop 释放出的空间。
因为 core 是同步读，还需要一个 pending fetch bit，用来记录已经向 core 请求、
但尚未由 core `rd_valid` 返回的数据字。

## 等宽 FWFT 契约

等宽 FWFT wrapper 的公开读侧行为定义为：

| 信号 | FWFT 含义 |
|---|---|
| `rd_data` | `rd_valid` 为高时稳定的用户可见数据 |
| `rd_valid` | 输出槽里有有效数据 |
| `rd_en` | 当 `rd_valid` 为高时 pop 当前可见数据 |
| `empty` | 用户接口层等价于 `!rd_valid` |
| `almost_empty` | 提前流控提示，不是 pop 条件 |
| `rd_used` | 本地读侧估计；必须说明是否包含输出槽 |

该 wrapper 在用户行为上暴露 `empty = !rd_valid`，并将 `rd_used` 定义为 core 读侧
视图加上可见槽、备用槽和 pending internal fetch。

## 稳定性规则

FWFT 必须满足类似 ready/valid 的输出稳定性：

- 当 `rd_valid && !rd_en` 时，`rd_data` 必须保持稳定。
- 一个已可见的数据字可以停留任意多个读时钟周期。
- 如果下一个字已经可用，或能在同一时钟沿进入输出槽，消费当前字时
  `rd_valid` 可以继续保持为高。
- `rd_valid == 0` 时的 consume 尝试必须是非破坏性的。
- 复位会清空可见槽、pending fetch bit 和 `rd_valid`。

这些规则也是为什么 FWFT 更适合做成读侧 prefetch/output 层，而不是去修改
Gray pointer CDC 机制。

## Empty 和 Almost-Empty 语义

最关键的命名决策是 `empty`。

FWFT 的用户侧 `empty` 应该表示：

```text
empty == !rd_valid
```

也就是“用户当前没有可见数据”。这不同于 core 内部的 `empty`，后者表示
“core 现在不能接受下一次内部读请求”。

`almost_empty` 应保持为提示信号。它可以来自 core occupancy，也可以来自包含
可见槽的读侧 occupancy，或者一个清楚文档化的组合。它不能替代正式 pop 条件：

```text
FWFT pop = rd_rstn && rd_en && rd_valid
```

## 和 XPM 的关系

AMD/Xilinx `XPM_FIFO_ASYNC` 通过 `READ_MODE` 支持 standard 和 FWFT。本项目不应该
复刻 XPM 的每个细节；真正值得对齐的是接口预期：

- standard 模式：请求读，然后限定响应；
- FWFT 模式：第一个数据自动可见，之后用户消费可见数据。

effective depth、读延迟参数、busy 端口、ECC、programmable flags 等 vendor 细节
仍然不在范围内，除非它们服务于教学路径。

## 已实现结构

1. `async_fifo_core` 保持 standard 且不变。
2. 读侧 prefetch 逻辑包含：
   - 一个可见输出槽；
   - 一个备用预取槽；
   - 一个 pending internal-read bit；
   - stall 时稳定的 `rd_data`；
   - 用户侧 `empty = !rd_valid`。
3. directed tests 覆盖第一个数据自动可见、反压稳定、连续读取、复位清空、
   空时 pop 非破坏。
4. formal properties 覆盖顺序、不重复 fetch、不丢数据、stall 时输出稳定和复位清空。
5. tutorial 波形对比 standard 和 FWFT 读时序。
6. `async_fifo` 继续保持 standard 读契约；`async_fifo_fwft` 是公开的等宽 FWFT
   入口。

## 验证覆盖

directed simulations 覆盖这些场景：

| 场景 | 期望行为 |
|---|---|
| 写入一个字，不拉 `rd_en` | 指针同步和 RAM fetch 后，`rd_valid` 拉高，`rd_data` 显示该字。 |
| 输出被 stall | 当 `rd_valid && !rd_en` 时，`rd_data` 保持稳定。 |
| 消费一个字 | `rd_en && rd_valid` 只 pop 一个字。 |
| 连续数据流 | `rd_en` 持续为高时，数据按顺序输出，没有重复。 |
| 空时 pop 尝试 | `rd_valid == 0` 时拉 `rd_en` 非破坏。 |
| 可见数据期间复位 | 复位清除 `rd_valid`；旧 `rd_data` 不再有意义。 |

formal properties 对应同一份契约：

- 被接受的写入进入期望序列；
- FWFT pop 返回最老的期望数据；
- 如果前一次 fetch 仍 pending 且没有可用输出槽，不能再次发起 core read；
- stall 时输出数据稳定；
- 读复位期间不得断言 `rd_valid`。

## 范围和非目标

已实现的 FWFT option 会保持收窄：

- FWFT 只支持等宽接口。
- 位宽转换继续由 `async_fifo_width_conv` 负责。
- 包级 ready/valid 行为继续由 `async_fifo_stream` 负责。
- `async_fifo` 保持 standard 同步读时序。
- 教学主入口不暴露 XPM 兼容的 `READ_MODE` 参数。

未来允许两个扩展，但它们都应该留在 core 外面：

- 如果真实用例证明值得增加额外存储和验证工作，可以新增专门的 FWFT 变宽 wrapper；
- 如果项目未来需要 vendor-facing facade，可以新增 XPM-like 兼容 wrapper。

这两类扩展都不应该把 fallthrough 行为推入 Gray-pointer CDC 机制。
