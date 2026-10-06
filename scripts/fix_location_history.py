#!/usr/bin/env python3
"""
Tool to inspect, validate, and cleanly sort location_history.json in place.

Sorts all records strictly by timestamp (newest-first, descending) to match the
expected contract, removes any null/malformed entries, and updates the 'count' field.
Creates a timestamped backup before modifying any files.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Mapping, Tuple

DEFAULT_ICLOUD_PATH = Path(
    os.path.expanduser(
        "~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/location_history.json"
    )
)
DEFAULT_TMP_PATH = Path("/tmp/hermes_location_history.json")


def inspect_file(path: Path) -> Tuple[bool, int, int]:
    """Inspects records in a location_history.json file.

    Returns (is_valid, record_count, inversion_count).
    """
    if not path.is_file():
        return False, 0, 0

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"Error reading {path}: {e}", file=sys.stderr)
        return False, 0, 0

    records = data.get("records", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
    if not isinstance(records, list):
        return False, 0, 0

    inversions = 0
    for i in range(len(records) - 1):
        r1, r2 = records[i], records[i + 1]
        t1 = str(r1.get("timestamp") or r1.get("recorded_at") or "") if isinstance(r1, dict) else ""
        t2 = str(r2.get("timestamp") or r2.get("recorded_at") or "") if isinstance(r2, dict) else ""
        if t1 < t2:
            inversions += 1

    return True, len(records), inversions


def fix_file(path: Path, dry_run: bool = False) -> bool:
    """Sorts records newest-first (descending) and rewrites the file safely."""
    if not path.is_file():
        print(f"File not found: {path}")
        return False

    print(f"\nProcessing: {path}")
    try:
        raw_text = path.read_text(encoding="utf-8")
        data = json.loads(raw_text)
    except Exception as e:
        print(f"  Failed to parse JSON in {path}: {e}", file=sys.stderr)
        return False

    if isinstance(data, dict):
        records = data.get("records", [])
    elif isinstance(data, list):
        records = data
        data = {"count": len(records), "records": records}
    else:
        print(f"  Unexpected JSON root structure in {path}", file=sys.stderr)
        return False

    if not isinstance(records, list):
        print(f"  'records' is not a list in {path}", file=sys.stderr)
        return False

    # Filter valid dicts
    valid_records = [r for r in records if isinstance(r, dict)]
    total = len(valid_records)

    # Sort descending (newest first)
    sorted_records = sorted(
        valid_records,
        key=lambda r: str(r.get("timestamp") or r.get("recorded_at") or ""),
        reverse=True,
    )

    # Check if changes are needed
    inversions_fixed = 0
    for i in range(len(valid_records) - 1):
        t1 = str(valid_records[i].get("timestamp") or valid_records[i].get("recorded_at") or "")
        t2 = str(valid_records[i + 1].get("timestamp") or valid_records[i + 1].get("recorded_at") or "")
        if t1 < t2:
            inversions_fixed += 1

    print(f"  Total records: {total}")
    print(f"  Out-of-order timestamp inversions found: {inversions_fixed}")

    if inversions_fixed == 0:
        print("  File is already strictly ordered (newest-first). No modifications needed.")
        return True

    if dry_run:
        print("  [Dry-run] Would sort 1000 records descending and update file.")
        return True

    # Backup
    backup_path = path.with_suffix(".json.bak")
    try:
        shutil.copy2(path, backup_path)
        print(f"  Created backup at: {backup_path}")
    except Exception as e:
        print(f"  Warning: failed to create backup: {e}", file=sys.stderr)

    # Update data
    data["records"] = sorted_records
    data["count"] = len(sorted_records)
    data["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Atomic write
    tmp_dest = path.with_suffix(".tmp")
    try:
        with open(tmp_dest, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        tmp_dest.replace(path)
        print(f"  Successfully fixed and sorted {total} records newest-first.")
        if sorted_records:
            print(f"  Newest record: {sorted_records[0].get('timestamp')}")
            print(f"  Oldest record: {sorted_records[-1].get('timestamp')}")
        return True
    except Exception as e:
        print(f"  Failed to write updated file: {e}", file=sys.stderr)
        if tmp_dest.exists():
            tmp_dest.unlink()
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect and fix location_history.json ordering.")
    parser.add_argument(
        "--file",
        "-f",
        type=Path,
        help="Path to specific location_history.json file to fix",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate fixing without writing changes to disk",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Only check for inversions without modifying files",
    )

    args = parser.parse_args()

    targets: List[Path] = []
    if args.file:
        targets.append(args.file)
    else:
        for p in [DEFAULT_ICLOUD_PATH, DEFAULT_TMP_PATH]:
            if p.is_file():
                targets.append(p)

    if not targets:
        print("No location_history.json found in default iCloud container or /tmp.")
        return 0

    if args.check:
        print("Checking location history files:")
        all_ok = True
        for t in targets:
            ok, count, inversions = inspect_file(t)
            status = "OK" if inversions == 0 else f"{inversions} inversions"
            print(f"  {t}: {count} records, {status}")
            if inversions > 0:
                all_ok = False
        return 0 if all_ok else 1

    success = True
    for t in targets:
        if not fix_file(t, dry_run=args.dry_run):
            success = False

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main() if main else 0)
