extends RefCounted

## Builders shared by the battle engine tests: combatants from specs, skill records in
## GameDatabase's shape, engines, and clock helpers. Nothing here touches the database.

static var _skill_schema: Dictionary = {}
static var _passive_schema: Dictionary = {}


## Rules with the random limit-crystal and esper-orb drops, the final and weapon variances
## and level correction turned off, so hit tests are exact. Tests of those terms turn
## them back on.
static func rules() -> BattleRules:
	var battle_rules := BattleRules.new()
	battle_rules.lb_crystal_drop_chance = 0.0
	battle_rules.esper_orb_drop_chance = 0.0
	battle_rules.damage_variance_min = 1.0
	battle_rules.damage_variance_max = 1.0
	battle_rules.weapon_variance = false
	battle_rules.level_correction = false
	return battle_rules


## A fresh catalog sharing the opcode schemas read from disk once.
static func catalog() -> SkillCatalog:
	if _skill_schema.is_empty():
		_skill_schema = SkillCatalog.load_schema(SkillCatalog.SKILL_SCHEMA_PATH)
		_passive_schema = SkillCatalog.load_schema(SkillCatalog.PASSIVE_SCHEMA_PATH)
	return SkillCatalog.new(_skill_schema, _passive_schema)


## A party member: 1000 HP, 100 MP and 100 in every stat unless `spec` says otherwise.
static func unit(unit_name: String, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"name": unit_name, "party": true, "attack_frames": "10:100"}
	full.merge(spec, true)
	return CombatantFactory.from_spec(full)


## An enemy: 100000 HP by default, so it survives unless a test wants a kill.
static func monster(monster_name: String, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"name": monster_name, "party": false, "hp": 100000, "attack_frames": "42:100"}
	full.merge(spec, true)
	return CombatantFactory.from_spec(full)


## An engine holding `party` (slots in order) and `foes`, not started yet.
static func engine(party: Array, foes: Array, battle_rules: BattleRules = null, skill_catalog: SkillCatalog = null, seed_value: int = 7) -> BattleEngine:
	var battle := BattleEngine.new(
		skill_catalog if skill_catalog != null else catalog(),
		battle_rules if battle_rules != null else rules(),
		seed_value
	)
	for member in party:
		battle.add_party_member(member)
	for foe in foes:
		battle.add_enemy(foe)
	return battle


## A skill record with one effect, in GameDatabase's shape. `params` is the opcode's
## positional payload; `frames` an attackFrames string ("10:50-20:50").
static func skill_record(skill_name: String, opcode: int, params: Array, frames: String, target_area: int = 1, target_type: int = 1, mp_cost: int = 0, elements: Array = []) -> Dictionary:
	var parsed: Dictionary = BattleSkill.parse_attack_frames(frames)
	return {
		"name": skill_name,
		"cost": {"MP": mp_cost} if mp_cost > 0 else {},
		"effects_raw": [[target_area, target_type, opcode, params]],
		"attack_frames": parsed["frames"],
		"attack_damage": parsed["damage"],
		"element_inflict": elements if not elements.is_empty() else null,
	}


## A skill record with several effects ([area, target, opcode, params] each) sharing
## one attackFrames group. `extra` is merged in (attack_type, cost, element_inflict...).
static func record(skill_name: String, effects_raw: Array, frames: String = "10:100", extra: Dictionary = {}) -> Dictionary:
	var parsed: Dictionary = BattleSkill.parse_attack_frames(frames)
	var data: Dictionary = {
		"name": skill_name,
		"effects_raw": effects_raw,
		"attack_frames": parsed["frames"],
		"attack_damage": parsed["damage"],
	}
	data.merge(extra, true)
	return data


## Events of `type` whose `target` is `target_id`.
static func events_on(battle: BattleEngine, type: StringName, target_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(type):
		if int(event.get("target", -1)) == target_id:
			out.append(event)
	return out


## Opcode 1 payload with `modifier` in its slot.
static func physical_params(modifier: int) -> Array:
	return [0, 0, 0, 0, 0, 0, modifier, 0]


## Opcode 15 payload with `modifier` in its slot.
static func magic_params(modifier: int) -> Array:
	return [0, 0, 0, 0, 0, modifier, 0]


## Ticks until `condition` holds or `max_frames` pass. Returns whether it held.
static func run_until(battle: BattleEngine, condition: Callable, max_frames: int = 2000) -> bool:
	for _i in range(max_frames):
		if condition.call():
			return true
		battle.tick()
	return bool(condition.call())


static func run_until_phase(battle: BattleEngine, phase: int, max_frames: int = 2000) -> bool:
	return run_until(battle, func() -> bool: return battle.phase == phase, max_frames)


static func run_until_ended(battle: BattleEngine, max_frames: int = 20000) -> bool:
	return run_until(battle, func() -> bool: return battle.phase == BattleEngine.Phase.ENDED, max_frames)


## HIT_LANDED events, optionally only those on `target_id`.
static func hits(battle: BattleEngine, target_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.HIT_LANDED):
		if target_id < 0 or int(event["target"]) == target_id:
			out.append(event)
	return out


## The amount of each HIT_LANDED event in `events`.
static func amounts(events: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for event in events:
		out.append(int(event["amount"]))
	return out


## ACTION_STARTED events by `actor_id` (all actors when -1).
static func actions_by(battle: BattleEngine, actor_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.ACTION_STARTED):
		if actor_id < 0 or int(event["actor"]) == actor_id:
			out.append(event)
	return out
