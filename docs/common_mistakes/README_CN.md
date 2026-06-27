# 常见异步 FIFO 错误

这个目录把异步 FIFO 和 CDC 常见错误整理成短小的调试/学习页面。每篇详细页面都按同一条线索组织：

```text
看似合理的想法 -> 为什么简单仿真可能通过 -> 硬件风险
                -> 正确做法 -> 本仓库在哪里处理
```

详细页面目前维护英文单一来源，避免中英文内容长期漂移。本页提供中文阅读入口。

## 错误索引

| 错误 | 为什么重要 | 详细页面 |
|---|---|---|
| 直接同步二进制指针 | 多个 bit 可能在异步边界同时变化。 | [Binary Pointer Crossing](binary_pointer_crossing.md) |
| 缺少 Gray bus 约束 | 逻辑上的 Gray code 不能约束布局布线后的 bit skew。 | [Missing Gray-Bus Constraints](missing_gray_bus_constraints.md) |
| 把空满标志当作全局真值 | `full`、`empty` 和 occupancy 都是本地保守视图。 | [Wrong Full/Empty Assumptions](wrong_full_empty_assumptions.md) |
| 不安全的复位释放 | 复位是破坏性的，两个时钟域必须回到一致的空 FIFO 状态。 | [Unsafe Reset Release](unsafe_reset_release.md) |
| 任意非 2 次幂深度 | 本项目使用的 reflected-Gray 指针方案依赖 2 次幂环形序列。 | [Non-Power-of-Two Depths](non_power_of_two_depths.md) |

## 推荐阅读顺序

学习异步 FIFO 时：

1. [逐步教程](../tutorial_CN.md)
2. [Cummings 风格 FIFO 映射](../cummings_mapping_CN.md)
3. 本常见错误索引

审阅集成或签核边界时：

1. [接口与时序](../interface.md)
2. [CDC 和时序约束](../cdc_constraints.md)
3. [证据中心](../evidence/README.md)
4. 本常见错误索引
