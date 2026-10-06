extends "res://tests/test_case.gd"

## BattleDirector with a stub screen that answers every request at once and instant
## waits: the intro, a cleared wave, victory, defeat, a battle with no enemies and the
## debug Finish button on fixture battles, then real missions (their wave plans,
## dialogue, cutscenes and challenges) run through it as the old engine's flow would.
## The finisher and the kill recorder are stubs, so nothing writes a save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const POTION: String = "101000100"

var _session: BattleSession = null
var _director: BattleDirector = null
## What the director asked for, in order: "say <first line>", "transition 1>2/2",
## "wait 1.0", "finish".
var _log: Array[String] = []
var _paused_while_talking: Array[bool] = []
var _finished: Array = []
var _kills: Array[String] = []
var _drops: Array = []
var _completed: Array = []
var _on_completed: Callable = Callable()


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	_session = BattleSession.new()
	_director = BattleDirector.new()
	_director.session = _session
	_director.print_monster_ai = false
	_director.finisher = _finish
	_director.kill_recorder = func(template_id: String) -> void: _kills.append(template_id)
	_director.wait = _wait
	_director.dialogue_requested.connect(_on_dialogue)
	_director.wave_transition_requested.connect(_on_transition)
	_director.item_dropped.connect(func(enemy_id: int, item_id: String) -> void: _drops.append([enemy_id, item_id]))
	_on_completed = func(party: Variant, turns: Variant) -> void: _completed.append([party, turns])
	BattleEvents.mission_completed.connect(_on_completed)


func after_each() -> void:
	if _director.challenges != null:
		_director.challenges.cleanup()
	if BattleEvents.mission_completed.is_connected(_on_completed):
		BattleEvents.mission_completed.disconnect(_on_completed)
	# The lambda captures this test: holding it would keep the test alive.
	_on_completed = Callable()
	_director.free()
	_session.free()


# === The stub screen and services ===

func _on_dialogue(lines: Array) -> void:
	_paused_while_talking.append(_session.paused)
	for line in lines:
		_log.append("say " + str(line.get("text", "")).split("\n")[0])
	_director.dialogue_finished()


func _on_transition(wave: int, next_wave: int, waves: int) -> void:
	_log.append("transition %d>%d/%d" % [wave, next_wave, waves])
	_director.transition_finished()


func _wait(seconds: float) -> Variant:
	_log.append("wait %.1f" % seconds)
	return null


func _finish(win: bool, mission_id: String, used_items: Dictionary, challenge_results: Array, drops: Array, unit_exp: int, gil: int) -> void:
	_log.append("finish")
	_finished.append([win, mission_id, used_items, challenge_results, drops, unit_exp, gil])


# === Fixtures ===

## Two waves of scripted lines ("s1 start", "s1 won", ...). The second wave's first-time
## switch is set, so its lines are skipped. One cutscene before the battle, one after
## each wave.
static func _story() -> BattleStory:
	var plan: Array = [{"battle_script_id": "s1"}, {"battle_script_id": "s2", "switch_non_info": "seen"}]
	var cutscenes: Array = [
		{"story_event_id": "e0", "after_wave": 0},
		{"story_event_id": "e1", "after_wave": 1},
		{"story_event_id": "e2", "after_wave": 2},
		{"story_event_id": "replay", "after_wave": 2, "switch_info": "not_yet"},
	]
	return BattleStory.new(plan, cutscenes,
		func(switch: Variant) -> bool: return str(switch) == "seen",
		func(script_id: String) -> Array: return [
			{"cond": BattleStory.COND_START, "lines": [{"speaker": "A", "text": "%s start" % script_id}]},
			{"cond": BattleStory.COND_VICTORY, "lines": [{"speaker": "A", "text": "%s won" % script_id}]},
		],
		func(story_event_id: String) -> Dictionary: return {"name": "scene %s" % story_event_id})


static func _foe(template_id: String, exp_value: int, gil_value: int, loot: Array) -> Combatant:
	var foe: Combatant = Fixtures.monster("Foe %s" % template_id, {"template_id": template_id, "hp": 50, "brain": IdleEnemyBrain.new()})
	foe.meta = {"exp": exp_value, "gil": gil_value, "loot": {"drops": loot}}
	return foe


