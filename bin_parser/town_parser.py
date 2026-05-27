import struct
import json
import os
import math
import sys

import bin_common
from bin_common import TOWN_DATA_ROOT


def _split_scripted_payload(payload):
    """Decompose a scripted_entity payload into named unknown_N fields.

    The first 24 bytes have a stable layout across all observed
    visible-NPC records; bytes 6-9 are the sprite_id (handled by the
    caller). After offset 24, the record consists of chained TLV-style
    sub-blocks whose total size is `tag_byte + 1`. Each tail block
    typically has the shape `[tag][08 00 04][u32 value][trailer...]`.

    Returns a dict of hex-string fields. Trigger records (no valid
    sprite) get the raw u32 at offset 6-9 as `unknown_id_hex` so the
    bytes are still visible for pattern-hunting.
    """
    out = {}
    n = len(payload)

    def _hex(a, b):
        if a >= n:
            return None
        return payload[a:min(b, n)].hex().upper()

    out["unknown_1"]  = _hex(0,  2)   # class tag (00BA / 00C8)
    out["unknown_2"]  = _hex(2,  4)   # always 0101 so far
    out["unknown_3"]  = _hex(4,  6)   # varies (0101 / 0201 / 0010)
    # bytes 6-9 = sprite_or_event_id, handled by caller
    out["unknown_4"]  = _hex(10, 14)  # usually zeros
    out["unknown_5"]  = _hex(14, 16)  # 0104 / 0004
    out["unknown_6"]  = _hex(16, 17)  # usually 14
    out["unknown_7"]  = _hex(17, 18)  # flag
    out["unknown_8"]  = _hex(18, 19)  # flag
    out["unknown_9"]  = _hex(19, 23)  # 4 bytes flag block
    out["unknown_10"] = _hex(23, 24)  # 1 byte
    # The tail begins at a `[tag][08 00 04][u32]` marker. Bytes
    # between the fixed prefix and that marker form a variable
    # scratch/event-id region (often `01 01 31 58 XX 01 00 00 00`
    # on records that carry a per-instance event id). Locate the
    # first valid marker and split there.
    tail_start = None
    for off in range(24, n - 7):
        tag = payload[off]
        size = tag + 1
        if (size >= 8 and off + size <= n
                and payload[off + 1:off + 4] == b"\x08\x00\x04"):
            tail_start = off
            break
    if tail_start is None:
        tail_start = n  # no tail markers found
    out["unknown_11"] = payload[24:tail_start].hex().upper() or None

    # Parse chained tail blocks starting from the first marker. Each
    # block's total size equals tag_byte + 1; subsequent blocks may
    # be plain bytes when they don't carry the `08 00 04` marker.
    tail_blocks = []
    off = tail_start
    while off < n:
        tag = payload[off]
        size = tag + 1
        if size < 1 or off + size > n:
            tail_blocks.append({"unparsed_hex": payload[off:].hex().upper()})
            break
        block_bytes = payload[off:off + size]
        block = {
            "tag_hex": f"{tag:02X}",
            "size": size,
        }
        # Recognized shape: [tag][08 00 04][u32][trailer...]
        if size >= 8 and block_bytes[1:4] == b"\x08\x00\x04":
            val = struct.unpack(">I", block_bytes[4:8])[0]
            block["marker"] = "08 00 04"
            block["u32_hex"] = f"{val:08X}"
            block["u32_int"] = val
            if size > 8:
                block["trailer_hex"] = block_bytes[8:].hex().upper()
        else:
            block["body_hex"] = block_bytes[1:].hex().upper()
        tail_blocks.append(block)
        off += size

    out["tail_blocks"] = tail_blocks
    # Drop None entries (records shorter than the full prefix)
    return {k: v for k, v in out.items() if v is not None}


def _decode_scripted_entities(blueprint):
    """Pure-bin post-processor for scripted_entity records (type 0x01).

    Extracts everything the parser knows about each record FROM THE
    BIN BYTES ALONE: the sprite_id (or raw id_hex for trigger
    records), the dialogue_line_id (the last `[tag][08 00 04][u32]`
    tail block's u32 value), and the named unknown_N fields produced
    by `_split_scripted_payload`. Does NOT consult external files
    like `map_teller.txt` or `map_text.txt`; frontends are
    responsible for joining those.
    """
    for layer in blueprint.get("layers", []):
        for ent in layer.get("objects", {}).get("dynamic_entities", []):
            if ent.get("kind") != "scripted_entity":
                continue
            payload_hex = ent.get("payload_hex", "")
            if not payload_hex:
                continue
            try:
                payload = bytes.fromhex(payload_hex)
            except ValueError:
                continue
            # Sprite/NPC ID is a u32 BE at payload offset 6. Values
            # in the ~100000000 - 900300000 range correspond to
            # `npc<id>.png` filenames. Outside that range the bytes
            # encode some other id (script/event) which we expose
            # verbatim as `unknown_id_hex`.
            if len(payload) >= 10:
                sprite_id = struct.unpack(">I", payload[6:10])[0]
                if 100_000_000 <= sprite_id <= 900_300_000:
                    ent["sprite_id"] = sprite_id
                else:
                    ent["unknown_id_hex"] = payload[6:10].hex().upper()
            # Split the rest of the payload into atomic named fields
            # so unknown bytes can be pattern-hunted by the frontend.
            ent.update(_split_scripted_payload(payload))
            # Structural extraction of dialogue_line_id: take the
            # LAST tail block carrying the `08 00 04` marker (large
            # records can chain multiple dialogue blocks; the final
            # one is the primary line per current observation).
            for block in reversed(ent.get("tail_blocks", [])):
                if block.get("marker") == "08 00 04":
                    ent["dialogue_line_id"] = block["u32_int"]
                    break
            # Drop the now-redundant raw payload dump.
            ent.pop("payload_hex", None)


