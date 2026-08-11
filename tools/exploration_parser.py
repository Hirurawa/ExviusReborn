"""Parser scaffold for FFBE exploration-mission map.bin files (variant v2).

These files share the 32-byte file header + texture manifest layout with
town maps (see `bin_common.py`), but diverge immediately after the
manifest:

  * u16 layer_count   (observed = 14 across every exploration sample)
  * u16 pad           (observed = 0)
  * u32[layer_count] layer_id_table

The layer-id table is byte-identical across 111010100 / 111010200 /
111010300:

    [0, 10, 11, 12, 13, 14, 20, 21, 22, 30, 31, 32, 40, 50]

That fixed schema is the structural backbone of every exploration map.
This module bakes in that assumption: each known layer id maps to a slot
*role* (ground / visual / collision / region / events / objects), and
each role gets its own decoder. Decoders are stubs for now -- they emit
the raw byte range of their layer to the blueprint so downstream tools
can inspect what's actually there. Fill them in as the per-layer
encoding becomes clearer.

Detection of where a layer ends is still an open question; until that's
nailed down we read each layer's body opportunistically based on the
next layer's expected starting bytes (or, failing that, walk forward
naively).
"""

import json
import os
import struct
import sys

import bin_common
import town_parser


# Layer slot taxonomy. Roles are best-guesses based on numeric grouping
# observed in town v1 (visual = 10..14 range, collision = ~20, region =
# ~30 etc.) and the fact that the same set repeats across every
# exploration sample.
LAYER_ROLES = {
    0:  "ground",
    10: "visual_1",
    11: "visual_2",
    12: "visual_3",
    13: "visual_4",
    14: "visual_5",
    20: "collision_1",
    21: "collision_2",
    22: "collision_3",
    30: "region_1",
    31: "region_2",
    32: "region_3",
    40: "grid_events",
    50: "objects",
}

EXPECTED_LAYER_IDS = (0, 10, 11, 12, 13, 14, 20, 21, 22, 30, 31, 32, 40, 50)


# ---------------------------------------------------------------------------
# Post-manifest preamble
# ---------------------------------------------------------------------------

def read_layer_table(f):
    """Read the post-manifest preamble.

    Layout (60 bytes total when layer_count == 14):
      * u16 layer_count
      * u16 pad (observed = 0)
      * layer_count entries of 4 bytes each:
          - u16 layer_id   (the lookup key in LAYER_ROLES)
          - u16 aux        (observed = 0 for every entry except the
                             objects/dynamic-entities slot, where it
                             carries an as-yet-unknown count or flag)

    Cursor is left at the first byte after the table.
    """
    layer_count = struct.unpack(">H", f.read(2))[0]
    pad = struct.unpack(">H", f.read(2))[0]
    entries = []
    for _ in range(layer_count):
        layer_id, aux = struct.unpack(">HH", f.read(4))
        entries.append({"layer_id": layer_id, "aux": aux})
    return {
        "layer_count": layer_count,
        "pad": pad,
        "entries": entries,
        "layer_id_table": [e["layer_id"] for e in entries],
    }


# ---------------------------------------------------------------------------
# Per-layer decoders (stubs)
# ---------------------------------------------------------------------------
# Each decoder receives (f, layer_id, role, end_hint) and must:
#   * read the bytes for its layer
#   * leave `f` positioned at the byte immediately after its layer
#   * return a dict describing what it parsed (for the blueprint JSON)
#
# `end_hint` is the offset of the next layer's start when known, else
# None. Until we know how to derive layer boundaries from the data
# itself, decoders fall back to dumping raw bytes between `start` and
# `end_hint`.


def _dump_raw(f, layer_id, role, end_hint):
    """Fallback decoder: record start offset and (optionally) raw bytes
    up to end_hint. Useful while reverse-engineering per-layer formats.
    """
    start = f.tell()
    if end_hint is None:
        # No hint: peek what's here and leave the cursor untouched so
        # outer loop can decide how to advance.
        return {
            "layer_id": layer_id,
            "role": role,
            "start_offset": start,
            "status": "no_end_hint_unknown_layout",
        }
    raw = f.read(end_hint - start)
    return {
        "layer_id": layer_id,
        "role": role,
        "start_offset": start,
        "end_offset": end_hint,
        "byte_length": len(raw),
        "first_16_hex": raw[:16].hex(),
        "status": "raw_dump",
    }


# Decoder dispatch table. Today every role uses the raw-dump stub; swap
# entries here as you write real decoders.
DECODERS = {role: _dump_raw for role in LAYER_ROLES.values()}


# ---------------------------------------------------------------------------
# Top-level parse
# ---------------------------------------------------------------------------

def parse_exploration_map(file_path, output_path=None, common=None):
    """Parse an exploration v2 map.bin and write a blueprint JSON.

    The 32-byte file header, texture manifest, and 14-entry layer table
    are read locally (variant-specific). Everything from the chunk
    stream onward is delegated to `town_parser.parse_ffbe_map`, which
    walks chunks until EOF -- the chunk encoding itself is identical to
    town v1, so the heavy lifting (visual layers, collision, region,
    grid_events / static_assets / dynamic_entities) is shared.
    """
    if not os.path.exists(file_path):
        print(f"Error: Could not find {file_path}")
        return False
    if output_path is None:
        output_path = bin_common.default_blueprint_path(file_path)

    with open(file_path, "rb") as f:
        if common is None:
            common = bin_common.read_common_prefix(f)
        else:
            f.seek(common["manifest_end_offset"])

        print("--- EXPLORATION v2: reading layer table ---")
        table = read_layer_table(f)
        chunk_stream_start = f.tell()
        print(f"  layer_count={table['layer_count']}  pad={table['pad']}")
        print(f"  layer_id_table={table['layer_id_table']}")

        if tuple(table["layer_id_table"]) != EXPECTED_LAYER_IDS:
            print("  Warning: layer_id_table differs from the canonical schema")
            print(f"  expected: {EXPECTED_LAYER_IDS}")

    # Seed the blueprint with the v2-specific metadata. The shared
    # chunk loop (town_parser.parse_ffbe_map) will fill in "layers"
    # and any chunk-stream trailing bytes.
    blueprint = {
        "format_variant": bin_common.VARIANT_EXPLORATION_V2,
        "file_size": common["file_size"],
        "header_words": common["header_words"],
        "initial_layer_id": common["initial_layer_id"],
        "initial_player_x": common["initial_player_x"],
        "initial_player_y": common["initial_player_y"],
        "num_textures": common["num_textures"],
        "textures": common["textures"],
        "manifest_end_offset": common["manifest_end_offset"],
        "layer_table_offset": common["manifest_end_offset"],
        "layer_count": table["layer_count"],
        "layer_id_table": table["layer_id_table"],
        "layer_table_entries": table["entries"],
        "chunk_stream_start": chunk_stream_start,
        "layers": [],
    }

    pre_parsed = {
        "blueprint": blueprint,
        "chunk_stream_start": chunk_stream_start,
        "file_end_offset": common["file_size"],
    }
    town_parser.parse_ffbe_map(file_path, output_path=output_path,
                               pre_parsed=pre_parsed)
    return True


def parse_town(town_id):
    bin_path = bin_common.town_bin_path(town_id)
    if not bin_path:
        return False
    return parse_exploration_map(bin_path)


if __name__ == "__main__":
    town_id = sys.argv[1] if len(sys.argv) > 1 else "111010300"
    parse_town(town_id)
