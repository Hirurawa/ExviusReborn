extends "res://tests/test_case.gd"

## The battle scene (BattleUI.tscn) on the new engine, driven headless the way a player
## would: the test battle opens, panel gestures, enemy taps, the menus and an ally pick
## reach the engine, the info popup, auto battle to a victory, a defeat's popup, and a
## real mission's dialogue and wave change. The director's finisher and kill recorder
## are stubs and its waits are instant, so nothing writes a save or waits on real time.
## The headless renderer draws nothing; what is checked is the state behind the widgets.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")
const BATTLE_SCENE: PackedScene = preload("res://features/battle/ui/BattleUI.tscn")
const POTION: String = "101000100"

var _screen: BattleScreen = null
var _finished: Array = []


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	_screen = BATTLE_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_screen)
	var director: BattleDirector = _screen.director
	director.print_monster_ai = false
	director.finisher = func(win: bool, mission_id: String, used_items: Dictionary, results: Array, drops: Array, unit_exp: int, gil: int) -> void:
		_finished.append([win, mission_id, used_items, results, drops, unit_exp, gil])
	director.kill_recorder = func(_template_id: String) -> void: pass
	director.wait = func(_seconds: float) -> Variant: return null


## Detached now, freed at the end of the frame: TouchScrollInstaller's deferred calls
## for the menus' ScrollContainers must still find them (KNOWN-BUGS.md #8).
func after_each() -> void:
	_screen.get_parent().remove_child(_screen)
	_screen.queue_free()


## Starts the battle as init_scene would, without its one-frame wait.
func _start(params: Dictionary = {}, seed_value: int = 7) -> BattleEngine:
	_screen._apply_battle_background(str(params.get("mission_id", "")))
	_screen.director.start(params, seed_value)
	return _screen.session.engine


func _panel(unit: Combatant) -> UnitPanel:
	return _screen.menus.panel(unit.id)


## The buttons of the open menu, in order.
func _menu_buttons() -> Array[Control]:
	var scroll: Node = _screen.menus.find_children("*", "ScrollContainer", true, false)[0]
	var grid: GridContainer = scroll.get_child(0)
	var buttons: Array[Control] = []
	for child in grid.get_children():
		if not child.is_queued_for_deletion():
			buttons.append(child)
	return buttons


## Plays until the battle ends or `until` holds: dialogue is clicked through, the wave
## counter roll answered, and the party attacks whenever it can (auto battle).
func _play(until: Callable = Callable(), max_frames: int = 20000) -> void:
	_screen.auto_button.set_pressed_no_signal(true)
	for _i in range(max_frames):
		var engine: BattleEngine = _screen.session.engine
		if not _finished.is_empty() or (until.is_valid() and until.call()):
			return
		if _screen.dialogue.visible:
			_screen.dialogue._advance()
			continue
		if engine.phase == BattleEngine.Phase.WAVE_CLEARED:
			_screen.director.transition_finished()
		elif engine.phase == BattleEngine.Phase.PLAYER:
			_screen._run_auto()
		_screen.session.step(1)


# === Opening ===

func test_the_test_battle_opens_with_its_party_and_enemy() -> void:
	var engine: BattleEngine = _start()
	assert_eq(engine.phase, BattleEngine.Phase.PLAYER)
	assert_false(engine.events.keep_history, "a real battle keeps no log")
	assert_false(_screen.session.auto_advance_waves, "the director starts each wave")
	var party: Array[Combatant] = engine.party_members()
	assert_eq(party.size(), 2)
	for member in party:
		assert_not_null(_panel(member), member.name)
	assert_eq(_screen.menus.get_node("BottomSection").get_child_count(), 6, "two panels and four slot frames")
	assert_true(_screen.party_field.get_child(0).get_child_count() > 0, "slot 0's sprite on UnitDot0")
	assert_true(_screen.party_field.get_child(2).get_child_count() > 0, "slot 1's sprite on UnitDot2")
	assert_eq(_screen.party_field.get_child(1).get_child_count(), 0, "slot 3 is empty")

	var zu: Combatant = engine.enemies[0]
	assert_true(_screen.enemy_field.has_view(zu.id))
	assert_eq(_screen._target_enemy_id, zu.id, "the first enemy is the target")
	assert_eq(_screen.get_node("%EnemyNameLabel").text, zu.name)
	assert_eq(_screen.get_node("%TurnLabel").text, "Turn 1")
	var gauge: Range = _screen.get_node("VisualLayer/SummonGaugeBg/BattleSummonBar")
	assert_eq([gauge.value, gauge.max_value], [0.0, float(engine.rules.esper_gauge_max)])
	assert_not_null(_screen.background.texture, "the colosseum background")


