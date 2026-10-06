extends "res://tests/test_case.gd"

## What the battle sandbox relies on: the engine's debug tools (pending hits, debug
## edits, unsupported-effect queries, an idle enemy brain), the frame ruler's model and
## SandboxBattleFactory, part of it against the real database. Writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const ZU_ID: String = "302001000"


func _duel(hero_spec: Dictionary = {}, foe_spec: Dictionary = {}) -> BattleEngine:
	var hero: Combatant = Fixtures.unit("Hero", hero_spec)
	var spec: Dictionary = {"brain": IdleEnemyBrain.new()}
	spec.merge(foe_spec, true)
	var foe: Combatant = Fixtures.monster("Foe", spec)
	var battle: BattleEngine = Fixtures.engine([hero], [foe])
	battle.start()
	return battle


# === Engine debug tools ===

func test_pending_hits_lists_the_timeline_in_landing_order() -> void:
	var battle: BattleEngine = _duel({"attack_frames": "20:50-10:50"})
	var hero: Combatant = battle.party_members()[0]
	battle.execute(hero.id)
	var pending: Array[ScheduledHit] = battle.timeline.pending_hits()
	assert_eq(pending.size(), 2)
	assert_eq(pending[0].frame, 10)
	assert_eq(pending[1].frame, 20)
	pending.clear()
	assert_eq(battle.timeline.pending_hits().size(), 2, "a copy: clearing it leaves the timeline alone")
	battle.advance(10)
	assert_eq(battle.timeline.pending_hits().size(), 1)


func test_debug_edit_sets_values_and_logs_them() -> void:
	var battle: BattleEngine = _duel()
	var foe: Combatant = battle.enemies[0]
	assert_eq(battle.debug_edit(foe.id, &"hp", 500), BattleEngine.OK)
	assert_eq(foe.hp, 500)
	var edited: Dictionary = battle.events.last_of_type(BattleEventLog.DEBUG_EDITED)
	assert_eq(int(edited["old"]), 100000)
	assert_eq(int(edited["value"]), 500)
	assert_true(battle.format_event(edited).contains("hp 100000 -> 500"), battle.format_event(edited))

	battle.debug_edit(foe.id, &"hp", 999999999)
	assert_eq(foe.hp, foe.max_hp, "clamped to max HP")
	battle.debug_edit(foe.id, &"max_hp", 300)
	assert_eq(foe.hp, 300, "lowering max HP lowers HP with it")

	battle.debug_edit(foe.id, &"stat", 250, "DEF")
	assert_eq(foe.stat("DEF"), 250)
	battle.debug_edit(foe.id, &"element_resist", -50, "FIRE")
	assert_eq(foe.element_resistance("FIRE"), -50)
	assert_eq(battle.debug_edit(foe.id, &"stat", 1, "LUCK"), BattleEngine.REJECT_UNKNOWN_FIELD)
	assert_eq(battle.debug_edit(foe.id, &"speed", 1), BattleEngine.REJECT_UNKNOWN_FIELD)
	assert_eq(battle.debug_edit(999, &"hp", 1), BattleEngine.REJECT_UNKNOWN_TARGET)


func test_debug_ko_defeats_and_ends_the_battle() -> void:
	var battle: BattleEngine = _duel()
	var foe: Combatant = battle.enemies[0]
	battle.debug_edit(foe.id, &"hp", 0)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, foe.id).size(), 1)
	battle.tick()
	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)


func test_debug_lb_edit_enables_the_limit_burst_check() -> void:
	var battle: BattleEngine = _duel({"max_lb": 800, "limit_burst_id": "lb"})
	var hero: Combatant = battle.party_members()[0]
	battle.debug_edit(hero.id, &"lb", 5000)
	assert_eq(hero.lb, 800, "clamped to the gauge")


