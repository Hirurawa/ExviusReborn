"""Opcode walker for FFBE *_event.bin scripts.

Frame format:

    <op_u8>  <length_u16_BE>  <payload[length]>

So each command is 3 + length bytes. This was previously read as
`<op_u16_BE> <length_u8>`, which decodes identically for any payload
under 256 bytes -- the length's high byte is the same byte as the
supposed "opcode low byte", and it is zero in that case. See
`walk_script` for why the difference matters.

Currently named opcodes:

    0x01  advance         length 0
    0x02  short_wait      length 2  -- u16 BE ticks
    0x07  move_actor      length 15 -- two variants, see _decode_move
    0x08  text            length 4  -- u32 BE text_id
    0x0b  face_actor      length 6  -- actor + direction
    0x46  show_bubble     length 21 -- actor + bubble id + duration

All other opcodes are emitted as `op_0xXX` with their raw payload hex,
so we can read the script in order and progressively name them.

The script stream is interleaved with tables of embedded entity records --
the cutscene's actor and asset declarations, in map.bin's dynamic-entity
format. See `decode_entity_record`; those tables are what used to be
mis-read as "781-byte op_0x00 blobs".
"""
from __future__ import annotations

import struct

import town_parser


# ---------------------------------------------------------------------------
# Embedded entity (actor / asset) records
# ---------------------------------------------------------------------------
#
# An event bin does not hold script frames end to end. Interleaved with the
# frames are tables of *entity records* in exactly the map.bin dynamic-entity
# format -- the cutscene's actor and asset declarations, one table per
# sub-scene. Each record's id is `200000 + slot` == `0x00030d40 + slot`, so its
# top three bytes are the constant `00 03 0d`.
#
# Read as a frame header, `00 03 0d` decodes as "op 0x00, payload length
# 0x030d (781)". That is why the corpus appeared to contain 436 fixed-size
# 781-byte `op_0x00` blobs, always exactly 781 bytes, always sitting at a
# fade-to-black: there is no such opcode. The walker was standing on the first
# three bytes of a record id. Skipping the phantom 781 bytes cleared the record
# table often enough to look plausible -- which is why the resulting script
# still read coherently -- and when it did not, it landed in the file's 0xff
# fill and produced one of the 255 "overrun" stops.
#
# Verified: of the 8950 flag=1 actor references in the corpus, 100% carry a u32
# in the 0x00030dNN band and 97.4% resolve to a record decoded here (375 of 395
# files resolve every one of their references).
ENTITY_RID_BASE = 200_000                 # 0x00030d40
ENTITY_RID_PREFIX = b"\x00\x03\x0d"
ENTITY_HEADER_SIZE = 25

# Class word at header+0 (record payload offset 0). 0x00ba / 0x00c8 are the
# scripted-entity class words documented for map.bin; 0x0064 / 0x00b6 / 0x007d
# additionally appear on event-embedded records.
ENTITY_CLASS_WORDS = {0x00ba, 0x00c8, 0x0064, 0x00b6, 0x007d}

TILE_PX = 58
_MAX_ENTITY_COORD = 0x20000
_MAX_ENTITY_EXTENT = 0x2000
# Record payloads observed in the corpus run 41..993 bytes. A table's last
# record has no successor to bound it, and the script region that follows can
# be tens of kB, so cap how far we scan for its payload rather than swallowing
# the script. Only the fixed header + identity slot are load-bearing; the
# payload scan exists to surface asset filenames.
_ENTITY_PAYLOAD_SCAN_CAP = 1024

_ASSET_SUFFIXES = (".bmb", ".acb", ".usm", ".png", ".cgs", ".bmp")

# Opcodes that reference an actor by record id, and their payload length. Their
# payload is `<flag u8> <u32 BE actor_rid> ...`; when flag=1 the u32 is a record
# id, so `00 03 0d` appears at payload offset 1. Those in-script occurrences are
# references, not record headers, and must not be mistaken for one.
ACTOR_REF_OPS = {0x07: 15, 0x0b: 6, 0x0c: 6}


def _is_actor_reference_site(b, off):
    """True when the `00 03 0d` at `off` is an actor reference inside a frame
    payload rather than the start of a record.

    A reference always sits at payload offset 1 of an actor-referencing frame,
    so the byte before it is the flag 0x01 and the three bytes before that are
    that frame's `<op> <length u16 BE>` header.
    """
    if off < 4:
        return False
    if b[off - 1] != 0x01:
        return False
    op = b[off - 4]
    need = ACTOR_REF_OPS.get(op)
    if need is None:
        return False
    return struct.unpack_from(">H", b, off - 3)[0] == need


