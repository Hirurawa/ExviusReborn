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

# A text anchor can land *inside* an entity record's payload, where a `08 00 04`
# byte triple happens to be followed by an id that is really in the sidecar. The
# walk from such an anchor decodes garbage: it runs away for tens of kB and dies
# in a padding run. Measured over the corpus, blocks separate cleanly on the
# share of frames carrying a named opcode -- real script sits at 0.8..1.0 (692
# blocks), while runaways sit at or below 0.65. In 111010105 the false anchors
# score 0.636 / 0.651 against 0.731..0.929 for every real block.
#
# A candidate below the threshold is not dropped: we reject it and retry from
# the next anchor, so the real block further on is still found. Without this,
# 111010105 lost 16 of its 30 dialogue lines to a single runaway.
_BLOCK_MIN_NAMED_FRACTION = 0.70
_BLOCK_GATE_MIN_FRAMES = 10   # too few frames to judge; accept and move on


def _walk_setup_region(raw, ps_start, ps_end, record_offsets=()):
    """Locate and walk the setup-opcode region inside a pre_script.

    The pre_script begins with a small fixed header, then the sub-scene's
    entity-record table, then a setup-opcode stream that flows directly into the
    first dialog frame at ``ps_end``.

    We don't yet know how to derive the setup-start offset from the header, so we
    brute-force it: try every non-fill byte offset between ``ps_start + 12`` and
    ``ps_end`` and keep the ones at which ``walk_script`` walks cleanly (no stop
    record) and the *next* frame after the last walked command begins exactly at
    ``ps_end``.

    ⚠️ Many offsets satisfy that. A false sync point still lands on ``ps_end``
    because the misread ``<op> <length>`` pairs happen to swallow whole regions
    in one phantom long frame and resync afterwards -- so the choice among
    candidates is the whole ballgame. This used to prefer the **earliest**
    candidate, which is systematically the worst one: the earliest clean walk
    starts inside the entity-record table and swallows the real setup frames.
    In 111010105 it started at 7028, read the record table as a 58-byte
    `op_0x66` plus a 256-byte `op_0x64`, and ate the two absolute `move_actor`
    spawns at 7182/7200 -- so the party had no initial placement at all and
    every actor rendered stacked at (0,0). 154 of 497 files were affected.

    Two signals separate real sync points from false ones:

    * **A real frame never swallows an entity record.** Record offsets are known
      exactly (`find_entity_records`), so any candidate with a record header
      strictly inside a frame's payload is out of sync.
    * **A named opcode has a fixed payload length** (`NAMED_OPCODE_LENGTHS`).
      A `camera_scroll` of length 1542 (111010201 @15993) is not a camera
      scroll; it is proof the walk is misaligned.

    Among the survivors we take the one decoding the most well-formed named
    frames, tie-broken by the earliest offset. Pools are tried in decreasing
    strictness so a file whose true setup genuinely trips a signal still gets
    its best-effort walk rather than nothing.

    Returns ``(start_offset, commands, sync_quality)``, or ``(None, [], None)``
    if nothing parses cleanly.
    """
    if ps_end <= ps_start + 12:
        return None, [], None
    candidates = []
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
        swallows_record = any(
            any(c["offset"] < r < c["offset"] + 3 + c["length"]
                for r in record_offsets)
            for c in cmds
        )
        malformed = sum(1 for c in cmds
                        if c["op"] in event_script.NAMED_OPCODE_LENGTHS
                        and c["length"] != event_script.NAMED_OPCODE_LENGTHS[c["op"]])
        candidates.append({
            "offset": off,
            "commands": cmds,
            "swallows_record": swallows_record,
            "malformed": malformed,
            "well_formed": sum(1 for c in cmds if event_script.is_well_formed(c)),
        })
    if not candidates:
        return None, [], None
    pools = [
        ("clean", [c for c in candidates
                   if not c["swallows_record"] and not c["malformed"]]),
        ("malformed_frames", [c for c in candidates
                              if not c["swallows_record"]]),
        ("record_overlap", candidates),
    ]
    for quality, pool in pools:
        if not pool:
            continue
        best = max(pool, key=lambda c: (c["well_formed"], -c["offset"]))
        return best["offset"], best["commands"], quality
    return None, [], None


