# RTL Filelists

`rtl/files.f` remains the compatibility filelist used by the Makefile,
examples, scripts, and existing documentation. Keep it working.

The optional filelists under `rtl/filelists/` provide narrower entry points
for tools or readers that want a specific layer:

| Filelist | Scope |
|---|---|
| `rtl/filelists/core.f` | Internal equal-width FIFO core implementation. |
| `rtl/filelists/public.f` | Core plus stable public `async_fifo` and `async_reset_sync`. |
| `rtl/filelists/stable_wrappers.f` | Public filelist plus stable optional wrappers: FWFT, width conversion, stream. |
| `rtl/filelists/experimental_wrappers.f` | Public filelist plus beta/experimental wrappers: bidirectional, RAMIF, bidirectional RAMIF. |
| `rtl/filelists/all.f` | Expanded complete RTL list, aligned with `rtl/files.f`. |

## Compatibility Rule

Do not remove or rename `rtl/files.f`. Existing commands such as:

```bash
iverilog -g2012 -f rtl/files.f ...
verilator --lint-only -f rtl/files.f ...
```

should keep working. The layered filelists are additive convenience files.

## Maintenance Check

Run:

```bash
make filelists-check
```

This verifies that `rtl/filelists/all.f` and `rtl/files.f` contain the same
expanded RTL source list in the same order.