def decode_entity_record(b, off, strict=True):
    """Decode the entity-record header at `off`, or return None if the bytes
    there are not a plausible record.

    Header (25 bytes, identical to map.bin's dynamic-entity header):

        [ 0: 4] u32 rid          -- ENTITY_RID_BASE + slot
        [ 4]    u8  type         -- 0x01 scripted entity (actor),
                                    0x00 asset / VFX record
        [ 5: 9] u32 src_x        -- pixels
        [ 9:13] u32 src_y        -- pixels
        [13:15] u16 w
        [15:17] u16 h
        [17:19] i16 collision_offset_y
        [19:21] u16 interaction_height
        [21:23] u16 sprite_height
        [23:25] u16 sprite_width

    then the record payload, which opens with the class word and `0101` and
    carries the identity slot (npc texture id or npc instance id) at payload
    offset 4 or 6 -- probed with town_parser's shared heuristic, since this is
    the same payload shape map.bin uses.

    Unlike map.bin entities, cutscene actors are not tile-aligned: only ~2/3 of
    records sit on an exact 58px multiple, the rest are mid-stride positions. So
    coordinates are range-checked, not alignment-checked.

    `strict` applies the plausibility filters that make a blind scan usable.
    When the caller already knows a record starts here -- because the block
    header said how many there are and which slots they use -- pass
    strict=False, so a record is not thrown away merely for carrying a class
    word or extent this decoder has not seen before.
    """
    if off + ENTITY_HEADER_SIZE + 2 > len(b):
        return None
    if b[off:off + 3] != ENTITY_RID_PREFIX:
        return None
    if strict and _is_actor_reference_site(b, off):
        return None
    rid, = struct.unpack_from(">I", b, off)
    rec_type = b[off + 4]
    src_x, = struct.unpack_from(">I", b, off + 5)
    src_y, = struct.unpack_from(">I", b, off + 9)
    w, = struct.unpack_from(">H", b, off + 13)
    h, = struct.unpack_from(">H", b, off + 15)
    class_word, = struct.unpack_from(">H", b, off + ENTITY_HEADER_SIZE)
    if strict:
        if rec_type >= 0x20:
            return None
        if src_x > _MAX_ENTITY_COORD or src_y > _MAX_ENTITY_COORD:
            return None
        if w > _MAX_ENTITY_EXTENT or h > _MAX_ENTITY_EXTENT:
            return None
        if w % TILE_PX or h % TILE_PX:
            return None
        if class_word not in ENTITY_CLASS_WORDS:
            return None
    coll, = struct.unpack_from(">h", b, off + 17)
    return {
        "offset": off,
        "rid": rid,
        "slot": rid - ENTITY_RID_BASE,
        "type": rec_type,
        "src_x": src_x,
        "src_y": src_y,
        "tile_x": src_x / TILE_PX,
        "tile_y": src_y / TILE_PX,
        "w": w,
        "h": h,
        "collision_offset_y": coll,
        "interaction_height": struct.unpack_from(">H", b, off + 19)[0],
        "sprite_height": struct.unpack_from(">H", b, off + 21)[0],
        "sprite_width": struct.unpack_from(">H", b, off + 23)[0],
        "class_word": class_word,
    }


def _entity_asset_files(payload):
    """Pull ASCII asset filenames out of a record payload.

    These are the `.acb` audio banks, `.bmb` VFX and `.usm` movies that the
    "781-byte blob" write-up listed as blob contents -- they belong to these
    records. `map_warp_another_world.bmb` (the dark portal in 111020101) and
    `townname_1101.png` both come from here.
    """
    out = []
    run = []
    start = 0
    for i, c in enumerate(payload):
        if 32 <= c < 127:
            if not run:
                start = i
            run.append(chr(c))
            continue
        if len(run) >= 4:
            s = "".join(run)
            if s.lower().endswith(_ASSET_SUFFIXES):
                out.append({"offset": start, "filename": s})
        run = []
    if len(run) >= 4:
        s = "".join(run)
        if s.lower().endswith(_ASSET_SUFFIXES):
            out.append({"offset": start, "filename": s})
    return out


