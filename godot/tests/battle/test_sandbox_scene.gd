extends "res://tests/test_case.gd"

## Drives the sandbox scene headless the way a user would (setup, commands, inspect and
## edit, enemy behaviour, restart), so a script error in its UI code fails a test. The
## headless renderer draws nothing; what is checked is the state behind the widgets.
## remember_setup is off, so nothing is written to user://.

const Sandbox = preload("res://features/battle/sandbox/battle_sandbox.gd")
const SANDBOX_SCENE: PackedScene = preload("res://features/battle/sandbox/BattleSandbox.tscn")

var _sandbox: Sandbox = null


func before_each() -> void:
	_sandbox = SANDBOX_SCENE.instantiate()
	_sandbox.remember_setup = false
	(Engine.get_main_loop() as SceneTree).root.add_child(_sandbox)


## Detached now, freed at the end of the frame: TouchScrollInstaller's deferred calls
## for the scene's ScrollContainers must still find them (KNOWN-BUGS.md #8).
func after_each() -> void:
	_sandbox.get_parent().remove_child(_sandbox)
	_sandbox.queue_free()


func test_opens_on_the_test_battle() -> void:
	var engine: BattleEngine = _sandbox.session.engine
	assert_not_null(engine)
	assert_eq(engine.phase, BattleEngine.Phase.PLAYER)
	assert_eq(engine.party_members().size(), 2)
	assert_eq(_sandbox._cards.size(), 3, "two party cards and Zu's")
	_sandbox._refresh()
	assert_true(_sandbox._status.text.contains("Turn 1"), _sandbox._status.text)
	assert_not_null(_sandbox._ruler.model)


func test_commands_from_the_cards_reach_the_engine() -> void:
	var engine: BattleEngine = _sandbox.session.engine
	var lasswell: Combatant = engine.party_members()[0]
	var rain: Combatant = engine.party_members()[1]
	var zu: Combatant = engine.enemies[0]
	var lasswell_card = _sandbox._cards[lasswell.id]
	var rain_card = _sandbox._cards[rain.id]

	lasswell_card._target.item_selected.emit(1)
	assert_eq(lasswell.queued_command.target_id, zu.id, "picking a target queues an attack on it")
	rain_card._actions.item_selected.emit(1)
	assert_eq(rain.queued_command.kind, BattleCommand.Kind.DEFEND)
	_sandbox._refresh()
	assert_eq(rain_card._actions.selected, 1, "the card mirrors the queued command")

	# The card's own signal, not the button's: a button press plays the click sound,
	# which is still playing when the test run quits.
	lasswell_card.execute_pressed.emit(lasswell.id)
	assert_true(lasswell.acted)
	_sandbox._execute_all_units()
	assert_true(rain.acted and rain.defending)
	_sandbox.session.step(10)
	_sandbox._refresh()
	assert_true(_sandbox._log._events.size() > 5)
	assert_true(_sandbox._ruler.model.rows.size() >= 1)
	_sandbox.session.step(400)
	_sandbox._refresh()
	assert_true(engine.turn >= 2 or engine.phase == BattleEngine.Phase.ENDED)


func test_inspect_edit_and_behaviour_survive_as_intended_across_restart() -> void:
	var zu: Combatant = _sandbox.session.engine.enemies[0]
	_sandbox._on_card_inspected(zu.id)
	assert_eq(_sandbox._tabs.current_tab, Sandbox.TAB_INSPECT)
	_sandbox._inspector._emit_edit(&"hp", "", 1)
	assert_eq(zu.hp, 1)
	_sandbox._inspector._emit_edit(&"element_resist", "WIND", -100)
	assert_eq(zu.element_resistance("WIND"), -100)
	_sandbox._refresh()
	assert_true(_sandbox._inspector._details.text.contains("WIN -100"), _sandbox._inspector._details.text)

	_sandbox._cards[zu.id]._behaviour.item_selected.emit(2)
	assert_true(zu.brain is IdleEnemyBrain)

	_sandbox._restart(false)
	var fresh: Combatant = _sandbox.session.engine.enemies[0]
	assert_ne(fresh, zu, "a new engine")
	assert_eq(fresh.hp, fresh.max_hp, "edits do not survive a restart")
	assert_true(fresh.brain is IdleEnemyBrain, "the behaviour does")
	assert_eq(_sandbox._selected_id, fresh.id, "ids are stable, so the selection stays")

	_sandbox._restart(true)
	assert_eq(_sandbox._setup.get_setup()["seed"], _sandbox.session.battle_seed)


