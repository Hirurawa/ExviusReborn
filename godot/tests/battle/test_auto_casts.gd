extends "res://tests/test_case.gd"

## Skills passives cast on their own (Reaction): at the battle start (103, 35, 56), at
## each turn start (66) and after a revive (35, 56). Battle-start and turn-start casts run
## in the turn's opening phase, one at a time, before the player phase; a cast after a
## revive runs right after the revive. They cost nothing, spend no limit, leave `acted`
## and the action history alone. REACTIONS-PLAN.md has the plan.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

## ATK +50% on the caster for 3 turns, 10 MP.
const WAR_CRY: String = "10"
## SPR +30% on the caster for 1 turn.
const GUARD_UP: String = "11"
## Finishing Blow for one turn, one use (op 100), on the caster.
const ENABLE_BLOW: String = "12"
const FINISHING_BLOW: String = "13"
## Regen (Auto) 10121 (magic): a permanent regen on one ally.
const AUTO_REGEN: String = "10121"
## A full revive of one KO'd ally.
const RAISE: String = "14"

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()
	_ability(WAR_CRY, Fixtures.record("War Cry", [[0, 3, 3, [50, 0, 0, 0, 3]]], "10:100", {"cost": {"MP": 10}}))
	_ability(GUARD_UP, Fixtures.record("Guard Up", [[0, 3, 3, [0, 0, 0, 30, 1]]], "10:100"))
	_ability(ENABLE_BLOW, Fixtures.record("Enable Blow", [[0, 3, 100, [2, int(FINISHING_BLOW), 1, 1]]], ""))
	_ability(FINISHING_BLOW, Fixtures.record("Finishing Blow", [[1, 1, 1, Fixtures.physical_params(300)]], "10:100",
		{"attack_type": BattleSkill.ATTACK_PHYSICAL}))
	_ability(RAISE, Fixtures.record("Raise", [[1, 2, 4, [100]]], "10:100"))
	catalog.add_record(BattleSkill.KIND_MAGIC, AUTO_REGEN, Fixtures.record("Regen (Auto)", [[1, 2, 8, [120, 1, 60, -1]]], ""))


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


## One CombatantPassives.auto_casts entry.
static func _cast(skill_id: String, when: Array, chance: int = 100, kind: StringName = BattleSkill.KIND_ABILITY) -> Dictionary:
	return {
		"skill_kind": kind, "skill_id": skill_id, "battle_start": when.has("battle_start"), "revive": when.has("revive"),
		"turn_start": when.has("turn_start"), "chance": chance, "source_skill_id": "9%s" % skill_id,
	}


static func _caster(unit_name: String, casts: Array) -> Combatant:
	return Fixtures.unit(unit_name, {"passives": {"auto_casts": casts}})


static func _idle(foe_name: String = "Foe") -> Combatant:
	return Fixtures.monster(foe_name, {"brain": IdleEnemyBrain.new()})


static func _reactions(battle: BattleEngine, kind: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.ACTION_STARTED):
		if int(event["origin"]) == BattleAction.Origin.REACTION and (kind == &"" or StringName(event["reaction"]) == kind):
			out.append(event)
	return out


## Every living party member defends, then the battle runs to the next turn's player phase.
static func _next_turn(battle: BattleEngine) -> void:
	var turn: int = battle.turn
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	for member in battle.units_to_act():
		battle.execute(member.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn > turn and battle.phase == BattleEngine.Phase.PLAYER, 5000)


func test_a_battle_start_cast_runs_before_the_player_phase() -> void:
	var hero: Combatant = _caster("Hero", [_cast(WAR_CRY, ["battle_start"])])
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	assert_eq(battle.phase, BattleEngine.Phase.OPENING)
	assert_eq(battle.can_execute(hero.id, BattleCommand.attack()), BattleEngine.REJECT_NOT_PLAYER_PHASE, "no commands meanwhile")
	var started: Array[Dictionary] = _reactions(battle)
	assert_eq(started.size(), 1, "the cast starts on the turn's first frame")
	if started.size() == 1:
		assert_eq([started[0]["reaction"], started[0]["skill_id"], started[0]["source_skill_id"]], [Reaction.BATTLE_START, WAR_CRY, "910"])
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER))
	assert_eq(hero.status_value(BattleStatus.STAT, "ATK"), 50)
	assert_eq(hero.mp, 100, "a reaction pays no MP")
	assert_false(hero.acted, "nor does it use up the turn")
	assert_eq(hero.history.previous_declared, "", "nor go into the history")
	var phases: Array = battle.events.of_type(BattleEventLog.PHASE_CHANGED).map(func(event: Dictionary) -> StringName: return event["phase"])
	assert_eq(phases, [&"opening", &"player"])


