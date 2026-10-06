class_name BattleSkill
extends RefCounted

## A resolved skill the engine can run: costs, elements and effects in data order. Built
## from the record shape GameDatabase returns for magic, abilities, limit bursts and
## monster skills (from_record), or made up for a basic attack (basic_attack).

const KIND_ATTACK: StringName = &"attack"
const KIND_MAGIC: StringName = &"magic"
const KIND_ABILITY: StringName = &"ability"
const KIND_LIMIT_BURST: StringName = &"limitburst"
const KIND_ITEM: StringName = &"item"
const KIND_ESPER: StringName = &"esper"
const KIND_MONSTER: StringName = &"monster_skill"

## Attack types (the records' `attack_type`, from the Isb1GDe2 column). They decide
## what a hit counts as for dodge, mitigation and cover, independently of the damage
## formula. 0 means the record did not say.
const ATTACK_UNKNOWN: int = 0
const ATTACK_PHYSICAL: int = 1
const ATTACK_MAGIC: int = 2
const ATTACK_HYBRID: int = 3
const ATTACK_NONE: int = 4
## The alternate cost types (GameDatabase's `alternate_cost`): esper orbs from the
## party's gauge, or the unit's own limit gauge.
const ALTERNATE_COST_ORBS: int = 1
const ALTERNATE_COST_LB: int = 2

var id: String = ""
var kind: StringName = KIND_ABILITY
var name: String = ""
## One of the ATTACK_* values.
var attack_type: int = ATTACK_UNKNOWN
var mp_cost: int = 0
## Limit gauge the skill needs, in hundredths of a crystal: a limit burst's level cost,
## or what an ability that "consumes own LB gauge" takes (alternateCost "2:N"; N is
## already in hundredths, a reading: Rough Divide's 2:400 is 4 crystals).
var lb_cost: int = 0
## Esper orbs the skill consumes from the party's gauge, on top of its MP (both are
## needed: the user's rule, 2026-10-02).
var orb_cost: int = 0
## "White", "Black", "Green" or "Blue" for magic, "" otherwise.
var magic_type: String = ""
var move_type: int = 0
## 1-based element ids (1 fire .. 8 dark), from element_inflict.
var elements: PackedInt32Array = PackedInt32Array()
var effects: Array[SkillEffect] = []
## The record the skill was built from, kept for adapters and debugging.
var record: Dictionary = {}


## Builds a skill from a GameDatabase-shaped record: name, cost, alternate_cost, element_inflict,
## effects_raw, attack_frames / attack_damage (one group per effect), magic_type,
## move_type. An effect past the last frame group uses the first group, as
## OpcodeParser does (Bio has three effects and one group).
static func from_record(skill_kind: StringName, skill_id: String, data: Dictionary, schema: Dictionary) -> BattleSkill:
	var skill := BattleSkill.new()
	skill.id = skill_id
	skill.kind = skill_kind
	skill.record = data
	skill.name = str(data.get("name", ""))
	skill.attack_type = int(data.get("attack_type", ATTACK_UNKNOWN))
	skill.mp_cost = _mp_cost(data.get("cost"))
	skill.orb_cost = _alternate_cost(data.get("alternate_cost"), ALTERNATE_COST_ORBS)
	skill.lb_cost = _alternate_cost(data.get("alternate_cost"), ALTERNATE_COST_LB)
	skill.magic_type = str(data.get("magic_type", ""))
	skill.move_type = int(data.get("move_type", 0))
	skill.elements = _elements(data.get("element_inflict"))
	var frame_groups: Array = data.get("attack_frames", [])
	var damage_groups: Array = data.get("attack_damage", [])
	var effects_raw: Array = data.get("effects_raw", [])
	for i in range(effects_raw.size()):
		skill.effects.append(SkillEffect.from_raw(
			i, effects_raw[i], _group(frame_groups, i), _group(damage_groups, i), schema
		))
	return skill


## A basic attack: one single-target physical hit at 100% per swing, timed by the
## attacker's own attackFrames string ("4:100:3:2", "15:60:3:2-36:40:3:2").
static func basic_attack(attack_frames: String, attack_move_type: int = 0) -> BattleSkill:
	var skill := BattleSkill.new()
	skill.id = "attack"
	skill.kind = KIND_ATTACK
	skill.name = "Attack"
	skill.attack_type = ATTACK_PHYSICAL
	skill.move_type = attack_move_type
	var parsed: Dictionary = parse_attack_frames(attack_frames)
	var effect := SkillEffect.new()
	effect.opcode = 1
	effect.type = "PHYSICAL_DAMAGE"
	effect.target_area = SkillEffect.AREA_SINGLE
	effect.target_type = SkillEffect.TARGET_OPPONENT
	effect.params = {"modifier": 100}
	effect.set_hits(_group(parsed["frames"], 0), _group(parsed["damage"], 0))
	skill.effects.append(effect)
	return skill


