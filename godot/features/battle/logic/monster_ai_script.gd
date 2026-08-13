extends RefCounted
class_name MonsterAIScript

## Compiled, index-preserving view of one monster's behaviour script (the `ai`
## table, F_AI_MST). This is the PARSE layer only: it turns the raw delimited rows
## into typed rules and does no evaluation and no formatting. MonsterAIResolver
## renders it for the console; a runtime evaluator walks it to pick actions.
##
## ROW GRAMMAR. Every row is one rule, and every `rule` string has the same shape
## (verified across all 49944 rows -- 4 trigger slots and 5 atoms, always):
##
##     T1@T2@T3@T4@#A1@A2@A3@A4@A5@
##     └─ 4 trigger slots ─┘└─ 5 condition atoms ─┘
##
##   Trigger slot   "scope:subject:type:param", or the literal 0:non:non:non when
##                  unused. `scope` picks WHOSE state the trigger reads (see the
##                  TRIGGER_SCOPE_* constants). The physics_*/magic_* types make the
##                  rule a counter-attack reaction to an incoming hit of that kind.
##   Condition atom "type:param", where param may be a comma list (counters use
##                  "id,value"). Every atom is AND-ed with the others, and `non:0`
##                  is no-op padding -- EXCEPT one atom, `skill:N`, which is not a
##                  condition at all: it is the action payload, a 1-based index into
##                  the monster's skill set. (Rules whose command verb is `skill`
##                  carry exactly one such atom in 38724 of 38775 rows, and rules
##                  with any other verb carry none, so the association is certain.)
##                  The atom's slot position carries no meaning; `skill:N` shows up
##                  in all five.
##
## The conditionType / conditionParam / effectType / effectParam columns are merely
## a projection of atoms 1 and 2 -- they are NOT a condition/effect pair, and they
## drop atoms 3-5 and every trigger slot. Always parse `rule`.
##
## COMMAND GRAMMAR. `verb@flgWrites@flg2Writes`, where each write list is six
## (flagId, value) pairs padded out with -1. The writes are the state half of the
## machine: a rule typically tests `flg_off:12` and then sets flag 12, which is how
## "use each skill once", phase latches and turn gates are built. flg ids run 1-30,
## but flg2 ids are SPARSE over 1-110 (1-62, 91-98, 110), so a runtime must hold the
## banks in a Dictionary rather than a fixed-size array.
##
## TURN MODEL. A monster's turn re-walks the rule list once per action: the first
## rule whose triggers and conditions hold and whose probability roll passes fires,
## its writes are applied, the act counter advances, and the turn ends when a
## matching rule's verb is `turn_end`. 1084 of the 2778 scripted monsters have no
## turn_end rule at all and so act once per turn; nothing in this DB carries an
## actions-per-turn value, so turn_end is the only budget signal there is.

## Command verbs. `wait` burns an action doing nothing (used by rules that exist
## only to write flags); `turn_end` ends the monster's turn.
const VERB_SKILL: String = "skill"
const VERB_ATTACK: String = "attack"
const VERB_WAIT: String = "wait"
const VERB_GUARD: String = "guard"
const VERB_TURN_END: String = "turn_end"

## `skill:0` -- 31 rows, on monsters whose script the designer literally named
## "スキルランダム" (random skill). Index 0 is not slot 0 of a 1-based list; it means
## "pick any skill from the set".
const SKILL_INDEX_RANDOM: int = 0
## No `skill:N` atom in the rule at all (51 rows still carry the `skill` verb).
const SKILL_INDEX_NONE: int = -1

