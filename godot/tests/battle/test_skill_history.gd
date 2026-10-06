extends "res://tests/test_case.gd"

## What a combatant's history decides (SkillHistory): the stacks of abilities that power
## up with consecutive use (ops 72, 126, 1007), by the wiki's rules, and op 99's branch
## (the true skill when a condition skill was used last turn).

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

## Blood Pulsar's numbers (0,0,250,100,100,4): 3.5x base, 1x per stack, 3 stacks.
const PULSAR: String = "300"
const SUPREMACY: String = "301"
const POINT_BLANK: String = "302"
const SLASH: String = "10"
const TORNADO: String = "40"
const AEROGA: String = "41"
const STONEGA: String = "42"
const DUALCAST: String = "100"
const POTION: String = "potion"
const LIMIT: String = "30"
const PLAIN_LIMIT: String = "31"
const MONSTER_FIRAJA: String = "900"

const FAST_BLADE: String = "50"
const SAVAGE_BLADE: String = "51"
const SAVAGE_TRUE: String = "52"
const SAVAGE_FALSE: String = "53"
const BLOOD_REND: String = "54"
const TWIN_STRIKE: String = "55"
const FLARE: String = "60"

var catalog: SkillCatalog


## An enemy that casts one monster skill a turn.
class SkillBrain:
	extends EnemyBrain

	var skill_id: String = ""

	func _init(id: String) -> void:
		skill_id = id

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _attacks_left <= 0:
			return turn_over("cast")
		_attacks_left -= 1
		return action(KIND_SKILL, skill_id)


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	catalog = Fixtures.catalog()
	var magic: Dictionary = {"attack_type": BattleSkill.ATTACK_MAGIC}
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	_ability(PULSAR, Fixtures.record("Blood Pulsar", [[1, 1, 72, [0, 0, 250, 100, 100, 4]]], "10:100", magic))
	_ability(SUPREMACY, Fixtures.record("Supremacy", [[1, 1, 126, [1, 0, 0, 600, 100, 100, 7]]], "10:100", physical))
	_ability(POINT_BLANK, Fixtures.record("Point-Blank Shot", [[1, 1, 1007, [0, 0, 110, 100, 100, 2]]], "10:100", physical))
	_ability(SLASH, Fixtures.record("Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_spell(TORNADO, "Tornado", Fixtures.skill_record("Tornado", 15, Fixtures.magic_params(100), "10:100"))
	# 1.5x base, 0.5x per stack, 3 stacks.
	_spell(AEROGA, "Aeroga V", Fixtures.skill_record("Aeroga V", 72, [0, 0, 100, 50, 50, 4], "10:100"))
	_spell(STONEGA, "Stonega V", Fixtures.skill_record("Stonega V", 72, [0, 0, 100, 50, 50, 4], "10:100"))
	_ability(DUALCAST, Fixtures.record("Dualcast", [[0, 3, 45, ["none"]]], ""))
	catalog.add_record(BattleSkill.KIND_ITEM, POTION, Fixtures.record("Potion", [[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 16, [200]]]))
	catalog.add_record(BattleSkill.KIND_LIMIT_BURST, LIMIT, {
		"name": "Stacking Blade",
		"attack_type": BattleSkill.ATTACK_PHYSICAL,
		"levels": [[8, [[1, 1, 126, [1, 0, 0, 200, 100, 100, 3]]]]],
		"attack_frames": [[10]],
		"attack_damage": [[100]],
	})
	catalog.add_record(BattleSkill.KIND_LIMIT_BURST, PLAIN_LIMIT, {
		"name": "Plain Blade",
		"attack_type": BattleSkill.ATTACK_PHYSICAL,
		"levels": [[8, [[1, 1, 1, Fixtures.physical_params(100)]]]],
		"attack_frames": [[10]],
		"attack_damage": [[100]],
	})
	# Firaja's monster row: the initial cast takes the first increment, each stack the second.
	catalog.add_record(BattleSkill.KIND_MONSTER, MONSTER_FIRAJA, Fixtures.record("Firaja", [[1, 1, 72, [0, 0, 0, 210, 230, 3]]], "10:100", magic))

	_ability(FAST_BLADE, Fixtures.record("Fast Blade", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_ability(SAVAGE_TRUE, Fixtures.record("Savage Blade (after Fast Blade)", [[1, 1, 1, Fixtures.physical_params(300)]], "10:100", physical))
	_ability(SAVAGE_FALSE, Fixtures.record("Savage Blade", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	# A one-id condition list arrives as plain numbers, as in most rows.
	_ability(SAVAGE_BLADE, Fixtures.record("Savage Blade", [[1, 1, 99, [2, int(FAST_BLADE), 2, int(SAVAGE_TRUE), 2, int(SAVAGE_FALSE)]]], ""))
	# Blood Rend 910223: a magic condition (type 1), Flare.
	_ability(BLOOD_REND, Fixtures.record("Blood Rend", [[1, 1, 99, [[1], [int(FLARE)], 2, int(SAVAGE_TRUE), 2, int(SAVAGE_FALSE)]]], ""))
	_spell(FLARE, "Flare", Fixtures.skill_record("Flare", 15, Fixtures.magic_params(100), "10:100"))
	# An ability with Flare's id: not the condition, which names the spell.
	_ability(FLARE, Fixtures.record("Flare Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_ability(TWIN_STRIKE, Fixtures.record("Twin Strike", [[0, 3, 53, [2, int(TWIN_STRIKE), -1,
		[int(FAST_BLADE), int(SAVAGE_BLADE), int(SLASH)], 1, 0]]], ""))


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


func _spell(id: String, _spell_name: String, data: Dictionary) -> void:
	data["magic_type"] = "Black"
	catalog.add_record(BattleSkill.KIND_MAGIC, id, data)


func _skill(id: String) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_ABILITY, id)


func _cast(id: String) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_MAGIC, id)


func _dualcast(first: BattleCommand, second: BattleCommand) -> BattleCommand:
	var picks: Array[BattleCommand] = [first, second]
	return BattleCommand.multicast(DUALCAST, picks)


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


## The stacks of each action `unit` started (-1 for non-stacking ones).
func _stacks(battle: BattleEngine, unit: Combatant) -> Array[int]:
	var out: Array[int] = []
	for event in Fixtures.actions_by(battle, unit.id):
		out.append(int(event["stacks"]))
	return out


## The executed skill id of each action `unit` started.
func _ran(battle: BattleEngine, unit: Combatant) -> Array[String]:
	var out: Array[String] = []
	for event in Fixtures.actions_by(battle, unit.id):
		out.append(str(event["executed_skill_id"]))
	return out


# --- Stacks ---

func test_a_stacking_ability_adds_a_stack_each_cast_up_to_its_maximum() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle()
	var battle: BattleEngine = _battle([hero], [foe])
	for _i in range(5):
		_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, 1, 2, 3, 3])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [350, 450, 550, 650, 650], "3.5x + 1x per stack, 6.5x at most")
	assert_eq(hero.history.stack_key, "ability:" + PULSAR)
	assert_true(battle.format_event(Fixtures.actions_by(battle, hero.id)[1]).contains("(1 stacks)"))