static func _catalog() -> SkillCatalog:
	var catalog: SkillCatalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_ITEM, POTION, Fixtures.record("Potion",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 16, [200]]]))
	return catalog


## A strong hero against one foe, then a second wave of one foe; one Potion.
func _two_waves(seed_value: int) -> BattleEngine:
	var hero: Combatant = Fixtures.unit("Hero", {"atk": 1000})
	hero.source = {"instance_id": "hero"}
	var battle: BattleEngine = Fixtures.engine([hero], [_foe("100", 10, 5, ["1001", "1002"])], null, _catalog(), seed_value)
	battle.queue_wave(_second_wave)
	battle.item_stock = {POTION: 1}
	return battle


func _second_wave() -> Array[Combatant]:
	var foes: Array[Combatant] = [_foe("200", 20, 7, ["2001"])]
	return foes


## A frail hero against a foe that attacks.
func _hopeless(seed_value: int) -> BattleEngine:
	var hero: Combatant = Fixtures.unit("Hero", {"hp": 10})
	var brute: Combatant = Fixtures.monster("Brute", {"atk": 1000})
	var battle: BattleEngine = Fixtures.engine([hero], [brute], null, _catalog(), seed_value)
	battle.item_stock = {POTION: 1}
	return battle


func _no_enemies(seed_value: int) -> BattleEngine:
	return Fixtures.engine([Fixtures.unit("Hero")], [], null, _catalog(), seed_value)


func _start(battle_factory: Callable, story: BattleStory = null, challenges: Array = []) -> void:
	_director.factory = battle_factory
	_director.story = story if story != null else _story()
	_director.challenges = ChallengeSet.new(challenges)
	_director.start({"mission_id": "m1"}, 7)


## Party members act as soon as they can (the first one uses a Potion on itself when
## `potion` is set) until the battle ends or `until` holds.
func _fight(potion: bool = false, until: Callable = Callable(), max_frames: int = 20000) -> void:
	for _i in range(max_frames):
		var engine: BattleEngine = _session.engine
		if engine.phase == BattleEngine.Phase.ENDED or (until.is_valid() and until.call()):
			return
		if engine.phase == BattleEngine.Phase.PLAYER:
			var acting: Array[Combatant] = engine.units_to_act()
			if potion and not acting.is_empty():
				_session.execute(acting[0].id, BattleCommand.item(POTION, acting[0].id))
				potion = false
				acting = engine.units_to_act()
			var ids: Array = []
			for unit in acting:
				ids.append(unit.id)
			if not ids.is_empty():
				_session.execute_many(ids)
		_session.step(1)


static func _says(log_lines: Array[String]) -> Array:
	return log_lines.filter(func(line: String) -> bool: return line.begins_with("say "))


# === Fixture battles ===

func test_the_intro_plays_the_opening_cutscenes_then_the_first_waves_lines() -> void:
	_start(_two_waves)
	assert_eq(_log, ["say scene e0", "say s1 start"] as Array[String])
	assert_eq(_paused_while_talking, [true, true] as Array[bool], "the battle waits while dialogue shows")
	assert_false(_session.paused, "and runs once the intro is over")
	assert_false(_session.auto_advance_waves, "the director starts each wave")
	assert_eq(_session.engine.phase, BattleEngine.Phase.PLAYER)


func test_a_cleared_wave_plays_its_victory_the_transition_then_the_next_wave() -> void:
	_start(_two_waves)
	_log.clear()
	_fight(false, func() -> bool: return _session.engine.wave == 2)
	assert_eq(_log, ["wait 1.0", "say s1 won", "say scene e1", "transition 1>2/2", "wait 2.0"] as Array[String],
		"wave 2's opening lines were seen already (its switch is set)")
	assert_eq([_session.engine.wave, _session.engine.phase], [2, BattleEngine.Phase.PLAYER])
	assert_false(_session.paused)
	assert_eq(_finished.size(), 0)


