class_name SkillEffect
extends RefCounted

## One effect of a skill: its opcode, what the opcode schema calls it, whom it targets
## and when its hits land. Built from one `effects_raw` entry,
## [targetRange, target, opcode, params], plus that effect's attackFrames group.

## targetRange values.
const AREA_SELF: int = 0
const AREA_SINGLE: int = 1
const AREA_ALL: int = 2
## One random living target per hit.
const AREA_RANDOM: int = 3

## target values, from the caster's point of view.
const TARGET_NONE: int = 0
const TARGET_OPPONENT: int = 1
const TARGET_ALLY: int = 2
const TARGET_SELF: int = 3
## Both sides at once (rare, AoE only).
const TARGET_EVERYONE: int = 4
const TARGET_ALLY_EXCEPT_SELF: int = 5
## Ally. Which way it differs from 2 is not established; treated the same.
const TARGET_ALLY_ALT: int = 6

## Position in the skill's effect list.
var index: int = 0
var opcode: int = 0
## Schema type, e.g. "PHYSICAL_DAMAGE"; "" when the schema does not map the opcode.
var type: String = ""
var target_area: int = AREA_SINGLE
var target_type: int = TARGET_OPPONENT
## Params under the schema's key names. Zeros, "none" and unnamed slots are dropped.
var params: Dictionary = {}
## The positional params as they came from the data.
var raw_params: Array = []
## Frame offset of each hit, relative to the action's start (after any move offset).
var hit_frames: PackedInt32Array = PackedInt32Array()
## Share of the effect's total amount carried by each hit, in percent.
var hit_damage: PackedInt32Array = PackedInt32Array()


## `frames` and `damage` are this effect's attackFrames group. An effect with no frame
## data (common for buffs and self effects) resolves once, on frame 0, at full strength.
static func from_raw(effect_index: int, raw: Array, frames: Array, damage: Array, schema: Dictionary) -> SkillEffect:
	var effect := SkillEffect.new()
	effect.index = effect_index
	effect.target_area = int(raw[0]) if raw.size() > 0 else AREA_SINGLE
	effect.target_type = int(raw[1]) if raw.size() > 1 else TARGET_OPPONENT
	effect.opcode = int(raw[2]) if raw.size() > 2 else 0
	var payload: Array = raw[3] if raw.size() > 3 and raw[3] is Array else []
	effect.raw_params = payload
	var entry: Dictionary = OpcodeParser.resolve_schema_entry(schema, effect.opcode, payload)
	if not entry.is_empty():
		effect.type = str(entry.get("type", ""))
		effect.params = OpcodeParser.map_payload(entry, payload)
	effect.set_hits(frames, damage)
	return effect


## Sets the hit timeline. Missing splits are shared evenly; no frames at all means one
## hit on frame 0.
func set_hits(frames: Array, damage: Array) -> void:
	hit_frames = PackedInt32Array()
	hit_damage = PackedInt32Array()
	for frame in frames:
		hit_frames.append(int(frame))
	if hit_frames.is_empty():
		hit_frames.append(0)
	for i in range(hit_frames.size()):
		if i < damage.size():
			hit_damage.append(int(damage[i]))
		else:
			@warning_ignore("integer_division")
			hit_damage.append(100 / hit_frames.size())


## A copy whose params can change without touching this effect (a counter's attack).
func duplicate_effect() -> SkillEffect:
	var copy := SkillEffect.new()
	copy.index = index
	copy.opcode = opcode
	copy.type = type
	copy.target_area = target_area
	copy.target_type = target_type
	copy.params = params.duplicate()
	copy.raw_params = raw_params
	copy.hit_frames = hit_frames
	copy.hit_damage = hit_damage
	return copy


func is_known() -> bool:
	return type != ""


func hit_count() -> int:
	return hit_frames.size()


## Frame offset of the last hit.
func last_hit_frame() -> int:
	var last: int = 0
	for frame in hit_frames:
		last = maxi(last, frame)
	return last


## A numeric param as a float, `default` when the slot was unused or not a number.
func param_float(key: String, default: float = 0.0) -> float:
	var value: Variant = params.get(key, default)
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value)
	return default
