extends RefCounted
class_name MonsterAIResolver

## Human-readable dump of a monster's resolved behaviour: what skills it can use
## and, for scripted monsters, the ordered trigger/condition -> action rules that
## decide when each one fires. Presentation only -- MonsterAIScript owns the parse
## and documents the grammar; this file just names things for a reader.
##
## One rule per line:
##
##   #  7 [100%] ON party slot 2 dead | IF cnt1@step0 & flg12=OFF | DO skill 1 -> Foo
##                                    | SET flg13=1, flg17=1 | TARGET random
##
##   ON      scoped trigger slots (incoming-hit reactions, other monsters' state,
##           party state). Absent when the rule uses none.
##   IF      the AND-ed condition atoms. "IF always" when the rule is unconditional.
##   DO      the command verb, with the skill the payload index resolves to.
##   SET     the flag writes the rule applies when it fires.
##   TARGET  the targetSelect mode (48089 of 49944 rows are plain "random").
##
## Undecoded condition types fall through to a raw "type(params)" label rather than
## being hidden. The labels below cover 99.94% of the table's condition atoms; the
## remainder are the five *_use_possible types, which stay visible as raw text.

## How MonsterAIScript's hit `kind` codes read in a label.
const _HIT_KINDS: Dictionary = {
	"physical": "phys",
	"magical": "magic",
	"both": "phys/magic",
}


## Prints one monster's resolved behaviour to the console.
static func print_behaviour(monster_id: String) -> void:
	print(describe(monster_id))


## The full multi-line behaviour report for a 9-digit monsterId.
static func describe(monster_id: String) -> String:
	var ai_script: MonsterAIScript = MonsterAIScript.compile(monster_id)
	var meta: Dictionary = GameDatabase.get_monster_ai_meta(monster_id)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("=".repeat(78))
	var monster_name: String = _text(meta.get("name"))
	var title: String = "Monster %s: %s" % [monster_id, monster_name if monster_name != "" else "?"]
	if ai_script.script_name != "":
		title += "   [script: %s]" % ai_script.script_name
	lines.append(title)
	if not meta.is_empty():
		lines.append("  passive skill: %s" % _or_dash(_text(meta.get("passiveSkillId"))))

	lines.append("")
	lines.append("  Skill slots (%d; an AI 'skill N' action is a 1-based index into this list):" % ai_script.skill_slots.size())
	if ai_script.skill_slots.is_empty():
		lines.append("    <no monster_skill_set row -- every 'skill N' action is unresolvable>")
	for i in range(ai_script.skill_slots.size()):
		var slot: String = ai_script.skill_slots[i]
		lines.append("    %3d. %s" % [i + 1, _skill_label(slot) if slot != "" else "<empty slot>"])

	lines.append("")
	if not ai_script.has_script():
		lines.append("  No AI script (no `ai` rows) -- needs the caller's default behaviour.")
		return "\n".join(lines)

	lines.append("  AI script: %d rule(s). Each action re-walks the list top-to-bottom and the" % ai_script.rules.size())
	lines.append("  first rule whose triggers and conditions hold, and whose probability roll")
	lines.append("  passes, fires.")
	if ai_script.ends_turn_explicitly():
		lines.append("  Turn budget: scripted -- the turn ends when a matching rule's verb is turn_end.")
	else:
		lines.append("  Turn budget: no turn_end rule -- acts once per turn.")
	lines.append("")
	for rule in ai_script.rules:
		lines.append(_rule_line(ai_script, rule))

	var unresolved: int = _count_unresolved_skills(ai_script)
	if unresolved > 0:
		lines.append("")
		lines.append("  WARNING: %d rule(s) name a skill index outside this monster's %d-slot skill set." % [
			unresolved, ai_script.skill_slots.size(),
		])

	return "\n".join(lines)