func test_victory_reports_the_rewards_the_challenges_and_the_turns() -> void:
	_start(_two_waves, null, [{"parameter": "68"}, {"parameter": "33"}, {"parameter": "16"}, {"parameter": "0"}])
	_fight(true)
	var engine: BattleEngine = _session.engine
	assert_eq(engine.outcome, BattleEngine.OUTCOME_VICTORY)
	assert_eq(_log.slice(_log.size() - 3), ["wait 1.0", "say scene e2", "finish"] as Array[String],
		"the last wave's lines were seen; the outro cutscene; the replay-only one is not active")
	assert_eq(_finished.size(), 1)
	var drops: Array = _drops.map(func(drop: Array) -> String: return drop[1])
	assert_eq(_finished[0], [true, "m1", {POTION: 1}, [true, true, false, true], drops, 30, 12])
	assert_eq(_kills, ["100", "200"] as Array[String])
	assert_eq(_completed, [[[{"instance_id": "hero"}], engine.total_turns]])
	assert_true(engine.total_turns >= 2, "turns across both waves")


func test_defeat_reports_the_items_used_and_disconnects_the_challenges() -> void:
	var connections: int = BattleEvents.ally_defeated.get_connections().size()
	_start(_hopeless, null, [{"parameter": "33"}])
	assert_eq(BattleEvents.ally_defeated.get_connections().size(), connections + 1)
	_log.clear()
	_fight(true)
	assert_eq(_session.engine.outcome, BattleEngine.OUTCOME_DEFEAT)
	assert_eq(_finished, [[false, "m1", {POTION: 1}, [], [], 0, 0]])
	assert_eq(_log, ["finish"] as Array[String], "no wait, no dialogue")
	assert_eq(_completed.size(), 0, "no mission_completed on a defeat")
	assert_eq(BattleEvents.ally_defeated.get_connections().size(), connections, "the trackers are gone")


func test_a_battle_with_no_enemies_is_won_without_opening_a_wave() -> void:
	var story := BattleStory.new([], [{"story_event_id": "e0", "after_wave": 0}, {"story_event_id": "e1", "after_wave": 1}],
		func(_switch: Variant) -> bool: return false,
		func(_script_id: String) -> Array: return [],
		func(story_event_id: String) -> Dictionary: return {"name": "scene %s" % story_event_id})
	_start(_no_enemies, story)
	assert_eq(_log, ["say scene e0", "wait 1.0", "say scene e1", "finish"] as Array[String])
	assert_eq(_finished.size(), 1)
	assert_eq(_finished[0][0], true)


func test_debug_finish_takes_the_victory_path_once() -> void:
	_start(_two_waves, null, [{"parameter": "68"}])
	_log.clear()
	_director.debug_finish()
	assert_eq(_log, ["finish"] as Array[String], "at once, as the old Finish button")
	assert_eq(_finished, [[true, "m1", {}, [true], [], 0, 0]])
	assert_eq(_completed.size(), 1)
	assert_true(_session.paused, "the fight stops")
	_director.debug_finish()
	_fight(false, Callable(), 600)
	assert_true(_session.engine.wave == 2 or _session.engine.phase != BattleEngine.Phase.PLAYER, "the fight went on")
	assert_eq(_finished.size(), 1, "reported once")


# === Real missions ===

## The test battle's party (two starters with giant stats, as BattleBuilder's test
## battle) against every wave of `mission_id`, with two Potions.
static func _real_factory(mission_id: String) -> Callable:
	return func(seed_value: int) -> BattleEngine:
		var builder := BattleBuilder.new(null, null, seed_value)
		var waves: Array[Callable] = builder.mission_waves(mission_id)
		var party: Array[Combatant] = builder.party_from_units(builder.test_party_units(), BattleBuilder.TEST_STATS)
		var formation: Array[Combatant] = []
		formation.assign(waves[0].call())
		var engine: BattleEngine = builder.assemble(party, formation)
		for i in range(1, waves.size()):
			engine.queue_wave(waves[i])
		engine.item_stock = {POTION: 2}
		return engine