func test_unsupported_effects_names_what_the_engine_cannot_run() -> void:
	var catalog: SkillCatalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_ABILITY, "mixed", Fixtures.record("Mixed", [
		[1, 1, 1, Fixtures.physical_params(100)],
		[1, 1, 47, [1]],
		[1, 1, 9999, []],
	]))
	var battle := BattleEngine.new(catalog, Fixtures.rules(), 1)
	var skill: BattleSkill = catalog.get_skill(BattleSkill.KIND_ABILITY, "mixed")
	var unsupported: Array[SkillEffect] = battle.unsupported_effects(skill)
	assert_eq(unsupported.size(), 2)
	assert_eq(unsupported[0].opcode, 47, "in the schema (LIBRA), no handler")
	assert_eq(unsupported[1].opcode, 9999, "not in the schema")
	assert_eq(battle.unsupported_effects(null).size(), 0)


func test_an_idle_enemy_lets_the_turn_pass() -> void:
	var battle: BattleEngine = _duel()
	var hero: Combatant = battle.party_members()[0]
	battle.execute(hero.id)
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.turn == 2))
	assert_eq(Fixtures.actions_by(battle, battle.enemies[0].id).size(), 0)
	assert_eq(hero.hp, hero.max_hp)


# === Frame ruler model ===

func test_ruler_shows_pending_and_landed_hits_per_target() -> void:
	var battle: BattleEngine = _duel({"attack_frames": "10:50-30:50"})
	var hero: Combatant = battle.party_members()[0]
	var foe: Combatant = battle.enemies[0]
	battle.execute(hero.id)
	var model: FrameRulerModel = FrameRulerModel.build(battle, [])
	assert_eq(model.rows.size(), 1, "the enemy only: no mark falls on the hero")
	assert_eq(model.rows[0].target_id, foe.id)
	assert_eq(model.rows[0].marks.size(), 2)
	assert_true(model.rows[0].marks[0].pending)
	assert_true(model.rows[0].marks[0].damage)
	assert_eq(model.rows[0].marks[0].amount, roundi(battle.timeline.pending_hits()[0].amount))
	assert_eq(model.actors.size(), 1)
	assert_eq(model.actors[0], hero.id)
	assert_eq(model.chain_window, 20)

	battle.advance(15)
	model = FrameRulerModel.build(battle, battle.events.of_type(BattleEventLog.HIT_LANDED))
	var marks: Array[FrameRulerModel.Mark] = model.rows[0].marks
	assert_eq(marks.size(), 2)
	assert_false(marks[0].pending)
	assert_eq(marks[0].frame, 10)
	assert_true(marks[1].pending)
	assert_eq(marks[1].frame, 30)
	assert_true(model.describe(marks[0], battle).contains("Hero#%d -> Foe#%d" % [hero.id, foe.id]))
	assert_almost_eq(model.position_of(battle.frame), float(FrameRulerModel.PAST_FRAMES) / float(FrameRulerModel.PAST_FRAMES + FrameRulerModel.FUTURE_FRAMES), 0.0001)


func test_ruler_drops_hits_older_than_its_window() -> void:
	var battle: BattleEngine = _duel({"attack_frames": "5:100"})
	battle.execute(battle.party_members()[0].id)
	battle.advance(5 + FrameRulerModel.PAST_FRAMES + 1)
	var model: FrameRulerModel = FrameRulerModel.build(battle, battle.events.of_type(BattleEventLog.HIT_LANDED))
	assert_eq(model.rows[0].marks.size(), 0)


# === SandboxBattleFactory: parsing and behaviours ===

func test_stat_overrides_parse_loosely_and_report_unknown_keys() -> void:
	var errors: Array[String] = []
	var stats: Dictionary = SandboxBattleFactory.parse_stat_overrides("ATK=1000 hp:5000, mag 300 luck=9", errors)
	assert_eq(stats, {"ATK": 1000, "HP": 5000, "MAG": 300})
	assert_eq(errors.size(), 1)
	assert_eq(SandboxBattleFactory.parse_stat_overrides(""), {})