def parse_ffbe_map(file_path, output_path=None, pre_parsed=None):
    """Parse an FFBE map.bin into a blueprint JSON.

    When `pre_parsed` is None (default) this parses a town v1 file from
    scratch: 32-byte file header, texture manifest, u32 total_chunks,
    then chunks until EOF.

    When `pre_parsed` is supplied (used by `exploration_parser`) the
    caller has already read the shared prefix and any v2-specific
    preamble; this function reuses the chunk-decoding loop only. The
    dict must contain:
        * blueprint              -- partially-filled output dict; this
                                    function will append to its
                                    `layers` list.
        * chunk_stream_start     -- byte offset where chunks begin.
        * file_end_offset        -- byte offset where chunks end (EOF
                                    for both variants in practice).
        * total_chunks_hint      -- optional cap; loop stops early once
                                    this many chunks have been parsed.
    """
    if not os.path.exists(file_path):
        print(f"Error: Could not find {file_path}")
        return
    # Default the blueprint output to live next to the bin so a town's
    # folder stays self-contained.
    if output_path is None:
        output_path = os.path.join(os.path.dirname(os.path.abspath(file_path)),
                                   "map_blueprint.json")

    with open(file_path, "rb") as f:
        if pre_parsed is None:
            blueprint = {}
            print("--- PARSING BINARY HEADER ---")
            # Pull the three confirmed spawn fields from bytes 0x08/0x0C/0x10
            # before continuing with the existing manifest read at 0x1C.
            f.seek(8)
            initial_layer_id = struct.unpack(">I", f.read(4))[0]
            initial_player_x = struct.unpack(">I", f.read(4))[0]
            initial_player_y = struct.unpack(">I", f.read(4))[0]
            blueprint["initial_layer_id"] = initial_layer_id
            blueprint["initial_player_x"] = initial_player_x
            blueprint["initial_player_y"] = initial_player_y
            print(f"Spawn: layer_id={initial_layer_id} at "
                  f"({initial_player_x}, {initial_player_y}).")
            f.seek(28)

            num_textures = struct.unpack(">I", f.read(4))[0]
            blueprint["num_textures"] = num_textures
            blueprint["textures"] = []

            for _ in range(num_textures):
                atlas_id = struct.unpack(">H", f.read(2))[0]
                str_len = struct.unpack(">H", f.read(2))[0]
                filename = f.read(str_len).decode("ascii")
                blueprint["textures"].append({
                    "atlas_id": atlas_id,
                    "filename": filename
                })

            total_chunks = struct.unpack(">I", f.read(4))[0]
            blueprint["total_chunks"] = total_chunks
            blueprint["layers"] = []

            file_end_offset = os.fstat(f.fileno()).st_size
            total_chunks_hint = total_chunks
            print(f"Manifest ends. Engine declares {total_chunks} map chunks.")
        else:
            blueprint = pre_parsed["blueprint"]
            blueprint.setdefault("layers", [])
            f.seek(pre_parsed["chunk_stream_start"])
            file_end_offset = pre_parsed["file_end_offset"]
            total_chunks_hint = pre_parsed.get("total_chunks_hint")
            print(f"Exploration v2 preamble supplied; walking chunks until {file_end_offset:#x}.")

        print("--- PARSING TILE GRIDS ---")

        i = 0
        while f.tell() < file_end_offset:
            if total_chunks_hint is not None and i >= total_chunks_hint:
                break
            header_start_offset = f.tell()

            # 16-Byte Header
            chunk_size = struct.unpack(">I", f.read(4))[0]
            layer_id = struct.unpack(">H", f.read(2))[0]
            sep1 = struct.unpack(">H", f.read(2))[0]
            asset_id = struct.unpack(">H", f.read(2))[0]
            grid_width = struct.unpack(">H", f.read(2))[0]
            grid_height = struct.unpack(">H", f.read(2))[0]
            end_flag = struct.unpack(">H", f.read(2))[0]

            data_start_offset = f.tell()
            chunk_end_offset = header_start_offset + chunk_size
            
            grid_tile_count = grid_width * grid_height
            visual_layer_size = grid_tile_count * 4
            single_byte_layer_size = grid_tile_count * 1
            
            # Math handles the visual layer count dynamically
            available_tile_space = chunk_size - 16 - (single_byte_layer_size * 2)
            visual_layer_count = max(0, math.floor(available_tile_space / visual_layer_size))
            
            current_offset = data_start_offset
            sub_layers = []

            # --- THE PADDING VACUUM ---
            # Inter-visual gap consists of 0..3 \x00 padding bytes optionally
            # followed by a \x01 separator. The gap may also be empty (0 bytes)
            # when the next visual layer is itself an all-zero layer that
            # starts immediately at the previous layer's end (chunk 26 / lid
            # 110 is the canonical example: vis 4 spans 0x1f0ba5..0x1f25e8
            # and is entirely zero/0xFF data with no separator).
            #
            # We can't use "ran into too many zeros" as a signal that the
            # formula over-counted, because the next visual layer might
            # genuinely begin with a long run of zeros. Instead, trust the
            # formula: if budget is exhausted, commit to "0 separator bytes"
            # and let the next visual layer start immediately. If the formula
            # really over-counted, the resulting objects section will fail to
            # parse and we fall back -- same outcome as bailing out here.
            MAX_SEPARATOR_GAP = 3
            def consume_separator():
                """Eat 0..MAX_SEPARATOR_GAP \x00 bytes then an optional \x01 separator.
                Returns (bytes_consumed, ok=True) in all cases:
                - Found \x01 separator       -> (N+1, True)
                - Hit non-zero non-\x01 byte -> seek back 1, return (N, True)
                - Ate MAX_SEPARATOR_GAP zeros without resolving -> seek back
                  to start, return (0, True). This covers the "next visual
                  layer is all zeros and there is no separator" case."""
                start = f.tell()
                consumed = 0
                while consumed <= MAX_SEPARATOR_GAP:
                    peek = f.read(1)
                    if not peek:
                        break
                    if peek == b'\x01':
                        return consumed + 1, True
                    if peek == b'\x00':
                        consumed += 1
                        continue
                    # Non-padding, non-separator byte: next layer begins here.
                    f.seek(-1, os.SEEK_CUR)
                    return consumed, True
                # Budget exhausted: commit to zero-byte gap. Next visual layer
                # starts immediately at the previous layer's end.
                f.seek(start)
                return 0, True

            # 1. Map the Visual Layers
            # --- PRE-VISUAL SEPARATOR ---
            # A few chunks (e.g. layer_ids 127/128 in this corpus) place a
            # small inter-section gap *before* the first visual layer too:
            # up to 3 \x00 bytes optionally followed by a \x01 separator,
            # exactly matching the inter-visual gap format. For most chunks
            # this gap is empty (consume_separator finds no zero / no \x01
            # and seeks back). Only when the bytes are literally
            # `\x00*\x01` does the cursor advance; that keeps the rest of
            # the structure aligned for chunks that need it without
            # disturbing well-aligned chunks.
            consumed_pre, _ok_pre = consume_separator()
            if consumed_pre:
                current_offset = data_start_offset + consumed_pre

            actual_visual_count = 0
            for v in range(visual_layer_count):
                layer_start = current_offset
                layer_end_exclusive = layer_start + visual_layer_size

                # Safety: don't claim a visual layer that would extend past the chunk
                if layer_end_exclusive > chunk_end_offset:
                    break

                sub_layers.append({
                    "type": "visual",
                    "index": v,
                    "start_hex": hex(layer_start),
                    "end_hex_inclusive": hex(layer_end_exclusive - 1)
                })
                actual_visual_count = v + 1

                f.seek(layer_end_exclusive)

                # Check for padding and separator if NOT the last visual layer
                if v < visual_layer_count - 1:
                    consumed, ok = consume_separator()
                    if not ok:
                        # Budget exhausted -> formula over-counted; stop here.
                        current_offset = layer_end_exclusive
                        break
                    current_offset = layer_end_exclusive + consumed
                else:
                    current_offset = layer_end_exclusive

            visual_layer_count = actual_visual_count
                        
            # 2. Map the Collision Layer
            col_start = current_offset
            col_end_exclusive = col_start + single_byte_layer_size
            sub_layers.append({
                "type": "collision", 
                "index": visual_layer_count,
                "start_hex": hex(col_start), 
                "end_hex_inclusive": hex(col_end_exclusive - 1)
            })
            current_offset = col_end_exclusive
            
            # 3. Map the Region Layer
            reg_start = current_offset
            reg_end_exclusive = reg_start + single_byte_layer_size
            sub_layers.append({
                "type": "region", 
                "index": visual_layer_count + 1,
                "start_hex": hex(reg_start), 
                "end_hex_inclusive": hex(reg_end_exclusive - 1)
            })
            current_offset = reg_end_exclusive

            # --- OBJECTS SECTION PARSER (correct schema) ---
            # Schema after region layer:
            #   u32 ge_count + ge_count * 9 bytes  (x:u32, y:u32, event_id:u8)
            #   u16 ge_trailer (always 0x0000)
            #   u32 sa_count + sa_count * 27 bytes (x,y u32; w,h,z,atlas,sprite u16; params 9b)
            #   u16 de_count + de records dispatched by type byte @+0x04:
            #       0x0F -> 62 bytes (all warp variants, distinguished by sub_variant:
            #               0x01=entrance, 0x02=overworld doorway, 0x03=exit,
            #               0x04=alt doorway; 0x00 only seen in chunk 18's
            #               partial-walk misaligned records)
            #       0x01 -> 64 bytes (scripted entity / metadata)
            #   Optional trailing bytes (4-byte tail seen in some chunks)
            grid_events = []
            static_assets = []
            dynamic_entities = []
            objects_parse_status = "ok"
            objects_trailing_hex = ""
            objects_raw_hex_fallback = ""

            obj_start = current_offset
            obj_space = chunk_end_offset - obj_start

            # Per-section byte ranges (filled in as we parse). Each is a dict
            # with start_hex (inclusive) and end_hex_inclusive once the section
            # is successfully read. Missing on fallback.
            section_ranges = {}

            def _record_range(name, start, end_exclusive):
                if end_exclusive <= start:
                    return
                section_ranges[name] = {
                    "start_hex": hex(start),
                    "end_hex_inclusive": hex(end_exclusive - 1),
                    "size_bytes": end_exclusive - start,
                }

            def _read_warp_record(rec_bytes, rec_id, payload=None, rec_start=0):
                # Type-0x0F warp record. Two physical layouts coexist:
                #
                #   * Simple 62-byte form (used by chunks 5..17, 19..35):
                #     target_lid is the u32 BE at +0x2C, target_x/y at
                #     +0x30/+0x34, sub_variant at +0x38.
                #
                #   * Extended form (78/83/100 B, used inside chunk 18 --
                #     the central hub):  the trailer is offset by 0x14+
                #     bytes because an "intermediate lid" block has been
                #     inserted after the marker_0x64 metadata.
                #
                # Both layouts share the marker `05 00 0F` immediately
                # before the real target_lid / target_x / target_y / sub
                # fields, so we locate it by searching from byte +0x10 to
                # skip the type byte at +0x04. Verified against video of
                # the in-game town for 6 chunk-18 warps + chunk 16 rid=1
                # + chunk 18 rid=12 (the "warp_zone 10" the user
                # confirmed correct).
                src_x_px   = struct.unpack(">I", rec_bytes[0x05:0x09])[0]
                src_y_px   = struct.unpack(">I", rec_bytes[0x09:0x0D])[0]
                width_px   = struct.unpack(">H", rec_bytes[0x0D:0x0F])[0]
                height_px  = struct.unpack(">H", rec_bytes[0x0F:0x11])[0]
                marker_0x1A = rec_bytes[0x1A] if len(rec_bytes) > 0x1A else 0

                # Search the slice first. If the trailer doesn't fit
                # (chunk-18 extended records, 78+B, where the DE walker
                # picked the shorter 62B length), fall back to searching
                # the surrounding payload up to 120B past rec_start so
                # we still recover the correct target.
                trailer_pos = rec_bytes.find(b"\x05\x00\x0F", 0x10)
                trailer_src = rec_bytes
                trailer_base = 0
                if (trailer_pos < 0 or trailer_pos + 16 > len(rec_bytes)) and payload is not None:
                    scan_end = min(rec_start + 120, len(payload))
                    abs_pos = payload.find(b"\x05\x00\x0F", rec_start + 0x10, scan_end)
                    if abs_pos >= 0 and abs_pos + 16 <= len(payload):
                        trailer_pos = abs_pos - rec_start
                        trailer_src = payload
                        trailer_base = rec_start
                if trailer_pos >= 0:
                    tp = trailer_base + trailer_pos
                    target_lid = struct.unpack(">I", trailer_src[tp+3:tp+7])[0]
                    target_x   = struct.unpack(">I", trailer_src[tp+7:tp+11])[0]
                    target_y   = struct.unpack(">I", trailer_src[tp+11:tp+15])[0]
                    sub_variant = trailer_src[tp+15]
                    trailer_off_hex = f"0x{trailer_pos:X}"
                else:
                    # Fallback: assume strict 62-byte layout (kept for
                    # malformed records so we at least return *something*).
                    target_lid = struct.unpack(">I", rec_bytes[0x2C:0x30])[0]
                    target_x   = struct.unpack(">I", rec_bytes[0x30:0x34])[0]
                    target_y   = struct.unpack(">I", rec_bytes[0x34:0x38])[0]
                    sub_variant = rec_bytes[0x38] if len(rec_bytes) > 0x38 else 0
                    trailer_off_hex = "none"

                # Empirical sub_variant taxonomy (verified against in-game
                # video of the town and cross-checked target_lid/x/y values):
                #   0x00 -> only appears in chunk 18's partial-walk output
                #          where records are misaligned; treat as suspect.
                #   0x01 -> standard entrance warp
                #   0x02 -> overworld / inter-zone doorway
                #   0x03 -> exit warp (previously mislabeled "chest";
                #          the user confirmed chunk 21 rid=1 is a warp to
                #          lid 104, not a treasure chest. All 7 sub=3
                #          records have plausible warp targets.)
                #   0x04 -> alternate doorway (room-to-room shortcut)
                kind = {
                    0x00: "warp_suspect",
                    0x01: "warp",
                    0x02: "warp_zone",
                    0x03: "warp_exit",
                    0x04: "warp_alt",
                }.get(sub_variant, f"warp_unknown_0x{sub_variant:02X}")
                return {
                    "record_id": rec_id,
                    "record_type": "0x0F",
                    "kind": kind,
                    "source_x_px": src_x_px,
                    "source_y_px": src_y_px,
                    "width_px": width_px,
                    "height_px": height_px,
                    "target_lid": target_lid,
                    "marker_0x1A": marker_0x1A,
                    "trailer_offset": trailer_off_hex,
                    "target_x": target_x,
                    "target_y": target_y,
                    "sub_variant": sub_variant,
                    "raw_hex": rec_bytes.hex().upper(),
                }

            # Common 25-byte DE header shared by every observed record type.
            # See de_footprint_scan.py for derivation. The 16 bytes after the
            # header are either zero-trailer (41-byte minimal record) or the
            # start of a type-specific payload.
            #   0..3   u32 record_id (1-based, increments per record)
            #   4      u8  record_type
            #   5..8   u32 source_x_px
            #   9..12  u32 source_y_px
            #   13..14 u16 width_px  (almost always 0x003A = 58)
            #   15..16 u16 height_px (almost always 0x003A = 58)
            #   17..24 8B  target/extra (warps fill; minimal records zero)
            # Types confirmed to use ONLY the 41-byte minimal layout in our
            # corpus (header + 16-byte zero trailer):
            MINIMAL_DE_TYPES = {0x04, 0x05, 0x06, 0x07, 0x10, 0x11, 0x16, 0x18}

            # Printable ASCII range used for Pascal-string detection in
            # variable DE payloads. Excludes whitespace/control chars.
            _PRINTABLE_BYTES = set(range(0x20, 0x7F))

            def _extract_pascal_strings(buf, min_len=3, max_len=64):
                """Find <u8 len><ascii bytes> Pascal-style strings inside buf.
                Returns list of {"offset_in_payload": int, "text": str}.
                Used to surface embedded animation/effect references
                (e.g. 'map_effect.ssbp', 'room_shadow/anime') in DE records."""
                out = []
                i = 0
                while i < len(buf):
                    n = buf[i]
                    if min_len <= n <= max_len and i + 1 + n <= len(buf):
                        s = buf[i + 1:i + 1 + n]
                        if all(b in _PRINTABLE_BYTES for b in s):
                            out.append({
                                "offset_in_payload": i,
                                "text": s.decode("ascii"),
                            })
                            i += 1 + n
                            continue
                    i += 1
                return out

            def _decode_common_header(rec_bytes, rec_id, rec_type):
                if len(rec_bytes) < 25:
                    return {
                        "record_id": rec_id,
                        "record_type": f"0x{rec_type:02X}",
                        "kind": "truncated",
                    }
                src_x_px  = struct.unpack(">I", rec_bytes[5:9])[0]
                src_y_px  = struct.unpack(">I", rec_bytes[9:13])[0]
                width_px  = struct.unpack(">H", rec_bytes[13:15])[0]
                height_px = struct.unpack(">H", rec_bytes[15:17])[0]
                extra8    = rec_bytes[17:25].hex().upper()
                return {
                    "record_id": rec_id,
                    "record_type": f"0x{rec_type:02X}",
                    "source_x_px": src_x_px,
                    "source_y_px": src_y_px,
                    "width_px": width_px,
                    "height_px": height_px,
                    "extra8_hex": extra8,
                }

            # --- DE record length table ---
            # Known record_type bytes. The walker does NOT use hardcoded
            # record lengths -- different towns use wildly different lengths
            # for the same record_type (e.g. type 0x01 in 111020200 uses
            # lengths [54,58,65,68,70,73,82,122,132,198] while 111020100
            # uses [63,71,129]). Instead, lengths are inferred structurally
            # by locating the next plausible record header in the payload.
            DE_KNOWN_TYPES = {
                0x00, 0x01, 0x02, 0x04, 0x05, 0x06, 0x07, 0x08,
                0x0F, 0x10, 0x11, 0x12, 0x14, 0x16, 0x18, 0x1B,
            }
            # Per-type minimum record length (the fixed 17-byte header +
            # 8-byte extra block is 25 bytes; some types observed to need
            # more before the next record can begin).
            DE_MIN_LEN_BY_TYPE = {
                0x00: 36, 0x01: 54, 0x02: 70,
                0x04: 41, 0x05: 41, 0x06: 41, 0x07: 41,
                0x08: 41, 0x10: 41, 0x11: 41, 0x14: 46,
                0x16: 41, 0x18: 41, 0x0F: 59, 0x12: 117,
                0x1B: 51,
            }
            DE_MIN_REC_LEN = 25  # safety floor: never accept a shorter record

            def _de_header_at(payload, off, seen_now, rid_cap):
                """Return True if `off` looks like the start of a DE record
                header (u32 rid, u8 known type, plausible w/h, unique rid).
                The caller supplies the rid plausibility bound. Real records
                use small entity IDs near the chunk's de_count, while
                false-positive headers tend to land on bytes that decode as
                huge u32 values.

                Stricter coord/tile-alignment checks reject ghost headers
                whose bytes happen to decode to plausible-looking u32 rid
                and u8 type but whose source coords or width/height fail
                the half-tile alignment (multiple of 29 = 0x1D) and chunk
                pixel-extent constraints. This filters out byte patterns
                like `00 00 00 7F 06 00 07 00 0B ...` that previously
                minted phantom rid=127 / rid=261 records inside the
                payload of real string-bearing records."""
                if off + 25 > len(payload):
                    return False
                rid = struct.unpack(">I", payload[off:off+4])[0]
                rt = payload[off+4]
                if rt not in DE_KNOWN_TYPES:
                    return False
                if rid < 1 or rid > rid_cap or rid in seen_now:
                    return False
                src_x = struct.unpack(">I", payload[off+5:off+9])[0]
                src_y = struct.unpack(">I", payload[off+9:off+13])[0]
                # Chunk pixel extents top out around ~6000 px on either
                # axis in this corpus; 30000 is a safe ceiling that still
                # rejects ghost coords (typically > 100k).
                if src_x > 30000 or src_y > 30000:
                    return False
                w = struct.unpack(">H", payload[off+13:off+15])[0]
                h = struct.unpack(">H", payload[off+15:off+17])[0]
                if not (1 <= w <= 2048 and 1 <= h <= 2048):
                    return False
                # Real records always have w and h as multiples of 29
                # (half-tile). Ghost records typically don't.
                if w % 29 != 0 or h % 29 != 0:
                    return False
                return True

            def _walk_de_records(payload, count):
                """Walk DE records using pure structural inference.

                Record lengths are NOT taken from a hardcoded table --
                different towns use different lengths for the same
                record_type (see DE_KNOWN_TYPES comment). Instead the walker:

                1. Scans the full payload for every offset that satisfies
                   `_de_header_at` (strict u32 rid + known type + sane
                   coords + half-tile-aligned w/h). Each such offset is a
                   plausible record start.
                2. Walks forward from offset 0, greedily: at each step the
                   next record's start is the earliest candidate at
                   distance >= DE_MIN_LEN_BY_TYPE[current_type] whose rid
                   has not yet been consumed, scored to prefer low rid-
                   frequency (singletons over phantom-id matches) and
                   intact 0x0F trailers.
                3. When no further candidate fits, the current record is
                   treated as the final one and consumes the rest of the
                   payload.

                Returns a list of (start, end_exclusive, rid, type) tuples.
                May return fewer than `count` entries when the bin's
                de_count is greater than the number of structurally
                visible records (the downstream code sets a partial-status
                marker and the chest tail-marker post-scan recovers
                additional entries).
                """
                if count == 0:
                    return []
                if len(payload) < 25:
                    return None

                rid_cap = max(count * 3, 200)

                # 1. Scan all plausible header positions.
                all_cands = []
                for off in range(len(payload) - 24):
                    if _de_header_at(payload, off, frozenset(), rid_cap):
                        rid = struct.unpack(">I", payload[off:off+4])[0]
                        rt = payload[off+4]
                        all_cands.append((off, rid, rt))
                if not all_cands or all_cands[0][0] != 0:
                    return None
                from collections import Counter as _Cnt
                rid_freq = _Cnt(r for _, r, _ in all_cands)

                # 2. Walk forward greedily.
                walked = []
                seen = set()
                pos = 0
                for step in range(count):
                    h = _de_header_at(payload, pos, frozenset(), rid_cap)
                    if not h:
                        break
                    rid = struct.unpack(">I", payload[pos:pos+4])[0]
                    rt = payload[pos+4]
                    if rid in seen:
                        break
                    seen.add(rid)
                    # Last expected record: consume to end of payload.
                    if step == count - 1:
                        walked.append((pos, len(payload), rid, rt))
                        pos = len(payload)
                        break
                    # Find next candidate position.
                    min_next = pos + DE_MIN_LEN_BY_TYPE.get(rt, DE_MIN_REC_LEN)
                    best_next = None
                    best_score = None
                    for n_off, n_rid, n_rt in all_cands:
                        if n_off < min_next:
                            continue
                        if n_off >= len(payload):
                            break
                        if n_rid in seen:
                            continue
                        # Type 0x0F (warp) records must contain the
                        # '05 00 0F' trailer marker within the slice at
                        # offset >= 0x10. Score better when the slice
                        # preserves it.
                        trailer_ok = 1
                        if rt == 0x0F:
                            slice_bytes = payload[pos:n_off]
                            if len(slice_bytes) >= 0x14 and slice_bytes.find(b"\x05\x00\x0F", 0x10) >= 0:
                                trailer_ok = 0
                        score = (trailer_ok, rid_freq[n_rid], n_off - pos)
                        if best_score is None or score < best_score:
                            best_score = score
                            best_next = n_off
                    if best_next is None:
                        # No more candidates -> current record is the
                        # last structurally-visible one. Consume rest.
                        walked.append((pos, len(payload), rid, rt))
                        pos = len(payload)
                        break
                    walked.append((pos, best_next, rid, rt))
                    pos = best_next

                # Return whatever was walked (downstream handles partial).
                # Returning None only when zero records were recovered so
                # callers can distinguish "no walk possible" from "partial".
                if not walked:
                    return None
                return walked

            try:
                if obj_space < 12:
                    raise ValueError(f"only {obj_space} bytes after region (need >=12 for empty objects section)")

                f.seek(obj_start)

                # --- Grid events section: u32 ge_count + ge_count*9B records + u16 ge_trailer ---
                ge_section_start = f.tell()
                ge_count = struct.unpack(">I", f.read(4))[0]
                if ge_count > 5000:
                    raise ValueError(f"ge_count={ge_count} insane")
                if f.tell() + ge_count * 9 > chunk_end_offset:
                    raise ValueError("grid_events overflow chunk")
                for _ in range(ge_count):
                    gx, gy, gevent = struct.unpack(">IIB", f.read(9))
                    grid_events.append({"x": gx, "y": gy, "event_id": gevent})

                if f.tell() + 2 > chunk_end_offset:
                    raise ValueError("eof at ge_trailer")
                ge_trailer = struct.unpack(">H", f.read(2))[0]
                _record_range("grid_events_section", ge_section_start, f.tell())

                # --- Static assets section: u32 sa_count + sa_count*27B records ---
                sa_section_start = f.tell()
                if f.tell() + 4 > chunk_end_offset:
                    raise ValueError("eof at sa_count")
                sa_count = struct.unpack(">I", f.read(4))[0]
                if sa_count > 5000:
                    raise ValueError(f"sa_count={sa_count} insane")
                if f.tell() + sa_count * 27 > chunk_end_offset:
                    raise ValueError("static_assets overflow chunk")
                for _ in range(sa_count):
                    rec = f.read(27)
                    # Static-asset record layout (27 bytes, all big-endian):
                    #   [0:4]   u32  map_x_px       — blit destination on the map
                    #   [4:8]   u32  map_y_px
                    #   [8:10]  u16  width_px       — usually multiple of 58
                    #   [10:12] u16  height_px
                    #   [12:14] u16  render_flag    — always 1 in this corpus
                    #   [14:16] u16  atlas_id       — external sprite atlas id
                    #                                  (10000-20039 range; cf.
                    #                                  mapchip_xxxx_yyy.png files)
                    #   [16:18] u16  atlas_x_px     — source X inside atlas
                    #                                  (99.8% multiples of 58)
                    #   [18:20] u16  atlas_y_px     — source Y inside atlas
                    #                                  (99.9% multiples of 29)
                    #   [20:22] u16  flags_a        — observed values: 0, 259, 260
                    #   [22:24] u16  variant_word   — packed: low byte = layer
                    #                                  (0..3), high byte =
                    #                                  layer_flags (observed
                    #                                  values: 0, 10, 12, 15)
                    #   [24:26] u16  flags_c        — observed values: 0, 256
                    #   [26]    u8   scale_pct      — render scale percent
                    #                                  (100 = 1.0x, 150 = 1.5x).
                    #                                  Other observed values:
                    #                                  50, 70, 80, 85, 90, 200.
                    #
                    # The previous parser called atlas_x_px "sprite_id" which
                    # mis-led the renderer into using pixel coordinates as
                    # opaque ids. Corrected after user observation that the
                    # same "sprite_id" placed unrelated tiles on the map.
                    (sx, sy, sw, sh, srflag, satlas,
                     satlas_x, satlas_y, sflags_a, svariant_word,
                     sflags_c, sscale) = struct.unpack(
                        ">IIHHHHHHHHHB", rec)
                    # Split the u16 "variant_word" into its two bytes. The
                    # low byte (always 0..3 in observed data) tells the
                    # renderer which visual sub-layer the asset belongs to.
                    # The high byte is non-zero only on a handful of
                    # records (values 10/12/15) and is exposed as
                    # "layer_flags" so we can investigate it later.
                    slayer = svariant_word & 0xFF
                    slayer_flags = (svariant_word >> 8) & 0xFF
                    static_assets.append({
                        "x": sx, "y": sy, "width": sw, "height": sh,
                        "render_flag": srflag,
                        "atlas_id": satlas,
                        "atlas_x": satlas_x,
                        "atlas_y": satlas_y,
                        "flags_a": sflags_a,
                        "layer": slayer,
                        "layer_flags": slayer_flags,
                        "flags_c": sflags_c,
                        "scale": sscale,
                    })
                _record_range("static_assets_section", sa_section_start, f.tell())

                # --- Dynamic entities section: u16 de_count + variable-length records ---
                de_section_start = f.tell()
                if f.tell() + 2 > chunk_end_offset:
                    raise ValueError("eof at de_count")
                de_count = struct.unpack(">H", f.read(2))[0]
                if de_count > 5000:
                    raise ValueError(f"de_count={de_count} insane")

                # Read the entire DE payload (everything after de_count up to
                # chunk_end) and walk records using known type-specific
                # length tables + DFS-with-backtracking. See _walk_de_records
                # docstring for rationale. The old assumption that record_ids
                # were strictly +1 sequential was wrong; the new walker
                # handles arbitrary rid orderings.
                de_payload_start = f.tell()
                de_payload = f.read(chunk_end_offset - de_payload_start)
                de_partial_status = None

                if de_count == 0:
                    pass
                else:
                    boundaries = _walk_de_records(de_payload, de_count)
                    if boundaries is None:
                        de_partial_status = (
                            f"de walk failed (decoded 0 of {de_count})"
                        )
                    else:
                        if len(boundaries) < de_count:
                            de_partial_status = (
                                f"de walk partial (decoded {len(boundaries)} of {de_count})"
                            )
                        for k, (s, e, _walk_rid, _walk_rt) in enumerate(boundaries):
                            rec_bytes = de_payload[s:e]
                            rec_len = len(rec_bytes)
                            if rec_len < 5:
                                de_partial_status = (
                                    f"de rec {k} truncated to {rec_len}B "
                                    f"(decoded {k} of {de_count})"
                                )
                                break
                            rec_id = struct.unpack(">I", rec_bytes[:4])[0]
                            rec_type = rec_bytes[4]
                            abs_start = de_payload_start + s
                            abs_end_incl = de_payload_start + e - 1

                            # type 0x0F = chest/warp (59B or 62B variant; the
                            # extra 3 bytes in the 62B form are trailing flags
                            # the decoder doesn't read)
                            if rec_type == 0x0F and rec_len >= 57:
                                # Don't cap rec_bytes -- extended chunk-18
                                # records are 78/83/100B and the trailer
                                # sits past byte 62. Pass payload + start
                                # so the decoder can look beyond the slice.
                                entity = _read_warp_record(
                                    rec_bytes.ljust(62, b'\x00'), rec_id,
                                    payload=de_payload, rec_start=s,
                                )
                                entity["length_bytes"] = rec_len
                                entity["start_hex"] = hex(abs_start)
                                entity["end_hex_inclusive"] = hex(abs_end_incl)
                                dynamic_entities.append(entity)
                                # Recover absorbed warp records: when the
                                # DE walker collapsed N adjacent warps into
                                # one slice (chunk 18 partial walks), this
                                # slice contains multiple `05 00 0F`
                                # trailer markers. Each additional marker
                                # corresponds to another physical warp
                                # whose header begins at trailer_pos-0x3C
                                # (extended) or -0x29 (simple). Walk
                                # forward, splitting on every additional
                                # trailer, and emit synthetic records.
                                first_trailer = rec_bytes.find(b"\x05\x00\x0F", 0x10)
                                if first_trailer >= 0:
                                    scan_from = first_trailer + 16
                                    while True:
                                        tp = rec_bytes.find(b"\x05\x00\x0F", scan_from)
                                        if tp < 0 or tp + 16 > rec_len:
                                            break
                                        # Header sits 0x3C bytes before the
                                        # trailer for extended records and
                                        # 0x29 for simple. Try both; pick
                                        # whichever yields a plausible
                                        # type-0x0F header (rt byte == 0x0F
                                        # at hdr+4).
                                        for back in (0x3C, 0x29, 0x41):
                                            hdr = tp - back
                                            if hdr < 0 or hdr + 25 > rec_len:
                                                continue
                                            if rec_bytes[hdr + 4] != 0x0F:
                                                continue
                                            sub_rid = struct.unpack(">I", rec_bytes[hdr:hdr+4])[0]
                                            if sub_rid < 1 or sub_rid > 500:
                                                continue
                                            sub_slice = rec_bytes[hdr:hdr + back + 16 + 2]
                                            sub_entity = _read_warp_record(
                                                sub_slice.ljust(62, b'\x00'), sub_rid,
                                                payload=rec_bytes, rec_start=hdr,
                                            )
                                            sub_entity["length_bytes"] = len(sub_slice)
                                            sub_entity["start_hex"] = hex(abs_start + hdr)
                                            sub_entity["end_hex_inclusive"] = hex(abs_start + hdr + len(sub_slice) - 1)
                                            sub_entity["note"] = (
                                                f"recovered from collapsed parent rid={rec_id} slice via trailer split"
                                            )
                                            dynamic_entities.append(sub_entity)
                                            break
                                        scan_from = tp + 16
                                continue

                            # Common-header decode for all other types
                            entity = _decode_common_header(rec_bytes, rec_id, rec_type)
                            entity["length_bytes"] = rec_len
                            entity["start_hex"] = hex(abs_start)
                            entity["end_hex_inclusive"] = hex(abs_end_incl)

                            if rec_type in MINIMAL_DE_TYPES and rec_len == 41:
                                entity["kind"] = "generic_entity"
                                entity["trailer_hex"] = rec_bytes[25:].hex().upper()
                            elif rec_len == 41:
                                # any type, minimal 41B footprint
                                entity["kind"] = "generic_entity"
                                entity["trailer_hex"] = rec_bytes[25:].hex().upper()
                            elif rec_type == 0x01:
                                entity["kind"] = "scripted_entity"
                                entity["payload_hex"] = rec_bytes[25:].hex().upper()
                            elif rec_type == 0x02 and any(
                                sig in rec_bytes for sig in (
                                    b"\x01\x02\x62", b"\x01\x03\x19\x9C", b"\x01\x03\x0A\x59",
                                )
                            ):
                                # Treasure chest: type=0x02 record carrying
                                # one of the chest signatures. Most towns
                                # also embed a tail marker `4D 00 05 00 10
                                # [u16] 01` whose u16 is an entity_id
                                # (foreign key into an external treasure
                                # table); when present we extract it.
                                # Internal layouts (4th byte = layout marker):
                                #   `01 02 62 84 [s8]` consumables -84
                                #   `01 02 62 85 [s8]` consumables -85
                                #   `01 02 62 8C [s8]` consumables -8C (e.g. 111020300)
                                #   `01 03 19 9C [s8]` equipment / recipes
                                #   `01 03 0A 59 [s8]` equipment / recipes
                                # The [s8] byte is a signed offset such
                                # that entity_id = base + s8.
                                # User-verified mappings for chunk 18:
                                #   ent=0xD0B4 -> Phoenix Down (101003100)
                                #   ent=0xD0B7 -> Smelling Salts (102002100)
                                #   ent=0xD0B8 -> Echo Herbs (102003100)
                                #   ent=0xD0B9 -> Unicorn Horn (102004100)
                                #   ent=0xD0CB -> Recipe for Kenpongi (904000400)
                                entity["kind"] = "chest"
                                for sig in (b"\x01\x02\x62", b"\x01\x03\x19\x9C", b"\x01\x03\x0A\x59"):
                                    m_sig = rec_bytes.find(sig)
                                    if m_sig >= 0:
                                        off_byte_pos = m_sig + len(sig) + (1 if sig == b"\x01\x02\x62" else 0)
                                        # for `01 02 62`, the 4th byte is layout marker (84/85)
                                        # and the 5th byte is the signed offset.
                                        # for `01 03 ...`, the signed offset comes right after.
                                        if off_byte_pos < len(rec_bytes):
                                            b = rec_bytes[off_byte_pos]
                                            entity["chest_offset"] = b - 256 if b >= 0x80 else b
                                        entity["chest_signature"] = sig.hex().upper()
                                        break
                                m_ent = rec_bytes.find(b"\x4D\x00\x05\x00\x10")
                                if m_ent >= 0 and m_ent + 8 <= len(rec_bytes):
                                    entity["entity_id"] = struct.unpack(
                                        ">H", rec_bytes[m_ent + 5:m_ent + 7]
                                    )[0]
                                entity["payload_hex"] = rec_bytes[25:].hex().upper()
                                # Recover absorbed chest records: oversize
                                # slices (rid=51/56/59 in chunk 18) carry
                                # multiple tail markers; emit each one as a
                                # synthetic chest record.
                                scan_from = m_ent + 8 if m_ent >= 0 else 0
                                while True:
                                    mt = rec_bytes.find(b"\x4D\x00\x05\x00\x10", scan_from)
                                    if mt < 0 or mt + 8 > rec_len:
                                        break
                                    if rec_bytes[mt + 7] != 0x01:
                                        scan_from = mt + 1
                                        continue
                                    sub_ent = struct.unpack(">H", rec_bytes[mt + 5:mt + 7])[0]
                                    sub_entity = {
                                        "record_id": rec_id,
                                        "record_type": "0x02",
                                        "kind": "chest",
                                        "entity_id": sub_ent,
                                        "length_bytes": 0,
                                        "start_hex": hex(abs_start + mt),
                                        "end_hex_inclusive": hex(abs_start + mt + 7),
                                        "note": f"recovered from collapsed parent rid={rec_id} via tail-marker split",
                                    }
                                    # Look backward up to 80B for a chest
                                    # signature so we can extract the
                                    # signed-byte chest_offset and the
                                    # source_x/y from the synthetic header
                                    # that precedes this tail.
                                    back_window = rec_bytes[max(0, mt - 100):mt]
                                    for sig in (b"\x01\x02\x62", b"\x01\x03\x19\x9C", b"\x01\x03\x0A\x59"):
                                        bk = back_window.rfind(sig)
                                        if bk >= 0:
                                            off_byte_pos = bk + len(sig) + (1 if sig == b"\x01\x02\x62" else 0)
                                            if off_byte_pos < len(back_window):
                                                b = back_window[off_byte_pos]
                                                sub_entity["chest_offset"] = b - 256 if b >= 0x80 else b
                                            sub_entity["chest_signature"] = sig.hex().upper()
                                            break
                                    # Source coords: a chest record's `003A 003A 003A` width/height
                                    # tag appears ~60B before the tail marker, with the source
                                    # u32 x/y just before it. Try to locate it.
                                    src_pat = b"\x00\x3A\x00\x74\x00\x00\x00\x3A\x00\x3A\x00\x3A"
                                    sp = back_window.rfind(src_pat)
                                    if sp >= 8:
                                        # src x/y u32 BE sit immediately before this pattern
                                        sx = struct.unpack(">I", back_window[sp - 8:sp - 4])[0]
                                        sy = struct.unpack(">I", back_window[sp - 4:sp])[0]
                                        if sx < 100000 and sy < 100000:
                                            sub_entity["source_x_px"] = sx
                                            sub_entity["source_y_px"] = sy
                                    dynamic_entities.append(sub_entity)
                                    scan_from = mt + 8
                            else:
                                entity["kind"] = "unknown"
                                entity["payload_hex"] = rec_bytes[25:].hex().upper()
                                entity["note"] = (
                                    "boundary recovered via record_id scan; "
                                    "internal layout for this type is not yet decoded."
                                )

                            # Surface embedded Pascal-string references
                            # (e.g. 'map_effect.ssbp' animation files).
                            # Scan the post-header payload for length-prefixed
                            # ASCII; if any '.ssbp' filename is found, promote
                            # the kind to 'effect_spawner'.
                            payload = rec_bytes[25:]
                            strs = _extract_pascal_strings(payload)
                            if strs:
                                entity["strings"] = strs
                                if any(s["text"].endswith(".ssbp") for s in strs):
                                    entity["kind"] = "effect_spawner"
                            dynamic_entities.append(entity)

                # Post-process: scan the entire DE payload for any chest
                # tail markers (`4D 00 05 00 10 [u16] 01`) whose absolute
                # bin offset isn't already covered by an existing chest's
                # [start_hex, end_hex_inclusive] span. Catches chests
                # absorbed into parent slices of non-0x02 record types
                # (e.g. warp records in chunk 18 carrying trailing chest
                # data, or chunk 20 where the DE walker mis-typed the
                # parent record).
                covered_spans = []
                for e in dynamic_entities:
                    if e.get("kind") != "chest":
                        continue
                    sh, eh = e.get("start_hex"), e.get("end_hex_inclusive")
                    if isinstance(sh, str) and isinstance(eh, str):
                        try:
                            covered_spans.append((int(sh, 16), int(eh, 16)))
                        except ValueError:
                            pass
                _scan_from = 0
                while True:
                    mt = de_payload.find(b"\x4D\x00\x05\x00\x10", _scan_from)
                    if mt < 0 or mt + 8 > len(de_payload):
                        break
                    if de_payload[mt + 7] != 0x01:
                        _scan_from = mt + 1
                        continue
                    abs_tail = de_payload_start + mt
                    if any(s <= abs_tail <= e for s, e in covered_spans):
                        _scan_from = mt + 8
                        continue
                    sub_ent = struct.unpack(">H", de_payload[mt + 5:mt + 7])[0]
                    # Validate: must have a chest signature within 120B before.
                    back_window = de_payload[max(0, mt - 120):mt]
                    found_sig = None
                    sig_offset = None
                    for sig in (b"\x01\x02\x62", b"\x01\x03\x19\x9C", b"\x01\x03\x0A\x59"):
                        bk = back_window.rfind(sig)
                        if bk >= 0:
                            found_sig = sig
                            off_pos = bk + len(sig) + (1 if sig == b"\x01\x02\x62" else 0)
                            if off_pos < len(back_window):
                                b = back_window[off_pos]
                                sig_offset = b - 256 if b >= 0x80 else b
                            break
                    if found_sig is None:
                        _scan_from = mt + 8
                        continue
                    sub_entity = {
                        "record_id": -1,
                        "record_type": "0x02",
                        "kind": "chest",
                        "entity_id": sub_ent,
                        "chest_signature": found_sig.hex().upper(),
                        "length_bytes": 0,
                        "start_hex": hex(abs_tail),
                        "end_hex_inclusive": hex(abs_tail + 7),
                        "note": "recovered via chunk-wide chest tail-marker scan (parent slice unknown)",
                    }
                    if sig_offset is not None:
                        sub_entity["chest_offset"] = sig_offset
                    src_pat = b"\x00\x3A\x00\x74\x00\x00\x00\x3A\x00\x3A\x00\x3A"
                    sp = back_window.rfind(src_pat)
                    if sp >= 8:
                        sx = struct.unpack(">I", back_window[sp - 8:sp - 4])[0]
                        sy = struct.unpack(">I", back_window[sp - 4:sp])[0]
                        if sx < 100000 and sy < 100000:
                            sub_entity["source_x_px"] = sx
                            sub_entity["source_y_px"] = sy
                    dynamic_entities.append(sub_entity)
                    covered_spans.append((abs_tail, abs_tail + 7))
                    _scan_from = mt + 8

                # Seek to the end of the DE payload (= chunk_end) so the
                # trailing-bytes logic below operates on the right region.
                f.seek(chunk_end_offset)

                # Capture any trailing bytes between last record and chunk_end
                remaining = chunk_end_offset - f.tell()
                if remaining > 0:
                    objects_trailing_hex = f.read(remaining).hex().upper()

                # The DE section spans from de_count u16 up to chunk_end (the
                # variable-length trailing bytes are part of it).
                _record_range("dynamic_entities_section", de_section_start, chunk_end_offset)

                if de_partial_status:
                    objects_parse_status = f"partial: {de_partial_status}"

            except (ValueError, struct.error) as e:
                objects_parse_status = f"fallback: {e}"
                # Fallback: dump entire post-region area as raw hex for later analysis
                grid_events = []
                static_assets = []
                dynamic_entities = []
                objects_trailing_hex = ""
                if obj_space > 0:
                    f.seek(obj_start)
                    objects_raw_hex_fallback = f.read(obj_space).hex().upper()

            ge_count = len(grid_events)
            sa_count = len(static_assets)
            de_count = len(dynamic_entities)
            print(f"Layer {layer_id} | Grids: {visual_layer_count} | Events: {ge_count} | Statics: {sa_count} | Dynamic: {de_count} | {objects_parse_status}")

            objects_block = {
                "parse_status": objects_parse_status,
                "grid_events": grid_events,
                "static_assets": static_assets,
                "dynamic_entities": dynamic_entities,
            }
            # Whole-section byte range (always available, even on fallback).
            if obj_space > 0:
                objects_block["start_hex"] = hex(obj_start)
                objects_block["end_hex_inclusive"] = hex(chunk_end_offset - 1)
                objects_block["size_bytes"] = obj_space
            # Per-subsection byte ranges (only populated for the parts that
            # were parsed successfully).
            if section_ranges:
                objects_block["section_ranges"] = section_ranges
            if objects_trailing_hex:
                objects_block["trailing_bytes_hex"] = objects_trailing_hex
            if objects_raw_hex_fallback:
                objects_block["raw_hex_fallback"] = objects_raw_hex_fallback

            chunk_data = {
                "chunk_index": i, 
                "layer_id": layer_id,
                "grid_width": grid_width, 
                "grid_height": grid_height,
                "chunk_size_bytes": chunk_size,
                "sub_layers": sub_layers,
                "objects": objects_block
            }
            blueprint["layers"].append(chunk_data)

            # Leapfrog to the next header
            f.seek(chunk_end_offset)
            i += 1

        # Record any trailing bytes that the chunk stream didn't consume.
        # Town v1 normally lands exactly at EOF; exploration v2 sometimes
        # leaves a small objects-style trailer (observed ~3 KB on
        # 111010100). Surface it raw so it can be decoded later.
        tail_remaining = file_end_offset - f.tell()
        if tail_remaining > 0:
            blueprint["chunk_stream_trailing_hex"] = f.read(tail_remaining).hex().upper()
            print(f"Chunk stream trailing bytes: {tail_remaining} B")

    # Decode scripted_entity payloads into named fields (sprite_id,
    # dialogue_line_id, unknown_N, tail_blocks) using bin data only.
    _decode_scripted_entities(blueprint)

    with open(output_path, "w") as out_file:
        json.dump(blueprint, out_file, indent=4)

    print(f"--- PARSING COMPLETE -> {output_path} ---")
    return True


def parse_town(town_id):
    """Resolve `<town_data_root>/<town_id>/map.bin` and parse it. The
    resulting blueprint is written to `map_blueprint.json` in the same
    folder.

    Accepts either the short id from towns.json (e.g. '1103') or the
    real folder id derived from the icon name (e.g. '111020300').
    """
    bin_path = bin_common.town_bin_path(town_id)
    if not bin_path:
        return False
    parse_ffbe_map(bin_path)
    return True


if __name__ == "__main__":
    # Usage: python ffbe_parser.py <town_id>
    # Default to 1102 to preserve the previous hard-coded behavior when
    # the script is run with no arguments.
    town_id = sys.argv[1] if len(sys.argv) > 1 else "1102"
    parse_town(town_id)