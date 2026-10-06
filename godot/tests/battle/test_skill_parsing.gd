extends "res://tests/test_case.gd"

## Opcode schema lookups (variants), SkillEffect / BattleSkill construction, and the
## effect registry checked against the schema.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var schema: Dictionary


func before_each() -> void:
	schema = Fixtures.catalog().skill_schema


func test_overloaded_opcodes_pick_their_variant_by_param_count() -> void:
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 53, [3, 5]).get("type"), "HIDE", "Roy's Hide")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 53, [2, 0, 0, [1, 2], 0, 0]).get("type"), "MULTICAST")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 102, [100, 0, 250]).get("type"), "DEF_DAMAGE")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 102, [1, 2, 0, 3, 4, 0]).get("type"), "MULTICAST_SKILL_TYPES")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 52, [0, 0, 1, 1, 180]).get("type"), "JUMP", "Jump")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 52, [2, 2, 502090]).get("type"), "MAGIC_MULTICAST", "Dual White Magic")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 52, [1, 4, 513971, 0]).get("type"), "MAGIC_MULTICAST", "Quadruple Black Magic")
	assert_eq(OpcodeParser.resolve_schema_entry(schema, 52, [2, 3, 2, 2, 504180, 504180]).get("type"), "MAGIC_MULTICAST", "Dual White/Green Magic")
	assert_true(OpcodeParser.resolve_schema_entry(schema, 424242, []).is_empty())


func test_parse_skill_keeps_opcodes_and_uses_variants() -> void:
	var parsed: Dictionary = OpcodeParser.parse_skill({
		"effects_raw": [[1, 3, 53, [3, 5]], [1, 1, 1, [0, 0, 0, 0, 0, 0, 250, 0]]],
		"attack_frames": [[10]],
		"attack_damage": [[100]],
	}, schema)
	var effects: Array = parsed["effects"]
	assert_eq(effects[0]["type"], "HIDE")
	assert_eq(effects[0]["opcode"], 53)
	assert_eq(effects[0]["effect"], {"turns_min": 3, "turns_max": 5})
	assert_eq(effects[1]["effect"], {"modifier": 250})


func test_skill_effect_from_raw() -> void:
	var effect: SkillEffect = SkillEffect.from_raw(0, [2, 1, 15, [0, 0, 0, 0, 0, 180, 0]], [20, 40], [50, 50], schema)
	assert_eq(effect.type, "MAGIC_DAMAGE")
	assert_eq(effect.target_area, SkillEffect.AREA_ALL)
	assert_eq(effect.params, {"modifier": 180})
	assert_eq(Array(effect.hit_frames), [20, 40])
	assert_eq(Array(effect.hit_damage), [50, 50])

	var unknown: SkillEffect = SkillEffect.from_raw(1, [1, 1, 9999, [1]], [], [], schema)
	assert_false(unknown.is_known())
	assert_eq(Array(unknown.hit_frames), [0], "no frame data: one hit on frame 0")
	assert_eq(Array(unknown.hit_damage), [100])

	var unsplit: SkillEffect = SkillEffect.from_raw(2, [1, 1, 1, []], [5, 10], [], schema)
	assert_eq(Array(unsplit.hit_damage), [50, 50], "missing splits are shared evenly")


func test_consecutive_damage_replacement_and_unlock_keys() -> void:
	var blood_pulsar: SkillEffect = SkillEffect.from_raw(0, [1, 1, 72, [0, 0, 250, 100, 100, 4]], [], [], schema)
	assert_eq(blood_pulsar.type, "CONSECUTIVE_MAG_DAMAGE")
	assert_eq(blood_pulsar.params, {"modifier": 250, "modifier_increment": 100, "modifier_increment_2": 100, "max_stacks": 4})
	var supremacy: SkillEffect = SkillEffect.from_raw(0, [1, 1, 126, [1, 0, 0, 600, 100, 100, 7]], [], [], schema)
	assert_eq(supremacy.params, {"modifier": 600, "modifier_increment": 100, "modifier_increment_2": 100, "max_stacks": 7})
	var point_blank: SkillEffect = SkillEffect.from_raw(0, [1, 1, 1007, [0, 0, 110, 100, 100, 2]], [], [], schema)
	assert_eq(point_blank.params["modifier_increment_2"], 100)

	var savage_blade: SkillEffect = SkillEffect.from_raw(0, [1, 1, 99, [[2, 2, 2], [207780, 703950, 703960], 2, 500530, 2, 500540]], [], [], schema)
	assert_eq(savage_blade.type, "REPLACEMENT")
	assert_eq(savage_blade.params, {
		"condition_types": [2, 2, 2], "condition": [207780, 703950, 703960],
		"true_type": 2, "true": 500530, "false_type": 2, "false": 500540,
	})

	var five: SkillEffect = SkillEffect.from_raw(0, [0, 3, 100, [2, 501930, 99999, 4, 1]], [], [], schema)
	var six: SkillEffect = SkillEffect.from_raw(0, [0, 3, 100, [[2, 2], [502000, 502010], 99999, 2, 1, 0]], [], [], schema)
	assert_eq(five.params, {"skill_types": 2, "skill_ids": 501930, "uses": 99999, "turn_count": 4})
	assert_eq(six.params, {"skill_types": [2, 2], "skill_ids": [502000, 502010], "uses": 99999, "turn_count": 2})