func test_without_reactions_there_is_no_opening_phase() -> void:
	var battle: BattleEngine = Fixtures.engine([Fixtures.unit("Hero")], [_idle()], null, catalog)
	battle.start()
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER)
	_next_turn(battle)
	for event in battle.events.of_type(BattleEventLog.PHASE_CHANGED):
		assert_ne(event["phase"], &"opening")


func test_battle_start_casts_come_back_each_wave() -> void:
	var hero: Combatant = _caster("Hero", [_cast(WAR_CRY, ["battle_start"])])
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("First", {"hp": 1, "brain": IdleEnemyBrain.new()})], null, catalog)
	battle.queue_wave(func() -> Array[Combatant]: return [_idle("Second")])
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	battle.execute(hero.id)
	Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED)
	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(_reactions(battle, Reaction.BATTLE_START).size(), 2, "once per wave")
	_next_turn(battle)
	assert_eq(_reactions(battle, Reaction.BATTLE_START).size(), 2, "not on later turns")


func test_turn_start_casts_roll_their_chance_each_turn() -> void:
	var sure: Combatant = _caster("Sure", [_cast(GUARD_UP, ["turn_start"])])
	var never: Combatant = _caster("Never", [_cast(GUARD_UP, ["turn_start"], 0)])
	var maybe: Combatant = _caster("Maybe", [_cast(GUARD_UP, ["turn_start"], 50)])
	var battle: BattleEngine = Fixtures.engine([sure, never, maybe], [_idle()], null, catalog)
	battle.start()
	for _i in range(39):
		_next_turn(battle)
	var counts: Dictionary = {sure.id: 0, never.id: 0, maybe.id: 0}
	for event in _reactions(battle, Reaction.TURN_START):
		counts[int(event["actor"])] += 1
	assert_eq(counts[sure.id], 40, "every turn, the first included")
	assert_eq(counts[never.id], 0)
	assert_true(counts[maybe.id] > 10 and counts[maybe.id] < 30, "about half: %d of 40" % counts[maybe.id])
	assert_eq(sure.status_value(BattleStatus.STAT, "SPR"), 30, "a 1-turn buff from the turn start lasts the turn")


func test_reactions_run_one_at_a_time_in_slot_order() -> void:
	var first: Combatant = _caster("First", [_cast(WAR_CRY, ["battle_start"]), _cast(GUARD_UP, ["turn_start"])])
	var second: Combatant = _caster("Second", [_cast(GUARD_UP, ["battle_start"])])
	var battle: BattleEngine = Fixtures.engine([first, second], [_idle()], null, catalog)
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	var started: Array[Dictionary] = _reactions(battle)
	assert_eq(started.map(func(event: Dictionary) -> Array: return [int(event["actor"]), event["reaction"]]), [
		[first.id, Reaction.BATTLE_START], [second.id, Reaction.BATTLE_START], [first.id, Reaction.TURN_START],
	], "battle-start casts in slot order, then turn-start casts")
	if started.size() == 3:
		var gap: int = battle.rules.reaction_gap_frames
		assert_eq(int(started[1]["frame"]), int(started[0]["frame"]) + 10 + gap, "after the previous one's last hit and the gap")
		assert_eq(int(started[2]["frame"]), int(started[1]["frame"]) + 10 + gap)


func test_a_disabled_unit_loses_its_cast_and_a_petrified_one_casts_nothing() -> void:
	var sleeper: Combatant = _caster("Sleeper", [_cast(WAR_CRY, ["battle_start"])])
	var stone: Combatant = _caster("Stone", [_cast(WAR_CRY, ["battle_start"])])
	var awake: Combatant = Fixtures.unit("Awake")
	sleeper.add_status(BattleStatus.make(BattleStatus.AILMENT, "SLEEP", 0, 3))
	stone.add_status(BattleStatus.make(BattleStatus.AILMENT, "PETRIFY", 0, -1))
	var battle: BattleEngine = Fixtures.engine([sleeper, stone, awake], [_idle()], null, catalog)
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(_reactions(battle).size(), 0)
	var dropped: Array[Dictionary] = battle.events.of_type(BattleEventLog.REACTION_DROPPED)
	assert_eq(dropped.size(), 1, "the petrified unit's cast is never queued")
	if dropped.size() == 1:
		assert_eq([int(dropped[0]["actor"]), dropped[0]["reason"]], [sleeper.id, &"cannot_act"])