func test_setup_panel_builds_a_new_battle() -> void:
	var setup_panel = _sandbox._setup
	setup_panel._slots[0].name_edit.text = "100000205"
	setup_panel._find_unit(0)
	setup_panel._add_monster("302001000")
	setup_panel._add_monster("302001000")
	var setup: Dictionary = setup_panel.get_setup()
	assert_eq(setup["party"][0]["unit_id"], "100000205")
	assert_eq(int(setup["party"][0]["level"]), 80, "a picked unit starts at its max level")
	assert_eq(setup["enemy_mode"], SandboxBattleFactory.ENEMY_MODE_MONSTERS)
	assert_true(setup_panel._enemy_preview.text.contains("Zu"), setup_panel._enemy_preview.text)

	setup_panel.start_requested.emit(setup)
	var engine: BattleEngine = _sandbox.session.engine
	assert_eq(engine.party[0].level, 80)
	assert_eq(engine.enemies.size(), 2)
	assert_eq(_sandbox._cards.size(), 4)
	_sandbox._refresh()


func test_a_new_wave_replaces_the_enemy_cards() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["battle_group"] = "%s | %s" % [BattleBuilder.TEST_BATTLE_GROUP, BattleBuilder.TEST_BATTLE_GROUP]
	_sandbox._start(setup)
	var engine: BattleEngine = _sandbox.session.engine
	var first_zu: Combatant = engine.enemies[0]
	_sandbox._on_card_inspected(first_zu.id)
	_sandbox._inspector._ailment_toggles["POISON"].toggled.emit(true)
	assert_true(first_zu.has_ailment("POISON"), "the inspector's ailment toggle")
	_sandbox._inspector._emit_edit(&"hp", "", 0)
	_sandbox.session.step(1)
	assert_eq(engine.wave, 2, "the session started wave 2 by itself")
	var second_zu: Combatant = engine.enemies[0]
	assert_ne(second_zu.id, first_zu.id)
	assert_true(_sandbox._cards.has(second_zu.id) and not _sandbox._cards.has(first_zu.id))
	assert_eq(_sandbox._cards.size(), 3)
	_sandbox._refresh()
	assert_true(_sandbox._status.text.contains("Wave 2/2"), _sandbox._status.text)


func test_an_esper_picked_in_the_form_is_evoked_once_the_orbs_are_full() -> void:
	var setup_panel = _sandbox._setup
	setup_panel.set_setup(SandboxBattleFactory.test_setup())
	setup_panel._slots[0].esper.select(setup_panel._slots[0].esper.get_item_index(2))
	setup_panel._slots[0].esper_rank.value = 2
	var setup: Dictionary = setup_panel.get_setup()
	assert_eq([int(setup["party"][0]["esper"]), int(setup["party"][0]["esper_rank"])], [2, 2])
	assert_eq(int(setup["party"][1]["esper"]), 0, "no esper")
	setup_panel.set_setup(setup)
	assert_eq(setup_panel.get_setup()["party"][0]["esper"], 2, "the form reads back what it was given")

	setup_panel.start_requested.emit(setup)
	var engine: BattleEngine = _sandbox.session.engine
	var lasswell: Combatant = engine.party_members()[0]
	assert_eq(lasswell.esper_skill_id, "10202", "Ifrit, rank 2")
	var card = _sandbox._cards[lasswell.id]
	var evoke_index: int = int(card._option_index[SandboxBattleFactory.command_key(BattleCommand.evoke())])
	card._actions.item_selected.emit(evoke_index)
	assert_eq(lasswell.queued_command.kind, BattleCommand.Kind.EVOKE)
	_sandbox._refresh()
	assert_eq(card._note.text, str(BattleEngine.REJECT_ESPER_GAUGE_NOT_FULL))
	assert_true(_sandbox._status.text.contains("esper orbs 0/10"), _sandbox._status.text)

	_sandbox._on_card_inspected(lasswell.id)
	_sandbox._inspector._quick(&"orbs", "", func(_f: Combatant) -> int: return engine.rules.esper_gauge_max)
	assert_eq(engine.esper_orbs, 10)
	_sandbox._refresh()
	assert_true(_sandbox._inspector._details.text.contains("Esper 2: Hellfire"), _sandbox._inspector._details.text)
	card.execute_pressed.emit(lasswell.id)
	assert_eq(engine.esper_orbs, 0)
	assert_eq(engine.events.last_of_type(BattleEventLog.ACTION_STARTED)["skill_name"], "Hellfire")