## A copy of this skill whose physical damage effects hit at `modifier` percent: a
## counter's normal attack (Counters; passive 12's 200 doubles it). The effects are
## copies; everything else is shared.
func with_damage_modifier(modifier: int) -> BattleSkill:
	var copy: BattleSkill = _copy_without_effects()
	for effect in effects:
		var changed: SkillEffect = effect.duplicate_effect()
		if changed.type == "PHYSICAL_DAMAGE":
			changed.params["modifier"] = modifier
		copy.effects.append(changed)
	return copy


## The part of this skill that lands later: effect `effect_index` (delayed damage,
## opcode 13, or a jump, 52 and 134) as plain physical damage at its modifier, alone in a
## copy that costs nothing. It keeps the opcode (damage boosts filter on it), the frame
## group (the delayed hit's own timing), the id, kind, attack type and elements. A jump
## always lands on an opponent, one at a time, even when its effect says self (monster
## 900156). null for an index out of range.
func delayed_part(effect_index: int) -> BattleSkill:
	if effect_index < 0 or effect_index >= effects.size():
		return null
	var copy: BattleSkill = _copy_without_effects()
	copy.mp_cost = 0
	copy.lb_cost = 0
	copy.orb_cost = 0
	var part: SkillEffect = effects[effect_index].duplicate_effect()
	part.type = "PHYSICAL_DAMAGE"
	part.params = {"modifier": part.param_float("modifier", 100.0)}
	if part.opcode != 13:
		part.target_area = SkillEffect.AREA_SINGLE
		part.target_type = SkillEffect.TARGET_OPPONENT
	part.index = 0
	copy.effects.append(part)
	return copy


## A copy of everything but the effects, which the caller fills in.
func _copy_without_effects() -> BattleSkill:
	var copy := BattleSkill.new()
	copy.id = id
	copy.kind = kind
	copy.name = name
	copy.attack_type = attack_type
	copy.mp_cost = mp_cost
	copy.lb_cost = lb_cost
	copy.orb_cost = orb_cost
	copy.magic_type = magic_type
	copy.move_type = move_type
	copy.elements = elements
	copy.record = record
	return copy


## Splits an attackFrames string into { frames: [[int]], damage: [[int]] }, one inner
## array per '@' group. Same grammar as GameDatabase._decode_attack_frames: '-'
## separates hits, each hit is 'frame:damage:x:y'.
static func parse_attack_frames(raw: String) -> Dictionary:
	var frames: Array = []
	var damage: Array = []
	if raw.strip_edges() == "":
		return {"frames": frames, "damage": damage}
	for group in raw.split("@"):
		var group_frames: Array = []
		var group_damage: Array = []
		for hit in str(group).split("-", false):
			var parts: PackedStringArray = str(hit).split(":")
			if parts.size() >= 1 and parts[0].strip_edges().is_valid_int():
				group_frames.append(int(parts[0]))
			if parts.size() >= 2 and parts[1].strip_edges().is_valid_int():
				group_damage.append(int(parts[1]))
		frames.append(group_frames)
		damage.append(group_damage)
	return {"frames": frames, "damage": damage}


## True when any effect is one of `types`.
func has_effect_type(types: Array) -> bool:
	for effect in effects:
		if types.has(effect.type):
			return true
	return false


## Frame offset of the skill's last hit, over all its effects.
func last_hit_frame() -> int:
	var last: int = 0
	for effect in effects:
		last = maxi(last, effect.last_hit_frame())
	return last


## Physical and hybrid attacks are the weapon's: they carry the attacker's weapon
## elements and ailments, and a dual wielder makes them twice (wiki: magic takes the
## ability's elements only).
static func is_weapon_attack(attack_type: int) -> bool:
	return attack_type == ATTACK_PHYSICAL or attack_type == ATTACK_HYBRID


static func _group(groups: Array, index: int) -> Array:
	if groups.is_empty():
		return []
	var group: Variant = groups[index] if index < groups.size() else groups[0]
	return group if group is Array else []


static func _mp_cost(cost: Variant) -> int:
	if cost is Dictionary:
		return maxi(0, int((cost as Dictionary).get("MP", 0)))
	if typeof(cost) in [TYPE_INT, TYPE_FLOAT]:
		return maxi(0, int(cost))
	return 0


static func _alternate_cost(alternate_cost: Variant, cost_type: int) -> int:
	if alternate_cost is Dictionary and int((alternate_cost as Dictionary).get("type", 0)) == cost_type:
		return maxi(0, int((alternate_cost as Dictionary).get("amount", 0)))
	return 0


static func _elements(element_inflict: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if element_inflict is Array:
		for element in element_inflict:
			if typeof(element) in [TYPE_INT, TYPE_FLOAT] and int(element) >= 1 and int(element) <= 8:
				out.append(int(element))
	return out
