#!/usr/bin/env python3
"""Backward-compatible entry point. The skill reader is the source of truth."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parents[2] / "skills" / "hermes-companion" / "scripts" / "companion.py"


def main() -> None:
    if not SKILL.is_file():
        print(f"ERROR hermes-companion: missing {SKILL}", file=sys.stderr)
        raise SystemExit(1)
    sys.argv[0] = str(SKILL)
    runpy.run_path(str(SKILL), run_name="__main__")


if __name__ == "__main__":
    main()
