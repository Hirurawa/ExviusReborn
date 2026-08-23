#!/usr/bin/env python3
"""Cross-reference unit ids in ffbe-data.db against the unit icon sprites on disk.

Reports every unit in the `unit` table that has no matching
`unit_icons/unit_icon_<unitId>.png` file.

Usage:
    python tools/check_unit_icons.py [--csv missing.csv] [--summary]
"""

from __future__ import annotations

import argparse
import csv
import re
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = REPO_ROOT / "godot" / "assets" / "static_data" / "ffbe-data.db"
ICON_DIR = REPO_ROOT / "godot" / "assets" / "unit_icons"

ICON_RE = re.compile(r"^unit_icon_(\d+)\.png$", re.IGNORECASE)


def load_units(db_path: Path) -> list[tuple[int, str, int]]:
    """Return (unitId, unitName, rare) for every row in the unit table."""
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
        return list(
            conn.execute(
                "SELECT unitId, unitName, COALESCE(rare, 0) "
                "FROM unit ORDER BY unitId"
            )
        )


def load_icon_ids(icon_dir: Path) -> set[int]:
    """Return the set of unit ids that have a unit_icon_<id>.png on disk."""
    ids: set[int] = set()
    for entry in icon_dir.iterdir():
        match = ICON_RE.match(entry.name)
        if match:
            ids.add(int(match.group(1)))
    return ids


def main() -> int:
    # Unit names contain characters outside the default Windows console codepage.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB_PATH, help="path to ffbe-data.db")
    parser.add_argument("--icons", type=Path, default=ICON_DIR, help="unit_icons folder")
    parser.add_argument("--csv", type=Path, help="also write the missing list to a CSV")
    parser.add_argument(
        "--summary", action="store_true", help="print counts only, no per-unit listing"
    )
    args = parser.parse_args()

    if not args.db.is_file():
        print(f"error: database not found: {args.db}", file=sys.stderr)
        return 1
    if not args.icons.is_dir():
        print(f"error: icon folder not found: {args.icons}", file=sys.stderr)
        return 1

    units = load_units(args.db)
    icon_ids = load_icon_ids(args.icons)

    missing = [(uid, name, rare) for uid, name, rare in units if uid not in icon_ids]
    orphans = sorted(icon_ids - {uid for uid, _, _ in units})

    print(f"units in database : {len(units)}")
    print(f"icons on disk     : {len(icon_ids)}")
    print(f"missing icons     : {len(missing)}")
    print(f"orphan icons      : {len(orphans)}  (png with no unit row)")
    print()

    if missing and not args.summary:
        print("Units without sprite data:")
        print(f"{'unitId':>12}  {'rare':>4}  unitName")
        print(f"{'-' * 12}  {'-' * 4}  {'-' * 40}")
        for uid, name, rare in missing:
            print(f"{uid:>12}  {rare:>4}  {name}")
        print()

    if orphans and not args.summary:
        print(f"Orphan icon ids: {', '.join(str(o) for o in orphans)}")
        print()

    if args.csv:
        with args.csv.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(["unitId", "rare", "unitName"])
            writer.writerows(missing)
        print(f"wrote {len(missing)} rows to {args.csv}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