# === Commands ===

func test_panel_gestures_queue_and_execute_commands() -> void:
	var engine: BattleEngine = _start()
	var lasswell: Combatant = engine.party_members()[0]
	var rain: Combatant = engine.party_members()[1]
	var zu: Combatant = engine.enemies[0]

	_panel(lasswell).command_chosen.emit(lasswell.slot, UnitPanel.DEFEND)
	assert_eq(lasswell.queued_command.kind, BattleCommand.Kind.DEFEND)
	assert_eq(_panel(lasswell)._shown_icon, UnitPanel.ICON_DEFEND, "the panel shows the queued command")
	_panel(lasswell).panel_tapped.emit(lasswell.slot)
	assert_true(lasswell.acted and lasswell.defending)
	assert_eq(_panel(lasswell).modulate, UnitPanel.ACTED_COLOR, "greyed once it acted")

	_screen.enemy_field.enemy_tapped.emit(zu.id)
	_panel(rain).panel_tapped.emit(rain.slot)
	assert_true(rain.acted)
	assert_eq(rain.last_command.target_id, zu.id, "a tap attacks the chosen enemy")
	assert_true(_screen.get_node("%ActionFeedbackLabel").text.ends_with("- Attack"), _screen.get_node("%ActionFeedbackLabel").text)


## Counters run as the next turn opens; the screen names them and does not grey the
## unit, which can still act that turn.
func test_a_counter_shows_and_leaves_the_unit_free_to_act() -> void:
	var engine: BattleEngine = _start()
	var zu: Combatant = engine.enemies[0]
	zu.max_hp = 10000000
	zu.hp = zu.max_hp
	var party: Array[Combatant] = engine.party_members()
	for member in party:
		for trigger in ["physical", "magic"]:
			member.passives.counters.append({"trigger": trigger, "chance": 100, "modifier": 0, "max": 0,
				"skill_kind": BattleSkill.KIND_ATTACK, "skill_id": "", "source_skill_id": "101200"})
	var feedback: Label = _screen.get_node("%ActionFeedbackLabel")
	var countering: Combatant = null
	for _i in range(5000):
		if engine.phase == BattleEngine.Phase.ENDED:
			break
		if engine.phase == BattleEngine.Phase.PLAYER:
			for member in engine.units_to_act():
				_screen.session.execute(member.id, BattleCommand.defend())
		_screen.session.step(1)
		if feedback.text.contains("Counter: Attack"):
			for member in party:
				if feedback.text.begins_with(member.name):
					countering = member
			break
	assert_not_null(countering, "a counter played: %s" % feedback.text)
	if countering == null:
		return
	assert_eq(engine.phase, BattleEngine.Phase.OPENING)
	assert_ne(_panel(countering).modulate, UnitPanel.ACTED_COLOR, "the counter does not use up the turn")
	for _i in range(600):
		if engine.phase != BattleEngine.Phase.OPENING:
			break
		_screen.session.step(1)
	assert_eq(engine.phase, BattleEngine.Phase.PLAYER)
	assert_false(countering.acted)


## Dragoon Dive (227620, op 134): the sprite leaves the field and the panel greys out;
## from the next turn the panel is free again and a tap lands the unit.
func test_a_jumper_leaves_the_field_and_a_tap_lands_it() -> void:
	var engine: BattleEngine = _start()
	var zu: Combatant = engine.enemies[0]
	zu.max_hp = 10000000
	zu.hp = zu.max_hp
	var hero: Combatant = engine.party_members()[0]
	hero.mp = hero.max_mp
	assert_eq(_screen.session.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "227620", zu.id)), BattleEngine.OK)
	_screen.session.step(5)
	assert_true(hero.is_away())
	assert_true(_screen.party_field.is_away(hero.id), "the sprite leaves")
	assert_eq(_panel(hero).modulate, UnitPanel.ACTED_COLOR)
	for _i in range(5000):
		if engine.turn == 2 and engine.phase == BattleEngine.Phase.PLAYER:
			break
		if engine.phase == BattleEngine.Phase.PLAYER:
			for member in engine.units_to_act():
				_screen.session.execute(member.id, BattleCommand.defend())
		_screen.session.step(1)
	assert_eq([engine.turn, engine.phase], [2, BattleEngine.Phase.PLAYER])
	assert_ne(_panel(hero).modulate, UnitPanel.ACTED_COLOR, "ready to land: the panel is free")
	assert_true(_screen.party_field.is_away(hero.id))
	_screen.menus.unit_tapped.emit(hero.id)
	_screen.session.step(2)
	assert_false(hero.is_away(), "the tap lands it")
	assert_false(_screen.party_field.is_away(hero.id), "the sprite comes back")
	var feedback: Label = _screen.get_node("%ActionFeedbackLabel")
	assert_true(feedback.text.contains("Landing: Dragoon Dive"), feedback.text)
	assert_eq(_panel(hero).modulate, UnitPanel.ACTED_COLOR, "the landing is its action")


