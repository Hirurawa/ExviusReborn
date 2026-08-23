#!/usr/bin/env python3
"""Reference oracle for the monster AI compile layer.

A line-for-line port of features/battle/logic/monster_ai_script.gd (the parse) and
monster_ai_resolver.gd (the labels), run over the whole `ai` table. Use it two ways:

  * as a regression check -- it asserts the compile layer's invariants across all
    49944 rows and reports how many condition atoms still fall through to a raw
    label, so a change to either GDScript file can be mirrored here and measured;
  * as an inspector -- pass monsterIds to print their decoded scripts.

Keep this in step with the GDScript when the grammar understanding changes; the
whole point is that the two implementations agree.

Usage:
    python tools/check_monster_ai.py                     # invariants + coverage
    python tools/check_monster_ai.py 900011280 205031003 # decode these monsters
"""

from __future__ import annotations

import collections
import math
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = REPO_ROOT / "godot" / "assets" / "static_data" / "ffbe-data.db"

VERB_SKILL, VERB_TURN_END = "skill", "turn_end"
SKILL_INDEX_RANDOM, SKILL_INDEX_NONE = 0, -1
SCOPES = {1: "SELF", 2: "MONSTER_ID", 3: "ENEMY_SLOT", 4: "PARTY",
          5: "INCOMING_ACTION", 7: "PARTY_SLOT", 8: "MONSTER_PART"}

c = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
c.row_factory = sqlite3.Row
warnings = []


def load_skill_slots(raw):
    if raw is None:
        return []
    slots = raw.split(",")
    while slots and slots[-1] == "":
        slots.pop()
    return slots


def parse_trigger(slot):
    f = slot.split(":")
    if len(f) != 4 or f[2] == "non":
        return None
    return {"scope": int(f[0]) if f[0].lstrip("-").isdigit() else 0,
            "subject": f[1], "type": f[2], "param": f[3]}


def parse_atom(text):
    h = text.split(":", 1)
    return {"type": h[0], "params": h[1].split(",") if len(h) > 1 else []}


def parse_writes(group):
    fields = group.split(",")
    out, i = [], 0
    while i + 1 < len(fields):
        a, b = fields[i], fields[i + 1]
        i += 2
        if not _isint(a) or not _isint(b):
            continue
        if int(a) < 0:
            continue
        out.append({"id": int(a), "value": int(b)})
    return out


def _isint(s):
    return s.lstrip("-").isdigit() and s.strip() != ""


def compile_rule(row):
    raw = str(row["rule"] or "")
    segments = raw.split("@")
    cut = next((i for i, s in enumerate(segments) if s.startswith("#")), -1)
    triggers, conditions, skill_index = [], [], SKILL_INDEX_NONE
    if cut == -1:
        warnings.append(f"no '#' separator: m={row['monsterId']} order={row['ruleOrder']}")
    else:
        for i in range(cut):
            t = parse_trigger(segments[i])
            if t:
                triggers.append(t)
        for i in range(cut, len(segments)):
            text = segments[i][1:] if i == cut else segments[i]
            if text == "":
                continue
            atom = parse_atom(text)
            if atom["type"] == VERB_SKILL:
                p = atom["params"]
                found = int(p[0]) if p and _isint(p[0]) else SKILL_INDEX_NONE
                if skill_index == SKILL_INDEX_NONE:
                    skill_index = found
                elif found != skill_index:
                    warnings.append(f"two skills {skill_index},{found}: m={row['monsterId']} order={row['ruleOrder']}")
                continue
            if atom["type"] != "non" and atom["type"] != "":
                conditions.append(atom)
    cg = str(row["command"] or "").split("@")
    ts = str(row["targetSelect"] or "").split(":")
    return {"order": row["ruleOrder"], "triggers": triggers, "conditions": conditions,
            "verb": cg[0] if cg else "", "skill_index": skill_index,
            "flg_writes": parse_writes(cg[1] if len(cg) > 1 else ""),
            "flg2_writes": parse_writes(cg[2] if len(cg) > 2 else ""),
            "target_mode": ts[0] if ts else "",
            "target_param": int(ts[1]) if len(ts) > 1 and _isint(ts[1]) else 0,
            "probability": float(row["probability"] or 0.0), "raw": raw}


