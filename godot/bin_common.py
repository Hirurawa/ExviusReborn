"""Shared helpers for both town (v1) and exploration (v2) FFBE map.bin parsers.

Both formats share:
  * 32-byte file header (file_size + metadata + num_textures).
  * A texture manifest of (u16 atlas_id, u16 str_len, ascii name) entries.

They diverge in the bytes immediately following the manifest:
  * Town v1:        u32 total_chunks, then chunks with the canonical
                    16-byte chunk header.
  * Exploration v2: u16 layer_count, u16 pad, u32[layer_count] layer_id
                    table (a fixed 14-slot schema in samples so far),
                    then per-layer data blocks.

This module centralises the parts both parsers agree on, plus a small
town-id resolver and a variant detector.
"""

import json
import os
import struct


TOWN_DATA_ROOT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "assets", "town_data",
)


# ---------------------------------------------------------------------------
# Town-id resolution (short id from towns.json -> long folder id)
# ---------------------------------------------------------------------------

def resolve_town_folder_id(town_id):
    """Resolve a short town id (e.g. '1103') to its full folder id (e.g.
    '111020300') via `assets/town_data/towns.json`.

    Long folder ids and exact-match folders are returned unchanged. If
    the id cannot be resolved, the input is returned as-is so callers can
    surface a meaningful "folder not found" error themselves.
    """
    town_id = str(town_id)
    if os.path.isdir(os.path.join(TOWN_DATA_ROOT, town_id)):
        return town_id
    for catalog_name in ("towns.json", "dungeons.json"):
        catalog = os.path.join(TOWN_DATA_ROOT, catalog_name)
        if not os.path.isfile(catalog):
            continue
        try:
            with open(catalog, "r", encoding="utf-8") as fh:
                entries = json.load(fh)
        except Exception as exc:  # noqa: BLE001 - tolerate malformed catalogs
            print(f"Warning: could not read {catalog_name} ({exc})")
            continue
        entry = entries.get(town_id)
        if not entry:
            continue
        icon = entry.get("icon", "")
        base = os.path.splitext(os.path.basename(icon))[0]
        if base.startswith("map_icon_"):
            short = base[len("map_icon_"):]
            candidate = short + "00"
            if os.path.isdir(os.path.join(TOWN_DATA_ROOT, candidate)):
                names = entry.get("names", [town_id])
                print(f"Resolved short id {town_id} ('{names[0]}') -> {candidate}")
                return candidate
    return town_id


def town_bin_path(town_id):
    """Return the absolute path to `<town_folder>/map.bin` (resolving short
    ids first). Returns None when the folder or bin cannot be found.
    """
    folder_id = resolve_town_folder_id(town_id)
    folder = os.path.join(TOWN_DATA_ROOT, folder_id)
    if not os.path.isdir(folder):
        print(f"Error: town folder not found: {folder}")
        return None
    bin_path = os.path.join(folder, "map.bin")
    if not os.path.isfile(bin_path):
        print(f"Error: no map.bin under {folder}")
        return None
    return bin_path


def default_blueprint_path(bin_path):
    return os.path.join(os.path.dirname(os.path.abspath(bin_path)),
                        "map_blueprint.json")


# ---------------------------------------------------------------------------
# File header + texture manifest (shared by both formats)
# ---------------------------------------------------------------------------

def read_file_header(f):
    """Read the 32-byte file header. Leaves `f` positioned just past it,
    at the start of the texture manifest (byte 0x20).

    Returns a dict with the verified `file_size`, the verbatim metadata
    words (`header_words`), and the decoded spawn fields:

        * initial_layer_id  -- u32 at 0x08; chunk layer id the engine
                               loads first.
        * initial_player_x  -- u32 at 0x0C; player spawn tile X.
        * initial_player_y  -- u32 at 0x10; player spawn tile Y.
    """
    f.seek(0)
    raw = f.read(32)
    if len(raw) < 32:
        raise ValueError("File too small for 32-byte header")
    file_size = struct.unpack(">I", raw[0:4])[0]
    # Bytes 4..27 hold file-level metadata; expose them verbatim plus
    # the three confirmed spawn fields decoded below.
    header_words = list(struct.unpack(">6I", raw[4:28]))
    initial_layer_id = struct.unpack(">I", raw[8:12])[0]
    initial_player_x = struct.unpack(">I", raw[12:16])[0]
    initial_player_y = struct.unpack(">I", raw[16:20])[0]
    num_textures = struct.unpack(">I", raw[28:32])[0]
    return {
        "file_size": file_size,
        "header_words": header_words,
        "initial_layer_id": initial_layer_id,
        "initial_player_x": initial_player_x,
        "initial_player_y": initial_player_y,
        "num_textures": num_textures,
    }


def read_texture_manifest(f, num_textures):
    """Read `num_textures` `(atlas_id, str_len, name)` entries. Leaves `f`
    positioned at the byte immediately after the manifest."""
    textures = []
    for _ in range(num_textures):
        atlas_id = struct.unpack(">H", f.read(2))[0]
        str_len = struct.unpack(">H", f.read(2))[0]
        filename = f.read(str_len).decode("ascii")
        textures.append({"atlas_id": atlas_id, "filename": filename})
    return textures


# ---------------------------------------------------------------------------
# Variant detection
# ---------------------------------------------------------------------------

VARIANT_TOWN_V1 = "town_v1"
VARIANT_EXPLORATION_V2 = "exploration_v2"


def detect_variant(f):
    """Peek the 4 bytes following the manifest to decide the format.

    Town v1 stores a `u32 total_chunks` value whose upper u16 is always
    zero (no real-world map has >= 65 536 chunks). Exploration v2 stores
    a `u16 layer_count` followed by a `u16 pad` -- the count word is
    non-zero, so its high byte never matches the v1 pattern.

    Restores the read cursor to its original position before returning.
    """
    pos = f.tell()
    peek = f.read(4)
    f.seek(pos)
    if len(peek) < 4:
        raise ValueError("Unexpected EOF while detecting variant")
    if peek[0] == 0 and peek[1] == 0:
        return VARIANT_TOWN_V1
    return VARIANT_EXPLORATION_V2


def read_common_prefix(f):
    """Read the shared file header + texture manifest and detect the
    post-manifest variant. Leaves `f` positioned at the first byte after
    the manifest.

    Returns: dict with `file_size`, `header_words`, `num_textures`,
    `textures`, `manifest_end_offset`, and `variant`.
    """
    header = read_file_header(f)
    textures = read_texture_manifest(f, header["num_textures"])
    manifest_end = f.tell()
    variant = detect_variant(f)
    return {
        "file_size": header["file_size"],
        "header_words": header["header_words"],
        "initial_layer_id": header["initial_layer_id"],
        "initial_player_x": header["initial_player_x"],
        "initial_player_y": header["initial_player_y"],
        "num_textures": header["num_textures"],
        "textures": textures,
        "manifest_end_offset": manifest_end,
        "variant": variant,
    }
