extends "res://tests/test_case.gd"

## Op 100 grants (SkillGrant, GrantHandler): skills a unit may use for some turns or
## uses. Turns go down when the enemy phase begins, a use is spent when the granted
## skill's action starts, a new grant of the same skill replaces the old one, KO ends
## them and waves keep them.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const SLASH: String = "10"
const FIRE: String = "20"
const TWIN_STRIKE: String = "100"
## Killer Shot 209240: damage, then Finishing Blow for one turn, one use (2, 501160, 1, 2, 1, 0).
const KILLER_SHOT: String = "200"
const FINISHING_BLOW: String = "201"
## Mark-like: Finishing Blow "for three turns", unlimited uses, the 5-param form.
const MARK: String = "202"
## Infiltrate Server 913026: an ability and a spell, uses 0, turn_count -1.
const INFILTRATE: String = "203"
## Bonds of Battle 232078: all allies, five turns.
const BONDS: String = "204"

var catalog: SkillCatalog


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	catalog = Fixtures.catalog()
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	_ability(SLASH, Fixtures.record("Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	var fire: Dictionary = Fixtures.skill_record("Fire", 15, Fixtures.magic_params(100), "10:100")
	fire["magic_type"] = "Black"
	catalog.add_record(BattleSkill.KIND_MAGIC, FIRE, fire)
	_ability(KILLER_SHOT, Fixtures.record("Killer Shot", [
		[1, 1, 1, Fixtures.physical_params(100)],
		[0, 3, 100, [2, int(FINISHING_BLOW), 1, 2, 1, 0]],
	], "10:100", physical))
	_ability(FINISHING_BLOW, Fixtures.record("Finishing Blow", [[1, 1, 1, Fixtures.physical_params(300)]], "10:100", physical))
	_ability(MARK, Fixtures.record("Mark", [[0, 3, 100, [2, int(FINISHING_BLOW), 99999, 4, 1]]], ""))
	_ability(INFILTRATE, Fixtures.record("Infiltrate Server", [[0, 3, 100, [[2, 1], [int(FINISHING_BLOW), int(FIRE)], 0, -1, 1, 913026]]], ""))
	_ability(BONDS, Fixtures.record("Bonds of Battle", [[2, 2, 100, [2, int(FINISHING_BLOW), 99999, 5, 1, 1000]]], "10:100"))
	_ability(TWIN_STRIKE, Fixtures.record("Twin Strike", [[0, 3, 53, [2, int(TWIN_STRIKE), -1, [int(FINISHING_BLOW), int(SLASH)], 1, 0]]], ""))


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


func _skill(id: String) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_ABILITY, id)


func _twin(first: String, second: String) -> BattleCommand:
	var picks: Array[BattleCommand] = [_skill(first), _skill(second)]
	return BattleCommand.multicast(TWIN_STRIKE, picks)


func _idle(spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster("Foe", full)


func _battle(party: Array, foes: Array = []) -> BattleEngine:
	var battle: BattleEngine = Fixtures.engine(party, foes if not foes.is_empty() else [_idle()], null, catalog)
	battle.start()
	return battle


## Executes each [unit, command] pair, then plays on to the next turn (enemies pass).
func _turn(battle: BattleEngine, orders: Array) -> void:
	var next_turn: int = battle.total_turns + 1
	for order in orders:
		var unit: Combatant = order[0]
		assert_eq(battle.execute(unit.id, order[1]), BattleEngine.OK, "%s acts on turn %d" % [unit.name, battle.total_turns])
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.total_turns == next_turn), "turn %d starts" % next_turn)


func _act(battle: BattleEngine, unit: Combatant, command: BattleCommand) -> void:
	_turn(battle, [[unit, command]])


## [skill_kind:skill_id, turns_left, uses_left] of each grant `unit` holds.
func _grants(battle: BattleEngine, unit: Combatant) -> Array:
	var out: Array = []
	for grant in battle.grants_of(unit.id):
		out.append([grant.key(), grant.turns_left, grant.uses_left])
	return out