func test_consecutive_damage_rows_use_the_wiki_base_and_stack() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle()
	var battle: BattleEngine = _battle([hero], [foe])
	_act(battle, hero, _skill(SUPREMACY))
	_act(battle, hero, _skill(SUPREMACY))
	_act(battle, hero, _skill(POINT_BLANK))
	_act(battle, hero, _skill(POINT_BLANK))
	_act(battle, hero, _skill(POINT_BLANK))
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [700, 800, 210, 310, 310],
		"126: 6x + 1x per stack; 1007: 2.1x + 1x, one stack at most; switching resets")


func test_a_normal_attack_or_a_guard_before_the_cast_restarts_the_stack() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, BattleCommand.defend())
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, BattleCommand.attack())
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, 1, -1, 0, 1, -1, 0])


func test_a_dualcast_of_another_spell_then_the_stacking_one_keeps_the_stack_after_a_guard() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _cast(AEROGA))
	_act(battle, hero, _cast(AEROGA))
	_act(battle, hero, BattleCommand.defend())
	_act(battle, hero, _dualcast(_cast(TORNADO), _cast(AEROGA)))
	assert_eq(_stacks(battle, hero), [0, 1, -1, -1, 2], "Aeroga V > guard > Tornado + Aeroga V keeps it")

	_act(battle, hero, BattleCommand.defend())
	_act(battle, hero, BattleCommand.attack())
	_act(battle, hero, BattleCommand.defend())
	_act(battle, hero, _dualcast(_cast(TORNADO), _cast(AEROGA)))
	assert_eq(_stacks(battle, hero).back(), 3, "however many attacks and guards came first")

	_act(battle, hero, BattleCommand.defend())
	_act(battle, hero, _dualcast(_cast(AEROGA), _cast(TORNADO)))
	assert_eq(_stacks(battle, hero)[-2], 0, "the stacking spell first: its previous action is the guard")


