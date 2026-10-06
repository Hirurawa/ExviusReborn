extends "res://tests/test_case.gd"

## BattleEventsBridge and ChallengeSet: engine events reach the BattleEvents autoload in
## the old payload shapes, checked against real ChallengeFactory trackers (their known
## bugs, KNOWN-BUGS #2 and #9, included), and the trackers disconnect when the set is
## cleaned up. Fixture skills; writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const FIRE: String = "1001"
const STRIKE: String = "2001"
const LIMIT: String = "3001"
const ESPER_SKILL: String = "10101"
const SIREN: int = 1
const POTION: String = "101000100"
const DUALCAST: String = "200150"
const THUNDER: String = "1002"

var _sets: Array[ChallengeSet] = []
## [Signal, Callable] pairs this test connected to BattleEvents.
var _connections: Array = []


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


func after_each() -> void:
	for challenge_set in _sets:
		challenge_set.cleanup()
	for pair in _connections:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


static func _catalog() -> SkillCatalog:
	var catalog: SkillCatalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_MAGIC, FIRE, Fixtures.record("Fire",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]], "10:100",
		{"element_inflict": [1], "attack_type": BattleSkill.ATTACK_MAGIC}))
	catalog.add_record(BattleSkill.KIND_ABILITY, STRIKE, Fixtures.record("Strike",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 1, Fixtures.physical_params(150)]]))
	catalog.add_record(BattleSkill.KIND_LIMIT_BURST, LIMIT, {
		"name": "Blade Flash",
		"levels": [[8, [[1, 1, 1, Fixtures.physical_params(180)]]]],
		"attack_frames": [[60]],
		"attack_damage": [[100]],
	})
	catalog.add_record(BattleSkill.KIND_ESPER, ESPER_SKILL, Fixtures.record("Lunatic Voice",
		[[SkillEffect.AREA_ALL, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]], "10:100",
		{"attack_type": BattleSkill.ATTACK_NONE}))
	catalog.add_record(BattleSkill.KIND_ITEM, POTION, Fixtures.record("Potion",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 16, [200]]]))
	catalog.add_record(BattleSkill.KIND_MAGIC, THUNDER, Fixtures.record("Thunder",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]], "10:100",
		{"magic_type": "Black", "attack_type": BattleSkill.ATTACK_MAGIC}))
	catalog.add_record(BattleSkill.KIND_ABILITY, DUALCAST, Fixtures.record("Dualcast", [[0, 3, 45, ["none"]]], ""))
	return catalog


static func _hero() -> Combatant:
	return Fixtures.unit("Hero", {"limit_burst_id": LIMIT, "max_lb": 800, "esper_id": SIREN, "esper_skill_id": ESPER_SKILL})


static func _foe(spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"template_id": "302001", "brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster("Zu", full)


func _challenges(parameters: Array) -> ChallengeSet:
	var challenges: Array = parameters.map(func(parameter: String) -> Dictionary: return {"parameter": parameter})
	var challenge_set := ChallengeSet.new(challenges)
	_sets.append(challenge_set)
	return challenge_set


## A typed result as a plain array, so it compares with a literal.
static func _bools(results: Array[bool]) -> Array:
	var out: Array = []
	for result in results:
		out.append(result)
	return out


## Records the arguments of each emission of a BattleEvents signal with two arguments.
func _record_pairs(sig: Signal) -> Array:
	var calls: Array = []
	var recorder: Callable = func(first: Variant, second: Variant) -> void: calls.append([first, second])
	sig.connect(recorder)
	_connections.append([sig, recorder])
	return calls


## Records the argument of each emission of a BattleEvents signal with one argument.
func _record(sig: Signal) -> Array:
	var calls: Array = []
	var recorder: Callable = func(value: Variant) -> void: calls.append(value)
	sig.connect(recorder)
	_connections.append([sig, recorder])
	return calls


## Runs `battle` until the next turn with basic attacks for whoever has not acted, and
## relays what happened.
static func _finish_turn(battle: BattleEngine, bridge: BattleEventsBridge) -> void:
	var next_turn: int = battle.turn + 1
	var ids: Array = []
	for unit in battle.units_to_act():
		ids.append(unit.id)
	battle.execute_many(ids)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == next_turn or battle.phase == BattleEngine.Phase.ENDED)
	bridge.relay(battle, battle.events.drain())