# ---- the resolver's label tables, to measure fallback coverage ----
KNOWN = {"non", "flg_on", "flg_off", "flg2_on", "flg2_off", "flg_cntup_act", "flg2_cntup_act",
         "flg_cntup_over", "flg2_cntup_over", "flg_cntup_under", "flg2_cntup_under",
         "flg_timer_act", "flg_timer_over", "flg_timer_under", "hp_pr_under", "hp_pr_over",
         "lb_pr_over", "actbetween", "act", "turn_act", "limited_act", "alive", "outside_field",
         "breaking", "abnormal_state", "normal_state", "stup_buff", "stdown_buff", "rifrect_mode",
         "party_alive_num", "party_members", "total_damage_over", "turn_damage_over",
         "turn_damage_over_new", "join_party", "special_user_id", "magic_user_id"}
HIT_ELEMENTS = {"fire", "ice", "thunder", "water", "aero", "quake", "light", "dark", "none", "elem_none"}


def labelled(type_):
    if type_ in KNOWN or type_.startswith("before_turn_"):
        return True
    for prefix, _ in (("physics_and_magic_elem_", 0), ("physics_", 0), ("magic_", 0)):
        if type_.startswith(prefix):
            rest = type_[len(prefix):]
            if rest.endswith("_lb"):
                rest = rest[:-3]
            return rest in HIT_ELEMENTS
    return False


rows = [dict(r) for r in c.execute("select * from ai order by monsterId, ruleOrder")]
slots_by_monster = {m: load_skill_slots(s) for m, s in c.execute("select monsterId, skillId from monster_skill_set")}

by_monster = collections.defaultdict(list)
for r in rows:
    by_monster[r["monsterId"]].append(compile_rule(r))

# ---- invariants ----
print(f"rows compiled: {len(rows)}  monsters: {len(by_monster)}")
print(f"warnings emitted: {len(warnings)}")
for w in warnings[:5]:
    print("   ", w)

bad = collections.Counter()
skill_state = collections.Counter()
unlabelled_cond = collections.Counter()
unlabelled_trig = collections.Counter()
scope_counts = collections.Counter()
write_ids = {"flg": collections.Counter(), "flg2": collections.Counter()}
verbs = collections.Counter()

for mid, rules in by_monster.items():
    slots = slots_by_monster.get(mid, [])
    for rule in rules:
        verbs[rule["verb"]] += 1
        # no condition may be a skill payload or padding
        for cond in rule["conditions"]:
            if cond["type"] in (VERB_SKILL, "non"):
                bad["condition is payload/padding"] += 1
            if not labelled(cond["type"]):
                unlabelled_cond[cond["type"]] += 1
        for trig in rule["triggers"]:
            scope_counts[SCOPES.get(trig["scope"], f"UNKNOWN({trig['scope']})")] += 1
            if not labelled(trig["type"]):
                unlabelled_trig[trig["type"]] += 1
        # skill payload resolution
        n = rule["skill_index"]
        if rule["verb"] == VERB_SKILL:
            if n == SKILL_INDEX_NONE:
                skill_state["verb=skill but no payload"] += 1
            elif n == SKILL_INDEX_RANDOM:
                skill_state["random from set"] += 1
            elif 1 <= n <= len(slots) and slots[n - 1] != "":
                skill_state["resolved"] += 1
            elif 1 <= n <= len(slots):
                skill_state["lands on blank slot"] += 1
            else:
                skill_state["index outside skill set"] += 1
        elif n != SKILL_INDEX_NONE:
            skill_state["non-skill verb with payload"] += 1
        for w in rule["flg_writes"]:
            write_ids["flg"][w["id"]] += 1
        for w in rule["flg2_writes"]:
            write_ids["flg2"][w["id"]] += 1
        if not (0.0 <= rule["probability"] <= 100.0):
            bad["probability out of range"] += 1
        if rule["target_mode"] == "":
            bad["empty target mode"] += 1

print("\nINVARIANT VIOLATIONS:", dict(bad) or "none")
print("\nskill payload resolution:")
for k, v in skill_state.most_common():
    print(f"   {v:6d}  {k}")
print("\ncommand verbs:", dict(verbs))
print("\ntrigger scopes seen:", dict(scope_counts))
print(f"\nflg write ids: {min(write_ids['flg'])}..{max(write_ids['flg'])}   "
      f"flg2 write ids: {min(write_ids['flg2'])}..{max(write_ids['flg2'])}")
