# CDC and Timing Constraints

The RTL implements the logical CDC structure of a conventional asynchronous
FIFO, but RTL attributes alone are not a complete timing-closure strategy.
Every target project should add device- and tool-specific constraints and run
CDC analysis after synthesis.

The repository provides executable source-level checks:

```bash
make cdc
make synth
make formal
```

`make cdc` checks the expected two-stage synchronizer source structure and
Gray-pointer connections. `make synth` runs Yosys hierarchy and process
checks. Neither command replaces post-route CDC sign-off.
`make formal` runs multiple complementary layers. The pointer harness proves local Gray
transitions and blocked-access stability by k-induction. The multiclock core
harness performs bounded exhaustive exploration through 96 frames for
occupancy bounds, full/empty and almost-flag consistency, read-valid timing,
and end-to-end data ordering. Its
coprime clock schedule continually changes write/read phase; a separate cover
task reaches full and more reads than one physical FIFO depth. Two additional
symbolic-clock BMCs use independently selected write/read phase increments
and an arbitrary initial read-clock phase at `ADDR_WIDTH=1/2`. They cover a
bounded family of frequency ratios and edge coincidences rather than only the
fixed 2/3 schedule. Two additional
96-frame BMCs check write-first and read-first synchronous reset release while
traffic remains disabled until both domains initialize; matching cover tasks
reach repeated ordered reads after release. The packet-stream wrapper has the
same two release-order BMCs through its 8-to-16 pack path; matching covers
reach both final and non-final transfers after coordinated startup. Four 64-frame
wrapper BMCs check both packing directions: the request interface checks
unique-token slice ordering and occupancy bounds, while the stream interface
uses independent read-side expectation state to check `data/keep/last`
ordering and output stability under arbitrary backpressure. Four additional
wrapper cover tasks establish non-vacuity by reaching full, repeated reads,
and stream final/non-final transfers. Request-converter covers use 160 frames;
stream covers use 96 frames.

`make formal-matrix` adds 20 concrete 64-frame BMC elaborations across both
wrapper APIs, `ADDR_WIDTH=2/3/4/5`, 8/16-bit equal-width operation, and
bidirectional 1:2/1:4/1:8 conversion. Four ratio-4 cover tasks reach repeated
ordered outputs.
The full `make formal` target includes this matrix.

The deep packet/reset wrapper harnesses use representative fixed parameters;
the matrix broadens concrete width and depth coverage with a coprime 2/3
clock-divider schedule. The symbolic-clock core layer varies rates and initial
phase independently. None of these bounded layers claims one exhaustive proof
over every legal elaboration or continuously varying clock waveform.

## CDC paths in this design

Only the registered Gray pointers cross clock domains:

```text
wptr_gray -> sync_w2r -> wptr_gray_sync
rptr_gray -> sync_r2w -> rptr_gray_sync
```

The payload remains in dual-port RAM. In `async_fifo_stream`, the payload also
contains `keep` and `last`; all three fields cross together through RAM. Do not
add per-bit synchronizers to the data or metadata buses.

For generic integration, treat the source and destination domains as
asynchronous unless the system architecture proves a timing relationship.
Define both clocks accurately in the top-level constraints. Do not apply a
broad asynchronous clock-group or false-path exception that overrides the
Gray-pointer maximum-delay constraints.

## Synchronizer placement

The synchronizer registers use the `ASYNC_REG` attribute in RTL. Confirm in
post-synthesis reports that:

- both stages are preserved;
- the stages are placed close together;
- no combinational logic is inserted between them;
- optimization or retiming has not changed the synchronizer structure.

Attribute names and accepted values differ between tools. Add any required
vendor-specific preservation attributes in the consuming project.

## Gray-bus skew

For consecutive single-step source pointer values, reflected Gray encoding
changes one bit. This logical property does not constrain routed arrival
times. Constrain the paths from each source Gray-pointer register to the first
destination synchronizer stage so that excessive routing skew cannot make
multiple pointer transitions appear in one destination sampling window.

A common engineering target is to limit each Gray-bus delay or skew to no more
than one period of that crossing's source clock. This is a design guideline,
not a portable command; derive the actual limit from the clocks, technology, and
reliability requirements.