# === Hits and defeats ===

func test_a_fire_kill_reaches_the_damage_and_kill_signals() -> void:
	var challenges: ChallengeSet = _challenges(["26:1", "26:2", "33"])
	var damaged: Array = _record_pairs(BattleEvents.enemy_damaged)
	var defeated: Array = _record_pairs(BattleEvents.enemy_defeated)
	var allies_down: Array = []
	var on_ally: Callable = func() -> void: allies_down.append(true)
	BattleEvents.ally_defeated.connect(on_ally)
	_connections.append([BattleEvents.ally_defeated, on_ally])
	var hero: Combatant = _hero()
	var foe: Combatant = _foe({"hp": 30})
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, _catalog())
	battle.start()
	var bridge := BattleEventsBridge.new()

	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, FIRE, foe.id)), BattleEngine.OK)
	battle.advance(10)
	bridge.relay(battle, battle.events.drain())

	assert_eq(damaged.size(), 1)
	var landed: Dictionary = battle.events.last_of_type(BattleEventLog.HIT_LANDED)
	assert_eq(damaged[0], ["302001", {"element": [1], "amount": int(landed["amount"])}],
		"the monster dictionary id and the hit's 1-based elements, as challenge 26 reads them")
	assert_eq(defeated, [["302001", damaged[0][1]]], "the kill carries the hit that dealt it")
	assert_eq(allies_down.size(), 0, "an enemy kill is not an ally down")
	assert_eq(_bools(challenges.evaluate()), [true, false, true])


func test_a_party_member_down_fails_the_no_ko_challenge() -> void:
	var challenges: ChallengeSet = _challenges(["33"])
	var damaged: Array = _record_pairs(BattleEvents.enemy_damaged)
	var hero: Combatant = _hero()
	var battle: BattleEngine = Fixtures.engine([hero], [_foe()], null, _catalog())
	BattleEventsBridge.new().relay(battle, [
		{"type": BattleEventLog.HIT_LANDED, "target": hero.id, "amount": 999, "elements": PackedInt32Array()},
		{"type": BattleEventLog.COMBATANT_DEFEATED, "target": hero.id, "by": -1, "action": -1},
	])
	assert_eq(damaged.size(), 0, "a hit on the party is not enemy damage")
	assert_eq(_bools(challenges.evaluate()), [false])


# === Commands ===

func test_player_commands_reach_the_magic_ability_limit_and_esper_signals() -> void:
	var challenges: ChallengeSet = _challenges(["5", "6", "7:1001", "16", "17", "28", "30:1", "45:2"])
	var magic: Array = _record(BattleEvents.magic_used)
	var abilities: Array = _record(BattleEvents.ability_used)
	var limits: Array = _record(BattleEvents.limitburst_used)
	var espers: Array = _record(BattleEvents.esper_evoked)
	var hero: Combatant = _hero()
	var battle: BattleEngine = Fixtures.engine([hero], [_foe()], null, _catalog())
	battle.start()
	var bridge := BattleEventsBridge.new()

	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, FIRE))
	_finish_turn(battle, bridge)
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, STRIKE))
	_finish_turn(battle, bridge)
	hero.lb = 800
	assert_eq(battle.execute(hero.id, BattleCommand.limit_burst(LIMIT)), BattleEngine.OK)
	_finish_turn(battle, bridge)
	battle.esper_orbs = battle.rules.esper_gauge_max
	assert_eq(battle.execute(hero.id, BattleCommand.evoke()), BattleEngine.OK)
	_finish_turn(battle, bridge)

	assert_eq(magic.size(), 1)
	assert_eq([magic[0]["source_type"], magic[0]["resolved_action_id"], magic[0]["resolved_action_data"]["name"]],
		["magic", FIRE, "Fire"], "the old queued payload's shape")
	assert_eq(abilities.size(), 1)
	assert_eq([abilities[0]["source_type"], abilities[0]["resolved_action_id"]], ["ability", STRIKE])
	assert_eq(limits, [LIMIT])
	assert_eq(espers, [SIREN], "the beastId, what challenge 30 compares")
	# 17 ("No limit bursts") can never pass: KNOWN-BUGS #9. 45:2 needs two evocations.
	assert_eq(_bools(challenges.evaluate()), [true, false, true, true, false, true, true, false])