## Trigger `scope` codes -- whose state the trigger slot reads. SELF, MONSTER_ID,
## INCOMING_ACTION and MONSTER_PART are pinned down by their subject format.
## PARTY_SLOT (subjects 1-6) is confirmed by monster 205031003, whose six rules map
## party slots 1-6 one-to-one onto flags 12-17. ENEMY_SLOT (subjects 1-14) is
## corroborated by monster 120, whose script the designer named
## "インデックス2生存変化" ("index 2 alive changes [behaviour]") and whose matching
## trigger is 3:2:alive:1 -- so the subject is a formation index, though the upper
## end of the range is still worth sanity-checking against real battle groups.
const TRIGGER_SCOPE_SELF: int = 1
const TRIGGER_SCOPE_MONSTER_ID: int = 2
const TRIGGER_SCOPE_ENEMY_SLOT: int = 3
const TRIGGER_SCOPE_PARTY: int = 4
const TRIGGER_SCOPE_INCOMING_ACTION: int = 5
const TRIGGER_SCOPE_PARTY_SLOT: int = 7
const TRIGGER_SCOPE_MONSTER_PART: int = 8

## Elements a physics_*/magic_* reaction type can name. Used to tell a real element
## reaction from an unrelated type sharing the prefix (magic_user_id is not one).
const HIT_ELEMENTS: Array = [
	"fire", "ice", "thunder", "water", "aero", "quake", "light", "dark", "none", "elem_none",
]

## Compiled scripts by monsterId. Compilation is spawn-time (one call per monster
## per wave), so this only exists to keep repeated inspection of the same wave
## cheap; clear_cache() covers a DB swap.
static var _cache: Dictionary = {}

var monster_id: String = ""
## The designer's own name for this script, from the `ai.WhQL5ev9` column (mostly
## Japanese, e.g. "1ターン五回行動、10ターン分" = "5 actions per turn, for 10 turns").
## Free documentation of intent -- worth keeping in debug output.
var script_name: String = ""
## The monster's skill list as raw slots. An AI `skill N` action is a 1-based index
## into THIS list, blanks included; see _load_skill_slots.
var skill_slots: PackedStringArray = PackedStringArray()
## One entry per row, ordered by ruleOrder. Keys:
##   order          int                ruleOrder, for display and stable identity.
##   triggers       Array[Dictionary]  scoped preconditions; { scope, subject, type,
##                                     param }. Unused slots are dropped, so this is
##                                     empty for the 41255 rows that use none.
##   conditions     Array[Dictionary]  AND-ed atoms; { type, params: PackedStringArray }.
##                                     The skill payload and `non:0` padding removed.
##   verb           String             one of the VERB_* constants.
##   skill_index    int                1-based index into skill_slots, or
##                                     SKILL_INDEX_RANDOM / SKILL_INDEX_NONE.
##   flg_writes     Array[Dictionary]  { id, value } applied when the rule fires.
##   flg2_writes    Array[Dictionary]  same, for the second flag bank.
##   target_mode    String             targetSelect verb ("random", "hp_min", ...).
##   target_param   int                its parameter (slot number for disp_order).
##   probability    float              0-100; rolled after the conditions hold.
##   raw            String             the original `rule` string, for debugging.
var rules: Array[Dictionary] = []


## Compiles (and caches) the script for a 9-digit monsterId. Always returns an
## instance; has_script() is false when the monster has no rows, which is the
## common case -- only 2778 of 16931 monsters are scripted.
static func compile(monster_id_in: String) -> MonsterAIScript:
	var key: String = str(monster_id_in)
	if _cache.has(key):
		var cached: MonsterAIScript = _cache[key]
		return cached

	var built: MonsterAIScript = MonsterAIScript.new()
	built.monster_id = key
	built.skill_slots = _load_skill_slots(key)
	for row in GameDatabase.get_monster_ai(key):
		if built.script_name == "":
			built.script_name = str(row.get("scriptName", ""))
		built.rules.append(_compile_rule(row))

	_cache[key] = built
	return built


## Drops every compiled script. Only needed if the underlying DB is replaced.
static func clear_cache() -> void:
	_cache.clear()


## True when this monster drives itself from an AI script. False means it has no
## `ai` rows and needs the caller's default behaviour.
func has_script() -> bool:
	return not rules.is_empty()