BLOCK_HEADER_SIZE = 14


def find_blocks(b, manifest_end):
    """Frame the post-manifest region as the chain of sized blocks it is.

    After the asset manifest comes a u16 block count, then the blocks. Each
    block is a 14-byte header -- u32 size, u16 block_id, u32 grid_width,
    u32 grid_height -- followed by `grid_width * grid_height` bytes of
    one-byte-per-tile collision grid, a u16 entity-record count, and the
    body (entity records interleaved with script frames). `size` spans from
    the start of `size` to the start of the next block, and the chain ends
    exactly at EOF.

    Returns [] when the chain does not frame cleanly, so callers can fall
    back to scanning. `declared_count` is the block count in the file, which
    disagrees with the walked count in a couple of bins; the walk wins.
    """
    if manifest_end + 2 > len(b):
        return []
    off = manifest_end + 2
    blocks = []
    while off < len(b):
        if off + BLOCK_HEADER_SIZE > len(b):
            return []
        size, block_id, gw, gh = struct.unpack_from(">IHII", b, off)
        if size < BLOCK_HEADER_SIZE or off + size > len(b):
            return []
        grid_start = off + BLOCK_HEADER_SIZE
        grid_end = grid_start + gw * gh
        if grid_end + 2 > off + size:
            return []
        blocks.append({
            "index": len(blocks),
            "offset": off,
            "size": size,
            "block_id": block_id,
            "grid_width": gw,
            "grid_height": gh,
            "grid_start": grid_start,
            "grid_end": grid_end,
            "num_entities": struct.unpack_from(">H", b, grid_end)[0],
            "body_start": grid_end + 2,
            "body_end": off + size,
        })
        off += size
    if off != len(b):
        return []
    return blocks


def _slot_sites(b, lo, hi):
    """Every `00 03 0d NN` site in [lo, hi), grouped by its slot byte."""
    by_slot = {}
    i = b.find(ENTITY_RID_PREFIX, lo, hi)
    while i >= 0:
        if i + 4 <= hi:
            by_slot.setdefault(b[i + 3], []).append(i)
        i = b.find(ENTITY_RID_PREFIX, i + 1, hi)
    return by_slot


def select_entity_records(b, block):
    """Choose one record site per slot inside one block's body.

    The block header states how many records the body holds, and each
    record's slot is distinct, so the set of distinct slot bytes among the
    body's `00 03 0d NN` sites *is* the record set -- it matches the
    declared count in 689 of 711 blocks, against 631 for a validated blind
    scan. Every other occurrence of a slot is an actor reference inside a
    script frame, which `_is_actor_reference_site` recognises exactly.

    So the count is a checksum rather than a guess: `slot_count_matches`
    says whether the distinct slots agree with the header, and each record
    carries how its site was picked --

        unique     -- one non-reference site for the slot; no heuristic used
        validated  -- several survived, one passed decode_entity_record
        first_valid / fallback -- still ambiguous, first candidate taken
    """
    lo, hi = block["body_start"], block["body_end"]
    by_slot = _slot_sites(b, lo, hi)
    chosen = []
    for slot, sites in sorted(by_slot.items()):
        non_ref = [s for s in sites if not _is_actor_reference_site(b, s)]
        pool = non_ref or sites
        if len(non_ref) == 1:
            off, how = non_ref[0], "unique"
        else:
            valid = [s for s in pool if decode_entity_record(b, s)]
            if len(valid) == 1:
                off, how = valid[0], "validated"
            elif valid:
                off, how = valid[0], "first_valid"
            else:
                off, how = pool[0], "fallback"
        rec = decode_entity_record(b, off, strict=False)
        if rec is None:
            continue
        rec["resolution"] = how
        rec["block_index"] = block["index"]
        chosen.append(rec)
    chosen.sort(key=lambda r: r["offset"])
    return chosen, len(by_slot) == block["num_entities"]