func test_other_abilities_items_and_limit_bursts_keep_the_stack() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"limit_burst_id": LIMIT, "max_lb": 800})
	var battle: BattleEngine = _battle([hero])
	battle.item_stock = {POTION: 1}
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, _skill(SLASH))
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, BattleCommand.item(POTION, hero.id))
	_act(battle, hero, _skill(PULSAR))
	battle.debug_edit(hero.id, &"lb", 800)
	_act(battle, hero, BattleCommand.limit_burst(PLAIN_LIMIT))
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, -1, 1, -1, 2, -1, 3])
	battle.debug_edit(hero.id, &"lb", 800)
	_act(battle, hero, BattleCommand.limit_burst(LIMIT))
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero).slice(-2), [0, 0], "a stacking limit burst takes the stack over")


func test_a_stacking_limit_burst_stacks_on_consecutive_uses() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"limit_burst_id": LIMIT, "max_lb": 800})
	var foe: Combatant = _idle()
	var battle: BattleEngine = _battle([hero], [foe])
	for _i in range(2):
		battle.debug_edit(hero.id, &"lb", 800)
		_act(battle, hero, BattleCommand.limit_burst(LIMIT))
	assert_eq(_stacks(battle, hero), [0, 1])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [300, 400])


func test_another_stacking_ability_takes_the_stack_over() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _cast(AEROGA))
	_act(battle, hero, _cast(AEROGA))
	_act(battle, hero, _cast(STONEGA))
	_act(battle, hero, _cast(AEROGA))
	assert_eq(_stacks(battle, hero), [0, 1, 0, 0], "Aeroga V followed by Stonega V resets")


func test_each_cast_of_a_dualcast_counts() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle()
	var battle: BattleEngine = _battle([hero], [foe])
	_act(battle, hero, _dualcast(_cast(AEROGA), _cast(AEROGA)))
	_act(battle, hero, _dualcast(_cast(AEROGA), _cast(TORNADO)))
	_act(battle, hero, _cast(AEROGA))
	assert_eq(_stacks(battle, hero), [0, 1, 2, -1, 3])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [150, 200, 250, 100, 300])


func test_dying_clears_the_stack_even_with_a_reraise() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle()
	var battle: BattleEngine = _battle([hero], [foe])
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, _skill(PULSAR))
	hero.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 50, 3))
	battle.kill(hero, foe.id, null)
	assert_true(hero.is_alive(), "the reraise brought it back")
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, 1, 0])


func test_a_turn_lost_to_an_ailment_keeps_the_stack() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(PULSAR))
	assert_eq(battle.debug_edit(hero.id, &"ailment", 1, "STOP"), BattleEngine.OK)
	var next_turn: int = battle.total_turns + 1
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.total_turns == next_turn), "the stopped hero's turn passes")
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, 1])


func test_each_unit_has_its_own_stack() -> void:
	var first: Combatant = Fixtures.unit("First")
	var second: Combatant = Fixtures.unit("Second")
	var battle: BattleEngine = _battle([first, second])
	_turn(battle, [[first, _skill(PULSAR)], [second, _skill(SLASH)]])
	_turn(battle, [[first, _skill(PULSAR)], [second, _skill(PULSAR)]])
	assert_eq(_stacks(battle, first), [0, 1])
	assert_eq(_stacks(battle, second), [-1, 0])


func test_a_confused_units_attack_resets_the_stack() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(PULSAR))
	_act(battle, hero, _skill(PULSAR))
	battle.debug_edit(hero.id, &"ailment", 1, "CONFUSION")
	_act(battle, hero, _skill(PULSAR))
	battle.debug_edit(hero.id, &"ailment", 0, "CONFUSION")
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, 1, -1, 0], "the confused cast became a normal attack")


func test_an_enemy_stacks_by_the_same_rules() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"hp": 5000})
	var foe: Combatant = Fixtures.monster("Bomb", {"brain": SkillBrain.new(MONSTER_FIRAJA)})
	var battle: BattleEngine = _battle([hero], [foe])
	for _i in range(3):
		_act(battle, hero, BattleCommand.defend())
	assert_eq(_stacks(battle, foe), [0, 1, 2])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [105, 220, 335], "2.1x, then 2.3x per stack, halved by the guard")


func test_the_stack_carries_into_the_next_wave() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [_idle({"hp": 100})], null, catalog)
	battle.queue_wave(func() -> Array: return [_idle()])
	battle.start()
	assert_eq(battle.execute(hero.id, _skill(PULSAR)), BattleEngine.OK)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED))
	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	_act(battle, hero, _skill(PULSAR))
	assert_eq(_stacks(battle, hero), [0, 1])


# --- Op 99 ---