print("\ncondition types with NO label (fall through to raw):",
      unlabelled_cond.most_common(12) or "none")
print("trigger types with NO label:", unlabelled_trig.most_common(12) or "none")
total_atoms = sum(len(r["conditions"]) for rs in by_monster.values() for r in rs)
print(f"\nlabel coverage: {100 * (1 - sum(unlabelled_cond.values()) / max(1, total_atoms)):.2f}% "
      f"of {total_atoms} condition atoms")
te = sum(1 for rs in by_monster.values() if any(r["verb"] == VERB_TURN_END for r in rs))
print(f"monsters with a turn_end rule: {te} / {len(by_monster)}")


# ============ renderer port (monster_ai_resolver.gd), for eyeballing output ============
def cond_label(cond):
    t = cond["type"]; p = cond["params"]
    p0 = p[0] if len(p) > 0 else ""; p1 = p[1] if len(p) > 1 else ""
    table = {
        "non": lambda: "always", "flg_on": lambda: f"flg{p0}=ON", "flg_off": lambda: f"flg{p0}=OFF",
        "flg2_on": lambda: f"flg2_{p0}=ON", "flg2_off": lambda: f"flg2_{p0}=OFF",
        "flg_cntup_act": lambda: f"cnt{p0}@step{p1}", "flg2_cntup_act": lambda: f"cnt2_{p0}@step{p1}",
        "flg_cntup_over": lambda: f"cnt{p0}>={p1}", "flg2_cntup_over": lambda: f"cnt2_{p0}>={p1}",
        "flg_cntup_under": lambda: f"cnt{p0}<{p1}", "flg2_cntup_under": lambda: f"cnt2_{p0}<{p1}",
        "flg_timer_act": lambda: f"timer{p0}@{p1}", "flg_timer_over": lambda: f"timer{p0}>={p1}",
        "flg_timer_under": lambda: f"timer{p0}<{p1}", "hp_pr_under": lambda: f"HP<{p0}%",
        "hp_pr_over": lambda: f"HP>{p0}%", "lb_pr_over": lambda: f"LB>{p0}%",
        "actbetween": lambda: f"every {p0} acts", "act": lambda: f"act {p0}",
        "turn_act": lambda: f"turn {p0} act {p1}", "limited_act": lambda: f"limited_act({p0})",
        "alive": lambda: "alive" if p0 == "1" else "dead",
        "outside_field": lambda: "off-field" if p0 == "1" else "on-field",
        "breaking": lambda: "broken" if p0 == "1" else "not broken",
        "abnormal_state": lambda: f"status({p0})", "normal_state": lambda: "no status",
        "stup_buff": lambda: f"buffed({p0})", "stdown_buff": lambda: f"debuffed({p0})",
        "rifrect_mode": lambda: f"reflect mode({p0})", "party_alive_num": lambda: f"party alive {p0}",
        "party_members": lambda: f"party has unit {p0}", "total_damage_over": lambda: f"total dmg>={p0}",
        "turn_damage_over": lambda: f"turn dmg>={p0}", "turn_damage_over_new": lambda: f"turn dmg>={p0}",
        "join_party": lambda: f"unit {p0} in party",
        "special_user_id": lambda: f"acted on by unit {p0}", "magic_user_id": lambda: f"acted on by unit {p0}",
    }
    if t in table:
        return table[t]()
    if t.startswith("before_turn_"):
        return "player about to " + t[len("before_turn_"):]
    h = hit_label(t)
    if h:
        return h
    return t if not p else f"{t}({','.join(p)})"


def hit_label(t):
    for prefix, kind in (("physics_and_magic_elem_", "phys/magic"), ("physics_", "phys"), ("magic_", "magic")):
        if t.startswith(prefix):
            el = t[len(prefix):]
            lb = el.endswith("_lb")
            if lb:
                el = el[:-3]
            if el not in HIT_ELEMENTS:
                return ""
            el = el[len("elem_"):] if el.startswith("elem_") else el
            return f"hit by {'non-elemental' if el == 'none' else el} {kind}{' LB' if lb else ''}"
    return ""