func test_an_item_picked_for_an_ally_keeps_its_target() -> void:
	var engine: BattleEngine = _start()
	engine.item_stock = {POTION: 2}
	var lasswell: Combatant = engine.party_members()[0]
	var rain: Combatant = engine.party_members()[1]

	_panel(lasswell).open_item_menu.emit(lasswell.slot)
	assert_eq(_screen.menus.open_menu, BattleMenus.MENU_ITEM)
	var buttons: Array[Control] = _menu_buttons()
	assert_eq(buttons.size(), 1, "the Potion")
	(buttons[0] as Button).pressed.emit()
	assert_true(_screen.menus.is_picking_ally(), "a Potion asks for an ally")
	assert_eq(_panel(rain).modulate, UnitPanel.VALID_TARGET_COLOR)

	_panel(rain).panel_tapped.emit(rain.slot)
	assert_false(_screen.menus.is_picking_ally())
	assert_eq([lasswell.queued_command.kind, lasswell.queued_command.target_id], [BattleCommand.Kind.ITEM, rain.id])
	assert_eq(_panel(lasswell)._shown_icon, "item")
	assert_eq(engine.items_available(POTION, rain.id), 1, "the queued Potion is held for Lasswell")

	_panel(lasswell).panel_tapped.emit(lasswell.slot)
	assert_eq(lasswell.last_command.target_id, rain.id, "executing does not send the heal to the enemy (KNOWN-BUGS #10)")
	assert_eq(engine.item_stock[POTION], 1)


func test_tapping_an_enemy_cancels_an_ally_pick() -> void:
	var engine: BattleEngine = _start()
	engine.item_stock = {POTION: 1}
	var lasswell: Combatant = engine.party_members()[0]
	_panel(lasswell).open_item_menu.emit(lasswell.slot)
	(_menu_buttons()[0] as Button).pressed.emit()
	assert_true(_screen.menus.is_picking_ally())
	_screen.enemy_field.enemy_tapped.emit(engine.enemies[0].id)
	assert_false(_screen.menus.is_picking_ally())
	assert_null(lasswell.queued_command, "nothing was queued")


func test_the_skill_menu_lists_the_units_options() -> void:
	var engine: BattleEngine = _start()
	var lasswell: Combatant = engine.party_members()[0]
	_panel(lasswell).open_skill_menu.emit(lasswell.slot)
	assert_eq(_screen.menus.open_menu, BattleMenus.MENU_SKILL)
	var options: Array[Dictionary] = BattleCommandMenu.options(engine, lasswell)
	assert_true(options.size() > 0)
	var buttons: Array[Control] = _menu_buttons()
	assert_eq(buttons.size(), options.size(), "one Skill button per option")
	assert_eq(options[0]["command"].kind, BattleCommand.Kind.LIMIT_BURST)
	var limit_burst: Control = buttons[0]
	assert_true(limit_burst.get_node("Button").disabled, "the gauge is empty")
	assert_true(limit_burst.get_node("unit_magic_unavailable_reason_1").visible, "with the lack-limit overlay")


func test_a_grant_joins_the_open_skill_menu() -> void:
	var engine: BattleEngine = _start()
	var lasswell: Combatant = engine.party_members()[0]
	var rain: Combatant = engine.party_members()[1]
	# Regis's Bonds of Battle: Light Glaive (510360) for all allies, five turns.
	(rain.profile["skills"]["ability"] as Array).append({"id": 232078, "source": "Trait"})
	_panel(lasswell).open_skill_menu.emit(lasswell.slot)
	var before: int = _menu_buttons().size()
	assert_eq(_screen.session.execute(rain.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "232078")), BattleEngine.OK)
	for _i in range(600):
		if not lasswell.grants.is_empty():
			break
		_screen.session.step(1)
	assert_false(lasswell.grants.is_empty(), "the grant landed")
	assert_eq(_menu_buttons().size(), before + 1, "Light Glaive joined Lasswell's open menu")
	var options: Array[Dictionary] = BattleCommandMenu.options(engine, lasswell)
	assert_eq((options.back()["command"] as BattleCommand).skill_id, "510360")


