# Experimental and Advanced Modules

This page names the modules whose integration boundary needs extra care. It is
not a warning against studying them; it is a reminder that they are advanced
composition or external-resource topics, not the main teaching entry point.

Most users should start with [Public Module API](api.md) and instantiate
`async_fifo`.

## Status Summary

| Module | Status | Why it is advanced |
|---|---|---|
| `async_bidir_fifo` | Beta | Composes two independent FIFO directions and exposes more status surfaces. |
| `async_fifo_ramif` | Experimental | Externalizes storage, so the consuming project owns RAM implementation and sign-off. |
| `async_bidir_ramif_fifo` | Experimental | Composes two RAMIF directions, doubling the RAM-interface boundary. |

Stable wrappers such as `async_fifo_fwft`, `async_fifo_width_conv`, and
`async_fifo_stream` are still optional wrappers. They are public and tested,
but users should choose them only when their documented interface behavior
matches the system.

## Bidirectional FIFO Boundary

`async_bidir_fifo` is full-duplex composition:

```text
A -> async_fifo -> B
B -> async_fifo -> A
```

It does not implement a new CDC algorithm. The two directions are independent:

- A->B full/empty does not describe B->A;
- one direction becoming full does not block the other direction;
- there is no cross-direction transaction atomicity;
- there is no runtime direction switching or half-duplex shared RAM.

Read [Bidirectional FIFO Wrapper Design](bidir_fifo_design.md) before using it.

## RAMIF Boundary

`async_fifo_ramif` externalizes storage only. It keeps pointer, synchronizer,
`full`, `empty`, and `rd_valid` behavior in this repository, but the connected
RAM must follow the documented contract:

- simple dual-port shape;
- one write port in `wr_clk`;
- one synchronous read port in `rd_clk`;
- fixed one-read-clock latency;
- no read or write backpressure;
- no variable-latency ready/busy behavior;
- reset clears FIFO control, not RAM contents.

The consuming project owns RAM inference, macro binding, collision behavior,
timing closure, and RAM-specific waivers.

Read [External RAM Interface FIFO Design](ramif_design.md) before using it.

## Bidirectional RAMIF Boundary

`async_bidir_ramif_fifo` is two independent `async_fifo_ramif` directions:

```text
A -> async_fifo_ramif -> B
B -> async_fifo_ramif -> A
```

It does not share RAM, ports, pointer state, flags, or transaction state
between directions. Each direction needs its own external RAM contract and
sign-off evidence.

Read [Bidirectional External-RAM FIFO Wrapper Design](bidir_ramif_fifo_design.md)
before using it.

## Unsupported Advanced Features

The advanced modules do not provide:

- shared bidirectional RAM ports;
- runtime `a_dir` / `b_dir` direction controls;
- data-preserving one-sided reset;
- RAM wait states or variable read latency;
- dynamic programmable thresholds;
- ECC or byte-enable semantics;
- complete vendor-IP equivalence;
- commercial CDC sign-off.

If a future study adds one of these features, it should start with an explicit
contract, then add matching simulation, formal checks, interface docs, and
evidence notes.

## Review Checklist

Before using an advanced or experimental wrapper, confirm:

- [Interface and Timing](interface.md) describes the public behavior you need;
- [Evidence Center](evidence/README.md) lists checks relevant to the module;
- [CDC and Timing Constraints](cdc_constraints.md) are applied in the target
  project;
- RAMIF integrations have a project-owned RAM wrapper and timing/collision
  sign-off evidence;
- reset behavior is acceptable as destructive coordinated reset;
- optional wrapper status does not obscure the main `async_fifo` learning path.