def trig_label(tr):
    body = cond_label({"type": tr["type"], "params": tr["param"].split(",")})
    s, subj = tr["scope"], tr["subject"]
    if s in (1, 5): return body
    if s == 2: return f"monster {subj} {body}"
    if s == 3: return f"enemy slot {subj} {body}"
    if s == 4: return f"party {body}"
    if s == 7: return f"party slot {subj} {body}"
    if s == 8: return f"part {subj} {body}"
    return f"scope{s}:{subj} {body}"


SKILL_NAMES = {r[0]: (r[1], r[2]) for r in c.execute("select monsterSkillId,name,effectFrames from monster_skill")}


def skill_label(sid):
    row = SKILL_NAMES.get(int(sid))
    if not row:
        return f"<skill {sid} not in monster_skill>"
    return f"{row[0]} (id {sid}, effect {row[1] or '-'})"


def action_label(slots, rule):
    verb, n = rule["verb"], rule["skill_index"]
    if verb != "skill":
        if n != SKILL_INDEX_NONE:
            return f"{verb or '-'}  (rule also names skill {n})"
        return verb or "-"
    if n == SKILL_INDEX_NONE: return "skill <rule names none>"
    if n == SKILL_INDEX_RANDOM: return "skill <random from set>"
    sid = slots[n - 1] if 1 <= n <= len(slots) else ""
    if sid == "":
        return f"skill {n} -> <outside this monster's {len(slots)}-slot skill set>"
    return f"skill {n} -> {skill_label(sid)}"


def pct(v):
    return f"{int(v)}%" if v == math.floor(v) else f"{v:.1f}%"


def rule_line(slots, rule):
    sec = []
    if rule["triggers"]:
        sec.append("ON " + " & ".join(trig_label(t) for t in rule["triggers"]))
    sec.append("IF always" if not rule["conditions"] else "IF " + " & ".join(cond_label(x) for x in rule["conditions"]))
    sec.append("DO " + action_label(slots, rule))
    w = [f"flg{x['id']}={x['value']}" for x in rule["flg_writes"]] + \
        [f"flg2_{x['id']}={x['value']}" for x in rule["flg2_writes"]]
    if w:
        sec.append("SET " + ", ".join(w))
    tm, tp = rule["target_mode"], rule["target_param"]
    if tm and tm != "non":
        sec.append(f"TARGET {tm if tp == 0 else f'{tm}:{tp}'}")
    return f"    #{str(rule['order']).rjust(4)} [{pct(rule['probability']).rjust(4)}] " + " | ".join(sec)


def describe(mid, max_rules=None):
    rules = by_monster[mid]
    slots = slots_by_monster.get(mid, [])
    meta = c.execute("select name from monster where monsterId=?", (mid,)).fetchone()
    sname = c.execute("select WhQL5ev9 from ai where monsterId=? limit 1", (mid,)).fetchone()[0] or ""
    out = ["=" * 78, f"Monster {mid}: {meta[0] if meta else '?'}" + (f"   [script: {sname}]" if sname else ""), ""]
    out.append(f"  Skill slots ({len(slots)}; an AI 'skill N' action is a 1-based index into this list):")
    if not slots:
        out.append("    <no monster_skill_set row -- every 'skill N' action is unresolvable>")
    for i, s in enumerate(slots):
        out.append(f"    {str(i+1).rjust(3)}. " + (skill_label(s) if s else "<empty slot>"))
    out += ["", f"  AI script: {len(rules)} rule(s). Each action re-walks the list top-to-bottom and the",
            "  first rule whose triggers and conditions hold, and whose probability roll",
            "  passes, fires."]
    out.append("  Turn budget: scripted -- the turn ends when a matching rule's verb is turn_end."
               if any(r["verb"] == "turn_end" for r in rules)
               else "  Turn budget: no turn_end rule -- acts once per turn.")
    out.append("")
    shown = rules if max_rules is None else rules[:max_rules]
    out += [rule_line(slots, r) for r in shown]
    if max_rules and len(rules) > max_rules:
        out.append(f"    ... {len(rules) - max_rules} more rule(s)")
    bad_n = sum(1 for r in rules if r["skill_index"] > 0 and
                not (1 <= r["skill_index"] <= len(slots) and slots[r["skill_index"] - 1]))
    if bad_n:
        out += ["", f"  WARNING: {bad_n} rule(s) name a skill index outside this monster's {len(slots)}-slot skill set."]
    return "\n".join(out)


if len(sys.argv) > 1:
    for mid in sys.argv[1:]:
        print(describe(int(mid), max_rules=26))
        print()