func test_each_multicast_pick_is_a_use_of_its_skill_and_the_command_is_none() -> void:
	var magic: Array = _record(BattleEvents.magic_used)
	var abilities: Array = _record(BattleEvents.ability_used)
	var hero: Combatant = _hero()
	var battle: BattleEngine = Fixtures.engine([hero], [_foe()], null, _catalog())
	battle.start()
	var picks: Array[BattleCommand] = [
		BattleCommand.skill(BattleSkill.KIND_MAGIC, THUNDER), BattleCommand.skill(BattleSkill.KIND_MAGIC, THUNDER),
	]
	assert_eq(battle.execute(hero.id, BattleCommand.multicast(DUALCAST, picks)), BattleEngine.OK)
	_finish_turn(battle, BattleEventsBridge.new())
	assert_eq(magic.size(), 2, "one per pick")
	assert_eq(abilities.size(), 0, "Dualcast itself is not cast")


func test_forced_cast_and_enemy_actions_are_not_the_players() -> void:
	var magic: Array = _record(BattleEvents.magic_used)
	var hero: Combatant = _hero()
	var foe: Combatant = _foe()
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, _catalog())
	var spell: Dictionary = {"type": BattleEventLog.ACTION_STARTED, "kind": BattleCommand.Kind.SKILL,
		"skill_kind": BattleSkill.KIND_MAGIC, "skill_id": FIRE, "forced_by": "", "esper_id": 0}
	var by_enemy: Dictionary = spell.merged({"actor": foe.id, "origin": BattleAction.Origin.AI}, true)
	var forced: Dictionary = spell.merged({"actor": hero.id, "origin": BattleAction.Origin.COMMAND, "forced_by": "CONFUSION"}, true)
	var cast: Dictionary = spell.merged({"actor": hero.id, "origin": BattleAction.Origin.CAST}, true)
	var chosen: Dictionary = spell.merged({"actor": hero.id, "origin": BattleAction.Origin.COMMAND}, true)
	BattleEventsBridge.new().relay(battle, [by_enemy, forced, cast, chosen])
	assert_eq(magic.size(), 1, "only the player's own command counts")


## A jump's landing (a LAND command, or one on its own) and a delayed cast are no ability
## use: the jump was one when the player chose it.
func test_landings_and_delayed_casts_are_no_ability_use() -> void:
	var abilities: Array = _record(BattleEvents.ability_used)
	var hero: Combatant = _hero()
	var battle: BattleEngine = Fixtures.engine([hero], [_foe()], null, _catalog())
	var ability: Dictionary = {"type": BattleEventLog.ACTION_STARTED, "actor": hero.id, "kind": BattleCommand.Kind.SKILL,
		"skill_kind": BattleSkill.KIND_ABILITY, "skill_id": STRIKE, "forced_by": "", "esper_id": 0, "origin": BattleAction.Origin.COMMAND}
	var landed: Dictionary = ability.merged({"kind": BattleCommand.Kind.LAND}, true)
	var landed_on_its_own: Dictionary = landed.merged({"origin": BattleAction.Origin.REACTION, "reaction": Reaction.LANDING}, true)
	var delayed: Dictionary = ability.merged({"origin": BattleAction.Origin.REACTION, "reaction": Reaction.DELAYED}, true)
	BattleEventsBridge.new().relay(battle, [ability, landed, landed_on_its_own, delayed])
	assert_eq(abilities.size(), 1, "only the chosen ability")


