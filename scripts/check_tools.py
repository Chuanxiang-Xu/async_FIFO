#!/usr/bin/env python3
"""Check local tool availability for repository make targets."""

from __future__ import annotations

import argparse
import shlex
import shutil
import sys


def command_name(command: str) -> str:
    parts = shlex.split(command)
    return parts[0] if parts else command


def check_tool(label: str, command: str, required: bool, errors: list[str]) -> None:
    executable = command_name(command)
    path = shutil.which(executable)
    if path:
        print(f"PASS: {label}: {path}")
    elif required:
        errors.append(f"{label}: command not found ({executable})")
    else:
        print(f"SKIP: {label}: command not found ({executable})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--sby", default="sby")
    parser.add_argument("--z3", default="z3")
    parser.add_argument("--vivado", default="vivado")
    parser.add_argument(
        "--with-vivado",
        action="store_true",
        help="also require Vivado for vendor CDC and board-flow targets",
    )
    args = parser.parse_args()

    errors: list[str] = []
    required_tools = (
        ("Icarus Verilog", args.iverilog),
        ("VVP runtime", args.vvp),
        ("Verilator", args.verilator),
        ("Yosys", args.yosys),
        ("SymbiYosys", args.sby),
        ("Z3 solver", args.z3),
    )
    for label, command in required_tools:
        check_tool(label, command, True, errors)

    check_tool("Vivado", args.vivado, args.with_vivado, errors)

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        print(
            "NOTE: install the missing tools, activate the project environment, "
            "or override the matching Makefile variable.",
            file=sys.stderr,
        )
        return 1

    print("PASS: required open-source tools are available")
    return 0


if __name__ == "__main__":
    sys.exit(main())