func test_counter_keys() -> void:
	var avoid: SkillEffect = SkillEffect.from_raw(0, [0, 3, 119, [50, 1, 1000, 2, 1, 0]], [], [], schema)
	assert_eq(avoid.type, "PHYS_COUNTER")
	assert_eq(avoid.params, {"counter_chance": 50, "modifier": 1000, "turn_count": 2})
	var antagonize: SkillEffect = SkillEffect.from_raw(0, [0, 3, 123, [50, 1, 150, 5, 1, 2]], [], [], schema)
	assert_eq(antagonize.params, {"counter_chance": 50, "modifier": 150, "turn_count": 5, "max": 2})
	var passives: Dictionary = Fixtures.catalog().passive_schema
	var face_me: Dictionary = OpcodeParser.parse_passive({"effects_raw": [[0, 0, 49, [45, 2, 91003]], [0, 0, 50, [30, 3, 505050, 2]]]}, passives)
	assert_eq(face_me["effects"].map(func(effect: Dictionary) -> Dictionary: return effect["effect"]), [
		{"chance_pct": 45, "cast_type": 2, "skill_id": 91003},
		{"chance_pct": 30, "cast_type": 3, "skill_id": 505050, "max": 2},
	])


func test_effects_past_the_last_frame_group_use_the_first() -> void:
	var skill: BattleSkill = BattleSkill.from_record(BattleSkill.KIND_MAGIC, "1", {
		"name": "Bio",
		"cost": {"MP": 12},
		"element_inflict": [8],
		"effects_raw": [[1, 1, 15, [0, 0, 0, 0, 0, 100, 0]], [1, 1, 139, [0]], [1, 1, 6, [0]]],
		"attack_frames": [[120]],
		"attack_damage": [[100]],
	}, schema)
	assert_eq(skill.mp_cost, 12)
	assert_eq(Array(skill.elements), [8])
	assert_eq(skill.effects.size(), 3)
	for effect in skill.effects:
		assert_eq(Array(effect.hit_frames), [120])


func test_basic_attack_reads_attack_frames() -> void:
	var attack: BattleSkill = BattleSkill.basic_attack("15:60:3:2-36:40:3:2", 1)
	assert_eq(attack.kind, BattleSkill.KIND_ATTACK)
	assert_eq(attack.move_type, 1)
	assert_eq(attack.effects[0].type, "PHYSICAL_DAMAGE")
	assert_eq(Array(attack.effects[0].hit_frames), [15, 36])
	assert_eq(Array(attack.effects[0].hit_damage), [60, 40])
	assert_eq(BattleSkill.parse_attack_frames("")["frames"], [])


func test_registered_handlers_name_real_schema_types() -> void:
	var registry: EffectRegistry = EffectRegistry.create_default()
	assert_eq(registry.unknown_types(schema), PackedStringArray(), "a typo would show up here")
	assert_true(registry.handles("PHYSICAL_DAMAGE"))
	assert_true(registry.handles("MAGIC_DAMAGE"))
	assert_true(registry.handles("HYBRID_DAMAGE"))
	assert_true(registry.handles("HEAL"))
	assert_true(registry.handles("JUMP") and registry.handles("JUMP_ACTIVATED"))
	assert_true(registry.handles("DELAYED_CAST") and registry.handles("DELAYED_PHYS_DAMAGE"))
	assert_has(registry.unhandled_types(schema), "LIBRA")
	assert_has(EffectRegistry.schema_types(schema), "HIDE", "variant types count")
