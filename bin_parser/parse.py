"""Top-level dispatcher: detects the map.bin variant and delegates to the
appropriate parser.

Usage:
    python parse.py <town_id>

The id may be the short id from towns.json / dungeons.json (e.g. 1103)
or the long folder id (e.g. 111020300).
"""

import os
import sys

import bin_common
import exploration_parser
import town_parser


def parse(town_id):
    bin_path = bin_common.town_bin_path(town_id)
    if not bin_path:
        return False

    # Sniff the variant using only the shared prefix.
    with open(bin_path, "rb") as f:
        common = bin_common.read_common_prefix(f)

    print(f"Detected variant: {common['variant']}")

    if common["variant"] == bin_common.VARIANT_TOWN_V1:
        return town_parser.parse_ffbe_map(bin_path)
    elif common["variant"] == bin_common.VARIANT_EXPLORATION_V2:
        return exploration_parser.parse_exploration_map(bin_path)
    else:
        print(f"Unknown variant: {common['variant']}")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python parse.py <town_id>")
        sys.exit(1)
    ok = parse(sys.argv[1])
    sys.exit(0 if ok else 1)