func test_monster_ids_parse_lists_and_counts() -> void:
	var errors: Array[String] = []
	var ids: PackedStringArray = SandboxBattleFactory.parse_monster_ids("302001000 x2, 101001000;123", errors)
	assert_eq(Array(ids), ["302001000", "302001000", "101001000"])
	assert_eq(errors.size(), 1, "123 is not a 9-digit id")
	assert_eq(SandboxBattleFactory.parse_monster_ids("302001000*20").size(), SandboxBattleFactory.MAX_ENEMIES)


func test_behaviour_switches_and_restores_the_built_brain() -> void:
	var built := EnemyBrain.new()
	var foe: Combatant = Fixtures.monster("Foe", {"brain": built})
	assert_eq(SandboxBattleFactory.behaviour_of(foe), SandboxBattleFactory.BEHAVIOUR_SCRIPTED)
	SandboxBattleFactory.set_behaviour(foe, SandboxBattleFactory.BEHAVIOUR_PASS)
	assert_true(foe.brain is IdleEnemyBrain)
	assert_eq(SandboxBattleFactory.behaviour_of(foe), SandboxBattleFactory.BEHAVIOUR_PASS)
	SandboxBattleFactory.set_behaviour(foe, SandboxBattleFactory.BEHAVIOUR_ATTACK)
	assert_ne(foe.brain, built)
	assert_eq(SandboxBattleFactory.behaviour_of(foe), SandboxBattleFactory.BEHAVIOUR_ATTACK)
	SandboxBattleFactory.set_behaviour(foe, SandboxBattleFactory.BEHAVIOUR_SCRIPTED)
	assert_eq(foe.brain, built)


func test_command_keys_match_by_kind_and_skill() -> void:
	var fire := BattleCommand.skill(BattleSkill.KIND_MAGIC, "20010", 3)
	assert_eq(SandboxBattleFactory.command_key(fire), SandboxBattleFactory.command_key(BattleCommand.skill(BattleSkill.KIND_MAGIC, "20010")))
	assert_eq(SandboxBattleFactory.command_key(null), SandboxBattleFactory.command_key(BattleCommand.attack(5)), "nothing queued is a basic attack")
	assert_ne(SandboxBattleFactory.command_key(BattleCommand.attack()), SandboxBattleFactory.command_key(BattleCommand.defend()))


# === SandboxBattleFactory against the database ===

func test_test_preset_builds_the_old_test_battle() -> void:
	var factory := SandboxBattleFactory.new()
	var battle: BattleEngine = factory.build(SandboxBattleFactory.test_setup(), 42, Fixtures.rules())
	assert_eq(factory.problems.size(), 0, str(factory.problems))
	var party: Array[Combatant] = battle.party_members()
	assert_eq(party.size(), 2)
	assert_eq(party[0].name, "Lasswell")
	assert_eq(party[1].name, "Rain")
	assert_eq(party[0].max_hp, 100000, "the test stats")
	assert_eq(party[0].stat("ATK"), 1000)
	assert_eq(battle.enemies.size(), 1)
	assert_eq(battle.enemies[0].source_id, ZU_ID)
	assert_eq(battle.battle_seed, 42)


func test_setup_slots_take_rarity_level_and_per_slot_overrides() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["party"][0] = {"unit_id": "100000205", "level": 60, "lb_level": 3, "stats": "MAG=777"}
	setup["party"][1] = {}
	setup["party"][3] = {"unit_id": "100000102", "level": 5, "lb_level": 1, "stats": ""}
	var factory := SandboxBattleFactory.new()
	var battle: BattleEngine = factory.build(setup, 1, Fixtures.rules())
	assert_null(battle.party[1], "an empty slot keeps its index")
	var lasswell: Combatant = battle.party[0]
	assert_eq(lasswell.level, 60)
	assert_eq(lasswell.limit_burst_level, 3)
	assert_eq(lasswell.limit_burst_id, "100000205")
	assert_eq(lasswell.stat("MAG"), 777)
	var rain: Combatant = battle.party[3]
	assert_eq(rain.level, 5)
	assert_ne(rain.stat("MAG"), 777, "overrides belong to their slot")


