#!/usr/bin/env python3
"""Backward-compatible health entry point for the Hermes Companion skill."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parents[2] / "skills" / "hermes-companion" / "scripts" / "companion.py"


def main() -> None:
    if not SKILL.is_file():
        print(f"ERROR hermes-companion: missing {SKILL}", file=sys.stderr)
        raise SystemExit(1)
    argv = sys.argv[1:]
    if "--context" in argv:
        argv = ["--context" if arg == "--context" else arg for arg in argv]
    elif "--health" not in argv:
        argv = ["--health", *argv]
    sys.argv = [str(SKILL), *argv]
    runpy.run_path(str(SKILL), run_name="__main__")


if __name__ == "__main__":
    main()