func test_a_multicast_command_takes_a_row_per_pick() -> void:
	var setup_panel = _sandbox._setup
	setup_panel.set_setup(SandboxBattleFactory.test_setup())
	setup_panel._slots[0].skills.text = "200150 20010 20020"
	var setup: Dictionary = setup_panel.get_setup()
	assert_eq(setup["party"][0]["skills"], "200150 20010 20020")
	setup_panel.set_setup(setup)
	assert_eq(setup_panel._slots[0].skills.text, "200150 20010 20020", "the form reads it back")
	setup_panel.start_requested.emit(setup)

	var engine: BattleEngine = _sandbox.session.engine
	var lasswell: Combatant = engine.party_members()[0]
	var zu: Combatant = engine.enemies[0]
	var card = _sandbox._cards[lasswell.id]
	var dualcast: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "200150")
	card._actions.item_selected.emit(int(card._option_index[SandboxBattleFactory.command_key(dualcast)]))
	_sandbox._refresh()
	assert_eq(card._pick_rows.size(), 2, "one row per pick")
	assert_eq(card._note.text, str(BattleEngine.REJECT_MULTICAST_INCOMPLETE))
	assert_true(card._execute.disabled)
	var rows: Array = card._pick_rows
	var fire: int = card._pick_item(BattleCommand.skill(BattleSkill.KIND_MAGIC, "20010"))
	var blizzard: int = card._pick_item(BattleCommand.skill(BattleSkill.KIND_MAGIC, "20020"))
	var dualcast_item: int = card._pick_item(dualcast)
	assert_true(fire > 0 and blizzard > 0 and dualcast_item > 0)
	assert_false((rows[0][0] as OptionButton).is_item_disabled(fire), "Fire can be picked")
	assert_true((rows[0][0] as OptionButton).is_item_disabled(dualcast_item), "Dualcast cannot pick itself")

	(rows[0][0] as OptionButton).select(fire)
	(rows[0][0] as OptionButton).item_selected.emit(fire)
	(rows[1][0] as OptionButton).select(blizzard)
	(rows[1][0] as OptionButton).item_selected.emit(blizzard)
	assert_eq(lasswell.queued_command.picks.size(), 2)
	_sandbox._refresh()
	assert_false(card._execute.disabled, card._note.text)
	assert_eq((rows[1][0] as OptionButton).selected, blizzard, "the rows mirror the queued picks")

	# The test stats' Fire alone would KO Zu (3,000 HP) before Blizzard lands.
	engine.debug_edit(zu.id, &"max_hp", 10000000)
	engine.debug_edit(zu.id, &"hp", 10000000)
	card.execute_pressed.emit(lasswell.id)
	_sandbox.session.step(200)
	var picks: Array = engine.events.of_type(BattleEventLog.ACTION_STARTED).filter(
		func(event: Dictionary) -> bool: return int(event["actor"]) == lasswell.id)
	assert_eq(picks.map(func(event: Dictionary) -> String: return event["skill_id"]), ["20010", "20020"])
	assert_eq(int(picks[1]["frame"]) - int(picks[0]["frame"]), engine.rules.cast_gap_frames)
	for pick in picks:
		var landed: Array = engine.events.of_type(BattleEventLog.HIT_LANDED).filter(
			func(event: Dictionary) -> bool: return int(event["action"]) == int(pick["action"]) and int(event["target"]) == zu.id)
		assert_false(landed.is_empty(), "%s reaches Zu, the default target" % pick["skill_name"])
	_sandbox._refresh()


func test_a_granted_skill_joins_the_card_and_the_inspector() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	# Noctis's Warp Strike: Point-Blank Warp-Strike (501620) for one turn.
	setup["party"][0]["skills"] = "211760"
	_sandbox._setup.start_requested.emit(setup)
	var engine: BattleEngine = _sandbox.session.engine
	var lasswell: Combatant = engine.party_members()[0]
	var zu: Combatant = engine.enemies[0]
	engine.debug_edit(zu.id, &"max_hp", 10000000)
	engine.debug_edit(zu.id, &"hp", 10000000)
	var card = _sandbox._cards[lasswell.id]
	var warp_strike: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "211760")
	var point_blank: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "501620")
	assert_false(card._option_index.has(SandboxBattleFactory.command_key(point_blank)), "not granted yet")

	card._actions.item_selected.emit(int(card._option_index[SandboxBattleFactory.command_key(warp_strike)]))
	card.execute_pressed.emit(lasswell.id)
	_sandbox._execute_all_units()
	for _i in range(2000):
		if engine.turn == 2:
			break
		_sandbox.session.step(1)
	assert_eq(engine.turn, 2)
	_sandbox._refresh()
	assert_true(card._option_index.has(SandboxBattleFactory.command_key(point_blank)), "the card lists the grant")
	var index: int = int(card._option_index[SandboxBattleFactory.command_key(point_blank)])
	assert_true(card._actions.get_item_text(index).ends_with("[granted: 1 turn, unlimited uses]"), card._actions.get_item_text(index))
	card._actions.item_selected.emit(index)
	_sandbox._refresh()
	assert_true(card._note.text.contains("granted: 1 turn(s) left, unlimited uses"), card._note.text)
	var details: String = Sandbox.Inspector._details_text(engine, lasswell)
	assert_true(details.contains("Point-Blank Warp-Strike (ability:501620): 1 turn, unlimited uses"), details)
	assert_true(details.contains("History: stack none, previous action ability:211760"), details)