## Gives `unit` Dualcast (200150), Fire (20010) and Cure (10020, an ally pick) and opens
## its skill menu. Returns the menu's option index of each, by id.
func _open_dualcast_menu(engine: BattleEngine, unit: Combatant) -> Dictionary:
	var skills: Dictionary = unit.profile["skills"]
	skills["ability"].append({"id": 200150, "source": "Trait"})
	skills["magic"].append({"id": 20010, "source": "Trait"})
	skills["magic"].append({"id": 10020, "source": "Trait"})
	_panel(unit).open_skill_menu.emit(unit.slot)
	var index: Dictionary = {}
	var options: Array[Dictionary] = BattleCommandMenu.options(engine, unit)
	for i in range(options.size()):
		index[(options[i]["command"] as BattleCommand).skill_id] = i
	return index


func _press(index: int) -> void:
	_menu_buttons()[index].pressed.emit()


func _enabled(index: int) -> bool:
	return not (_menu_buttons()[index].get_node("Button") as Button).disabled


func test_a_multicast_keeps_the_menu_open_until_its_last_pick() -> void:
	var engine: BattleEngine = _start()
	var lasswell: Combatant = engine.party_members()[0]
	var rain: Combatant = engine.party_members()[1]
	var zu: Combatant = engine.enemies[0]
	var at: Dictionary = _open_dualcast_menu(engine, lasswell)
	assert_true(_enabled(at["200150"]), "Dualcast can start")
	var mp: int = lasswell.mp

	_press(at["200150"])
	assert_eq(_screen.menus.open_menu, BattleMenus.MENU_SKILL, "the menu stays open")
	assert_true(_screen.get_node("%ActionFeedbackLabel").text.begins_with("Dualcast"), _screen.get_node("%ActionFeedbackLabel").text)
	assert_true(_enabled(at["20010"]) and _enabled(at["10020"]), "magic can be picked")
	assert_false(_enabled(at["200150"]), "the command itself cannot")
	assert_false(_enabled(0), "nor the limit burst")
	for option in BattleCommandMenu.options(engine, lasswell):
		if (option["command"] as BattleCommand).skill_kind == BattleSkill.KIND_ABILITY:
			assert_false(_enabled(at[(option["command"] as BattleCommand).skill_id]), "no ability: %s" % option["name"])

	_press(at["10020"])
	assert_true(_screen.menus.is_picking_ally(), "Cure asks for an ally")
	_panel(rain).panel_tapped.emit(rain.slot)
	assert_eq(_screen.menus.open_menu, BattleMenus.MENU_SKILL, "the menu comes back for the second pick")
	assert_true(_enabled(at["20010"]) and not _enabled(at["200150"]), "drawn for the draft")
	assert_null(lasswell.queued_command, "nothing is queued yet")

	_press(at["20010"])
	assert_true(_screen._draft.is_empty(), "the last pick ends the draft")
	var queued: BattleCommand = lasswell.queued_command
	assert_eq(queued.skill_id, "200150")
	assert_eq([queued.picks[0].skill_id, queued.picks[0].target_id, queued.picks[1].skill_id, queued.picks[1].target_id],
		["10020", rain.id, "20010", -1])
	assert_eq(lasswell.mp, mp, "selecting pays nothing")

	_panel(lasswell).panel_tapped.emit(lasswell.slot)
	assert_true(lasswell.acted)
	assert_eq(lasswell.last_command.target_id, zu.id, "Fire's target: the chosen enemy")
	assert_eq(lasswell.last_command.picks[0].target_id, rain.id, "Cure keeps Rain")
	assert_eq(lasswell.mp, mp - 3, "only Cure is cast so far")
	_screen.session.step(40)
	assert_eq(lasswell.mp, mp - 6, "then Fire")


func test_back_drops_a_multicast_draft() -> void:
	var engine: BattleEngine = _start()
	var lasswell: Combatant = engine.party_members()[0]
	var at: Dictionary = _open_dualcast_menu(engine, lasswell)
	_press(at["200150"])
	_press(at["20010"])
	for button in _screen.menus.find_children("*", "Button", true, false):
		if (button as Button).text == "Back":
			(button as Button).pressed.emit()
	assert_true(_screen._draft.is_empty())
	assert_null(lasswell.queued_command)
	_panel(lasswell).open_skill_menu.emit(lasswell.slot)
	assert_true(_enabled(at["200150"]) and not _enabled(0), "a fresh menu, not the draft")
	_press(at["20010"])
	assert_eq(lasswell.queued_command.skill_id, "20010", "Fire alone")


# === Info ===