func _ended(battle: BattleEngine, unit: Combatant) -> Array:
	var out: Array = []
	for event in Fixtures.events_on(battle, BattleEventLog.SKILL_GRANT_ENDED, unit.id):
		out.append([event["skill_id"], event["reason"]])
	return out


func test_a_one_turn_grant_is_usable_next_turn_and_its_one_use_ends_it() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(KILLER_SHOT))
	var granted: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.SKILL_GRANTED, hero.id)
	assert_eq(granted.size(), 1)
	assert_eq([granted[0]["skill_kind"], granted[0]["skill_id"], granted[0]["turns"], granted[0]["uses"]],
		[BattleSkill.KIND_ABILITY, FINISHING_BLOW, 2, 1])
	assert_eq([granted[0]["source_skill_id"], granted[0]["by"], granted[0]["replaced"]], [KILLER_SHOT, hero.id, false])
	assert_true(battle.format_event(granted[0]).contains("2 turn(s), 1 use(s)"), battle.format_event(granted[0]))
	assert_eq(_grants(battle, hero), [["ability:" + FINISHING_BLOW, 1, 1]], "the enemy phase took a turn")
	assert_eq(battle.skill_limits(hero.id, _skill(FINISHING_BLOW)), {"grant_turns_left": 1, "grant_uses_left": 1})

	assert_eq(battle.execute(hero.id, _skill(FINISHING_BLOW)), BattleEngine.OK)
	assert_eq(_grants(battle, hero), [], "the last use ends it as the action starts")
	assert_eq(_ended(battle, hero), [[FINISHING_BLOW, &"used_up"]])


func test_an_unused_one_turn_grant_expires_when_the_next_enemy_phase_begins() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(KILLER_SHOT))
	_act(battle, hero, _skill(SLASH))
	assert_eq(_grants(battle, hero), [])
	var ended: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.SKILL_GRANT_ENDED, hero.id)
	assert_eq(ended[0]["reason"], &"expired")
	var enemy_phases: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.PHASE_CHANGED):
		if event["phase"] == BattleEngine.PHASE_NAMES[BattleEngine.Phase.ENEMY] and int(event["turn"]) == 2:
			enemy_phases.append(event)
	assert_eq(int(ended[0]["seq"]) + 1, int(enemy_phases[0]["seq"]), "it ends as turn 2's enemy phase begins")
	assert_true(battle.format_event(ended[0]).contains("loses ability:%s (expired)" % FINISHING_BLOW), battle.format_event(ended[0]))


func test_turn_count_4_lasts_three_more_turns_with_unlimited_uses() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(MARK))
	_act(battle, hero, _skill(FINISHING_BLOW))
	_act(battle, hero, _skill(FINISHING_BLOW))
	assert_eq(_grants(battle, hero), [["ability:" + FINISHING_BLOW, 1, -1]], "turn 4: the last one")
	_act(battle, hero, _skill(SLASH))
	assert_eq(_grants(battle, hero), [], "gone on turn 5")


func test_uses_0_and_turn_count_minus_1_never_run_out_and_magic_can_be_granted() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(INFILTRATE))
	assert_eq(_grants(battle, hero), [["ability:" + FINISHING_BLOW, -1, -1], ["magic:" + FIRE, -1, -1]])
	for _i in range(3):
		_act(battle, hero, BattleCommand.skill(BattleSkill.KIND_MAGIC, FIRE))
	_act(battle, hero, _skill(FINISHING_BLOW))
	assert_eq(_grants(battle, hero).size(), 2)
	var granted: Dictionary = Fixtures.events_on(battle, BattleEventLog.SKILL_GRANTED, hero.id)[0]
	assert_true(battle.format_event(granted).contains("no time limit, unlimited uses"))


