#!/usr/bin/env python3
"""Opcode inventory for skill_schema.json and passive_schema.json.

Walks every record in ffbe-data.db that carries opcodes (processId) and measures what
the two opcode schemas cover: which opcodes are used where, how often, with which param
shapes, and which are still unmapped. Use it two ways:

  * as a coverage check -- after editing a schema, rerun it to see coverage by
    confidence and family, and which opcodes are left unmapped;
  * as an inspector -- pass opcode numbers to print per-slot value statistics next to
    the schema's key names, plus sample skills.

Samples prefer skills whose ONLY effect is the opcode, so their description maps 1:1 to
it, and skip rows described as test data. Active and passive opcodes are separate
namespaces (99 is REPLACEMENT on an active ability and a damage-limit boost on a
passive), so each kind reads its own schema. Limit bursts are read from their base row;
per-level params live in limitburst_lv.

A schema entry may carry `variants`: [{"match": {"param_count": N}, "type": ..., "keys":
...}]. The first variant whose match holds replaces the entry for that effect.

Usage:
    python tools/opcode_inventory.py                       # coverage, both kinds
    python tools/opcode_inventory.py --kind active 130 53  # inspect active opcodes
    python tools/opcode_inventory.py --kind passive 73     # inspect a passive opcode
    python tools/opcode_inventory.py --report <dir>        # full markdown + JSON reports
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = REPO_ROOT / "godot" / "assets" / "static_data" / "ffbe-data.db"
SCHEMA_DIR = REPO_ROOT / "godot" / "features" / "battle" / "logic"
SCHEMA_PATHS = {
    "active": SCHEMA_DIR / "skill_schema.json",
    "passive": SCHEMA_DIR / "passive_schema.json",
}

# Every query yields (id, name, target, targetRange, processId, processParam, description).
SOURCES = {
    "active": {
        "ability": "SELECT a.abilityId, a.name, a.target, a.targetRange, a.processId, a.processParam, e.explainShort"
                   " FROM ability a LEFT JOIN ability_explain e ON e.abilityId = a.abilityId WHERE a.abilityType = 2",
        "magic": "SELECT m.magicId, m.name, m.target, m.targetRange, m.processId, m.processParam, e.explainShort"
                 " FROM magic m LEFT JOIN magic_explain e ON e.magicId = m.magicId",
        "limitburst": "SELECT limitBurstId, name, target, targetRange, processId, processParam, description FROM limitburst",
        "esper": "SELECT beastSkillId, name, target, targetRange, processId, processParam, description FROM beast_skill",
        "monster": "SELECT monsterSkillId, name, target, targetRange, processId, processParam, '' FROM monster_skill",
        "item": "SELECT itemId, name, target, targetRange, processId, processParam, '' FROM item",
    },
    "passive": {
        "ability": "SELECT a.abilityId, a.name, '', '', a.processId, a.processParam, e.explainShort"
                   " FROM ability a LEFT JOIN ability_explain e ON e.abilityId = a.abilityId WHERE a.abilityType = 1",
        "monster": "SELECT passiveSkillId, name, '', '', processId, processParam, '' FROM monster_passive_skill",
    },
}

CONFIDENCES = ("verified", "strong", "hypothesis")
# Slot values OpcodeParser treats as "nothing here" (it drops zeros, empty strings and "none").
EMPTY_VALUES = ("0", "", "none")
# Key names OpcodeParser.map_payload drops, so their slot never reaches a handler.
DROPPED_KEYS = ("", "UNKNOWN", "???")
SAMPLES_SINGLE = 8
SAMPLES_MULTI = 4
TOP_VALUES = 6


def split_groups(raw) -> list[str]:
    return [] if raw is None or str(raw) == "" else str(raw).split("@")


def broadcast(groups: list[str], i: int) -> str:
    if not groups:
        return ""
    return groups[i] if i < len(groups) else groups[-1]


def slot_kind(token: str) -> str:
    if any(sep in token for sep in "&:;"):
        return "list"
    if re.fullmatch(r"-?\d+", token):
        return "int"
    if re.fullmatch(r"-?\d+\.\d+", token):
        return "float"
    return "str"


def is_english(text: str) -> bool:
    return bool(text) and all(ord(ch) < 0x2000 for ch in text)


def is_test_row(effect: dict) -> bool:
    return "test data" in effect["desc"].lower()


def resolve_entry(schema: dict, op: str, param_count: int) -> dict | None:
    """The schema entry that applies to one effect, honouring `variants`."""
    entry = schema.get(op)
    if entry is None:
        return None
    for variant in entry.get("variants", []):
        if variant.get("match", {}).get("param_count") == param_count:
            return variant
    return entry


def load_effects(con: sqlite3.Connection, kind: str) -> list[dict]:
    effects = []
    for source, sql in SOURCES[kind].items():
        for sid, name, target, rng, proc, param, desc in con.execute(sql):
            procs = [p.strip() for p in split_groups(proc)]
            if not procs:
                continue
            targets, ranges, params = split_groups(target), split_groups(rng), split_groups(param)
            for i, op in enumerate(procs):
                if op in ("", "0"):
                    continue
                raw = params[i] if i < len(params) else ""
                effects.append({
                    "source": source, "id": str(sid), "name": name or "",
                    "desc": (desc or "").replace("\n", " ").replace("<br>", " "),
                    "idx": i, "n": len(procs), "ops": procs, "op": op,
                    "range": broadcast(ranges, i), "target": broadcast(targets, i),
                    "slots": raw.split(",") if raw != "" else [], "raw": raw,
                })
    return effects


def pick_samples(rows: list[dict], single: bool, limit: int) -> list[dict]:
    pool = [r for r in rows if (r["n"] == 1) == single and not is_test_row(r)]
    pool.sort(key=lambda r: (not is_english(r["desc"]), r["desc"] == "", r["source"] != "ability"))
    seen, picked = set(), []
    for r in pool:
        key = (r["desc"], r["raw"])
        if key in seen:
            continue
        seen.add(key)
        picked.append(r)
        if len(picked) >= limit:
            break
    return picked


def summarize(op: str, rows: list[dict], schema: dict) -> dict:
    arity = collections.Counter(len(r["slots"]) for r in rows)
    entry = schema.get(op)
    resolved = collections.Counter()
    for r in rows:
        e = resolve_entry(schema, op, len(r["slots"]))
        resolved[e.get("type") if e else None] += 1
    main_keys = (entry or {}).get("keys", [])
    slots = []
    for s in range(max(arity)):
        vals = [r["slots"][s] for r in rows if len(r["slots"]) > s]
        ints = [int(v) for v in vals if slot_kind(v) == "int"]
        slots.append({
            "slot": s,
            "key": main_keys[s] if s < len(main_keys) else None,
            "present": len(vals),
            "carries_data": any(v not in EMPTY_VALUES for v in vals),
            "kinds": dict(collections.Counter(slot_kind(v) for v in vals)),
            "nonzero_pct": round(100.0 * sum(1 for v in vals if v not in ("0", "")) / max(1, len(vals))),
            "min": min(ints) if ints else None,
            "max": max(ints) if ints else None,
            "distinct": len(set(vals)),
            "top": [[v[:48], c] for v, c in collections.Counter(vals).most_common(TOP_VALUES)],
        })
    co_ops = collections.Counter(o for r in rows for o in set(r["ops"]) if o != op)
    return {
        "op": op,
        "mapped": entry is not None,
        "type": (entry or {}).get("type"),
        "family": (entry or {}).get("family"),
        "confidence": (entry or {}).get("confidence"),
        "keys": (entry or {}).get("keys"),
        "notes": (entry or {}).get("notes"),
        "variant_types": {str(k): v for k, v in resolved.items()} if len(resolved) > 1 else None,
        "effects": len(rows),
        "skills": len({(r["source"], r["id"]) for r in rows}),
        "by_source": dict(collections.Counter(r["source"] for r in rows).most_common()),
        "arity": {str(k): v for k, v in arity.most_common()},
        "targets": dict(collections.Counter(f"{r['range']}/{r['target']}" for r in rows).most_common(6)),
        "co_ops": co_ops.most_common(8),
        "slots": slots,
        "single_samples": [sample_view(r) for r in pick_samples(rows, True, SAMPLES_SINGLE)],
        "multi_samples": [sample_view(r) for r in pick_samples(rows, False, SAMPLES_MULTI)],
    }


def sample_view(r: dict) -> dict:
    return {k: r[k] for k in ("source", "id", "name", "desc", "raw", "range", "target", "idx")} | {"ops": "@".join(r["ops"])}


def build(kind: str, con: sqlite3.Connection) -> dict:
    schema = json.loads(SCHEMA_PATHS[kind].read_text(encoding="utf-8"))
    by_op = collections.defaultdict(list)
    for effect in load_effects(con, kind):
        by_op[effect["op"]].append(effect)
    entries = sorted((summarize(op, rows, schema) for op, rows in by_op.items()), key=lambda e: -e["effects"])
    total = sum(e["effects"] for e in entries)
    mapped = [e for e in entries if e["mapped"]]
    by_conf = collections.OrderedDict((c, [0, 0]) for c in CONFIDENCES + ("unrated",))
    by_family = collections.Counter()
    for e in mapped:
        bucket = by_conf[e["confidence"] if e["confidence"] in CONFIDENCES else "unrated"]
        bucket[0] += 1
        bucket[1] += e["effects"]
        by_family[e["family"] or "none"] += e["effects"]
    # Slots past the end of `keys` that ever hold a real value: data the parser silently drops.
    short_keys = [e["op"] for e in mapped if e["keys"] is not None
                  and any(s["carries_data"] for s in e["slots"][len(e["keys"]):])]
    # Slots inside `keys` whose name OpcodeParser drops ("", UNKNOWN, ???) but that hold a
    # real value: how opcode 13's wield mode went missing until 2026-09-30.
    unnamed = [f"{e['op']}:{','.join(str(s['slot']) for s in e['slots'] if s['key'] in DROPPED_KEYS and s['carries_data'])}"
               for e in mapped
               if any(s["key"] in DROPPED_KEYS and s["carries_data"] for s in e["slots"])]
    return {
        "kind": kind,
        "schema": str(SCHEMA_PATHS[kind].relative_to(REPO_ROOT)).replace("\\", "/"),
        "totals": {
            "opcodes_used": len(entries),
            "mapped": len(mapped),
            "unmapped": len(entries) - len(mapped),
            "effect_instances": total,
            "mapped_instances": sum(e["effects"] for e in mapped),
            "schema_entries_unused": sorted(set(schema) - set(by_op), key=lambda x: int(x) if x.isdigit() else 0),
            "entries_with_unnamed_trailing_slots": short_keys,
            "entries_with_data_in_unnamed_slots": unnamed,
        },
        "by_confidence": {c: {"opcodes": v[0], "instances": v[1]} for c, v in by_conf.items()},
        "by_family": dict(by_family.most_common()),
        "opcodes": entries,
    }


def pct(part: int, whole: int) -> str:
    return f"{100.0 * part / max(1, whole):.1f}%"


def summary_lines(inv: dict) -> list[str]:
    t = inv["totals"]
    total = t["effect_instances"]
    lines = [
        f"== {inv['kind']} opcodes ({inv['schema']})",
        f"opcodes used {t['opcodes_used']}, mapped {t['mapped']}, unmapped {t['unmapped']}",
        f"effect instances {total}, mapped {t['mapped_instances']} ({pct(t['mapped_instances'], total)})",
        "mapped by confidence: " + ", ".join(
            f"{c} {v['opcodes']} ops / {pct(v['instances'], total)}" for c, v in inv["by_confidence"].items() if v["opcodes"]),
        "mapped by family: " + ", ".join(f"{f} {pct(n, total)}" for f, n in inv["by_family"].items()),
    ]
    if t["schema_entries_unused"]:
        lines.append(f"schema entries no record uses: {t['schema_entries_unused']}")
    if t["entries_with_unnamed_trailing_slots"]:
        lines.append(f"entries with data in slots past their keys: {t['entries_with_unnamed_trailing_slots']}")
    if t["entries_with_data_in_unnamed_slots"]:
        lines.append(f"entries with data in unnamed slots (op:slots): {t['entries_with_data_in_unnamed_slots']}")
    unmapped = [e for e in inv["opcodes"] if not e["mapped"]]
    if unmapped:
        lines.append("unmapped (op instances sources):")
        for e in unmapped:
            src = ", ".join(f"{k} {v}" for k, v in e["by_source"].items())
            lines.append(f"  {e['op']:>6} {e['effects']:>6}  {src}")
    return lines


def detail_lines(e: dict) -> list[str]:
    head = f"-- op {e['op']}: " + (f"{e['type']} [{e['family']}, {e['confidence']}]" if e["mapped"] else "UNMAPPED")
    lines = [head,
             f"effects {e['effects']} in {e['skills']} skills, sources {e['by_source']}",
             f"param counts {e['arity']}, targets (range/target) {e['targets']}",
             f"co-occurs with {e['co_ops']}"]
    if e["notes"]:
        lines.append(f"notes: {e['notes']}")
    if e["variant_types"]:
        lines.append(f"resolved types by variant: {e['variant_types']}")
    for s in e["slots"]:
        key = "" if s["key"] is None else (s["key"] or "-")
        top = " ".join(f"{v}x{c}" for v, c in s["top"])
        lines.append(f"  slot {s['slot']:>2} {key:<18} n={s['present']:<6} nz={s['nonzero_pct']:>3}% "
                     f"[{s['min']}, {s['max']}] distinct={s['distinct']:<5} {top}")
    for label, samples in (("single", e["single_samples"]), ("multi", e["multi_samples"])):
        for r in samples:
            where = f"#{r['idx']} of {r['ops']}" if label == "multi" else f"t{r['range']}/{r['target']}"
            lines.append(f"  {label:<6} [{r['source']} {r['id']}] {r['name'][:32]} | {r['raw'][:64]} | {where} | {r['desc'][:150]}")
    return lines


def report_markdown(inv: dict) -> str:
    lines = [f"# {inv['kind'].capitalize()} opcode inventory", "", f"Schema: `{inv['schema']}`", "", "```"]
    lines += summary_lines(inv)
    lines += ["```", "", "| op | type | family | confidence | effects | skills | sources | param counts |", "|---|---|---|---|---|---|---|---|"]
    for e in inv["opcodes"]:
        src = ", ".join(f"{k} {v}" for k, v in e["by_source"].items())
        ar = ", ".join(f"{k}:{v}" for k, v in list(e["arity"].items())[:3])
        lines.append(f"| {e['op']} | {e['type'] or '**unmapped**'} | {e['family'] or ''} | {e['confidence'] or ''} "
                     f"| {e['effects']} | {e['skills']} | {src} | {ar} |")
    for e in inv["opcodes"]:
        lines += ["", "```"] + detail_lines(e) + ["```"]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("ops", nargs="*", help="opcodes to inspect")
    parser.add_argument("--kind", choices=("active", "passive", "both"), default=None,
                        help="which schema (default: both for coverage, active for inspection)")
    parser.add_argument("--report", metavar="DIR", help="write <kind>_opcodes.md and .json into DIR")
    args = parser.parse_args()

    kind = args.kind or ("active" if args.ops else "both")
    kinds = ("active", "passive") if kind == "both" else (kind,)
    con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    inventories = {k: build(k, con) for k in kinds}

    if args.ops:
        for k, inv in inventories.items():
            index = {e["op"]: e for e in inv["opcodes"]}
            for op in args.ops:
                if op in index:
                    print("\n".join(detail_lines(index[op])) + "\n")
                else:
                    print(f"-- op {op}: not used by any {k} record\n")
        return 0

    for inv in inventories.values():
        print("\n".join(summary_lines(inv)) + "\n")
    if args.report:
        out = Path(args.report)
        out.mkdir(parents=True, exist_ok=True)
        for k, inv in inventories.items():
            (out / f"{k}_opcodes.md").write_text(report_markdown(inv), encoding="utf-8")
            (out / f"{k}_opcodes.json").write_text(json.dumps(inv, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"reports written to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
