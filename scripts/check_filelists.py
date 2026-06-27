#!/usr/bin/env python3
"""Check RTL filelist consistency."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def expand_filelist(path: Path, seen: set[Path] | None = None) -> list[str]:
    if seen is None:
        seen = set()
    path = path.resolve()
    if path in seen:
        raise ValueError(f"recursive filelist include: {path.relative_to(ROOT)}")
    seen.add(path)

    entries: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("+"):
            continue
        candidate = ROOT / line
        if line.endswith(".f"):
            entries.extend(expand_filelist(candidate, seen.copy()))
        else:
            entries.append(line)
    return entries


def main() -> int:
    legacy = expand_filelist(ROOT / "rtl/files.f")
    layered_all = expand_filelist(ROOT / "rtl/filelists/all.f")

    errors: list[str] = []
    if legacy != layered_all:
        errors.append("rtl/files.f and rtl/filelists/all.f differ")

    for filelist in sorted((ROOT / "rtl/filelists").glob("*.f")) + [ROOT / "rtl/files.f"]:
        for entry in expand_filelist(filelist):
            if not (ROOT / entry).exists():
                errors.append(
                    f"{filelist.relative_to(ROOT)} references missing file {entry}"
                )

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: RTL filelists are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