## Real jump and delayed damage abilities as extra skills: Dragoon Dive (227620, op 134)
## waits in the air until its card executes it; Charge Shot (202880, op 13) lands at the
## next turn's start. The inspector shows both while they wait.
func test_a_jump_and_delayed_damage_from_real_skills() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["party"][0]["skills"] = "227620"
	setup["party"][1]["skills"] = "202880"
	_sandbox._setup.start_requested.emit(setup)
	var engine: BattleEngine = _sandbox.session.engine
	var lasswell: Combatant = engine.party_members()[0]
	var other: Combatant = engine.party_members()[1]
	var zu: Combatant = engine.enemies[0]
	engine.debug_edit(zu.id, &"max_hp", 10000000)
	engine.debug_edit(zu.id, &"hp", 10000000)
	var dive: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "227620")
	var charge: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "202880")
	var card = _sandbox._cards[lasswell.id]
	var other_card = _sandbox._cards[other.id]
	card._actions.item_selected.emit(int(card._option_index[SandboxBattleFactory.command_key(dive)]))
	card.execute_pressed.emit(lasswell.id)
	other_card._actions.item_selected.emit(int(other_card._option_index[SandboxBattleFactory.command_key(charge)]))
	other_card.execute_pressed.emit(other.id)
	_sandbox.session.step(5)
	assert_true(lasswell.is_away())
	var details: String = Sandbox.Inspector._details_text(engine, lasswell)
	assert_true(details.contains("In the air: Dragoon Dive, can land from turn 2"), details)
	details = Sandbox.Inspector._details_text(engine, other)
	assert_true(details.contains("Delayed: Charge Shot (ability:202880), turn 2"), details)
	for _i in range(3000):
		if engine.turn == 2 and engine.phase == BattleEngine.Phase.PLAYER:
			break
		_sandbox.session.step(1)
	assert_eq([engine.turn, engine.phase], [2, BattleEngine.Phase.PLAYER])
	var delayed: Array = engine.events.of_type(BattleEventLog.ACTION_STARTED).filter(
		func(event: Dictionary) -> bool: return StringName(event["reaction"]) == Reaction.DELAYED)
	assert_eq(delayed.map(func(event: Dictionary) -> String: return event["skill_id"]), ["202880"], "Charge Shot fires")
	_sandbox._refresh()
	details = Sandbox.Inspector._details_text(engine, lasswell)
	assert_true(details.contains("In the air: Dragoon Dive, ready to land"), details)
	card.execute_pressed.emit(lasswell.id)
	_sandbox.session.step(120)
	var landed: Array = engine.events.of_type(BattleEventLog.HIT_LANDED).filter(
		func(event: Dictionary) -> bool: return int(event["actor"]) == lasswell.id and int(event["opcode"]) == 134)
	assert_false(landed.is_empty(), "the card's execute lands it")
	assert_false(lasswell.is_away())
	_sandbox._refresh()


## Passive ids in the extra skills field count like the unit's own: Counter (101200)
## and Preemptive Cover - Physical (106190), cast before the first player phase.
func test_extra_passives_give_counters_and_battle_start_casts() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["party"][0]["skills"] = "101200 106190"
	_sandbox._setup.start_requested.emit(setup)
	var engine: BattleEngine = _sandbox.session.engine
	var lasswell: Combatant = engine.party_members()[0]
	assert_eq(engine.phase, BattleEngine.Phase.OPENING, "Preemptive Cover runs first")
	_sandbox._refresh()
	assert_true(_sandbox._status.text.contains("opening phase"), _sandbox._status.text)
	for _i in range(600):
		if engine.phase == BattleEngine.Phase.PLAYER:
			break
		_sandbox.session.step(1)
	assert_eq(engine.phase, BattleEngine.Phase.PLAYER)
	assert_not_null(lasswell.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE))
	var details: String = Sandbox.Inspector._details_text(engine, lasswell)
	assert_true(details.contains("Counter physical attacks 30%: attack, 5 per turn"), details)
	assert_true(details.contains("Casts ability:514923 at battle start"), details)


func test_the_setup_form_keeps_a_mission() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["enemy_mode"] = SandboxBattleFactory.ENEMY_MODE_MISSION
	setup["mission"] = "1110100"
	_sandbox._setup.set_setup(setup)
	var read: Dictionary = _sandbox._setup.get_setup()
	assert_eq([read["enemy_mode"], read["mission"], read["battle_group"]], [SandboxBattleFactory.ENEMY_MODE_MISSION, "1110100", ""])
	assert_true(_sandbox._setup._enemy_preview.text.begins_with("Wave 1"), _sandbox._setup._enemy_preview.text)
