"""Skeleton parser for FFBE *_event.bin (cutscene / story) files.

Currently decodes:
  * the 28-byte file header (file_size, version, four unknown counts,
    num_assets), and
  * the asset manifest -- a list of `(marker, filename)` entries that
    reference NPC sprites, event objects, and other per-cutscene assets.

The remainder of the file (slot/actor table + opcode-stream script)
is not yet decoded; for now we emit a `post_manifest` block that
captures its byte range plus a short hex preview, so we can iterate.

Usage:
    python event_parser.py <event_id>          # parse one event
    python event_parser.py --all               # parse every *_event.bin
                                               # under the asset root

Writes `<folder>/event_blueprint.json` next to each source bin.
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter
from pathlib import Path

import event_common
import event_script


_PREVIEW_BYTES = 64
_TEXT_PREVIEW_CHARS = 60
_MAX_SCRIPT_CMDS = 100_000  # safety cap; real scripts are much smaller
_SETUP_MIN_CMDS = 3          # require at least this many ops to count


def _walk_setup_region(raw, ps_start, ps_end):
    """Locate and walk the setup-opcode region inside a pre_script.

    The pre_script begins with a small fixed header, then a long run
    of fill bytes (0x00 or 0xFF), then a setup-opcode stream that
    flows directly into the first dialog frame at ``ps_end``.

    We don't yet know how to derive the setup-start offset from the
    header, so we brute-force it: try every non-fill byte offset
    between ``ps_start + 12`` and ``ps_end``; the correct start is the
    earliest offset at which ``walk_script`` walks cleanly (no stop
    record) and the *next* frame after the last walked command begins
    exactly at ``ps_end``.

    Returns ``(start_offset, commands)`` or ``(None, [])`` if nothing
    parses cleanly.
    """
    if ps_end <= ps_start + 12:
        return None, []
    best = None  # (non_noop_count, total_count, start, cmds)
    scan_start = ps_start + 12
    for off in range(scan_start, ps_end):
        b = raw[off]
        # Skip fill bytes -- a real opcode high-byte is rarely 0x00/0xff
        if b == 0x00 or b == 0xff:
            continue
        # Quick reject: low byte of the u16-BE opcode must be 0x00
        if off + 1 >= len(raw) or raw[off + 1] != 0x00:
            continue
        cmds = []
        ok = True
        for rec in event_script.walk_script(raw, off, ps_end + 1):
            if "_stop" in rec:
                ok = False
                break
            cmds.append(rec)
            if len(cmds) >= _MAX_SCRIPT_CMDS:
                ok = False
                break
        if not ok or not cmds:
            continue
        last = cmds[-1]
        last_end = last["offset"] + 3 + last["length"]
        # The walker should have consumed *exactly* up to ps_end -- one
        # past the last setup frame, which is where dialog starts.
        if last_end != ps_end:
            continue
        non_noop = sum(1 for c in cmds if c["name"] != "op_0x00")
        if non_noop < _SETUP_MIN_CMDS:
            continue
        # Prefer the earliest start that still walks cleanly (captures
        # the most setup info).
        if best is None or off < best[2]:
            best = (non_noop, len(cmds), off, cmds)
    if best is None:
        return None, []
    return best[2], best[3]


def _load_text_strings(event_id):
    """Load `<event_id>_event_text.txt` as {text_id: line}. Returns {}
    if the file is missing. The sidecar lets us preview which text each
    `op 0x08` command references without leaving the parser, so the
    blueprint reads as a screenplay.
    """
    folder = Path(event_common.EVENT_ASSET_ROOT) / event_id
    p = folder / f"{event_id}_event_text.txt"
    if not p.exists():
        return {}
    out = {}
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if "," in line:
            k, _, v = line.partition(",")
            try:
                out[int(k)] = v
            except ValueError:
                pass
    return out


def _build_blueprint(bin_path):
    """Read header + manifest + script and assemble the blueprint."""
    actual_size = os.path.getsize(bin_path)
    event_id = os.path.basename(os.path.dirname(bin_path))
    text_strings = _load_text_strings(event_id)
    text_id_set = set(text_strings.keys())

    with open(bin_path, "rb") as f:
        header = event_common.read_event_header(f)
        manifest_start = f.tell()
        manifest_status = "ok"
        assets = []
        try:
            assets = event_common.read_asset_manifest(
                f, header["num_assets"]
            )
        except Exception as exc:  # noqa: BLE001 - record and continue
            manifest_status = f"unrecognised manifest variant: {exc}"
            f.seek(manifest_start)
        manifest_end = f.tell()
        post_manifest_preview = f.read(_PREVIEW_BYTES).hex()
        f.seek(0)
        raw = f.read()

    # --- script walk ----------------------------------------------------
    # A single event.bin often contains several independent script blocks
    # separated by metadata (sub-scene tables, branch records, etc.). We
    # walk forward from the first text anchor; when the walker bails on
    # a non-canonical opcode we scan ahead for the next text anchor and
    # resume, so every dialogue line in the file is captured.
    blocks = []
    next_search = manifest_end
    while True:
        anchor = event_script.find_first_text_anchor(
            raw, text_id_set, next_search
        )
        if anchor is None:
            break
        commands = []
        stop_record = None
        for rec in event_script.walk_script(raw, anchor, len(raw)):
            if "_stop" in rec:
                stop_record = rec
                break
            if rec["name"] == "text":
                tid = rec.get("text_id")
                if tid is not None and tid in text_strings:
                    preview = text_strings[tid]
                    if len(preview) > _TEXT_PREVIEW_CHARS:
                        preview = preview[:_TEXT_PREVIEW_CHARS] + "..."
                    rec["text_preview"] = preview
            commands.append(rec)
            if len(commands) >= _MAX_SCRIPT_CMDS:
                stop_record = {"_stop": "safety_cap", "limit": _MAX_SCRIPT_CMDS}
                break
        last_end = (commands[-1]["offset"] + 3 + commands[-1]["length"]
                    if commands else anchor)
        blocks.append({
            "block_index": len(blocks),
            "start_offset": anchor,
            "end_offset": last_end,
            "command_count": len(commands),
            "stop_record": stop_record,
            "commands": commands,
        })
        # Advance past the block (or at least past this anchor) before
        # searching for the next one, otherwise we'd loop forever on the
        # same anchor.
        next_search = max(last_end, anchor + 8)

    # Aggregate opcode histogram across all blocks.
    op_counter = Counter()
    len_per_op = {}
    for blk in blocks:
        for c in blk["commands"]:
            op_counter[c["op"]] += 1
            len_per_op.setdefault(c["op"], Counter())[c["length"]] += 1
    histogram = []
    for op, total in op_counter.most_common():
        named = event_script.NAMED_OPCODES.get(op)
        name = named[0] if named else f"op_0x{op:02x}"
        lengths = sorted(len_per_op[op].items())
        histogram.append({
            "op": op,
            "name": name,
            "count": total,
            "lengths": [{"length": L, "count": c} for L, c in lengths],
        })

    total_cmds = sum(b["command_count"] for b in blocks)
    if not blocks:
        script_block = {
            "block_count": 0,
            "command_count": 0,
            "parse_status": "no text anchor found",
            "opcode_histogram": [],
            "blocks": [],
        }
    else:
        full_blocks = [b for b in blocks if b["stop_record"] is None]
        partial_blocks = [b for b in blocks if b["stop_record"] is not None]
        if not partial_blocks:
            parse_status = (f"ok: {len(blocks)} block(s), "
                            f"{total_cmds} commands total")
        else:
            parse_status = (f"partial: {len(blocks)} block(s), "
                            f"{total_cmds} commands, "
                            f"{len(partial_blocks)} stopped on unknown opcode")
        script_block = {
            "block_count": len(blocks),
            "command_count": total_cmds,
            "first_block_start": blocks[0]["start_offset"],
            "last_block_end": blocks[-1]["end_offset"],
            "parse_status": parse_status,
            "opcode_histogram": histogram,
            "blocks": blocks,
        }

    # --- setup walk (inside pre_script, immediately before block 0) ----
    # We walk every non-fill offset between manifest_end+12 and the
    # first dialog block; the correct start is the one that lands
    # exactly on the dialog opcode.
    setup_start = None
    setup_cmds = []
    if blocks:
        setup_start, setup_cmds = _walk_setup_region(
            raw, manifest_end, blocks[0]["start_offset"]
        )

    blueprint = {
        "source_file": os.path.basename(bin_path),
        "event_id": event_id,
        "header": {
            "file_size": header["file_size"],
            "actual_file_size": actual_size,
            "file_size_matches": header["file_size"] == actual_size,
            "format_version": header["format_version"],
            "count_a": header["count_a"],
            "count_b": header["count_b"],
            "count_c": header["count_c"],
            "count_d": header["count_d"],
            "num_assets": header["num_assets"],
        },
        "asset_manifest": {
            "start_offset": manifest_start,
            "end_offset": manifest_end,
            "entry_count": len(assets),
            "parse_status": manifest_status,
            "entries": assets,
        },
        "pre_script": {
            "start_offset": manifest_end,
            "end_offset": script_block.get("first_block_start", actual_size)
                          if script_block.get("block_count") else actual_size,
            "size_bytes": (script_block.get("first_block_start", actual_size)
                           if script_block.get("block_count") else actual_size) - manifest_end,
            "preview_hex": post_manifest_preview,
            "setup_start_offset": setup_start,
            "setup_command_count": len(setup_cmds),
            "setup_commands": setup_cmds,
            "parse_status": (
                f"setup ok: {len(setup_cmds)} commands from offset "
                f"{setup_start}"
                if setup_cmds else
                "setup region not located"
            ),
        },
        "script": script_block,
    }
    return blueprint


def parse_event_bin(bin_path, verbose=True):
    out_path = event_common.default_blueprint_path(bin_path)
    blueprint = _build_blueprint(bin_path)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(blueprint, fh, indent=2, ensure_ascii=False)

    if verbose:
        h = blueprint["header"]
        m = blueprint["asset_manifest"]
        s = blueprint["script"]
        print(f"Wrote {out_path}")
        print(f"  file_size={h['file_size']} "
              f"({'ok' if h['file_size_matches'] else 'MISMATCH'}) "
              f"version={h['format_version']} "
              f"counts=({h['count_a']},{h['count_b']},{h['count_c']},{h['count_d']}) "
              f"assets={h['num_assets']}  manifest={m['parse_status']}")
        print(f"  script: {s['parse_status']}")
        ps = blueprint["pre_script"]
        print(f"  pre_script: {ps['parse_status']}")
        if s["opcode_histogram"]:
            top = s["opcode_histogram"][:10]
            top_s = ", ".join(f"{e['name']}×{e['count']}" for e in top)
            print(f"    top opcodes: {top_s}")
    return blueprint


def parse_all():
    files = sorted(Path(event_common.EVENT_ASSET_ROOT).rglob("*_event.bin"))
    files = [p for p in files if p.stat().st_size >= 28]
    ok = bad = mismatched = manifest_unrecognised = 0
    script_ok = script_partial = script_none = 0
    setup_ok = setup_none = 0
    for p in files:
        try:
            bp = parse_event_bin(str(p), verbose=False)
        except Exception as exc:  # noqa: BLE001 - keep going
            print(f"  ERR {p.parent.name}: {exc}")
            bad += 1
            continue
        ok += 1
        if not bp["header"]["file_size_matches"]:
            mismatched += 1
        if bp["asset_manifest"]["parse_status"] != "ok":
            manifest_unrecognised += 1
        sstatus = bp["script"]["parse_status"]
        if sstatus.startswith("ok:"):
            script_ok += 1
        elif sstatus.startswith("partial:"):
            script_partial += 1
        else:
            script_none += 1
        if bp["pre_script"].get("setup_command_count", 0) > 0:
            setup_ok += 1
        else:
            setup_none += 1
    print(f"\nbatch: ok={ok}/{len(files)}  hard_errors={bad}  "
          f"size_mismatch={mismatched}  manifest_unrecognised={manifest_unrecognised}")
    print(f"       script: ok={script_ok}  partial={script_partial}  "
          f"no_anchor={script_none}")
    print(f"       setup:  decoded={setup_ok}  none={setup_none}")


def main(argv):
    if len(argv) < 2:
        print("Usage: python event_parser.py <event_id>")
        print("       python event_parser.py --all")
        return 1
    if argv[1] == "--all":
        parse_all()
        return 0
    event_id = argv[1]
    bin_path = event_common.event_bin_path(event_id)
    if not bin_path:
        print(f"Error: no event.bin found for {event_id}")
        return 1
    parse_event_bin(bin_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