def _annotate_payloads(b, records, hard_end):
    """Fill in payload_size / identity / asset_files for a record list.

    `payload_size` is the distance to the next record and so is only an
    upper bound -- script frames sit between records, so a record's real
    extent is somewhere inside that span.
    """
    for idx, rec in enumerate(records):
        payload_start = rec["offset"] + ENTITY_HEADER_SIZE
        limit = payload_start + _ENTITY_PAYLOAD_SCAN_CAP
        if idx + 1 < len(records):
            next_off = records[idx + 1]["offset"]
            rec["payload_size"] = next_off - rec["offset"]
            rec["payload_truncated"] = next_off > limit
            payload_end = min(next_off, limit, hard_end)
        else:
            rec["payload_size"] = hard_end - rec["offset"]
            rec["payload_truncated"] = hard_end > limit
            payload_end = min(limit, hard_end)
        payload = bytes(b[payload_start:payload_end])
        ident_off, identity = town_parser._find_identity_slot(payload)
        if identity is not None:
            rec["identity"] = identity
            rec["identity_offset"] = ident_off
        assets = _entity_asset_files(payload)
        if assets:
            rec["asset_files"] = assets
    return records


def find_entity_records_blockwise(b, blocks):
    """Entity records for the whole file, one block at a time.

    Blocks are framed exactly, so this never scans the collision grids and
    never has to guess how many records to expect. Returns
    (records, blocks_agreeing, blocks_with_entities).
    """
    records = []
    agree = with_entities = 0
    for block in blocks:
        if not block["num_entities"]:
            continue
        with_entities += 1
        chosen, matched = select_entity_records(b, block)
        agree += bool(matched)
        block["slot_count_matches"] = matched
        block["records_found"] = len(chosen)
        records.extend(_annotate_payloads(b, chosen, block["body_end"]))
    return records, agree, with_entities


def find_entity_records(b, start=0, end=None):
    """Scan `b[start:end]` for every embedded entity record, in file order.

    Each record additionally gets `identity` / `identity_offset` (the npc
    texture or instance id, when the payload holds one), `payload_size` and any
    `asset_files` found in its payload. `payload_size` is the distance to the
    next record and is therefore only meaningful inside a table -- the last
    record of a table is bounded by the scan cap instead and is flagged
    `payload_truncated`.
    """
    if end is None:
        end = len(b)
    records = []
    i = start
    while True:
        i = b.find(ENTITY_RID_PREFIX, i, end)
        if i < 0:
            break
        rec = decode_entity_record(b, i)
        if rec is None:
            i += 1
            continue
        records.append(rec)
        i += ENTITY_HEADER_SIZE
    for idx, rec in enumerate(records):
        payload_start = rec["offset"] + ENTITY_HEADER_SIZE
        limit = payload_start + _ENTITY_PAYLOAD_SCAN_CAP
        if idx + 1 < len(records):
            next_off = records[idx + 1]["offset"]
            rec["payload_size"] = next_off - rec["offset"]
            rec["payload_truncated"] = next_off > limit
            payload_end = min(next_off, limit, end)
        else:
            rec["payload_size"] = None
            rec["payload_truncated"] = True
            payload_end = min(limit, end)
        payload = bytes(b[payload_start:payload_end])
        ident_off, identity = town_parser._find_identity_slot(payload)
        if identity is not None:
            rec["identity"] = identity
            rec["identity_offset"] = ident_off
        assets = _entity_asset_files(payload)
        if assets:
            rec["asset_files"] = assets
    return records


def _decode_text(payload):
    if len(payload) != 4:
        return {"decode_status": f"unexpected length {len(payload)}"}
    return {"text_id": struct.unpack(">I", payload)[0]}


def _decode_short_wait(payload):
    if len(payload) != 2:
        return {"decode_status": f"unexpected length {len(payload)}"}
    return {"ticks": struct.unpack(">H", payload)[0]}


def _decode_empty(payload):
    if len(payload) != 0:
        return {"decode_status": f"unexpected length {len(payload)}"}
    return {}


def _decode_actor_ref(payload):
    """Decode the 5-byte actor reference that opens every actor-scoped frame.

        [0]    kind flag -- 0 = party cast, 1 = scene entity record
        [1:5]  u32 BE actor reference

    Verified across the corpus (19,386 actor-scoped frames): when the flag is 0
    the u32 is a bare cast index, always 1..12 and never 0 -- the party/guest
    line-up. When it is 1 the u32 is always in the 0x00030dNN band, i.e. an
    embedded entity record id (`ENTITY_RID_BASE + slot`), and 97.4% resolve to a
    record in the same file.

    This supersedes the old reading, which took [0] as a "variant", [2:4] as an
    `ext_ref` of 0x030d and [4] as the actor id. Those are the three middle bytes
    and the low byte of this one u32; the low byte works as an actor id only
    because slots never reach 256.
    """
    kind = payload[0]
    ref = struct.unpack_from(">I", payload, 1)[0]
    decoded = {
        "actor_id": payload[4],
        "actor_kind": "entity" if kind else "party",
        "actor_ref": ref,
    }
    if kind:
        decoded["actor_rid"] = ref
        decoded["actor_slot"] = ref - ENTITY_RID_BASE
    else:
        decoded["party_index"] = ref
    return decoded