func test_extra_skills_join_the_slots_skills_and_passives_and_bad_ids_are_reported() -> void:
	var errors: Array[String] = []
	assert_eq(SandboxBattleFactory.parse_skill_ids("200150, 20010;503330 abc", errors), PackedStringArray(["200150", "20010", "503330"]))
	assert_eq(errors.size(), 1, str(errors))

	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["party"][0]["skills"] = "200150 20010 217440 999999999"
	var factory := SandboxBattleFactory.new()
	var battle: BattleEngine = factory.build(setup, 1, Fixtures.rules())
	assert_eq(factory.problems, ["slot 1: unknown skill id 999999999"] as Array[String])
	var labels: Array = SandboxBattleFactory.command_options(battle, battle.party[0]).map(func(option: Dictionary) -> String: return option["label"])
	assert_true(labels.has("Dualcast  [multicast x2]"), str(labels))
	assert_true(battle.party[0].passives.multicast_commands.has("503330"), "the Steal Chance passive (217440) counts like the unit's own")
	assert_true(labels.any(func(label: String) -> bool: return label.begins_with("Fire")), str(labels))
	var rain_labels: Array = SandboxBattleFactory.command_options(battle, battle.party[1]).map(func(option: Dictionary) -> String: return option["label"])
	assert_false(rain_labels.has("Dualcast  [multicast x2]"), "the extra skills belong to their slot")


func test_monster_mode_builds_enemies_by_id_and_reports_unknown_ones() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["enemy_mode"] = SandboxBattleFactory.ENEMY_MODE_MONSTERS
	setup["monsters"] = "%s x2, 999999999" % ZU_ID
	var factory := SandboxBattleFactory.new()
	var battle: BattleEngine = factory.build(setup, 1, Fixtures.rules())
	assert_eq(battle.enemies.size(), 2)
	assert_eq(battle.enemies[1].name, "Zu")
	assert_ne(battle.enemies[0].id, battle.enemies[1].id)
	assert_eq(factory.problems.size(), 1, str(factory.problems))


func test_wave_lists_and_missions_queue_every_wave() -> void:
	var factory := SandboxBattleFactory.new()
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["battle_group"] = "%s | %s" % [BattleBuilder.TEST_BATTLE_GROUP, BattleBuilder.TEST_BATTLE_GROUP]
	assert_eq(factory.build(setup, 1, Fixtures.rules()).wave_count(), 2)
	assert_eq(factory.problems.size(), 0, str(factory.problems))
	setup["battle_group"] = "%s | 0" % BattleBuilder.TEST_BATTLE_GROUP
	factory.build(setup, 1, Fixtures.rules())
	assert_eq(factory.problems, ["wave 2: battle group \"0\" has no monsters"])

	setup["enemy_mode"] = SandboxBattleFactory.ENEMY_MODE_MONSTERS
	setup["monsters"] = "%s | %s x2" % [ZU_ID, ZU_ID]
	var battle: BattleEngine = factory.build(setup, 1, Fixtures.rules())
	assert_eq([battle.wave_count(), battle.enemies.size()], [2, 1])

	setup["enemy_mode"] = SandboxBattleFactory.ENEMY_MODE_MISSION
	setup["mission"] = "1110100"
	battle = factory.build(setup, 1, Fixtures.rules())
	assert_eq(battle.wave_count(), EncounterResolver.build_wave_plan("1110100").size())
	assert_true(battle.enemies.size() > 0)
	assert_eq(factory.problems.size(), 0, str(factory.problems))
	setup["mission"] = "0"
	factory.build(setup, 1, Fixtures.rules())
	assert_eq(factory.problems, ["mission \"0\" has no wave plan"])


func test_waves_split_on_bars_and_preview_per_wave() -> void:
	assert_eq(SandboxBattleFactory.split_waves(" a | | b "), PackedStringArray(["a", "b"]))
	var lines: PackedStringArray = SandboxBattleFactory.describe_enemies(SandboxBattleFactory.ENEMY_MODE_MONSTERS, "%s | %s" % [ZU_ID, ZU_ID])
	assert_eq(lines[0], "Wave 1")
	assert_true(lines[1].begins_with("  " + ZU_ID), lines[1])
	assert_eq(lines[2], "Wave 2")
	var single: PackedStringArray = SandboxBattleFactory.describe_enemies(SandboxBattleFactory.ENEMY_MODE_MONSTERS, ZU_ID)
	assert_true(single[0].begins_with(ZU_ID), "no heading for one wave")
	var mission: PackedStringArray = SandboxBattleFactory.describe_enemies(SandboxBattleFactory.ENEMY_MODE_MISSION, "1110100")
	assert_eq(mission[0], "Wave 1")


