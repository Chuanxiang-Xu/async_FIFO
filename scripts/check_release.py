#!/usr/bin/env python3
"""Check that public release metadata agrees on one semantic version."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is None:
        raise AssertionError(f"VERSION is not semantic versioning: {version!r}")

    core = (ROOT / "async_fifo.core").read_text(encoding="utf-8")
    if f"name: ::async_fifo:{version}" not in core:
        raise AssertionError("async_fifo.core version does not match VERSION")

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if re.search(
        rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}$",
        changelog,
        flags=re.MULTILINE,
    ) is None:
        raise AssertionError("CHANGELOG.md has no dated entry for VERSION")

    compatibility = (
        ROOT / "docs/compatibility.md"
    ).read_text(encoding="utf-8")
    if f"Current RTL release: `{version}`." not in compatibility:
        raise AssertionError(
            "docs/compatibility.md current release does not match VERSION"
        )

    print(f"PASS: release metadata is consistent for v{version}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