func test_an_all_allies_grant_reaches_living_allies_who_can_use_it_the_same_turn() -> void:
	var caster: Combatant = Fixtures.unit("Caster")
	var ally: Combatant = Fixtures.unit("Ally")
	var fallen: Combatant = Fixtures.unit("Fallen")
	var battle: BattleEngine = _battle([caster, ally, fallen])
	battle.kill(fallen, -1, null)
	assert_eq(battle.execute(caster.id, _skill(BONDS)), BattleEngine.OK)
	assert_true(Fixtures.run_until(battle, func() -> bool: return not ally.grants.is_empty()), "the grant lands with its hit")
	assert_eq(battle.execute(ally.id, _skill(FINISHING_BLOW)), BattleEngine.OK, "the ally has not acted yet")
	assert_eq(_grants(battle, caster), [["ability:" + FINISHING_BLOW, 5, -1]])
	assert_eq(_grants(battle, ally), [["ability:" + FINISHING_BLOW, 5, -1]])
	assert_eq(_grants(battle, fallen), [], "a KO'd ally gets nothing")


func test_a_new_grant_of_the_same_skill_replaces_the_old_one() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(KILLER_SHOT))
	_act(battle, hero, _skill(MARK))
	var granted: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.SKILL_GRANTED, hero.id)
	assert_true(bool(granted[1]["replaced"]))
	assert_eq(_grants(battle, hero), [["ability:" + FINISHING_BLOW, 3, -1]], "Mark's turns and uses")


func test_ko_ends_grants_and_a_wave_keeps_them() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [_idle({"hp": 50})], null, catalog)
	battle.queue_wave(func() -> Array: return [_idle()])
	battle.start()
	assert_eq(battle.execute(hero.id, _skill(KILLER_SHOT)), BattleEngine.OK)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED))
	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	assert_eq(_grants(battle, hero), [["ability:" + FINISHING_BLOW, 2, 1]], "no enemy phase came in between")
	hero.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 50, 3))
	battle.kill(hero, battle.enemies[0].id, null)
	assert_true(hero.is_alive())
	assert_eq(_grants(battle, hero), [])
	assert_eq(_ended(battle, hero), [[FINISHING_BLOW, &"ko"]])


func test_a_granted_skill_with_uses_is_picked_once_in_a_multicast() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(KILLER_SHOT))
	var command: BattleCommand = _twin(FINISHING_BLOW, SLASH)
	var none: Array[BattleCommand] = []
	var first: Array[BattleCommand] = [_skill(FINISHING_BLOW)]
	assert_eq(battle.multicast_pick_problem(hero.id, command, none, _skill(FINISHING_BLOW)), BattleEngine.OK)
	assert_eq(battle.multicast_pick_problem(hero.id, command, first, _skill(FINISHING_BLOW)), BattleEngine.REJECT_NO_USES_LEFT)
	assert_eq(battle.can_execute(hero.id, _twin(FINISHING_BLOW, FINISHING_BLOW)), BattleEngine.REJECT_NO_USES_LEFT)
	_act(battle, hero, command)
	assert_eq(_ended(battle, hero), [[FINISHING_BLOW, &"used_up"]], "spent when its pick was cast")

	_act(battle, hero, _skill(MARK))
	assert_eq(battle.multicast_pick_problem(hero.id, command, first, _skill(FINISHING_BLOW)), BattleEngine.OK, "unlimited uses: picked again")


func test_a_confused_unit_spends_no_grant_use() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(KILLER_SHOT))
	battle.debug_edit(hero.id, &"ailment", 1, "CONFUSION")
	assert_eq(battle.execute(hero.id, _skill(FINISHING_BLOW)), BattleEngine.OK)
	assert_eq(_grants(battle, hero), [["ability:" + FINISHING_BLOW, 1, 1]], "the attack it became spends nothing")


# --- Real data ---

func test_warp_strike_grants_point_blank_warp_strike_for_one_turn() -> void:
	var noctis: Combatant = Fixtures.unit("Noctis", {"mp": 500, "max_mp": 500})
	var battle: BattleEngine = Fixtures.engine([noctis], [_idle()], null, DatabaseSkillCatalog.new())
	battle.start()
	_act(battle, noctis, _skill("211760"))
	assert_eq(_grants(battle, noctis), [["ability:501620", 1, -1]], "usable on turn 2, uses 99999")
	assert_eq(battle.can_execute(noctis.id, _skill("501620")), BattleEngine.OK)
