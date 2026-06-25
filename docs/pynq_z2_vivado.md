# PYNQ-Z2 Vivado Validation

This example checks synthesis, implementation, CDC constraints, timing, BRAM
inference, and a simple on-board data sequence using a PYNQ-Z2.

Scope note: this board flow validates the minimal `async_fifo` integration and
the Xilinx Gray-pointer constraint strategy. Optional wrappers such as FWFT,
bidirectional FIFO, RAMIF, bidirectional RAMIF, width conversion, and stream
interfaces are covered by simulation, formal checks, lint, and generic
synthesis; they are not instantiated in this board demo.

## Target

- Device: Zynq-7000 XC7Z020, package CLG400, speed grade -1
- Vivado part: `xc7z020clg400-1`
- External PL clock: 125 MHz on package pin H16
- Generated FIFO clocks: 100 MHz write, 75 MHz read

The official PYNQ documentation identifies the board device as
XC7Z020-1CLG400C. Vivado represents the same device/package/speed selection as
`xc7z020clg400-1`.

## Files

```text
examples/pynq_z2/
├── async_fifo_pynq_z2_top.v   self-checking synthesizable top
├── async_fifo_pynq_z2.xdc     board pins and Gray-path constraints
└── build_vivado.tcl           batch build and report generation
```

The top level uses an MMCM to derive both FIFO clocks from the 125 MHz board
clock. These clocks are frequency-related rather than physically independent,
but they are sufficient to validate synthesis, placement, constraint object
matching, and the FIFO data path on this board.

## Run

From the repository root:

```bash
make pynq-z2
```

If Vivado is installed but is not in `PATH`, pass its executable explicitly:

```bash
make pynq-z2 VIVADO=/home/shane/vivado/2025.2/Vivado/bin/vivado
```

Vivado creates a disposable project under `examples/pynq_z2/build/` and writes
reports under `examples/pynq_z2/reports/`.

The generated bitstream is
`examples/pynq_z2/build/async_fifo_pynq_z2.runs/impl_1/async_fifo_pynq_z2_top.bit`.

## Verified result

The design was built locally with Vivado 2025.2 for `xc7z020clg400-1` on
2026-06-21. Synthesis, placement, routing, DRC, and bitstream generation all
completed successfully:

| Check | Result |
|---|---:|
| Worst setup slack | 5.625 ns |
| Total setup violation | 0.000 ns |
| Worst hold slack | 0.115 ns |
| Total hold violation | 0.000 ns |
| Gray exception coverage | 10/10 bits in both directions |
| Gray bus-skew slack, write to read | 9.017 ns |
| Gray bus-skew slack, read to write | 12.360 ns |
| Slice LUTs | 68 |
| Slice registers | 150 |
| RAMB18E1 | 1 |

The post-route CDC report marks all analyzed paths as safely timed. It does not
classify the Gray-pointer paths as asynchronous CDCs because this board example
derives both FIFO clocks from one MMCM, so Vivado knows that they are
frequency-related. The Tcl build therefore discovers each synthesized crossing
startpoint from its first-stage D pin. This includes a Gray MSB that Vivado may
merge with the identical binary-pointer MSB. It fails unless all 10 source
registers and all 10 first-stage pins are found in each direction.
`set_max_delay`, `set_bus_skew`, and `ASYNC_REG` then validate and preserve
those paths.

## Reports to inspect

At minimum, review:

```text
post_synth_cdc.rpt
post_synth_exceptions.rpt
post_route_timing.rpt
post_route_cdc.rpt
post_route_drc.rpt
post_route_clock_interaction.rpt
post_route_exceptions.rpt
post_route_bus_skew.rpt
post_route_utilization.rpt
```

Expected conditions:

- implementation completes and a bitstream is generated;
- WNS is non-negative and TNS is zero;
- the Tcl Gray-path checks find exactly 10 source registers and 10 first-stage
  pins in each direction;
- no higher-priority exception overrides the Gray `set_max_delay` constraints;
- Gray-bus skew checks pass;
- the FIFO memory is inferred as the intended memory resource;
- every CDC warning is either corrected or explicitly understood.

## LED behavior

| LED | Meaning | Expected |
|---|---|---|
| LED0 | Sticky data-sequence mismatch | Off |
| LED1 | FIFO full | May toggle |
| LED2 | Successful-read heartbeat (about 2.2 Hz) | Blinking |
| LED3 | MMCM locked | On |

Press BTN0 to reset the MMCM and FIFO test. Reset assertion is asynchronous;
release is synchronized independently into the 100 MHz and 75 MHz domains.
BTN0 resets the MMCM directly; `mmcm_locked` is the single asynchronous source
for both FIFO reset-release chains, avoiding a multi-input LUT on asynchronous
clear. LED2 is driven from the read-domain expected-count state, so it cannot
blink unless the FIFO produces repeated valid reads; this provides a positive
liveness indication in addition to the sticky error LED.

The FIFO core gates both inferred RAM ports with their local reset. Vivado can
still report that asynchronously reset pointer registers drive RAMB18 address
pins. For this destructive-reset test, that warning is reviewed under the
waiver conditions in [CDC and Timing Constraints](cdc_constraints.md): no RAM
access occurs during reset, old contents are discarded, and both domains are
returned to empty before traffic resumes.

After this reset change, the routed methodology report no longer contains
`LUTAR-1`. The remaining implementation DRC warnings are 20 `REQP-1840`
RAMB18 asynchronous-control findings covered by the reset waiver and one
`ZPS7-1` warning because this deliberately PL-only smoke test does not
instantiate the Zynq processing system. Vivado also emits one `CHECK-3`
bookkeeping warning because the `REQP-1840` report limit was reached.
`SYNTH-6` and two `TIMING-30` advisory methodology warnings remain; they do
not create a timing violation.

## Important limitations

The PYNQ-Z2 125 MHz PL clock is connected to the programmable logic, but PYNQ
systems commonly use clocks generated by the processing system instead. This
example deliberately uses the external PL clock to keep the validation project
independent of a Zynq block design.

Passing this example validates one device, clock configuration, parameter set,
and Vivado version. It does not prove every legal FIFO configuration or replace
the repository's simulation, assertions, and formal checks. It also does not
validate the optional wrapper top levels; use the wrapper-specific simulation,
formal, lint, and synthesis targets for those modules. The reported build
result does not by itself prove correct behavior on physical hardware; after
programming the board, LED0 must remain off, LED2 must keep blinking, and LED3
must remain on.