def _decode_move_actor(payload):
    """Decode op_0x07 (15 bytes).

    Layout:
        [0:5]  actor reference -- see _decode_actor_ref
        [5]    sub-flag (0 or 1)
        [6]    mode: 0 = absolute position, 1 = relative delta
        [7:9]  i16 BE  x  or  dx
        [9:11] i16 BE  y  or  dy
        [11]   u8 duration in ticks (used when mode=1)
        [12:15] trailer (usually 01 01 00 or 01 01 01)
    """
    if len(payload) != 15:
        return {"decode_status": f"unexpected length {len(payload)}"}
    sub_flag = payload[5]
    mode = payload[6]
    xy_x = struct.unpack_from(">h", payload, 7)[0]
    xy_y = struct.unpack_from(">h", payload, 9)[0]
    ticks = payload[11]
    trailer = payload[12:15].hex()
    decoded = _decode_actor_ref(payload)
    decoded.update({
        "sub_flag": sub_flag,
        "trailer_hex": trailer,
    })
    if mode == 1:
        decoded["mode"] = "relative"
        decoded["dx"] = xy_x
        decoded["dy"] = xy_y
        decoded["ticks"] = ticks
    elif mode == 0:
        decoded["mode"] = "absolute"
        decoded["x"] = xy_x
        decoded["y"] = xy_y
    else:
        decoded["mode"] = f"unknown(0x{mode:02x})"
        decoded["raw_hex"] = payload[6:12].hex()
    return decoded


# Direction byte mapping for op_0x0b / op_0x0c etc. Ground-truthed
# against the 112020301 cutscene narration (Grandport intro).
DIRECTION_NAMES = {
    0: "down",
    1: "up",
    2: "left",
    3: "right",
}


def _decode_face_actor(payload):
    """Decode op_0x0b (6 bytes).

    Layout: `<actor reference, 5 bytes> <direction u8>`.
    Direction encoding: 0=down, 1=up, 2=left, 3=right.
    """
    if len(payload) != 6:
        return {"decode_status": f"unexpected length {len(payload)}"}
    direction = payload[5]
    decoded = _decode_actor_ref(payload)
    decoded.update({
        "direction": direction,
        "direction_name": DIRECTION_NAMES.get(direction, f"unknown_{direction}"),
    })
    return decoded


def _decode_set_actor_visible(payload):
    """Decode op_0x0c (6 bytes) -- provisional name `set_actor_visible`.

    Shares the same actor-command shape as `move_actor` and `face_actor`:
    a 5-byte actor reference (see `_decode_actor_ref`) then a byte-5 flag.

    That flag splits ~50/50 across the 12,601 samples in the corpus, which is
    what you'd expect for a "show then hide" toggle that must fire once per
    actor per scene. The geometric meaning (visible vs hidden, or alive vs
    idle) is not yet ground-truthed.
    """
    if len(payload) != 6:
        return {"decode_status": f"unexpected length {len(payload)}"}
    decoded = _decode_actor_ref(payload)
    decoded["visible"] = payload[5]   # 0 or 1 -- semantic mapping TBD
    return decoded


