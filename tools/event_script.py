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
"""
from __future__ import annotations

import struct


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


def _decode_move_actor(payload):
    """Decode op_0x07 (15 bytes).

    Layout:
        [0]    variant flag (0 or 1; correlated with [2:4])
        [1]    pad
        [2:4]  u16 BE -- 0x0000 when variant=0, 0x030d when variant=1
               (variant=1 is "move with extended reference" -- the
               reference's meaning is not yet decoded)
        [4]    actor_id u8 (per-event actor table id)
        [5]    sub-flag (0 or 1)
        [6]    mode: 0 = absolute position, 1 = relative delta
        [7:9]  i16 BE  x  or  dx
        [9:11] i16 BE  y  or  dy
        [11]   u8 duration in ticks (used when mode=1)
        [12:15] trailer (usually 01 01 00 or 01 01 01)
    """
    if len(payload) != 15:
        return {"decode_status": f"unexpected length {len(payload)}"}
    variant = payload[0]
    ext_ref = struct.unpack_from(">H", payload, 2)[0]
    actor_id = payload[4]
    sub_flag = payload[5]
    mode = payload[6]
    xy_x = struct.unpack_from(">h", payload, 7)[0]
    xy_y = struct.unpack_from(">h", payload, 9)[0]
    ticks = payload[11]
    trailer = payload[12:15].hex()
    decoded = {
        "actor_id": actor_id,
        "sub_flag": sub_flag,
        "variant": variant,
        "trailer_hex": trailer,
    }
    if variant != 0:
        decoded["ext_ref"] = ext_ref
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

    Layout: `<pad u32> <actor_id u8> <direction u8>`.
    Direction encoding: 0=down, 1=left, 2=up, 3=right.
    """
    if len(payload) != 6:
        return {"decode_status": f"unexpected length {len(payload)}"}
    direction = payload[5]
    return {
        "actor_id": payload[4],
        "direction": direction,
        "direction_name": DIRECTION_NAMES.get(direction, f"unknown_{direction}"),
    }


def _decode_set_actor_visible(payload):
    """Decode op_0x0c (6 bytes) -- provisional name `set_actor_visible`.

    Shares the same actor-command shape as `move_actor` and `face_actor`:

        variant A: `01 00 03 0d <ext_id u8> <flag u8>`
        variant B: `00 00 00 00 <actor_id u8> <flag u8>`

    The byte-5 flag splits ~50/50 across the 12,601 samples in the
    corpus, which is what you'd expect for a "show then hide" toggle
    that must fire once per actor per scene. The geometric meaning
    (visible vs hidden, or alive vs idle) is not yet ground-truthed.
    """
    if len(payload) != 6:
        return {"decode_status": f"unexpected length {len(payload)}"}
    variant = payload[0]
    decoded = {
        "actor_id": payload[4],
        "visible": payload[5],   # 0 or 1 -- semantic mapping TBD
        "variant": variant,
    }
    if variant != 0:
        decoded["ext_ref"] = struct.unpack_from(">H", payload, 2)[0]
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
    whenever length < 256. The two readings only diverge on payloads of 256+
    bytes, and that is exactly where the old walker gave up: `00 03 0d` is
    op_0x00 carrying 781 bytes, not an opcode with a malformed low byte.
    Reading it correctly is what lets a walk continue past the big embedded
    data blobs that sit between a cutscene's sub-scenes.

    Each dict has: `offset`, `op` (u8), `name`, `length`, `payload_hex`,
    plus any fields the payload decoder adds. The walker stops with a
    `_stop` record when the length would overrun `file_end`, or when a long
    run of empty op_0x00 frames shows we have reached the trailing padding.
    """
    o = start
    zero_run = 0
    while o + 3 <= file_end:
        op = b[o]
        length = struct.unpack_from(">H", b, o + 1)[0]
        end = o + 3 + length
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