## Example intent

The following snippets illustrate intent only. Hierarchical names and syntax
must be adapted to the synthesized netlist and tool version.

### Xilinx Vivado-style intent

```tcl
# Apply max-delay and bus-skew constraints separately:
# wptr_gray -> first write-pointer synchronizer stage
# rptr_gray -> first read-pointer synchronizer stage
#
# Use each pointer's source-clock period as its bound.
```

Template: `constraints/xilinx/async_fifo.xdc`.

The Xilinx template discovers sequential source cells by tracing backward from
the first synchronizer-stage D pins. This avoids silently omitting a bit when
Vivado renames or merges a Gray-pointer register during optimization. Set
`fifo_pointer_width` to `ADDR_WIDTH + 1` and set `fifo_instance` to the exact
synthesized hierarchy of one `async_fifo_core` instance. All synchronizer
properties, endpoint discovery, and Gray-path constraints are restricted to
that hierarchy.

After `read_xdc`, source `constraints/xilinx/check_async_fifo.tcl` and call
`check_async_fifo_cdc` with the same instance path and pointer width. The
post-synthesis check fails unless the scope identifies exactly one core and
the synchronizer registers, first-stage D pins, and sequential startpoints all
have their expected exact counts. The check is a companion Tcl script because
standard XDC parsing does not support general Tcl `proc` or `if` commands.
Scripted non-project flows may instead call `constrain_async_fifo_cdc`, which
performs the exact checks first and then applies both directions of max-delay
and bus-skew constraints as one operation. Call it once for every FIFO
instance; the multi-instance regression demonstrates this integration.
Run the repository's default elaboration check with:

```sh
make xilinx-cdc
```

### Intel Quartus-style intent

```tcl
# Identify each Gray source register bank and its corresponding first
# synchronizer stage, then apply a datapath-only max delay using the source
# clock period.
```

Template: `constraints/intel/async_fifo.sdc`.

Do not copy broad clock-group or false-path constraints without checking their
priority and endpoints. Such exceptions can both hide real timing failures and
silently disable the intended Gray-path constraints.

## Reset crossings

The RTL uses asynchronous reset assertion. Reset release must be synchronized
independently in each clock domain by the surrounding system. Treat reset
deassertion as a recovery/removal timing concern and verify it with the target
flow.

The FIFO assumes both domains eventually return to the same empty state.
Resetting only one side while the other side continues transferring data is
not a supported data-preserving operation.

The reset-skew formal harness checks both initial release orders. Each reset
deasserts only on its local clock, and requests are held inactive until both
domains have completed initialization. A separate stream harness extends the
same contract through local pack/pending and read-buffer state, checking
`data/keep/last` ordering and output stability. Neither harness models or
authorizes a one-sided reset while traffic is active.

## Block-RAM asynchronous-reset waiver

The binary pointer registers drive the inferred block-RAM addresses and use
asynchronous reset. Some FPGA tools therefore warn that reset can change a RAM
address or enable outside normal clock timing. This repository treats FIFO
reset as destructive and relies on all of the following conditions:

- RAM write access is gated by `wr_rstn`;
- RAM read access is gated by `rd_rstn`;
- RAM contents and `rd_data` have no valid meaning during reset;
- both domains are returned to the same empty state before traffic resumes;
- data queued before reset is discarded rather than preserved.

Under these conditions, reset-time changes to stale RAM contents cannot become
valid FIFO output. A target project may document and waive the corresponding
RAM primitive warning after confirming these conditions in its synthesized
netlist. This rationale does not permit data-preserving one-sided reset.

## Sign-off checklist

- Both clocks are defined accurately.
- Gray crossings are constrained without a higher-priority exception
  overriding them.
- Synchronizer chains are recognized in synthesis and CDC reports.
- Gray source registers directly drive the crossing paths.
- Gray-bus maximum delay or skew is constrained.
- Recovery/removal behavior is checked for reset release.
- Dual-port RAM inference matches the intended device primitive.
- CDC reports contain no unexplained violations.
- Post-route timing and constraint coverage reports are reviewed.