def _decode_play_vfx(payload):
    """Decode op_0x5f (variable length) -- plays a VFX/animation file.

    Variable-length preamble because the payload may carry a numeric
    asset ID encoded as both an ASCII string AND a u32:

        [0:2]            u16 BE  id_str_len (m, often 0)
        [2 : 2+m]        ASCII id_str (decimal digits like "1063")
        [2+m : 2+m+4]    u32 BE  id_value
                            - if m > 0: equals int(id_str)
                            - if m == 0: an effect-slot/index (1-30ish)
        [+4 : +6]        u16 BE  file_str_len (n)
        [+6 : +6+n]      ASCII file_str (.bmb / .bmp / .cgs filename)
        tail (18 bytes):
            [0:4]   u32 BE  x
            [4:8]   u32 BE  y
            [8:12]  u32 BE  layer / z-index
            [12:16] u32 BE  pad
            [16]    u8 duration (ticks)
            [17]    u8 end-flag (0 normal, 1 loop?)
    """
    if len(payload) < 26:
        return {"decode_status": f"too short ({len(payload)} bytes)"}
    pos = 0
    id_str_len = struct.unpack_from(">H", payload, pos)[0]
    pos += 2
    if pos + id_str_len + 4 + 2 > len(payload):
        return {"decode_status": f"id_str_len {id_str_len} doesn't fit"}
    id_str_raw = payload[pos:pos + id_str_len]
    pos += id_str_len
    try:
        id_str = id_str_raw.decode("ascii") if id_str_len else ""
    except UnicodeDecodeError:
        id_str = id_str_raw.hex()
    id_value = struct.unpack_from(">I", payload, pos)[0]
    pos += 4
    file_str_len = struct.unpack_from(">H", payload, pos)[0]
    pos += 2
    if pos + file_str_len + 18 > len(payload):
        return {
            "id_str": id_str,
            "id_value": id_value,
            "decode_status": f"file_str_len {file_str_len} doesn't fit",
        }
    file_raw = payload[pos:pos + file_str_len]
    pos += file_str_len
    try:
        filename = file_raw.decode("ascii")
    except UnicodeDecodeError:
        return {
            "id_str": id_str,
            "id_value": id_value,
            "decode_status": "filename not ascii",
            "raw_filename_hex": file_raw.hex(),
        }
    tail = payload[pos:pos + 18]
    x = struct.unpack_from(">I", tail, 0)[0]
    y = struct.unpack_from(">I", tail, 4)[0]
    layer = struct.unpack_from(">I", tail, 8)[0]
    pad_u32 = struct.unpack_from(">I", tail, 12)[0]
    duration = tail[16]
    end_flag = tail[17]
    decoded = {
        "filename": filename,
        "id_value": id_value,
        "x": x,
        "y": y,
        "layer": layer,
        "duration": duration,
        "end_flag": end_flag,
    }
    if id_str:
        decoded["id_str"] = id_str
    if pad_u32 != 0:
        decoded["pad_u32"] = pad_u32
    return decoded


def _decode_camera_scroll(payload):
    """Decode op_0x06 (7 bytes) -- pans the camera.

    Confirmed in 112020301 where cmd `01 ff8c 0000 00 14` (dx=-116,
    dy=0, ticks=20) immediately precedes two move_actor commands that
    walk characters dx=-116; the user's narration says "camera follows
    them" at that beat. Layout:

        [0]     flag (0 or 1)
        [1:3]   i16 BE  dx
        [3:5]   i16 BE  dy
        [5]     pad (always 0?)
        [6]     u8 ticks
    """
    if len(payload) != 7:
        return {"decode_status": f"unexpected length {len(payload)}"}
    dx = struct.unpack_from(">h", payload, 1)[0]
    dy = struct.unpack_from(">h", payload, 3)[0]
    return {
        "flag": payload[0],
        "dx": dx,
        "dy": dy,
        "pad": payload[5],
        "ticks": payload[6],
    }


def _decode_show_bubble(payload):
    """Decode op_0x46 (21 bytes).

    Empirical layout, derived from confirmed thumbs-up / three-dots
    samples in `111010105`:

        [0:4]   pad
        [4]     actor_id
        [5:8]   pad
        [8]     bubble_id -- 1-based index into the
                `map_common/emotion_icon.png` atlas (2x12 grid;
                two columns are facing variants of the same emote)
        [9:12]  pad
        [12]    duration (ticks?  observed 0x50, 0x78)
        [13:17] pad
        [17:21] i32 BE -- offset / z value (often -1, sometimes -10)
    """
    if len(payload) != 21:
        return {"decode_status": f"unexpected length {len(payload)}"}
    actor_id = payload[4]
    bubble_id = payload[8]
    duration = payload[12]
    tail = struct.unpack_from(">i", payload, 17)[0]
    decoded = {
        "actor_id": actor_id,
        "bubble_id": bubble_id,
        "bubble_name": BUBBLE_NAMES.get(bubble_id, f"unknown_0x{bubble_id:02x}"),
        "duration": duration,
        "tail_i32": tail,
    }
    return decoded


