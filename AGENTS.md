# Agent Notes

This repository should grow as a readable, runnable, and verifiable teaching
RTL project for asynchronous FIFO design. Treat it as both reusable RTL and a
learning archive.

## North Star

Use three external references as complementary study directions:

| Direction | Reference | What to learn from it | How this repo should respond |
|---|---|---|---|
| Async FIFO theory | Clifford Cummings / Sunburst async FIFO papers | Gray pointers, extra pointer bit, synchronized pointer comparison, full/empty reasoning, CDC discipline | Keep the core RTL and learning docs aligned with the classic Cummings-style mental model. Explain deviations explicitly. |
| Formal verification | ZipCPU FIFO/formal writing | Small properties, induction-friendly invariants, safety/liveness framing, readable formal harnesses | Keep formal proofs approachable, named by intent, and connected back to the RTL and docs. |
| Industrial interface expectations | AMD/Xilinx `XPM_FIFO_ASYNC` | Parameter style, reset behavior, status flags, almost flags, CDC/IP integration expectations | Keep public interfaces practical and clearly documented. Match industrial expectations where useful, but preserve this repo's teaching clarity. |

The goal is not to clone any one source. The goal is to make this project the
bridge between them:

```text
Cummings: learn the async FIFO theory
ZipCPU:   learn how to prove it
AMD XPM:  learn what industrial FIFO users expect

async_FIFO: readable, runnable, verifiable teaching RTL
```

## Roadmap Philosophy

The main line should deepen the project's teaching value before adding more
top-level flavors. Do not chase feature count for its own sake.

Main-line work:

1. **Cummings mapping**
   - Map the classic async FIFO paper concepts to this repository's RTL.
   - Show where Gray pointers, extra pointer bits, synchronizers, `full`, and
     `empty` are implemented.
   - Explain any intentional deviation from the paper.
2. **Formal guide**
   - Teach the proof strategy, not only list that formal checks exist.
   - Connect intuitive FIFO requirements to properties: no overflow, no
     underflow, ordering, `rd_valid` alignment, reset behavior, and flag
     conservatism.
3. **XPM FIFO comparison**
   - Use AMD/Xilinx `XPM_FIFO_ASYNC` as the industrial interface reference.
   - Compare ports, parameters, read modes, status flags, data counts, reset
     behavior, and unsupported vendor-IP features.
   - Be explicit that this repository is a teaching RTL project, not a vendor
     IP replacement.
4. **FWFT / fallthrough option**
   - Add standard-vs-FWFT read behavior as a documented option.
   - Keep the Cummings-style CDC core clean; implement fallthrough behavior as
     read-side mode/wrapper logic where possible.
   - Add waveform examples, directed tests, and formal updates.

Optional future wrappers:

- `async_bidir_fifo`: two independent async FIFO channels for full-duplex CDC.
- `async_fifo_ramif`: experimental external/custom RAM backend.
- `async_bidir_ramif_fifo`: composition of bidirectional CDC and RAM interface.

These optional wrappers are allowed as future study, but they are not the main
identity of the project. They must not obscure the core learning path or pollute
the equal-width CDC core.

## What 10/10 Means

A 10/10 version of this project is not the version with the most features. It
is a small teaching-grade RTL reference where every important idea is:

```text
explainable -> runnable -> visible in RTL -> tested/proved -> compared to
industrial interface expectations
```

In practical terms, 10/10 means:

- **Theory loop closed:** Cummings/Sunburst concepts are mapped to code,
  waveforms, and common wrong implementations.
- **Formal loop closed:** proofs are explained from user-visible FIFO
  requirements to properties, covers, and failure traces.
- **Industrial loop closed:** XPM-style interface expectations are compared
  honestly against this repository's supported behavior and non-goals.
- **Run loop closed:** basic simulation, tutorial waveform generation, lint,
  docs checks, and core formal tasks are easy to run and understand.
- **Documentation loop closed:** first-time learners, RTL integrators,
  verification readers, and CDC/timing reviewers each have a clear route.
- **Boundary loop closed:** reset limits, CDC limits, formal coverage limits,
  target-device assumptions, and unsupported features are stated plainly.

