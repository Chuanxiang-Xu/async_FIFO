# FWFT / Fallthrough 设计说明

本文先定义 first-word-fall-through 行为，再决定是否修改 RTL。当前 RTL 仍然是
standard 同步读 FIFO；本文是未来 mode 或 wrapper 的设计契约。

## 当前状态

| 项目 | 状态 |
|---|---|
| standard 同步读 | 已实现 |
| FWFT / fallthrough 读模式 | 已实现等宽草案 wrapper |
| RTL 参数或 wrapper | `rtl/wrappers/async_fifo_fwft.v` |
| directed tests | `test/tb_fifo_fwft.sv` |
| formal properties | `formal/fwft_formal.sv` 和 `formal/fwft.sby` |

目标是在不扰动 Cummings 风格 CDC core 的前提下加入 FWFT。当前草案是在现有等宽
core 外面增加读侧 wrapper 逻辑。

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

## 目标：FWFT Read

FWFT 把读侧用户契约从“请求然后收到数据”改成“先看到数据，然后消费数据”。

未来 FWFT 模式的目标语义是：

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

## 建议内部模型

当前草案保持 `async_fifo_core` 为 standard 模式，在读侧增加预取层：

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

未来等宽 FWFT 模式的公开读侧行为建议定义为：

| 信号 | FWFT 含义 |
|---|---|
| `rd_data` | `rd_valid` 为高时稳定的用户可见数据 |
| `rd_valid` | 输出槽里有有效数据 |
| `rd_en` | 当 `rd_valid` 为高时 pop 当前可见数据 |
| `empty` | 用户接口层等价于 `!rd_valid` |
| `almost_empty` | 提前流控提示，不是 pop 条件 |
| `rd_used` | 本地读侧估计；必须说明是否包含输出槽 |

当前草案在用户行为上暴露 `empty = !rd_valid`，并将 `rd_used` 定义为 core 读侧
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

## 推荐实现路径

1. 保持 `async_fifo_core` standard 且不变。
2. 读侧 prefetch 逻辑包含：
   - 一个可见输出槽；
   - 一个备用预取槽；
   - 一个 pending internal-read bit；
   - stall 时稳定的 `rd_data`；
   - 用户侧 `empty = !rd_valid`。
3. 增加 directed tests，覆盖第一个数据自动可见、反压稳定、连续读取、复位清空、
   空时 pop 非破坏。
4. 将覆盖顺序、不重复 fetch、不丢数据、stall 时输出稳定和复位清空的 formal
   properties 保持在回归中。
5. 增加 standard 和 FWFT 读时序对比波形。
6. wrapper 行为被测试和证明后，再决定是否给公开 `async_fifo` 增加 `READ_MODE`
   参数。

## 测试计划

最小 directed 场景：

| 场景 | 期望行为 |
|---|---|
| 写入一个字，不拉 `rd_en` | 指针同步和 RAM fetch 后，`rd_valid` 拉高，`rd_data` 显示该字。 |
| 输出被 stall | 当 `rd_valid && !rd_en` 时，`rd_data` 保持稳定。 |
| 消费一个字 | `rd_en && rd_valid` 只 pop 一个字。 |
| 连续数据流 | `rd_en` 持续为高时，数据按顺序输出，没有重复。 |
| 空时 pop 尝试 | `rd_valid == 0` 时拉 `rd_en` 非破坏。 |
| 可见数据期间复位 | 复位清除 `rd_valid`；旧 `rd_data` 不再有意义。 |

formal properties 应该对应同一份契约：

- 被接受的写入进入期望序列；
- FWFT pop 返回最老的期望数据；
- 如果前一次 fetch 仍 pending 且没有可用输出槽，不能再次发起 core read；
- stall 时输出数据稳定；
- 读复位期间不得断言 `rd_valid`。

## RTL 前需要决定的问题

- FWFT 是否应该长期保持为单独模块 `async_fifo_fwft`，还是最终变成 `async_fifo`
  的参数？
- 当前 `rd_used` 包含两个读侧槽和 pending fetch 的定义是否适合作为长期公开契约？
- 初版 FWFT 是否只支持等宽 FIFO，wrapper 以后再扩展？
- stream 模式是否复用同一套 prefetch 层，还是继续保持自己的 ready/valid 实现？

保守建议：继续把等宽 FWFT wrapper 保持为独立模块。当前 `async_fifo` 的契约先
不变，等 FWFT 行为通过 formal 和波形文档验证后，再决定是否把 `READ_MODE`
参数并入公开入口。
