extends RefCounted
class_name MonsterAIResolver

## In-game port of the resolve_monster_ai.py datamine tool. Resolves a monster's
## BEHAVIOUR: what skills it can use and, for scripted monsters, the ordered
## condition -> action rules that decide *when* each skill fires, then formats it
## exactly like the Python script's console output.
##
## Data model (all read from GameDatabase / the bundled SQLite DB):
##   monster_parts (MONSTER_PARTS)      one row per monster instance / part.
##         skillSetId  "X:hp:min:max" -- generic behaviour class + HP phase +
##                     action-count. Even scripted bosses carry a default here, so
##                     this is a *fallback*, not the real script.
##   monster_skill_set (MONSTER_SKILL_SET)   keyed by monsterId. skillId is the
##                     ordered list of skills THIS monster can use; AI 'skill'
##                     actions reference a 1-BASED INDEX into it (skill 1 = slot 0).
##   monster_skill (MONSTER_SKILL)   keyed by monsterSkillId. name + effectFrames.
##   monster_ai (AI, F_AI_MST)   the behaviour script, keyed by monsterId. One AI
##                     id = many rows; each row (ordered by ruleOrder) is ONE rule:
##                     condition/trigger + params, effect (skill index / flag op),
##                     target selection, probability, and the full compiled `rule`:
##                        pre1@pre2@pre3@pre4@#cond@eff1@eff2@eff3@eff4@
##                     Rules are checked top-to-bottom; the first whose condition
##                     holds and whose probability roll passes fires. Only ~2700
##                     monsters have a script; the rest fall back to skillSetId.

# Human labels for the common condition/effect verbs (mirrors the Python COND map).
const COND: Dictionary = {
	"non": "always",
	"hp_pr_under": "HP% below",
	"hp_pr_over": "HP% above",
	"flg_on": "if flag ON",
	"flg_off": "if flag OFF",
	"flg_cntup_act": "counter step (id,value)",
	"flg_cntup_over": "counter >=",
	"flg_cntup_under": "counter <",
	"flg_timer_over": "turn-timer >=",
	"actbetween": "every N acts",
	"limited_act": "at most N times",
	"skill": "after using skill idx",
	"breaking": "while broken",
	"abnormal_state": "while status-afflicted",
	"stup_buff": "while buffed",
	"stdown_buff": "while debuffed",
}


## Prints one monster's resolved behaviour to the console (same structure as
## resolve_monster_ai.py). Convenience wrapper over describe().
static func print_behaviour(monster_id: String) -> void:
	print(describe(monster_id))


## Builds the full multi-line behaviour report for a 9-digit monsterId, matching
## the Python tool's layout line-for-line.
static func describe(monster_id: String) -> String:
	var lines: PackedStringArray = []
	lines.append("=".repeat(74))

	var meta: Dictionary = GameDatabase.get_monster_ai_meta(monster_id)
	var name: String = str(meta.get("name", "?")) if not meta.is_empty() else "?"
	lines.append("Monster %s: %s" % [monster_id, name])
	if not meta.is_empty():
		lines.append("  skillSetId (generic fallback): %s   passiveSkillSetId: %s" % [
			str(meta.get("skillSetId", "")), str(meta.get("passiveSkillSetId", "")),
		])

	var arr: Array = _skill_array(monster_id)
	lines.append("")
	lines.append("  Skill set (%d skills; AI 'skill N' = 1-based index):" % arr.size())
	for i in range(arr.size()):
		lines.append("    %2d. %s" % [i + 1, _skill_label(arr[i])])

	var rows: Array = GameDatabase.get_monster_ai(monster_id)
	if rows.is_empty():
		lines.append("")
		lines.append("  No monster-specific AI script (uses generic behaviour from skillSetId).")
		return "\n".join(lines)

	lines.append("")
	lines.append("  AI script: %d rule(s), evaluated top-to-bottom:" % rows.size())
	for r in rows:
		var ct: String = str(r.get("conditionType", ""))
		var cp: String = str(r.get("conditionParam", ""))
		var verb: String = str(r.get("command", "")).split("@")[0]
		var cond_label: String = str(COND.get(ct, ct))
		var cond: String = cond_label if (cp == "" or cp == "0") else "%s=%s" % [cond_label, cp]

		# The compiled rule is  pre..@#cond@eff1@eff2@eff3@eff4@ . The skill can live
		# in ANY effect slot, so scan them all (skip empty and the "non:0" no-ops).
		var rule_str: String = str(r.get("rule", ""))
		var after: String = rule_str.substr(rule_str.rfind("#") + 1) if rule_str.find("#") != -1 else rule_str
		var segments: PackedStringArray = after.split("@")
		var effects: PackedStringArray = []
		for i in range(1, segments.size()):
			var e: String = segments[i]
			if e != "" and e != "non:0":
				effects.append(e)

		var skill_txt: String = ""
		for e in effects:
			var colon: int = e.find(":")
			var t: String = e.substr(0, colon) if colon != -1 else e
			var p: String = e.substr(colon + 1) if colon != -1 else ""
			if t == "skill":
				var first: String = p.split(",")[0]
				if first.is_valid_int():
					var n: int = int(first)
					if n >= 1 and n <= arr.size():
						skill_txt = " -> skill %d = %s" % [n, _skill_label(arr[n - 1])]

		var act: String
		if skill_txt != "":
			act = verb + skill_txt
		elif not effects.is_empty():
			act = verb + "  [%s]" % ", ".join(effects)
		else:
			act = verb

		lines.append("    #%s [%s%%] WHEN %s DO %s  (target %s)" % [
			str(r.get("ruleOrder", "")).lpad(3),
			str(r.get("probability", "")).lpad(6),
			cond.rpad(26),
			act,
			str(r.get("targetSelect", "")),
		])

	return "\n".join(lines)


## The ordered skill-id list for a monster (AI 'skill N' is a 1-based index here),
## with blank entries stripped. [] if the monster has no skill set.
static func _skill_array(monster_id: String) -> Array:
	var ss: Dictionary = GameDatabase.get_monster_skill_set(monster_id)
	if ss.is_empty():
		return []
	var out: Array = []
	for s in str(ss.get("skillId", "")).split(","):
		if str(s) != "":
			out.append(str(s))
	return out


## "<name> (id <skillId>, effect <effectFrames|->)" for a monster skill id.
static func _skill_label(skill_id: String) -> String:
	var sk: Dictionary = GameDatabase.get_monster_skill(skill_id)
	if sk.is_empty():
		return "<skill %s>" % skill_id
	var eff: String = str(sk.get("effectFrames", ""))
	return "%s (id %s, effect %s)" % [str(sk.get("name", "")), skill_id, eff if eff != "" else "-"]