def _group_entity_tables(records):
    """Split a file's entity records into tables, one per sub-scene.

    Record slots are not a single monotonic sequence over the file -- they
    restart, so a slot that is not greater than its predecessor marks the start
    of a new table. 111020101 splits into 4 tables this way, matching its four
    fade-separated sub-scenes.

    Provisional: slots rise monotonically *within* a table, so this rule cannot
    see a table that is interrupted by a script region. 111010105's "table 4"
    (slots 3, 9, 13) is really two tables with a dialogue block between them.
    Use `records` for anything load-bearing; the grouping is for readability.
    """
    tables = []
    current = None
    prev_slot = None
    for rec in records:
        if current is None or prev_slot is None or rec["slot"] <= prev_slot:
            current = {
                "table_index": len(tables),
                "start_offset": rec["offset"],
                "records": [],
            }
            tables.append(current)
        current["records"].append(rec)
        prev_slot = rec["slot"]
    for t in tables:
        t["record_count"] = len(t["records"])
        t["end_offset"] = t["records"][-1]["offset"]
    return tables


def _annotate_actor_refs(commands, by_rid):
    """Resolve `actor_rid` on actor-scoped commands to its entity record.

    Adds `actor_identity` (the npc texture / instance id the actor is drawn
    with) and `actor_spawn` (the record's pixel position) so a command can be
    played back without a second lookup pass.
    """
    resolved = unresolved = 0
    for cmd in commands:
        rid = cmd.get("actor_rid")
        if rid is None:
            continue
        rec = by_rid.get(rid)
        if rec is None:
            cmd["actor_record"] = None
            unresolved += 1
            continue
        resolved += 1
        cmd["actor_record_offset"] = rec["offset"]
        if "identity" in rec:
            cmd["actor_identity"] = rec["identity"]
        cmd["actor_spawn"] = {"x": rec["src_x"], "y": rec["src_y"]}
    return resolved, unresolved