## One compiled rule as a single line.
static func _rule_line(ai_script: MonsterAIScript, rule: Dictionary) -> String:
	var sections: PackedStringArray = PackedStringArray()

	var triggers: Array = rule.get("triggers", [])
	if not triggers.is_empty():
		var trigger_labels: PackedStringArray = PackedStringArray()
		for trigger in triggers:
			trigger_labels.append(_trigger_label(trigger))
		sections.append("ON " + " & ".join(trigger_labels))

	var conditions: Array = rule.get("conditions", [])
	if conditions.is_empty():
		sections.append("IF always")
	else:
		var condition_labels: PackedStringArray = PackedStringArray()
		for condition in conditions:
			condition_labels.append(_condition_label(condition))
		sections.append("IF " + " & ".join(condition_labels))

	sections.append("DO " + _action_label(ai_script, rule))

	var writes: PackedStringArray = PackedStringArray()
	for write in rule.get("flg_writes", []):
		writes.append("flg%d=%d" % [int(write.get("id", 0)), int(write.get("value", 0))])
	for write in rule.get("flg2_writes", []):
		writes.append("flg2_%d=%d" % [int(write.get("id", 0)), int(write.get("value", 0))])
	if not writes.is_empty():
		sections.append("SET " + ", ".join(writes))

	var target_mode: String = str(rule.get("target_mode", ""))
	if target_mode != "" and target_mode != "non":
		var target_param: int = int(rule.get("target_param", 0))
		sections.append("TARGET %s" % (target_mode if target_param == 0 else "%s:%d" % [target_mode, target_param]))

	return "    #%s [%s] %s" % [
		str(rule.get("order", "")).lpad(4),
		_percent(float(rule.get("probability", 0.0))).lpad(4),
		" | ".join(sections),
	]


## The DO section: the command verb, plus the skill its payload index resolves to.
static func _action_label(ai_script: MonsterAIScript, rule: Dictionary) -> String:
	var verb: String = str(rule.get("verb", ""))
	var skill_index: int = int(rule.get("skill_index", MonsterAIScript.SKILL_INDEX_NONE))

	if verb != MonsterAIScript.VERB_SKILL:
		# 24 rows pair a non-skill verb with a skill payload. Surface rather than hide.
		if skill_index != MonsterAIScript.SKILL_INDEX_NONE:
			return "%s  (rule also names skill %d)" % [_or_dash(verb), skill_index]
		return _or_dash(verb)

	if skill_index == MonsterAIScript.SKILL_INDEX_NONE:
		return "skill <rule names none>"
	if skill_index == MonsterAIScript.SKILL_INDEX_RANDOM:
		return "skill <random from set>"

	var skill_id: String = ai_script.skill_id_at(skill_index)
	if skill_id == "":
		return "skill %d -> <outside this monster's %d-slot skill set>" % [skill_index, ai_script.skill_slots.size()]
	return "skill %d -> %s" % [skill_index, _skill_label(skill_id)]


## A scoped trigger slot. The scope decides whose state the condition body reads;
## see MonsterAIScript's TRIGGER_SCOPE_* constants for which readings are confirmed.
static func _trigger_label(trigger: Dictionary) -> String:
	var subject: String = str(trigger.get("subject", ""))
	var body: String = _condition_label({
		"type": str(trigger.get("type", "")),
		"params": str(trigger.get("param", "")).split(","),
	})

	var scope: int = int(trigger.get("scope", 0))
	if scope == MonsterAIScript.TRIGGER_SCOPE_SELF or scope == MonsterAIScript.TRIGGER_SCOPE_INCOMING_ACTION:
		return body
	if scope == MonsterAIScript.TRIGGER_SCOPE_MONSTER_ID:
		return "monster %s %s" % [subject, body]
	if scope == MonsterAIScript.TRIGGER_SCOPE_ENEMY_SLOT:
		return "enemy slot %s %s" % [subject, body]
	if scope == MonsterAIScript.TRIGGER_SCOPE_PARTY:
		return "party %s" % body
	if scope == MonsterAIScript.TRIGGER_SCOPE_PARTY_SLOT:
		return "party slot %s %s" % [subject, body]
	if scope == MonsterAIScript.TRIGGER_SCOPE_MONSTER_PART:
		return "part %s %s" % [subject, body]
	return "scope%d:%s %s" % [scope, subject, body]