# Maps `bubble_id` (1-based) to its name in
# assets/.../map_common/emotion_icon.png. Atlas is 2x12 -- two columns
# are left/right facing variants of the same emote, so there are 12
# distinct names.
BUBBLE_NAMES = {
    0x01: "exclamation",
    0x02: "music_note",
    0x03: "squiggly",
    0x04: "angry",
    0x05: "three_dots",
    0x06: "question",
    0x07: "heart",
    0x08: "sweat_drop",
    0x09: "light_bulb",
    0x0a: "dollar",
    0x0b: "thumbs_up",
    0x0c: "swirly",
}


NAMED_OPCODES = {
    0x01: ("advance", _decode_empty),
    0x02: ("short_wait", _decode_short_wait),
    0x06: ("camera_scroll", _decode_camera_scroll),
    0x07: ("move_actor", _decode_move_actor),
    0x08: ("text", _decode_text),
    0x0b: ("face_actor", _decode_face_actor),
    0x0c: ("set_actor_visible", _decode_set_actor_visible),
    0x3a: ("scene_config", lambda p: _decode_scene_config(p)),
    0x46: ("show_bubble", _decode_show_bubble),
    0x5f: ("play_vfx", _decode_play_vfx),
    0x67: ("set_move_mode", lambda p: _decode_set_move_mode(p)),
}


# Payload length of every named opcode whose length is fixed. A frame that
# carries one of these opcodes with any other length is proof the walker is out
# of sync -- the bytes it read as `<op> <len>` are really the middle of
# something else. `_walk_setup_region` uses this to reject false sync points.
# Variable-length named opcodes (0x3a, 0x5f) are deliberately absent.
NAMED_OPCODE_LENGTHS = {
    0x01: 0,
    0x02: 2,
    0x06: 7,
    0x07: 15,
    0x08: 4,
    0x0b: 6,
    0x0c: 6,
    0x46: 21,
    0x67: 1,
}


def is_well_formed(cmd):
    """True when `cmd` is a named opcode whose length matches its decoder."""
    op = cmd["op"]
    if op not in NAMED_OPCODES:
        return False
    need = NAMED_OPCODE_LENGTHS.get(op)
    return need is None or cmd["length"] == need


def _decode_set_move_mode(payload):
    """Decode op_0x67 (1 byte).

    Toggles the actor-motion mode for subsequent `move_actor` opcodes.
    Observed values in 112020101:
      * 0x01 -- emitted at end of setup; subsequent moves walk normally.
      * 0x00 -- emitted right before the "run after the lady" sequence;
        subsequent moves render at run speed (the engine swaps to the
        run sprite cycle and the displacements come through faster).
    The opcode also seems to flip a camera-unlock / scene-step flag,
    but the move-speed effect is what we model in the visualizer.
    """
    if len(payload) != 1:
        return {"decode_status": f"unexpected length {len(payload)}"}
    flag = payload[0]
    return {
        "flag": flag,
        "mode": "run" if flag == 0 else "walk",
    }


def _decode_scene_config(payload):
    """Decode op_0x3a (variable length, observed: 58..200 bytes).

    op_0x3a is a CONTAINER opcode -- its payload starts with a
    scene-wide config blob (lighting/camera/flags; not yet decoded) and
    ends with one or more embedded opcode frames in the canonical
    `<op_u16 BE> <len_u8> <payload[len]>` format. The frames that matter
    for visualization are the absolute-mode move_actor frames that
    place the party at their initial cutscene positions.

    For now we just scan the payload for move_actor frames (`07 00 0f`
    + 15-byte payload) and extract any that decode cleanly. Embedded
    moves come back as `embedded_moves`, a list of move_actor command
    dicts (same schema as a top-level move_actor record).
    """
    embedded: list[dict] = []
    i = 0
    L = len(payload)
    while i + 18 <= L:
        # Look for the start of a move_actor frame.
        if payload[i] == 0x07 and payload[i + 1] == 0x00 and payload[i + 2] == 0x0f:
            inner = payload[i + 3:i + 18]
            decoded = _decode_move_actor(inner)
            # Sanity-check: a real spawn has a small actor_id and a
            # canonical trailer. Reject frames that look like garbage.
            if decoded.get("actor_id", 999) < 200 and decoded.get("trailer_hex") == "010101":
                decoded["inner_offset"] = i
                embedded.append(decoded)
                i += 18
                continue
        i += 1
    # Scan for the initial camera-position record: `06 00 07 00 <x_BE>
    # <y_BE>`. Verified by cross-referencing 112020101 (camera centre
    # (1506, 2384) -> top-left (1216, 1920), which matches the user's
    # observed start tile (21, 33) = pixel (1218, 1914)) and 112020301
    # (centre (5220, 4872)). The record appears twice in both events
    # with identical coords; we keep the first.
    camera_pos = None
    for j in range(L - 7):
        if payload[j:j + 4] == b"\x06\x00\x07\x00":
            cx = struct.unpack_from(">H", payload, j + 4)[0]
            cy = struct.unpack_from(">H", payload, j + 6)[0]
            camera_pos = {"x": cx, "y": cy, "inner_offset": j}
            break
    out = {"payload_len": L}
    if embedded:
        out["embedded_moves"] = embedded
    if camera_pos is not None:
        out["camera_position"] = camera_pos
    return out