def _load_text_strings(event_id, folder=None):
    """Load `<event_id>_event_text.txt` as {text_id: line}. Returns {}
    if the file is missing. The sidecar lets us preview which text each
    `op 0x08` command references without leaving the parser, so the
    blueprint reads as a screenplay.

    `folder` defaults to the folder named after `event_id`, but 136 of the 502
    bins live in a folder named for a *different* event id (e.g.
    `111020201/111020101_event.bin`), and their sidecar is named after the bin.
    Callers that know the real folder should pass it.
    """
    folder = Path(folder) if folder else Path(event_common.EVENT_ASSET_ROOT) / event_id
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
    folder = os.path.dirname(os.path.abspath(bin_path))
    folder_id = os.path.basename(folder)
    # The event id is the bin's own name, not its folder's: 136 bins sit in a
    # folder named for another event, and their text sidecar follows the bin.
    basename = os.path.basename(bin_path)
    event_id = (basename[:-len("_event.bin")]
                if basename.endswith("_event.bin") else folder_id)
    text_strings = _load_text_strings(event_id, folder)
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
    # --- embedded entity records ---------------------------------------------
    # Tables of actor / asset declarations interleaved with the script. These
    # are what the old walker mis-read as 781-byte `op_0x00` blobs; see
    # event_script.decode_entity_record.
    # Prefer the block framing: the post-manifest region is a chain of sized
    # blocks, and each block header states how many entity records its body
    # holds, so records are picked against a known count instead of being
    # fished out of the whole file. Fall back to the blind scan when a bin
    # does not frame cleanly.
    block_frames = event_script.find_blocks(raw, manifest_end)
    if block_frames:
        entity_records, blocks_agreeing, blocks_with_entities = (
            event_script.find_entity_records_blockwise(raw, block_frames))
        entity_framing = {
            "source": "block_framed",
            "block_count": len(block_frames),
            "blocks_with_entities": blocks_with_entities,
            "blocks_matching_declared_count": blocks_agreeing,
            "declared_entity_total": sum(bl["num_entities"]
                                         for bl in block_frames),
        }
    else:
        entity_records = event_script.find_entity_records(raw, manifest_end)
        entity_framing = {"source": "scan", "block_count": 0}
    entity_by_rid = {r["rid"]: r for r in entity_records}
    entity_tables = _group_entity_tables(entity_records)

    blocks = []
    rejected = []
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
        named = sum(1 for c in commands
                    if c["op"] in event_script.NAMED_OPCODES)
        named_fraction = named / len(commands) if commands else 0.0
        if (len(commands) >= _BLOCK_GATE_MIN_FRAMES
                and named_fraction < _BLOCK_MIN_NAMED_FRACTION):
            # False anchor inside record data -- retry from the next anchor
            # rather than letting this runaway consume the region.
            rejected.append({
                "start_offset": anchor,
                "end_offset": last_end,
                "command_count": len(commands),
                "named_fraction": round(named_fraction, 3),
                "reason": "named_opcode_fraction below threshold",
                "_commands": commands,
                "_stop_record": stop_record,
            })
            next_search = anchor + 8
            continue
        _annotate_actor_refs(commands, entity_by_rid)
        blocks.append({
            "block_index": len(blocks),
            "start_offset": anchor,
            "end_offset": last_end,
            "command_count": len(commands),
            "named_fraction": round(named_fraction, 3),
            "stop_record": stop_record,
            "commands": commands,
        })
        # Advance past the block (or at least past this anchor) before
        # searching for the next one, otherwise we'd loop forever on the
        # same anchor.
        next_search = max(last_end, anchor + 8)

    # If the gate rejected every candidate, keep the best one rather than
    # reporting nothing: a low-confidence block is still more than no block, and
    # 14 files would otherwise go from "partial" to "no anchor".
    if not blocks and rejected:
        best = max(rejected, key=lambda r: (r["named_fraction"],
                                            r["command_count"]))
        rejected.remove(best)
        commands = best.pop("_commands")
        _annotate_actor_refs(commands, entity_by_rid)
        blocks.append({
            "block_index": 0,
            "start_offset": best["start_offset"],
            "end_offset": best["end_offset"],
            "command_count": len(commands),
            "named_fraction": best["named_fraction"],
            "low_confidence": True,
            "stop_record": best.pop("_stop_record"),
            "commands": commands,
        })
    for r in rejected:
        r.pop("_commands", None)
        r.pop("_stop_record", None)

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
            "rejected_anchors": rejected,
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
            "rejected_anchors": rejected,
            "blocks": blocks,
        }

    # --- setup walk (inside pre_script, immediately before block 0) ----
    # We walk every non-fill offset between manifest_end+12 and the first dialog
    # block, then choose among the candidates that land exactly on the dialog
    # opcode. The entity-record offsets are load-bearing for that choice -- a
    # candidate whose frames swallow a record is out of sync.
    setup_start = None
    setup_cmds = []
    setup_sync = None
    if blocks:
        pre_script_records = [r["offset"] for r in entity_records
                              if r["offset"] < blocks[0]["start_offset"]]
        setup_start, setup_cmds, setup_sync = _walk_setup_region(
            raw, manifest_end, blocks[0]["start_offset"], pre_script_records
        )

    actor_refs = [c for b in blocks for c in b["commands"]
                  if c.get("actor_rid") is not None]
    resolved_refs = sum(1 for c in actor_refs if c.get("actor_record") is not None
                        or "actor_record_offset" in c)

    blueprint = {
        "source_file": os.path.basename(bin_path),
        "event_id": event_id,
        "folder_id": folder_id,
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
            # Which pool the sync point came from: "clean" (no record swallowed,
            # every named frame the right length), or a named signal the chosen
            # candidate trips -- treat those as low confidence.
            "setup_sync": setup_sync,
            "setup_commands": setup_cmds,
            "parse_status": (
                f"setup ok ({setup_sync}): {len(setup_cmds)} commands from "
                f"offset {setup_start}"
                if setup_cmds else
                "setup region not located"
            ),
        },
        "blocks": block_frames,
        "entities": {
            "record_count": len(entity_records),
            "framing": entity_framing,
            "table_count": len(entity_tables),
            "actor_ref_count": len(actor_refs),
            "actor_refs_resolved": resolved_refs,
            "tables": entity_tables,
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
    setup_sync = Counter()
    setup_abs_spawns = 0
    stop_reasons = Counter()
    entity_records = entity_tables = 0
    refs_total = refs_resolved = 0
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
            setup_sync[bp["pre_script"].get("setup_sync")] += 1
            setup_abs_spawns += sum(
                1 for c in bp["pre_script"]["setup_commands"]
                if c["name"] == "move_actor" and c.get("mode") == "absolute")
        else:
            setup_none += 1
        for blk in bp["script"]["blocks"]:
            sr = blk.get("stop_record")
            stop_reasons[sr["_stop"] if sr else "clean_end"] += 1
        ent = bp["entities"]
        entity_records += ent["record_count"]
        entity_tables += ent["table_count"]
        refs_total += ent["actor_ref_count"]
        refs_resolved += ent["actor_refs_resolved"]
    print(f"\nbatch: ok={ok}/{len(files)}  hard_errors={bad}  "
          f"size_mismatch={mismatched}  manifest_unrecognised={manifest_unrecognised}")
    print(f"       script: ok={script_ok}  partial={script_partial}  "
          f"no_anchor={script_none}")
    print(f"       setup:  decoded={setup_ok}  none={setup_none}  "
          f"absolute_spawns={setup_abs_spawns}  sync: "
          + "  ".join(f"{k}={v}" for k, v in setup_sync.most_common()))
    print(f"       block stops: "
          + "  ".join(f"{k}={v}" for k, v in stop_reasons.most_common()))
    print(f"       entities: {entity_records} records in {entity_tables} tables; "
          f"actor refs resolved {refs_resolved}/{refs_total}")


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