func test_a_one_turn_grant_from_the_battle_start_is_usable_on_turn_1() -> void:
	var hero: Combatant = _caster("Hero", [_cast(ENABLE_BLOW, ["battle_start"])])
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(battle.grants_of(hero.id).size(), 1)
	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, FINISHING_BLOW, -1)), BattleEngine.OK)
	_next_turn(battle)
	assert_eq(battle.grants_of(hero.id).size(), 0)


func test_a_reraise_brings_back_the_revive_casts() -> void:
	var hero: Combatant = _caster("Hero", [_cast(AUTO_REGEN, ["battle_start", "revive"], 100, BattleSkill.KIND_MAGIC)])
	var battle: BattleEngine = Fixtures.engine([hero, Fixtures.unit("Friend")], [_idle()], null, catalog)
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_true(hero.status_value(BattleStatus.REGEN) > 0, "cast at the battle start")
	hero.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 50, 3))
	battle.debug_edit(hero.id, &"hp", 0)
	assert_eq(hero.status_value(BattleStatus.REGEN), 0, "KO cleared it")
	battle.tick()
	var revive_casts: Array[Dictionary] = _reactions(battle, Reaction.REVIVE)
	assert_eq(revive_casts.size(), 1, "cast again after the reraise")
	if revive_casts.size() == 1:
		assert_true(int(revive_casts[0]["seq"]) > int(battle.events.last_of_type(BattleEventLog.REVIVED)["seq"]))
	battle.advance(5)
	assert_true(hero.status_value(BattleStatus.REGEN) > 0)
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "a revive cast does not open a phase")


func test_a_revive_cast_runs_after_the_reviving_hit() -> void:
	var hero: Combatant = _caster("Hero", [_cast(GUARD_UP, ["revive"])])
	var healer: Combatant = Fixtures.unit("Healer")
	var battle: BattleEngine = Fixtures.engine([hero, healer], [_idle()], null, catalog)
	battle.start()
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "a revive-only cast does not run at the battle start")
	battle.debug_edit(hero.id, &"hp", 0)
	assert_eq(battle.execute(healer.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, RAISE, hero.id)), BattleEngine.OK)
	battle.advance(10)
	var revived: Dictionary = battle.events.last_of_type(BattleEventLog.REVIVED)
	var casts: Array[Dictionary] = _reactions(battle, Reaction.REVIVE)
	assert_eq(casts.size(), 1)
	if casts.size() == 1 and not revived.is_empty():
		assert_eq(int(casts[0]["frame"]), int(revived["frame"]), "on the same frame")
		assert_true(int(casts[0]["seq"]) > int(revived["seq"]), "after the revive")
	battle.advance(10)
	assert_eq(hero.status_value(BattleStatus.STAT, "SPR"), 30)
	assert_false(hero.acted, "the revived unit can still act")


func test_the_log_names_the_reaction() -> void:
	var hero: Combatant = _caster("Hero", [_cast(WAR_CRY, ["battle_start"])])
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	var started: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_STARTED)
	assert_true(battle.format_event(started).ends_with("War Cry (battle start)"), battle.format_event(started))


## Real passives: Preemptive Cover - Physical (106190) casts 514923, an AoE cover on the
## caster; Auto-Reflect (230914) casts the spell 30371; Reverie (227740) a dodge at the
## battle start.
func test_database_battle_start_casts() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var data := DatabaseSkillCatalog.new()
	var tank: Combatant = Fixtures.unit("Tank", {"passives": _passives_of(["106190"])})
	var mage: Combatant = Fixtures.unit("Mage", {"passives": _passives_of(["230914", "227740"])})
	assert_eq(mage.passives.auto_casts.map(func(cast: Dictionary) -> Array: return [cast["skill_kind"], cast["skill_id"], cast["revive"]]),
		[[BattleSkill.KIND_MAGIC, "30371", true], [BattleSkill.KIND_ABILITY, "508110", true]])
	var battle: BattleEngine = Fixtures.engine([tank, mage], [_idle()], null, data)
	battle.start()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(_reactions(battle).map(func(event: Dictionary) -> String: return str(event["skill_id"])), ["514923", "30371", "508110"])
	assert_not_null(tank.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE), "Preemptive Cover")
	assert_true(mage.status_value(BattleStatus.DODGE) > 0, "Reverie")


## A passive's battle modifiers as StatCalculator would give them (the profile's
## `passives`), from database passive ids.
static func _passives_of(passive_ids: Array) -> Dictionary:
	var sources: Array = []
	for passive_id in passive_ids:
		var effects: Array = SkillResolver.parse_passive_effects(GameDatabase.get_passive(int(passive_id))).get("effects", [])
		sources.append({"skill_id": str(passive_id), "source": "Trait", "effects": effects})
	return PassiveAggregator.aggregate(sources, PassiveSources.build_loadout([]), {})