## Short label for one condition atom (also used for trigger bodies, which share the
## type vocabulary). Falls through to "type(params)" for types we haven't decoded.
static func _condition_label(condition: Dictionary) -> String:
	var type: String = str(condition.get("type", ""))
	var params: PackedStringArray = condition.get("params", PackedStringArray())
	var p0: String = params[0] if params.size() > 0 else ""
	var p1: String = params[1] if params.size() > 1 else ""

	match type:
		"non":
			return "always"
		"flg_on":
			return "flg%s=ON" % p0
		"flg_off":
			return "flg%s=OFF" % p0
		"flg2_on":
			return "flg2_%s=ON" % p0
		"flg2_off":
			return "flg2_%s=OFF" % p0
		"flg_cntup_act":
			return "cnt%s@step%s" % [p0, p1]
		"flg2_cntup_act":
			return "cnt2_%s@step%s" % [p0, p1]
		"flg_cntup_over":
			return "cnt%s>=%s" % [p0, p1]
		"flg2_cntup_over":
			return "cnt2_%s>=%s" % [p0, p1]
		"flg_cntup_under":
			return "cnt%s<%s" % [p0, p1]
		"flg2_cntup_under":
			return "cnt2_%s<%s" % [p0, p1]
		"flg_timer_act":
			return "timer%s@%s" % [p0, p1]
		"flg_timer_over":
			return "timer%s>=%s" % [p0, p1]
		"flg_timer_under":
			return "timer%s<%s" % [p0, p1]
		"hp_pr_under":
			return "HP<%s%%" % p0
		"hp_pr_over":
			return "HP>%s%%" % p0
		"lb_pr_over":
			return "LB>%s%%" % p0
		"actbetween":
			return "every %s acts" % p0
		"act":
			return "act %s" % p0
		"turn_act":
			return "turn %s act %s" % [p0, p1]
		# Whether the param is a latch id or a max-fire count is still unconfirmed
		# (both readings behave identically on every boss checked), so it is left raw.
		"limited_act":
			return "limited_act(%s)" % p0
		"alive":
			return "alive" if p0 == "1" else "dead"
		"outside_field":
			return "off-field" if p0 == "1" else "on-field"
		"breaking":
			return "broken" if p0 == "1" else "not broken"
		"abnormal_state":
			return "status(%s)" % p0
		"normal_state":
			return "no status"
		"stup_buff":
			return "buffed(%s)" % p0
		"stdown_buff":
			return "debuffed(%s)" % p0
		"rifrect_mode":
			return "reflect mode(%s)" % p0
		"party_alive_num":
			return "party alive %s" % p0
		"party_members":
			return "party has unit %s" % p0
		"total_damage_over":
			return "total dmg>=%s" % p0
		"turn_damage_over", "turn_damage_over_new":
			return "turn dmg>=%s" % p0
		"join_party":
			return "unit %s in party" % p0
		"special_user_id", "magic_user_id":
			return "acted on by unit %s" % p0

	# "player is about to <act>" -- the pre-emptive interrupt triggers.
	if type.begins_with("before_turn_"):
		return "player about to %s" % type.trim_prefix("before_turn_")

	var hit: String = _hit_label(type)
	if hit != "":
		return hit

	if params.is_empty():
		return type
	return "%s(%s)" % [type, ",".join(params)]


## Label for a counter-attack trigger type: an incoming hit of a given kind and
## element, e.g. physics_fire, magic_ice_lb, physics_and_magic_elem_dark. Returns ""
## when `type` is not one of them.
static func _hit_label(type: String) -> String:
	var hit: Dictionary = MonsterAIScript.parse_hit_type(type)
	if hit.is_empty():
		return ""
	var element: String = str(hit.get("element", ""))
	return "hit by %s %s%s" % [
		"non-elemental" if element == "none" else element,
		_HIT_KINDS.get(str(hit.get("kind", "")), "?"),
		" LB" if bool(hit.get("limit_burst", false)) else "",
	]


## "<name> (id <skillId>, effect <effectFrames|->)" for a monsterSkillId.
static func _skill_label(skill_id: String) -> String:
	var skill: Dictionary = GameDatabase.get_monster_skill(skill_id)
	if skill.is_empty():
		return "<skill %s not in monster_skill>" % skill_id
	return "%s (id %s, effect %s)" % [
		_text(skill.get("name")), skill_id, _or_dash(_text(skill.get("effectFrames"))),
	]


## How many of the script's rules name a skill index it cannot resolve.
static func _count_unresolved_skills(ai_script: MonsterAIScript) -> int:
	var count: int = 0
	for rule in ai_script.rules:
		var skill_index: int = int(rule.get("skill_index", MonsterAIScript.SKILL_INDEX_NONE))
		if skill_index > 0 and ai_script.skill_id_at(skill_index) == "":
			count += 1
	return count


## A probability as "100%" / "47%" / "12.5%" -- every value in the table is whole,
## but a fractional one would still read correctly.
static func _percent(value: float) -> String:
	if is_equal_approx(value, floor(value)):
		return "%d%%" % int(value)
	return "%.1f%%" % value


static func _or_dash(text: String) -> String:
	return text if text != "" else "-"


## A column value as a String, mapping SQL NULL to "" so it never renders as the
## literal "<null>" that str(null) produces.
static func _text(value: Variant) -> String:
	return "" if value == null else str(value)