func test_op_99_takes_the_true_skill_the_turn_after_a_condition_skill() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(SAVAGE_BLADE))
	_act(battle, hero, _skill(FAST_BLADE))
	assert_eq(battle.executed_skill(hero.id, _skill(SAVAGE_BLADE)).id, SAVAGE_TRUE, "the menu sees the branch")
	_act(battle, hero, _skill(SAVAGE_BLADE))
	_act(battle, hero, _skill(SAVAGE_BLADE))
	assert_eq(_ran(battle, hero), [SAVAGE_FALSE, FAST_BLADE, SAVAGE_TRUE, SAVAGE_FALSE],
		"Fast Blade two turns earlier does not count")
	var started: Dictionary = Fixtures.actions_by(battle, hero.id)[2]
	assert_eq(started["skill_id"], SAVAGE_BLADE, "the event names the skill the command chose")


func test_op_99_ignores_what_the_unit_did_earlier_the_same_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _twin(FAST_BLADE, SAVAGE_BLADE))
	_act(battle, hero, _twin(SLASH, SAVAGE_BLADE))
	assert_eq(_ran(battle, hero), [FAST_BLADE, SAVAGE_FALSE, SLASH, SAVAGE_TRUE],
		"the same turn does not count; the next turn does, whatever came first")


func test_op_99_reads_the_condition_skill_type() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = _battle([hero])
	_act(battle, hero, _skill(FLARE))
	_act(battle, hero, _skill(BLOOD_REND))
	_act(battle, hero, _cast(FLARE))
	_act(battle, hero, _skill(BLOOD_REND))
	assert_eq(_ran(battle, hero), [FLARE, SAVAGE_FALSE, FLARE, SAVAGE_TRUE], "type 1 is the spell, not the ability with its id")


func test_op_99_after_a_wave_and_after_a_ko() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle({"hp": 50})
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.queue_wave(func() -> Array: return [_idle()])
	battle.start()
	assert_eq(battle.execute(hero.id, _skill(FAST_BLADE)), BattleEngine.OK)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED))
	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	_act(battle, hero, _skill(SAVAGE_BLADE))
	_act(battle, hero, _skill(FAST_BLADE))
	hero.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 50, 3))
	battle.kill(hero, battle.enemies[0].id, null)
	_act(battle, hero, _skill(SAVAGE_BLADE))
	assert_eq(_ran(battle, hero), [FAST_BLADE, SAVAGE_TRUE, FAST_BLADE, SAVAGE_FALSE], "the wave keeps it, KO clears it")


# --- Real data ---

func test_the_database_rows_read_as_the_wiki_numbers() -> void:
	var data := DatabaseSkillCatalog.new()
	var pulsar: BattleSkill = data.get_skill(BattleSkill.KIND_ABILITY, "910225")
	var effect: SkillEffect = SkillHistory.stacking_effect(pulsar)
	assert_eq(effect.type, "CONSECUTIVE_MAG_DAMAGE")
	assert_eq(SkillHistory.max_stacks_of(pulsar), 3, "Blood Pulsar stacks 3 times")
	assert_eq([SkillHistory.stacked_modifier(effect, 0), SkillHistory.stacked_modifier(effect, 3)], [350.0, 650.0], "3.5x, 6.5x at most")
	var fire_from_below: BattleSkill = data.get_skill(BattleSkill.KIND_ABILITY, "204980")
	effect = SkillHistory.stacking_effect(fire_from_below)
	assert_eq(SkillHistory.max_stacks_of(fire_from_below), 9)
	assert_eq([SkillHistory.stacked_modifier(effect, 0), SkillHistory.stacked_modifier(effect, 9)], [200.0, 2000.0],
		"a modifier slot of 0: 2x base, 20x at most")
	var supremacy: BattleSkill = data.get_skill(BattleSkill.KIND_ABILITY, "228051")
	assert_eq(SkillHistory.stacking_effect(supremacy).type, "CONSECUTIVE_PHYS_DAMAGE")
	assert_eq(SkillHistory.stacked_modifier(SkillHistory.stacking_effect(supremacy), 0), 700.0)


func test_savage_blade_after_fast_blade_from_the_database() -> void:
	var hero: Combatant = Fixtures.unit("Thancred", {"mp": 500, "max_mp": 500})
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, DatabaseSkillCatalog.new())
	battle.start()
	assert_eq(battle.executed_skill(hero.id, _skill("207790")).id, "500540", "without Fast Blade")
	_act(battle, hero, _skill("207780"))
	assert_eq(battle.executed_skill(hero.id, _skill("207790")).id, "500530", "the turn after Fast Blade")
	_act(battle, hero, _skill("207790"))
	assert_eq(_ran(battle, hero), ["207780", "500530"])
