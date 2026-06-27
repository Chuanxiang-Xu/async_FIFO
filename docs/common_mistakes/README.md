# Common Async FIFO Mistakes

This directory turns common asynchronous FIFO and CDC mistakes into short
debugging lessons. Each page follows the same pattern:

```text
tempting idea -> why simple simulation may pass -> hardware risk
              -> correct approach -> where this repo handles it
```

These pages are not a second design guide. Read them when you want to
understand why the Cummings-style structure exists, why the constraints matter,
and why some shortcuts are intentionally unsupported.

## Mistake Index

| Mistake | Why it matters | Start here |
|---|---|---|
| Synchronizing a binary pointer | Multiple bits can change at once across an asynchronous boundary. | [Binary Pointer Crossing](binary_pointer_crossing.md) |
| Skipping Gray-bus constraints | Logical Gray coding does not control routed bit skew. | [Missing Gray-Bus Constraints](missing_gray_bus_constraints.md) |
| Treating flags as global truth | `full`, `empty`, and occupancy are local conservative views. | [Wrong Full/Empty Assumptions](wrong_full_empty_assumptions.md) |
| Releasing reset unsafely | Reset is destructive and must return both domains to a consistent empty state. | [Unsafe Reset Release](unsafe_reset_release.md) |
| Requesting arbitrary depths | The reflected-Gray pointer scheme assumes power-of-two wrap behavior. | [Non-Power-of-Two Depths](non_power_of_two_depths.md) |

## Reading Order

If you are new to async FIFOs, start with:

1. [Step-by-step tutorial](../tutorial.md)
2. [Cummings-style FIFO mapping](../cummings_mapping.md)
3. this mistake index

If you are reviewing an integration, start with:

1. [Interface and Timing](../interface.md)
2. [CDC and Timing Constraints](../cdc_constraints.md)
3. [Evidence Center](../evidence/README.md)
4. this mistake index

The short Chinese project entry point is in [README-CN.md](../../README-CN.md);
the detailed mistake pages are currently maintained here in English to keep
one source of truth.
