#!/usr/bin/env python3
"""Check README entry points and local links in repository Markdown files."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def check_readme_entry_points() -> list[str]:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    required = (
        "## Which module should I use?",
        "`async_fifo`",
        "`async_fifo_width_conv`",
        "`async_fifo_stream`",
        "examples/basic_fifo/",
        "docs/architecture.md",
        "docs/interface.md",
    )
    return [f"README.md: missing {item}" for item in required if item not in readme]


def check_local_links() -> list[str]:
    errors: list[str] = []
    for document in sorted(ROOT.rglob("*.md")):
        if ".git" in document.parts or "build" in document.parts:
            continue
        text = document.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for raw_target in LINK_RE.findall(line):
                target = raw_target.strip().strip("<>")
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                relative_target = unquote(target.split("#", 1)[0])
                if not relative_target:
                    continue
                resolved = (document.parent / relative_target).resolve()
                if not resolved.exists():
                    errors.append(
                        f"{document.relative_to(ROOT)}:{line_number}: "
                        f"missing local link target {target}"
                    )
    return errors


def main() -> int:
    errors = check_readme_entry_points() + check_local_links()
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: README entry points and local Markdown links are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