func test_enemy_by_id_matches_the_battle_group_build() -> void:
	var builder := BattleBuilder.new(Fixtures.rules(), null, 42)
	var alone: Combatant = builder.enemy_by_id(ZU_ID)
	var grouped: Combatant = builder.formation_for("", BattleBuilder.TEST_BATTLE_GROUP)[0]
	assert_eq(alone.name, grouped.name)
	assert_eq(alone.max_hp, grouped.max_hp)
	assert_eq(alone.stat("ATK"), grouped.stat("ATK"))
	assert_eq(Array(alone.attack_skill.effects[0].hit_frames), Array(grouped.attack_skill.effects[0].hit_frames))
	assert_true(alone.brain is ScriptedEnemyBrain)
	assert_false(alone.is_boss)
	assert_null(builder.enemy_by_id("999999999"))


func test_unit_search_ranks_exact_names_first() -> void:
	var found: Array[Dictionary] = SandboxBattleFactory.search_units("lasswell")
	assert_true(found.size() > 1, "Lasswell has several versions")
	assert_eq(found[0]["series"], "100000202")
	assert_eq((found[0]["rows"] as Array).size(), 5, "rarity 2 to 6")
	assert_eq(SandboxBattleFactory.search_units("100000205")[0]["series"], "100000202", "an id finds its series")
	var rows: Array[Dictionary] = SandboxBattleFactory.series_rows("100000204")
	assert_eq(rows.size(), 5)
	assert_eq(rows[0]["unit_id"], "100000202")
	assert_eq(int(rows[4]["max_lv"]), 100)
	assert_eq(SandboxBattleFactory.search_units("").size(), 0)


func test_monster_search_and_descriptions() -> void:
	var found: Array = SandboxBattleFactory.search_monsters("zu")
	var ids: Array = found.map(func(row: Dictionary) -> String: return str(row["monsterId"]))
	assert_has(ids, ZU_ID)
	assert_eq(SandboxBattleFactory.describe_monster(ZU_ID), "Zu Lv %d, 3000 HP" % int(GameDatabase.get_monster_parts(ZU_ID)["level"]))
	var lines: PackedStringArray = SandboxBattleFactory.describe_battle_group(BattleBuilder.TEST_BATTLE_GROUP)
	assert_true(lines.size() >= 1 and lines[0].begins_with(ZU_ID), str(lines))


func test_command_options_follow_the_old_skill_menu() -> void:
	var battle: BattleEngine = SandboxBattleFactory.new().build(SandboxBattleFactory.test_setup(), 1, Fixtures.rules())
	var lasswell: Combatant = battle.party_members()[0]
	var options: Array[Dictionary] = SandboxBattleFactory.command_options(battle, lasswell)
	assert_eq(options[0]["label"], "Attack")
	assert_eq(options[1]["label"], "Defend")
	assert_true(str(options[2]["label"]).begins_with("LB: "), str(options[2]["label"]))
	assert_eq((options[2]["command"] as BattleCommand).kind, BattleCommand.Kind.LIMIT_BURST)
	var profile_skills: int = (lasswell.profile["skills"]["magic"] as Array).size() + (lasswell.profile["skills"]["ability"] as Array).size()
	assert_true(options.size() <= 3 + profile_skills)
	for option in options.slice(3):
		var command: BattleCommand = option["command"]
		assert_eq(command.kind, BattleCommand.Kind.SKILL)
		assert_true(command.skill_kind in [BattleSkill.KIND_MAGIC, BattleSkill.KIND_ABILITY] and command.skill_id != "", str(option["label"]))