## Runs `mission_id` through the director with the mission's own story (every
## first-time switch unset) and challenges, and checks what the old engine's flow would
## have produced: the dialogue of each wave in order, the cutscene cards, one
## transition per wave change, and the finisher's arguments.
func _run_real_mission(mission_id: String, expected_results: Array) -> void:
	var story: BattleStory = BattleStory.for_params({"mission_id": mission_id})
	story.switch_check = func(_switch: Variant) -> bool: return false
	_director.factory = _real_factory(mission_id)
	_director.story = story
	_director.start({"mission_id": mission_id}, 11)
	_fight(true)
	var engine: BattleEngine = _session.engine
	assert_eq(engine.outcome, BattleEngine.OUTCOME_VICTORY, mission_id)

	var plan: Array = EncounterResolver.build_wave_plan(mission_id)
	var cutscenes: Array = GameDatabase.get_mission_cutscenes(mission_id)
	var expected_says: Array = _cards(cutscenes, 0)
	var expected_transitions: Array[String] = []
	for wave in range(1, plan.size() + 1):
		expected_says.append_array(_lines(plan[wave - 1], BattleStory.COND_START))
		expected_says.append_array(_lines(plan[wave - 1], BattleStory.COND_VICTORY))
		expected_says.append_array(_cards(cutscenes, wave))
		if wave < plan.size():
			expected_transitions.append("transition %d>%d/%d" % [wave, wave + 1, plan.size()])
	assert_true(not expected_says.is_empty(), "%s has dialogue to check" % mission_id)
	assert_eq(_says(_log), expected_says, "%s dialogue" % mission_id)
	assert_eq(_log.filter(func(line: String) -> bool: return line.begins_with("transition")), expected_transitions)

	var exp_total: int = 0
	var gil_total: int = 0
	var killed: Array[String] = []
	var loot: Array = []
	for event in engine.events.of_type(BattleEventLog.COMBATANT_DEFEATED):
		var foe: Combatant = engine.combatant(int(event["target"]))
		if foe.is_enemy() and not killed.has(str(foe.id)):
			killed.append(str(foe.id))
			exp_total += int(foe.meta.get("exp", 0))
			gil_total += int(foe.meta.get("gil", 0))
			loot.append_array(foe.meta.get("loot", {}).get("drops", []).map(func(id: Variant) -> String: return str(id)))
	assert_true(exp_total > 0, "%s pays EXP" % mission_id)
	assert_eq(_kills.size(), killed.size(), "one kill recorded per enemy")
	assert_eq(_finished.size(), 1)
	var call: Array = _finished[0]
	assert_eq(call.slice(0, 4), [true, mission_id, {POTION: 1}, expected_results])
	assert_eq([call[5], call[6]], [exp_total, gil_total], "%s EXP and gil" % mission_id)
	assert_eq(call[4], _drops.map(func(drop: Array) -> String: return drop[1]))
	for item_id in call[4]:
		assert_has(loot, item_id)
	assert_eq(_completed.size(), 1)
	assert_eq(_completed[0][1], engine.total_turns)


static func _lines(wave: Dictionary, cond: int) -> Array:
	var script_id: String = str(wave.get("battle_script_id", ""))
	var out: Array = []
	if script_id == "" or script_id == "0":
		return out
	for segment in MissionTimeline.parse_battle_script(script_id):
		if int(segment.get("cond", 0)) == cond:
			for line in segment.get("lines", []):
				out.append("say " + str(line.get("text", "")).split("\n")[0])
	return out


static func _cards(cutscenes: Array, slot: int) -> Array:
	var out: Array = []
	for cut in cutscenes:
		if int(cut.get("after_wave", -1)) == slot and not BattleStory.switch_present(cut.get("switch_info")):
			out.append("say " + str(GameDatabase.get_story_event(str(cut.get("story_event_id", ""))).get("name", "?")))
	return out


func test_the_intro_mission_plays_its_dialogue_and_outro() -> void:
	# Two waves with dialogue, then a cutscene; no challenges.
	_run_real_mission("1110100", [])


func test_a_mission_with_challenges_reports_their_results() -> void:
	# Three waves (the second without dialogue); 68, 34:1 (two units), 33 (nobody KO'd
	# with the test stats) and 38 all pass.
	_run_real_mission("1110103", [true, true, true, true])