## A counter and a battle-start cast are the engine's, not the player's: Fire cast twice
## that way is no magic use for the challenges.
func test_counters_and_passive_casts_are_not_the_players() -> void:
	var magic: Array = _record(BattleEvents.magic_used)
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {
		"counters": [{"trigger": "physical", "chance": 100, "modifier": 0, "max": 0, "skill_kind": BattleSkill.KIND_MAGIC,
			"skill_id": FIRE, "source_skill_id": "910443"}],
		"auto_casts": [{"skill_kind": BattleSkill.KIND_MAGIC, "skill_id": FIRE, "battle_start": true, "revive": false,
			"turn_start": false, "chance": 100, "source_skill_id": "230914"}],
	}})
	var battle: BattleEngine = Fixtures.engine([hero], [_foe({"brain": EnemyBrain.new(), "atk": 1})], null, _catalog())
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2 and battle.phase == BattleEngine.Phase.PLAYER)
	BattleEventsBridge.new().relay(battle, battle.events.drain())
	var fires: Array = Fixtures.actions_by(battle, hero.id).filter(func(event: Dictionary) -> bool: return str(event["skill_id"]) == FIRE)
	assert_eq(fires.size(), 2, "the battle-start cast and the counter")
	assert_eq(magic.size(), 0)


func test_items_reach_the_item_signal() -> void:
	var challenges: ChallengeSet = _challenges(["0", "1", "40:1"])
	var items: Array = _record(BattleEvents.item_used)
	var hero: Combatant = _hero()
	var battle: BattleEngine = Fixtures.engine([hero], [_foe()], null, _catalog())
	battle.item_stock = {POTION: 2}
	battle.start()
	var bridge := BattleEventsBridge.new()
	battle.execute(hero.id, BattleCommand.item(POTION, hero.id))
	_finish_turn(battle, bridge)
	battle.execute(hero.id, BattleCommand.item(POTION, hero.id))
	_finish_turn(battle, bridge)
	assert_eq(items, [POTION, POTION])
	assert_eq(_bools(challenges.evaluate()), [true, false, false])


# === Mission end ===

func test_mission_completed_carries_every_slot_and_the_turns_across_waves() -> void:
	var challenges: ChallengeSet = _challenges(["34:1", "35:2", "38", "68"])
	var completed: Array = _record_pairs(BattleEvents.mission_completed)
	var hero: Combatant = _hero()
	var friend: Combatant = Fixtures.unit("Friend")
	hero.source = {"instance_id": "a", "unitSeries": 1}
	friend.source = {"instance_id": "b", "unitSeries": 2}
	var battle := BattleEngine.new(_catalog(), Fixtures.rules(), 7)
	battle.add_party_member(hero, 0)
	battle.add_party_member(friend, 2)
	battle.add_enemy(_foe())
	battle.total_turns = 5

	BattleEventsBridge.new().mission_completed(battle)
	assert_eq(completed, [[[hero.source, {}, friend.source], 5]], "{} for the empty slot; turns across waves")
	# 35:2 ("2 or less") needs 1 or less: KNOWN-BUGS #9.
	assert_eq(_bools(challenges.evaluate()), [true, false, true, true])
	assert_eq(BattleEventsBridge.party_sources(battle, 5), [hero.source, {}, friend.source, {}, {}], "padded to 5 slots")


# === ChallengeSet ===

func test_challenge_set_disconnects_its_trackers() -> void:
	var before: int = BattleEvents.item_used.get_connections().size()
	var challenges: ChallengeSet = _challenges(["0", "1"])
	assert_eq(BattleEvents.item_used.get_connections().size(), before + 2)
	assert_eq(_bools(challenges.evaluate()), [false, true], "nothing used: 0 not done, 1 holds")
	assert_eq(BattleEvents.item_used.get_connections().size(), before, "evaluate disconnects")

	var dropped: ChallengeSet = _challenges(["0", "40:3"])
	dropped.cleanup()
	dropped.cleanup()
	assert_eq(BattleEvents.item_used.get_connections().size(), before, "a defeat cleans up too, any number of times")


func test_challenge_set_for_params() -> void:
	assert_eq(ChallengeSet.for_params({}).trackers.size(), 0, "the test battle has none")
	assert_eq(ChallengeSet.for_params({"battle_group": "111050313"}).trackers.size(), 0)
	var mission: ChallengeSet = ChallengeSet.for_params({"mission_id": "1110103"})
	_sets.append(mission)
	assert_eq(mission.trackers.size(), 4, "68, 34:1, 33 and 38")
	assert_eq(_bools(mission.evaluate()), [true, false, true, false],
		"before mission_completed: only the defaults hold")
