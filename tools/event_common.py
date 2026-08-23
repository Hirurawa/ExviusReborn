"""Shared helpers for FFBE *_event.bin (cutscene / story) files.

Header layout (verified across 733 files):

    off  0: u32 BE  file_size                       (== actual bytes)
    off  4: u32 BE  format_version                  (observed: 1017..1051,
                                                     mostly 1042 / 1045)
    off  8: u32 BE  count_a                         (unknown)
    off 12: u32 BE  count_b                         (unknown)
    off 16: u32 BE  count_c                         (unknown)
    off 20: u32 BE  count_d                         (unknown)
    off 24: u32 BE  num_assets                      (entries that follow)
    off 28: num_assets × (u16 marker, u16 str_len, ascii name)

Beyond the asset manifest the file contains:
  * a sparse slot/actor table region (mostly zeros with 12-byte records
    scattered at fixed offsets -- layout not yet decoded), then
  * a dense script section (variable-length opcode stream) that ends at
    `file_size`.

This module currently exposes only the header + manifest reader. The
script section is handled by event_parser.py.
"""
from __future__ import annotations

import os
import struct


# Event bins ship inside the Godot project's town_data tree, one folder per
# event id, alongside the map data. (This previously pointed at a
# memorial-assets extraction path under tools/, which doesn't exist in the
# repo, so every lookup returned None.)
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVENT_ASSET_ROOT = os.path.join(REPO_ROOT, "godot", "assets", "town_data")


def event_bin_path(event_id):
    """Resolve `<event_id>` to the absolute path of its `*_event.bin`,
    or return None if not found.
    """
    event_id = str(event_id)
    folder = os.path.join(EVENT_ASSET_ROOT, event_id)
    if not os.path.isdir(folder):
        return None
    candidate = os.path.join(folder, f"{event_id}_event.bin")
    if os.path.isfile(candidate):
        return candidate
    return None


def default_blueprint_path(bin_path):
    """Where to write the blueprint for `bin_path`.

    A folder can hold several event bins -- 136 of the 502 are named for an
    event other than their folder (e.g. `111020201/111020101_event.bin`). The
    bin whose name matches its folder keeps the canonical
    `event_blueprint.json` that `event_runner.gd` loads by folder id; the others
    would otherwise overwrite it, so they get an id-qualified name.
    """
    folder = os.path.dirname(os.path.abspath(bin_path))
    basename = os.path.basename(bin_path)
    if basename.endswith("_event.bin"):
        event_id = basename[:-len("_event.bin")]
        if event_id != os.path.basename(folder):
            return os.path.join(folder, f"{event_id}_event_blueprint.json")
    return os.path.join(folder, "event_blueprint.json")


# Builds from 1023 onwards carry an extra metadata word (`count_d`) before
# the asset count, making the header 28 bytes instead of 24. The split is
# clean across the corpus: no format_version appears on both sides of it.
HEADER_COUNT_D_MIN_VERSION = 1023


def read_event_header(f):
    """Read the fixed header. Leaves `f` positioned at the first byte of
    the asset manifest -- 24 or 28 in, depending on `format_version`.

    Returns a dict with the verified `file_size`, the verbatim metadata
    words, and the asset count that drives the manifest reader. On the
    older layout `count_d` is None.
    """
    f.seek(0)
    raw = f.read(28)
    if len(raw) < 24:
        raise ValueError("File too small for the event header")
    version = struct.unpack_from(">I", raw, 4)[0]
    if version < HEADER_COUNT_D_MIN_VERSION:
        fields = struct.unpack_from(">6I", raw, 0)
        f.seek(24)
        return {
            "file_size": fields[0],
            "format_version": fields[1],
            "count_a": fields[2],
            "count_b": fields[3],
            "count_c": fields[4],
            "count_d": None,
            "num_assets": fields[5],
            "header_size": 24,
        }
    if len(raw) < 28:
        raise ValueError("File too small for 28-byte event header")
    fields = struct.unpack(">7I", raw)
    f.seek(28)
    return {
        "file_size": fields[0],
        "format_version": fields[1],
        "count_a": fields[2],
        "count_b": fields[3],
        "count_c": fields[4],
        "count_d": fields[5],
        "num_assets": fields[6],
        "header_size": 28,
    }


def read_asset_manifest(f, num_assets):
    """Read `num_assets` `(marker, str_len, name)` entries.

    Each entry stores a u16 marker (per-file asset slot id, e.g. 0x7919
    for the first NPC sprite reference) followed by a u16 string length
    and a raw ASCII filename. Leaves `f` positioned at the byte
    immediately after the manifest.
    """
    assets = []
    for slot_index in range(num_assets):
        marker, str_len = struct.unpack(">HH", f.read(4))
        if str_len == 0 or str_len > 256:
            raise ValueError(
                f"Asset slot {slot_index} has implausible str_len={str_len}"
            )
        name = f.read(str_len).decode("ascii", errors="replace")
        assets.append({
            "slot_index": slot_index,
            "marker": marker,
            "filename": name,
        })
    return assets


def read_header_and_manifest(f):
    """Convenience: read header + manifest, return both plus the byte
    offset where the manifest ends (== start of the rest of the file)."""
    header = read_event_header(f)
    assets = read_asset_manifest(f, header["num_assets"])
    manifest_end_offset = f.tell()
    return {
        "header": header,
        "assets": assets,
        "manifest_end_offset": manifest_end_offset,
    }