The project should remain clear enough for interviews and teaching. Prefer a
smaller feature set with excellent explanations, tests, and proofs over a large
IP family whose behavior is hard to learn.

## Documentation Policy

- Keep `README.md` and `README-CN.md` as project entry points, not full theory
  books. They may be substantial because the project has real features, but
  deep explanations should live in `docs/`.
- Keep English and Chinese docs paired when a document is part of the learning
  path:
  - `docs/tutorial.md` and `docs/tutorial_CN.md`
  - `docs/learning_async_fifo.md` and `docs/learning_async_fifo_CN.md`
- Use `docs/tutorial*.md` for the first-pass mental model and waveform walk.
- Use `docs/learning_async_fifo*.md` for deeper theory and RTL reading order.
- Use `docs/interface.md` as the authoritative contract for ports, reset,
  `rd_valid`, status flags, occupancy, wrapper capacity, and transfer
  acceptance.
- Use `docs/cdc_constraints.md` for physical implementation and sign-off
  expectations.
- Keep open-source contributor-facing docs current:
  - `CONTRIBUTING.md` for setup, review expectations, and what to run;
  - `.github/pull_request_template.md` for PR checklists;
  - `.github/ISSUE_TEMPLATE/` for bug reports and feature requests.
- When adding a new user-facing learning path, add it to the README roadmap
  and keep the Chinese entry point in sync.

## Open Source Maintenance Policy

Treat this as a public open-source teaching project, not only a personal code
archive.

- Keep `LICENSE`, `CONTRIBUTING.md`, issue templates, PR templates, and README
  verification guidance present and useful.
- Prefer small, reviewable changes with a clear verification story.
- For every public behavior change, update:
  - interface docs;
  - relevant English/Chinese learning-path docs;
  - tests or formal harnesses;
  - README contributor/check guidance if the required checks change.
- Preserve a clean release story:
  - update compatibility/release metadata when release-facing behavior changes;
  - do not commit generated `build/` output;
  - keep CI commands reproducible through `environment.yml` or pinned
    container/tool versions.
- Make issue and PR intake easy for outsiders: ask for parameters, clocks,
  tool versions, reproduction commands, waveforms/logs, and sign-off context.
- Keep non-goals explicit. This project may compare itself with XPM-style
  industrial expectations, but it must not imply vendor-IP equivalence.

## RTL Policy

- Keep `rtl/async_fifo.v` as the minimal public equal-width FIFO entry point.
- Keep the CDC core equal-width. Do not push width conversion into the
  crossing pointer mechanism.
- Keep wrappers responsible for protocol adaptation:
  - `async_fifo_width_conv` for request-style width conversion;
  - `async_fifo_stream` for ready/valid packet semantics.
- Preserve the Cummings-style core model:
  - local binary pointers for arithmetic and RAM addressing;
  - registered Gray pointers for CDC;
  - two-flop synchronizers for crossing pointers;
  - local-domain `full` and `empty`;
  - conservative flag deassertion because of synchronization latency.
- Any intentional deviation from that model should be documented near the RTL
  and in the relevant docs.

## Verification Policy

- Keep tests and formal properties tied to user-visible behavior:
  transfer acceptance, no overflow, no underflow, data ordering, `rd_valid`,
  reset behavior, wrapper capacity, and CDC structure.
- Prefer small, readable formal harnesses over clever monolithic proofs.
- When adding a property, give it a name that says what behavior it protects.
- When adding a waveform or tutorial scenario, make it reproducible from a
  checked-in testbench.

## Maintenance Checklist

Before finishing changes that affect behavior or documentation:

1. Run the relevant simulation or formal target.
2. Run `python3 scripts/check_docs.py` after Markdown edits.
3. Keep Chinese and English learning-path docs in sync.
4. Update interface docs before or alongside public RTL behavior changes.
5. Preserve the teaching path: intuition first, then mechanism, then RTL, then
   verification/sign-off.
6. For open-source-facing changes, update `CONTRIBUTING.md`, README quick
   checks, or GitHub templates when contributor expectations change.