func test_a_long_press_shows_the_combatants_info() -> void:
	var engine: BattleEngine = _start()
	var zu: Combatant = engine.enemies[0]
	_screen.enemy_field.enemy_long_pressed.emit(zu.id)
	var popup: UnitInfoPopup = _screen.unit_info_popup
	assert_true(popup.visible)
	assert_eq(popup.shown_id, zu.id)
	assert_true(popup.info_text.text.contains(zu.name), "the enemy's name")
	assert_true(popup.info_text.text.contains("None"), "no status yet")

	assert_eq(engine.debug_edit(zu.id, &"ailment", 3, "POISON"), BattleEngine.OK)
	_screen.session.flush_events()
	assert_true(popup.info_text.text.contains("POISON"), "an open popup follows the statuses: " + popup.info_text.text)


# === The end ===

func test_auto_battle_wins_the_test_battle() -> void:
	var engine: BattleEngine = _start()
	_play()
	assert_eq(engine.outcome, BattleEngine.OUTCOME_VICTORY)
	assert_eq(_finished.size(), 1)
	assert_eq(_finished[0].slice(0, 2), [true, ""], "the test battle finishes with no mission id, as before")
	assert_eq(_screen._target_enemy_id, -1)
	assert_eq(_screen.get_node("%EnemyNameLabel").text, "Cleared")


func test_a_defeat_shows_the_failure_popup_once() -> void:
	var popups: Array[int] = [0]
	_screen.rewards_popup.about_to_popup.connect(func() -> void: popups[0] += 1)
	# The real finisher on a defeat only emits MissionService.mission_failed.
	_screen.director.finisher = MissionService.request_finish_mission
	# A frail hero against a monster that attacks (the test battle's Zu only casts
	# Needle Breath, KNOWN-BUGS #1).
	_screen.director.factory = func(seed_value: int) -> BattleEngine:
		var hero: Combatant = Fixtures.unit("Hero", {"hp": 10})
		var brute: Combatant = Fixtures.monster("Brute", {"atk": 1000})
		return Fixtures.engine([hero], [brute], null, null, seed_value)
	var engine: BattleEngine = _start()
	_screen.auto_button.set_pressed_no_signal(true)
	for _i in range(5000):
		if engine.phase == BattleEngine.Phase.ENDED:
			break
		if engine.phase == BattleEngine.Phase.PLAYER:
			_screen._run_auto()
		_screen.session.step(1)
	assert_eq(engine.outcome, BattleEngine.OUTCOME_DEFEAT)
	MissionService.mission_failed.emit("again")
	assert_eq(popups[0], 1, "one popup, however many failure signals")
	assert_eq(_screen.rewards_popup.dialog_text, "Mission Failed!")


func test_a_mission_plays_its_dialogue_and_changes_wave() -> void:
	var mission_id: String = "1110100"
	var story: BattleStory = BattleStory.for_params({"mission_id": mission_id})
	story.switch_check = func(_switch: Variant) -> bool: return false
	_screen.director.story = story
	_screen.director.factory = func(seed_value: int) -> BattleEngine:
		var builder := BattleBuilder.new(null, null, seed_value)
		var waves: Array[Callable] = builder.mission_waves(mission_id)
		var formation: Array[Combatant] = []
		formation.assign(waves[0].call())
		var engine: BattleEngine = builder.assemble(builder.party_from_units(builder.test_party_units(), BattleBuilder.TEST_STATS), formation)
		for i in range(1, waves.size()):
			engine.queue_wave(waves[i])
		return engine
	var engine: BattleEngine = _start({"mission_id": mission_id}, 11)
	assert_true(_screen.dialogue.visible, "wave 1 opens with dialogue")
	assert_true(_screen.session.paused, "the battle waits while it shows")
	var first_wave: Array[int] = []
	for foe in engine.enemies:
		first_wave.append(foe.id)

	_play(func() -> bool: return engine.wave == 2 and engine.phase == BattleEngine.Phase.PLAYER and not _screen.dialogue.visible)
	assert_eq(engine.wave, 2)
	assert_true(_screen.get_node("%TransitionUI").visible, "the wave counter rolled")
	for foe_id in first_wave:
		assert_false(_screen.enemy_field.has_view(foe_id), "wave 1's views are gone")
	for foe in engine.enemies:
		assert_true(_screen.enemy_field.has_view(foe.id), "wave 2's %s has a view" % foe.name)
	assert_eq(_screen._target_enemy_id, engine.enemies[0].id)
	assert_eq(_screen.get_node("%TurnLabel").text, "Turn 1", "the turn restarts each wave")

	_play()
	assert_eq(_finished.size(), 1)
	assert_eq(_finished[0].slice(0, 2), [true, mission_id])