## The monsterSkillId an AI `skill N` action resolves to, or "" when N falls outside
## the skill set (or lands on a blank slot). Roughly 23% of the table's skill
## references are unresolvable -- 334 scripted monsters have no monster_skill_set
## row at all and 479 more over-index the one they have -- so callers MUST handle ""
## rather than assume a hit.
func skill_id_at(skill_index: int) -> String:
	if skill_index < 1 or skill_index > skill_slots.size():
		return ""
	return skill_slots[skill_index - 1]


## True when the script manages its own actions-per-turn budget with `turn_end`
## rules. When false, the monster acts once per turn.
func ends_turn_explicitly() -> bool:
	for rule in rules:
		if str(rule.get("verb", "")) == VERB_TURN_END:
			return true
	return false


## True when `type` names an incoming EVENT the monster reacts to, rather than a
## piece of state it can test at any time. Two families:
##   before_turn_*     the player is about to act (mg = Magic menu, sm = Summon,
##                     ab = Ability menu, lb = Limit Burst, attack, guard, ...).
##   physics_*/magic_* the monster was just hit by a blow of that kind and element.
## Reaction rules only hold while a matching event is pending, so a runtime has to
## feed the event in rather than read it off the battle state.
static func is_reaction_type(type: String) -> bool:
	return type.begins_with("before_turn_") or not parse_hit_type(type).is_empty()


## { kind: "physical"|"magical"|"both", element: String, limit_burst: bool } for a
## physics_*/magic_* reaction type, or {} when `type` is not one. `element` is
## "none" for the explicitly non-elemental variants.
static func parse_hit_type(type: String) -> Dictionary:
	var kind: String = ""
	var element: String = ""
	if type.begins_with("physics_and_magic_elem_"):
		kind = "both"
		element = type.trim_prefix("physics_and_magic_elem_")
	elif type.begins_with("physics_"):
		kind = "physical"
		element = type.trim_prefix("physics_")
	elif type.begins_with("magic_"):
		kind = "magical"
		element = type.trim_prefix("magic_")
	else:
		return {}

	var limit_burst: bool = element.ends_with("_lb")
	element = element.trim_suffix("_lb")
	if not HIT_ELEMENTS.has(element):
		return {}
	return {
		"kind": kind,
		"element": element.trim_prefix("elem_"),
		"limit_burst": limit_burst,
	}


## The monster's skill list as raw, INDEX-PRESERVING slots. 867 skill sets have
## interior blanks (e.g. "154960,,,154970"), so dropping empties would shift every
## index past the gap onto the wrong skill. Trailing blanks are padding from the
## fixed-width column and carry no index, so they go.
static func _load_skill_slots(monster_id_in: String) -> PackedStringArray:
	var skill_set: Dictionary = GameDatabase.get_monster_skill_set(monster_id_in)
	if skill_set.is_empty():
		return PackedStringArray()
	var slots: PackedStringArray = str(skill_set.get("skillId", "")).split(",")
	while not slots.is_empty() and slots[slots.size() - 1] == "":
		slots.remove_at(slots.size() - 1)
	return slots


