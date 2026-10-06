class_name Multicast
extends RefCounted

## Multicast commands: abilities the player taps to cast several skills in one turn
## (Dualcast). The data's reading and the user's rules (2026-10-05):
##   - A command is an ability whose only effect is one of COMMAND_TYPES and that costs
##     no MP (1,490 of the 1,491 single-effect multicast abilities). Its own effect never
##     runs: the command carries its picks (BattleCommand.picks) and each pick is cast as
##     its own action. Speed Drink, the one with an MP cost, and every 97 or 98 effect
##     next to other effects grant a command for some turns instead (not built).
##   - What a command may pick: 45 any magic and 44 black magic, twice; 97 and the short
##     op 52 magic of `magic_type` (0 any, 1 black, 2 white, 3 green: not the magic
##     table's numbering), `cast_count` times; 53 and 98 the abilities they list, `amount`
##     or `cast_count` times. Never a limit burst, an item, an esper, or another command
##     (the command itself included).
##   - A command a passive gives (52, 53; no unit learns those actives) picks what the
##     passive says: its count replaces the record's and its list joins the record's
##     (CombatantPassives.multicast_picks). The passive's copy is the kept one: Triple
##     Strongest Attack's active says 2 casts, its passive 3; in the pairs whose lists
##     differ, 65 abilities the owners know are only in the passive's list, 2 only in the
##     active's.
##   - The same skill can be picked again while the unit can pay for every pick (MP, LB
##     gauge, esper orbs). A skill with a cooldown or a use limit is picked once.
##   - Picks are checked when the player selects them and paid when they are cast, each
##     BattleRules.cast_gap_frames after the previous pick's start. Each computes its
##     damage when it is cast and swings with the right hand only (DualWield).
## BattleEngine.multicast_rule and multicast_pick_problem answer the menu.

const COMMAND_TYPES: PackedStringArray = [
	"DUALCAST", "DUAL_BLACK_MAGIC", "MAGIC_MULTICAST", "MULTICAST", "MULTICAST_SKILLS",
]
## magic_type of opcodes 97 and 52 -> BattleSkill.magic_type. 0 (or a missing slot) is
## any magic.
const MAGIC_TYPES: Dictionary = {1: "Black", 2: "White", 3: "Green"}
## "Any magic" (a reading: blue magic included).
const ANY_MAGIC: PackedStringArray = ["White", "Black", "Green", "Blue"]


## What one command lets the player pick.
class Rule:
	extends RefCounted
	## The command's ability id.
	var command_id: String = ""
	## How many picks it takes.
	var count: int = 0
	## Magic types it casts (BattleSkill.magic_type names); empty when it casts no magic.
	var magic_types: PackedStringArray = PackedStringArray()
	## Ability ids it casts, as a set of strings; empty when it casts no abilities.
	var ability_ids: Dictionary = {}


## The rule of `skill` when it is a multicast command, otherwise null. `passive_picks` is
## what a passive giving the command lets it pick ({ count, skill_ids }; {} for none).
static func rule_for(skill: BattleSkill, passive_picks: Dictionary = {}) -> Rule:
	if skill == null or skill.kind != BattleSkill.KIND_ABILITY or skill.mp_cost > 0 or skill.effects.size() != 1:
		return null
	var effect: SkillEffect = skill.effects[0]
	if not COMMAND_TYPES.has(effect.type):
		return null
	var rule := Rule.new()
	rule.command_id = skill.id
	match effect.type:
		"DUALCAST":
			rule.count = 2
			rule.magic_types = ANY_MAGIC
		"DUAL_BLACK_MAGIC":
			rule.count = 2
			rule.magic_types = PackedStringArray([MAGIC_TYPES[1]])
		"MAGIC_MULTICAST":
			rule.count = int(effect.param_float("cast_count"))
			rule.magic_types = _magic_types([effect.params.get("magic_type", 0), effect.params.get("magic_type_2", -1)])
		"MULTICAST":
			rule.count = int(effect.param_float("amount"))
			rule.ability_ids = _id_set(effect.params.get("skill_id_array"))
		"MULTICAST_SKILLS":
			rule.count = int(effect.param_float("cast_count"))
			rule.ability_ids = _id_set(effect.params.get("skill_ids"))
	if int(passive_picks.get("count", 0)) > 0:
		rule.count = int(passive_picks["count"])
	for id in passive_picks.get("skill_ids", []):
		rule.ability_ids[str(id)] = true
	return rule if rule.count > 0 else null


## Whether `rule` may cast `pick_skill`, the skill a pick names (before its links: a
## cooldown wrapper is listed by its own id).
static func allows(rule: Rule, pick_skill: BattleSkill) -> bool:
	if rule == null or pick_skill == null or pick_skill.id == rule.command_id or rule_for(pick_skill) != null:
		return false
	match pick_skill.kind:
		BattleSkill.KIND_MAGIC:
			return rule.magic_types.has(pick_skill.magic_type)
		BattleSkill.KIND_ABILITY:
			return rule.ability_ids.has(pick_skill.id)
	return false


## The magic types the slots name; any magic when the first is 0 or missing. A slot of
## -1 (or one the table does not know) adds nothing.
static func _magic_types(slots: Array) -> PackedStringArray:
	var first: Variant = slots[0]
	if typeof(first) not in [TYPE_INT, TYPE_FLOAT] or int(first) == 0:
		return ANY_MAGIC
	var out := PackedStringArray()
	for slot in slots:
		if typeof(slot) in [TYPE_INT, TYPE_FLOAT] and MAGIC_TYPES.has(int(slot)) and not out.has(MAGIC_TYPES[int(slot)]):
			out.append(MAGIC_TYPES[int(slot)])
	return out


## A list param as a set of id strings. A one-id list arrives as a plain number.
static func _id_set(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	var ids: Array = value if value is Array else [value]
	for id in ids:
		if typeof(id) in [TYPE_INT, TYPE_FLOAT] and int(id) > 0:
			out[str(int(id))] = true
	return out
