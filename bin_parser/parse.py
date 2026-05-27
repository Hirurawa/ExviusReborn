"""Top-level dispatcher: routes a folder id under
`godot/assets/town_data/<id>/` to the right parser.

* If the folder contains `map.bin`, sniff the variant byte pattern and
  delegate to `town_parser` (town_v1) or `exploration_parser`
  (exploration_v2).
* If the folder contains `<id>_event.bin`, delegate to `event_parser`.

Usage:
    python parse.py <id>

For maps the id may be the short id from towns.json / dungeons.json
(e.g. 1103) or the long folder id (e.g. 111020300). For events the
full folder id (e.g. 111020301) is required.
"""

import os
import sys

import bin_common
import event_common
import event_parser
import exploration_parser
import town_parser


def parse(folder_id):
    folder_id = str(folder_id)

    # Map branch: short-id resolution + variant sniff. Inline the folder
    # check so a missing map.bin doesn't print a misleading error before
    # we try the event branch below.
    resolved = bin_common.resolve_town_folder_id(folder_id)
    folder = os.path.join(bin_common.TOWN_DATA_ROOT, resolved)
    bin_path = os.path.join(folder, "map.bin")
    if os.path.isfile(bin_path):
        with open(bin_path, "rb") as f:
            common = bin_common.read_common_prefix(f)
        print(f"Detected variant: {common['variant']}")
        if common["variant"] == bin_common.VARIANT_TOWN_V1:
            return town_parser.parse_ffbe_map(bin_path)
        if common["variant"] == bin_common.VARIANT_EXPLORATION_V2:
            return exploration_parser.parse_exploration_map(bin_path)
        print(f"Unknown variant: {common['variant']}")
        return False

    # Event branch: <root>/<id>/<id>_event.bin.
    event_bin = event_common.event_bin_path(folder_id)
    if event_bin:
        print(f"Detected variant: event")
        event_parser.parse_event_bin(event_bin)
        return True

    print(f"Error: no map.bin or {folder_id}_event.bin under "
          f"{os.path.join(bin_common.TOWN_DATA_ROOT, folder_id)}")
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python parse.py <id>")
        sys.exit(1)
    ok = parse(sys.argv[1])
    sys.exit(0 if ok else 1)