## Turns one `ai` row into a compiled rule. See the class docs for the grammar and
## `rules` for the key layout.
static func _compile_rule(row: Dictionary) -> Dictionary:
	var raw: String = str(row.get("rule", ""))
	var segments: PackedStringArray = raw.split("@")

	# The '#'-prefixed segment separates the trigger slots from the condition atoms.
	var cut: int = -1
	for i in range(segments.size()):
		if segments[i].begins_with("#"):
			cut = i
			break

	var triggers: Array[Dictionary] = []
	var conditions: Array[Dictionary] = []
	var skill_index: int = SKILL_INDEX_NONE

	if cut == -1:
		push_warning("MonsterAIScript: rule for monster %s order %s has no '#' separator: %s" % [
			str(row.get("monsterId", "?")), str(row.get("ruleOrder", "?")), raw,
		])
	else:
		for i in range(cut):
			var trigger: Dictionary = _parse_trigger(segments[i])
			if not trigger.is_empty():
				triggers.append(trigger)

		for i in range(cut, segments.size()):
			var text: String = segments[i].trim_prefix("#") if i == cut else segments[i]
			if text == "":
				continue
			var atom: Dictionary = _parse_atom(text)
			var type: String = str(atom.get("type", ""))
			if type == VERB_SKILL:
				# The action payload, not a condition. 54 rules repeat it verbatim in
				# a later slot; the first wins and a genuine disagreement is loud.
				var found: int = _atom_int(atom, 0, SKILL_INDEX_NONE)
				if skill_index == SKILL_INDEX_NONE:
					skill_index = found
				elif found != skill_index:
					push_warning("MonsterAIScript: monster %s order %s names two skills (%d, %d): %s" % [
						str(row.get("monsterId", "?")), str(row.get("ruleOrder", "?")),
						skill_index, found, raw,
					])
				continue
			# `non` is padding, and monster 305941000 pads 42 of its rules with a bare
			# ":" instead. Neither is a condition.
			if type != "non" and type != "":
				conditions.append(atom)

	var command_groups: PackedStringArray = str(row.get("command", "")).split("@")
	var target_select: PackedStringArray = str(row.get("targetSelect", "")).split(":")

	return {
		"order": int(row.get("ruleOrder", 0)),
		"triggers": triggers,
		"conditions": conditions,
		"verb": command_groups[0] if command_groups.size() > 0 else "",
		"skill_index": skill_index,
		"flg_writes": _parse_writes(command_groups[1] if command_groups.size() > 1 else ""),
		"flg2_writes": _parse_writes(command_groups[2] if command_groups.size() > 2 else ""),
		"target_mode": target_select[0] if target_select.size() > 0 else "",
		"target_param": int(target_select[1]) if target_select.size() > 1 and target_select[1].is_valid_int() else 0,
		"probability": float(row.get("probability", 0.0)),
		"raw": raw,
	}


## One trigger slot, "scope:subject:type:param". {} for an unused slot: the literal
## 0:non:non:non, plus 31 rows that pad with a non-zero scope but a `non` type.
## `subject` stays a String because scope 2 uses a 9-digit monsterId and scope 8 a
## "monsterId&partsNum" pair.
static func _parse_trigger(slot: String) -> Dictionary:
	var fields: PackedStringArray = slot.split(":")
	if fields.size() != 4 or fields[2] == "non":
		return {}
	return {
		"scope": int(fields[0]) if fields[0].is_valid_int() else 0,
		"subject": fields[1],
		"type": fields[2],
		"param": fields[3],
	}


## One condition atom, "type:param[,param...]". Split on the FIRST colon only so a
## multi-part param survives intact.
static func _parse_atom(text: String) -> Dictionary:
	var halves: PackedStringArray = text.split(":", true, 1)
	return {
		"type": halves[0],
		"params": halves[1].split(",") if halves.size() > 1 else PackedStringArray(),
	}


## One `command` write list: six (flagId, value) pairs, -1-padded. Pairs with a
## negative id are unused slots.
static func _parse_writes(group: String) -> Array[Dictionary]:
	var fields: PackedStringArray = group.split(",")
	var out: Array[Dictionary] = []
	var i: int = 0
	while i + 1 < fields.size():
		var id_text: String = fields[i]
		var value_text: String = fields[i + 1]
		i += 2
		if not id_text.is_valid_int() or not value_text.is_valid_int():
			continue
		var flag_id: int = int(id_text)
		if flag_id < 0:
			continue
		out.append({"id": flag_id, "value": int(value_text)})
	return out


## Param `index` of an atom as an int, or `fallback` when absent/non-numeric.
static func _atom_int(atom: Dictionary, index: int, fallback: int) -> int:
	var params: PackedStringArray = atom.get("params", PackedStringArray())
	if index >= params.size() or not params[index].is_valid_int():
		return fallback
	return int(params[index])
