#!/usr/bin/env python3
"""Lightweight structural checks for the asynchronous FIFO CDC pattern.

This is intentionally not a replacement for post-synthesis CDC sign-off.
It catches accidental source-level damage to the two synchronizer chains and
the expected Gray-pointer connections.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def require(text: str, pattern: str, message: str) -> None:
    if re.search(pattern, text, flags=re.MULTILINE | re.DOTALL) is None:
        raise AssertionError(message)


def check_sync(path: Path, source_name: str, meta_name: str, sync_name: str) -> None:
    text = path.read_text(encoding="utf-8")
    async_regs = re.findall(r'ASYNC_REG\s*=\s*"TRUE"', text)
    if len(async_regs) < 2:
        raise AssertionError(f"{path}: both synchronizer stages need ASYNC_REG")

    require(
        text,
        rf"{re.escape(meta_name)}\s*<=\s*{re.escape(source_name)}\s*;",
        f"{path}: first stage must sample {source_name}",
    )
    require(
        text,
        rf"{re.escape(sync_name)}\s*<=\s*{re.escape(meta_name)}\s*;",
        f"{path}: second stage must sample only the first stage",
    )


def main() -> int:
    reset_sync = (ROOT / "rtl/async_reset_sync.v").read_text(encoding="utf-8")
    require(
        reset_sync,
        r"module\s+async_reset_sync.*?"
        r'ASYNC_REG\s*=\s*"TRUE".*?'
        r"posedge\s+clk\s+or\s+negedge\s+async_rstn.*?"
        r"reset_pipe\s*<=\s*\{STAGES\{1'b0\}\}.*?"
        r"assign\s+sync_rstn\s*=\s*reset_pipe\[STAGES-1\]",
        "async_reset_sync must asynchronously assert and synchronously release",
    )

    check_sync(
        ROOT / "rtl/core/sync_w2r.v",
        "wptr_gray",
        "wptr_gray_meta",
        "wptr_gray_sync_reg",
    )
    check_sync(
        ROOT / "rtl/core/sync_r2w.v",
        "rptr_gray",
        "rptr_gray_meta",
        "rptr_gray_sync_reg",
    )

    core = (ROOT / "rtl/core/async_fifo_core.v").read_text(encoding="utf-8")
    require(
        core,
        r"sync_w2r.*?\.wptr_gray\s*\(\s*wptr_gray\s*\).*?"
        r"\.wptr_gray_sync\s*\(\s*wptr_gray_sync\s*\)",
        "async_fifo_core: write Gray pointer synchronizer is not connected as expected",
    )
    require(
        core,
        r"sync_r2w.*?\.rptr_gray\s*\(\s*rptr_gray\s*\).*?"
        r"\.rptr_gray_sync\s*\(\s*rptr_gray_sync\s*\)",
        "async_fifo_core: read Gray pointer synchronizer is not connected as expected",
    )

    for relative_path in (
        "constraints/xilinx/async_fifo.xdc",
        "constraints/intel/async_fifo.sdc",
        "examples/pynq_z2/async_fifo_pynq_z2.xdc",
    ):
        constraint_path = ROOT / relative_path
        constraint_text = constraint_path.read_text(encoding="utf-8")
        active_lines = "\n".join(
            line for line in constraint_text.splitlines()
            if not line.lstrip().startswith("#")
        )
        if re.search(r"\bset_clock_groups\b", active_lines):
            raise AssertionError(
                f"{constraint_path}: broad set_clock_groups can override "
                "Gray-path max-delay constraints"
            )
        require(
            active_lines,
            r"wptr_source_regs.*?set_max_delay",
            f"{constraint_path}: missing write-pointer Gray max-delay constraint",
        )
        require(
            active_lines,
            r"rptr_source_regs.*?set_max_delay",
            f"{constraint_path}: missing read-pointer Gray max-delay constraint",
        )

        if relative_path in (
            "constraints/xilinx/async_fifo.xdc",
            "examples/pynq_z2/async_fifo_pynq_z2.xdc",
        ):
            require(
                active_lines,
                r"wptr_source_regs\s+\[all_fanin.*?wptr_meta_pins",
                f"{constraint_path}: write Gray sources must be discovered "
                "from synthesized synchronizer endpoints",
            )
            require(
                active_lines,
                r"rptr_source_regs\s+\[all_fanin.*?rptr_meta_pins",
                f"{constraint_path}: read Gray sources must be discovered "
                "from synthesized synchronizer endpoints",
            )

        if relative_path == "constraints/xilinx/async_fifo.xdc":
            require(
                active_lines,
                r"set\s+fifo_instance\s+\{[^}]+\}",
                f"{constraint_path}: the template must declare one exact "
                "FIFO instance scope",
            )
            require(
                active_lines,
                r"fifo_sync_regs\s+\[get_cells.*?"
                r"NAME\s+=~\s+\$\{fifo_instance\}/u_sync_w2r/.*?"
                r"NAME\s+=~\s+\$\{fifo_instance\}/u_sync_r2w/.*?"
                r"set_property\s+ASYNC_REG\s+TRUE\s+\$fifo_sync_regs",
                f"{constraint_path}: synchronizer properties must be scoped "
                "to fifo_instance",
            )
            require(
                active_lines,
                r"wptr_meta_pins\s+\[get_pins.*?"
                r"\$\{fifo_instance\}/u_sync_w2r/.*?"
                r"rptr_meta_pins\s+\[get_pins.*?"
                r"\$\{fifo_instance\}/u_sync_r2w/",
                f"{constraint_path}: Gray endpoints must be scoped to "
                "fifo_instance",
            )
            if re.search(r"^\s*(if|proc)\b", active_lines, flags=re.MULTILINE):
                raise AssertionError(
                    f"{constraint_path}: standard XDC must not contain "
                    "unsupported Tcl control commands"
                )

    xilinx_check = (
        ROOT / "constraints/xilinx/check_async_fifo.tcl"
    ).read_text(encoding="utf-8")
    require(
        xilinx_check,
        r"proc\s+check_async_fifo_cdc.*?"
        r"require_count\s+\$fifo_instance_cells\s+1.*?"
        r"require_count\s+\$fifo_sync_regs.*?"
        r"require_count\s+\$wptr_meta_pins\s+\$fifo_pointer_width.*?"
        r"require_count\s+\$rptr_meta_pins\s+\$fifo_pointer_width.*?"
        r"require_count\s+\$wptr_source_regs\s+\$fifo_pointer_width.*?"
        r"require_count\s+\$rptr_source_regs\s+\$fifo_pointer_width",
        "Xilinx post-synthesis CDC check must validate exact scoped counts",
    )
    require(
        xilinx_check,
        r"proc\s+constrain_async_fifo_cdc.*?"
        r"check_async_fifo_cdc\s+\$fifo_instance\s+\$fifo_pointer_width.*?"
        r"set_max_delay.*?set_bus_skew.*?"
        r"set_max_delay.*?set_bus_skew",
        "Xilinx integration procedure must validate before constraining both directions",
    )

    print("PASS: CDC synchronizer structure and constraint-template checks")
    print("NOTE: run vendor or commercial post-synthesis CDC analysis for sign-off")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