def find_first_text_anchor(b, known_text_ids, search_from):
    """Find the offset of the first `<0x08 0x00 0x04> <plausible_text_id>`
    at or after `search_from`. Returns None if not found.

    A "plausible" id is either present in the sidecar `_event_text.txt`
    (preferred) or falls in 0x010000..0x0fffff (the observed range of
    real dialogue ids).
    """
    i = search_from
    L = len(b)
    while i + 7 <= L:
        if b[i] == 0x08 and b[i + 1] == 0x00 and b[i + 2] == 0x04:
            tid = struct.unpack_from(">I", b, i + 3)[0]
            if (known_text_ids and tid in known_text_ids) or \
               (not known_text_ids and 0x010000 <= tid <= 0x0fffff):
                return i
        i += 1
    return None


# A run of this many consecutive zero-length op_0x00 frames means we have
# walked off the end of the script into the file's zero padding. Real scripts
# do use op_0x00, but never dozens in a row.
_ZERO_RUN_LIMIT = 12


def walk_script(b, start, file_end):
    """Yield decoded command dicts from `start` to `file_end`.

    Frame format is `<op u8> <length u16 BE> <payload[length]>`.

    This used to be read as `<op u16 BE> <length u8>`, which is the same
    thing for every frame whose payload fits in a byte -- the length's high
    byte and the "opcode low byte" are the same byte, and it is zero
    whenever length < 256.

    Where the stream stops being frames it is not carrying a jumbo opcode: it
    has run into a table of embedded entity records (see
    `decode_entity_record`), whose ids all begin `00 03 0d`. Reading those three
    bytes as a frame header yields the phantom "op_0x00, length 781". The walker
    now recognises a record header and stops there, so the caller can decode the
    table as data and resume past it.

    Each dict has: `offset`, `op` (u8), `name`, `length`, `payload_hex`,
    plus any fields the payload decoder adds. The walker stops with a
    `_stop` record when it reaches an entity-record table, when the length
    would overrun `file_end`, or when a long run of empty op_0x00 frames shows
    we have reached the trailing padding.
    """
    o = start
    zero_run = 0
    while o + 3 <= file_end:
        op = b[o]
        length = struct.unpack_from(">H", b, o + 1)[0]
        end = o + 3 + length
        if op == 0x00 and b[o:o + 3] == ENTITY_RID_PREFIX:
            record = decode_entity_record(b, o)
            if record is not None:
                yield {
                    "_stop": "entity_record_table",
                    "offset": o,
                    "record_slot": record["slot"],
                    "record_type": record["type"],
                }
                return
        if op == 0x00 and length == 0:
            zero_run += 1
            if zero_run >= _ZERO_RUN_LIMIT:
                yield {
                    "_stop": "padding_run",
                    "offset": o - 3 * (_ZERO_RUN_LIMIT - 1),
                    "zero_frames": zero_run,
                }
                return
        else:
            zero_run = 0
        if end > file_end:
            yield {
                "_stop": "overrun",
                "offset": o,
                "op": op,
                "length": length,
                "available": file_end - (o + 3),
            }
            return
        payload = bytes(b[o + 3:end])
        named = NAMED_OPCODES.get(op)
        if named:
            name, decoder = named
            extra = decoder(payload)
        else:
            name = f"op_0x{op:02x}"
            extra = {}
        record = {
            "offset": o,
            "op": op,
            "name": name,
            "length": length,
            "payload_hex": payload.hex(),
        }
        record.update(extra)
        yield record
        o = end
