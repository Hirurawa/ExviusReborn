extends "res://tests/test_case.gd"

## Multicast commands (Multicast): what a command may pick, the checks while the player
## picks (costs summed, nothing paid, limited skills once), and casting: each pick its
## own action, rules.cast_gap_frames after the previous pick's start, paying and
## computing its damage when it is cast, swinging with the right hand only.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const FIRE: int = 1
const ICE: int = 2

const DUALCAST: String = "100"
const DUAL_BLACK_MAGIC: String = "101"
const TRIPLE_WHITE_MAGIC: String = "102"
const CHAINSPELL: String = "103"
const DUAL_WHITE_GREEN: String = "104"
const TRIPLE_BLADE: String = "105"
const DUAL_FANGS: String = "106"
const DELAY_ATTACK: String = "107"
const SPEED_DRINK: String = "108"

const FIRE_SPELL: String = "20"
const BLIZZARD: String = "21"
const HOLY: String = "22"
const BUBBLE: String = "23"
const WHITE_WIND: String = "24"

const SLASH: String = "10"
const ARMOR_BREAK: String = "11"
const STRIKE_CD: String = "12"
const STRIKE_TWICE: String = "13"
const ROUGH_DIVIDE: String = "14"
const ORB_STRIKE: String = "15"

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()
	_magic(FIRE_SPELL, "Fire", "Black", [FIRE])
	_magic(BLIZZARD, "Blizzard", "Black", [ICE])
	_magic(HOLY, "Holy", "White")
	_magic(BUBBLE, "Bubble", "Green")
	_magic(WHITE_WIND, "White Wind", "Blue")
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL, "cost": {"MP": 5}}
	_ability(SLASH, Fixtures.record("Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_ability(ARMOR_BREAK, Fixtures.record("Armor Break", [[1, 1, 24, [0, -50, 0, 0, 3, 1]]], "10:100"))
	# "One use every 3 turns", ready at once; and two uses per battle. Both wrap Slash.
	_ability(STRIKE_CD, Fixtures.record("Strike (CD)", [[1, 1, 130, [10, 1, [2, 2], 0]]], ""))
	_ability(STRIKE_TWICE, Fixtures.record("Strike (2 uses)", [[1, 1, 157, [10, 0, 2, 2, 1, 1, 0, 0, 0]]], ""))
	_ability(ROUGH_DIVIDE, Fixtures.record("Rough Divide", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100",
		{"attack_type": BattleSkill.ATTACK_PHYSICAL, "alternate_cost": {"type": 2, "amount": 400}}))
	_ability(ORB_STRIKE, Fixtures.record("Orb Strike", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100",
		{"attack_type": BattleSkill.ATTACK_PHYSICAL, "alternate_cost": {"type": 1, "amount": 2}}))

	_ability(DUALCAST, Fixtures.record("Dualcast", [[0, 3, 45, ["none"]]], ""))
	_ability(DUAL_BLACK_MAGIC, Fixtures.record("Dual Black Magic", [[0, 3, 44, ["none"]]], ""))
	_ability(TRIPLE_WHITE_MAGIC, Fixtures.record("Triple White Magic", [[0, 3, 97, [2, 3, 102, 2, 1]]], ""))
	_ability(CHAINSPELL, Fixtures.record("Chainspell", [[0, 3, 52, [0, 3, 103]]], ""))
	_ability(DUAL_WHITE_GREEN, Fixtures.record("Dual White/Green Magic", [[0, 3, 52, [2, 3, 2, 2, 104, 104]]], ""))
	# Its list holds itself and another command, as 68 and 12 lists in the data do.
	_ability(TRIPLE_BLADE, Fixtures.record("Triple Blade", [[0, 3, 53, [3, 105, -1,
		[10, 11, 12, 13, 14, 15, 105, 100], 1, 0]]], ""))
	# A one-ability list arrives as a plain number (Dual Fangs 230808).
	_ability(DUAL_FANGS, Fixtures.record("Dual Fangs", [[0, 3, 98, [2, 106, -1, 10, 2, 1, 1, 0]]], ""))
	# Grants, not commands: 98 next to another effect, and a single 98 with an MP cost.
	_ability(DELAY_ATTACK, Fixtures.record("Delay Attack", [[1, 1, 1, Fixtures.physical_params(100)],
		[0, 3, 98, [2, 106, -1, [10], 2, 1, 1]]], "10:100"))
	_ability(SPEED_DRINK, Fixtures.record("Speed Drink", [[0, 3, 98, [2, 106, -1, [10], 3, 1, 1, 0]]], "", {"cost": {"MP": 12}}))


func _magic(id: String, magic_name: String, magic_type: String, elements: Array = [], frames: String = "10:100") -> void:
	var data: Dictionary = Fixtures.skill_record(magic_name, 15, Fixtures.magic_params(100), frames, 1, 1, 10, elements)
	data["magic_type"] = magic_type
	catalog.add_record(BattleSkill.KIND_MAGIC, id, data)


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


func _rule(id: String) -> Multicast.Rule:
	return Multicast.rule_for(catalog.get_skill(BattleSkill.KIND_ABILITY, id))


func _allows(rule: Multicast.Rule, kind: StringName, id: String) -> bool:
	return Multicast.allows(rule, catalog.get_skill(kind, id))


func _spell(id: String, target: int = -1) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_MAGIC, id, target)


func _skill(id: String, target: int = -1) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_ABILITY, id, target)


func _multicast(command_id: String, picks: Array, target: int = -1) -> BattleCommand:
	var typed: Array[BattleCommand] = []
	for pick in picks:
		typed.append(pick)
	return BattleCommand.multicast(command_id, typed, target)


func _picks(picks: Array) -> Array[BattleCommand]:
	var typed: Array[BattleCommand] = []
	for pick in picks:
		typed.append(pick)
	return typed


## An enemy that passes its turns.
func _idle(monster_name: String, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(monster_name, full)


## Runs the rest of turn 1 (the enemies pass), so every pick has been cast.
func _finish_turn(battle: BattleEngine) -> void:
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.turn == 2), "turn 2 starts")


func _frames(events: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for event in events:
		out.append(int(event["frame"]))
	return out


# --- Which abilities are commands, and what they pick ---

func test_each_command_picks_its_own_kind_of_skill() -> void:
	var dualcast: Multicast.Rule = _rule(DUALCAST)
	assert_eq(dualcast.count, 2)
	for id in [FIRE_SPELL, HOLY, BUBBLE, WHITE_WIND]:
		assert_true(_allows(dualcast, BattleSkill.KIND_MAGIC, id), "Dualcast casts any magic: %s" % id)
	assert_false(_allows(dualcast, BattleSkill.KIND_ABILITY, SLASH), "no abilities")

	var black: Multicast.Rule = _rule(DUAL_BLACK_MAGIC)
	assert_eq(black.count, 2)
	assert_true(_allows(black, BattleSkill.KIND_MAGIC, FIRE_SPELL))
	assert_false(_allows(black, BattleSkill.KIND_MAGIC, HOLY), "black magic only")

	# Op 97 counts 2 as white, where the magic table's 2 is black.
	var white: Multicast.Rule = _rule(TRIPLE_WHITE_MAGIC)
	assert_eq(white.count, 3)
	assert_true(_allows(white, BattleSkill.KIND_MAGIC, HOLY))
	assert_false(_allows(white, BattleSkill.KIND_MAGIC, FIRE_SPELL))

	var chainspell: Multicast.Rule = _rule(CHAINSPELL)
	assert_eq(chainspell.count, 3, "short op 52")
	assert_true(_allows(chainspell, BattleSkill.KIND_MAGIC, BUBBLE))

	var white_green: Multicast.Rule = _rule(DUAL_WHITE_GREEN)
	assert_eq(white_green.count, 2)
	assert_true(_allows(white_green, BattleSkill.KIND_MAGIC, HOLY))
	assert_true(_allows(white_green, BattleSkill.KIND_MAGIC, BUBBLE))
	assert_false(_allows(white_green, BattleSkill.KIND_MAGIC, FIRE_SPELL))

	var blade: Multicast.Rule = _rule(TRIPLE_BLADE)
	assert_eq(blade.count, 3)
	assert_true(_allows(blade, BattleSkill.KIND_ABILITY, SLASH))
	assert_true(_allows(blade, BattleSkill.KIND_ABILITY, STRIKE_CD), "a cooldown wrapper is listed by its own id")
	assert_false(_allows(blade, BattleSkill.KIND_MAGIC, FIRE_SPELL), "not magic")
	assert_false(_allows(blade, BattleSkill.KIND_ABILITY, TRIPLE_BLADE), "not itself, though its list has it")
	assert_false(_allows(blade, BattleSkill.KIND_ABILITY, DUALCAST), "not another command, though its list has it")
	assert_false(_allows(blade, BattleSkill.KIND_ABILITY, DELAY_ATTACK), "not an unlisted ability")

	var fangs: Multicast.Rule = _rule(DUAL_FANGS)
	assert_eq(fangs.count, 2)
	assert_true(_allows(fangs, BattleSkill.KIND_ABILITY, SLASH), "a one-id list")
	assert_false(_allows(fangs, BattleSkill.KIND_ABILITY, ARMOR_BREAK))


func test_a_command_a_passive_gives_picks_what_the_passive_says() -> void:
	# Dual Fangs' record picks Slash twice; the passive giving it says three times, from
	# Slash and Armor Break.
	var passives: Dictionary = {"multicast_commands": [DUAL_FANGS], "multicast_picks": {DUAL_FANGS: {"count": 3, "skill_ids": [ARMOR_BREAK]}}}
	var owner: Combatant = Fixtures.unit("Owner", {"passives": passives})
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = Fixtures.engine([owner, other], [_idle("Foe")], null, catalog)
	battle.start()
	var fangs: BattleCommand = _skill(DUAL_FANGS)
	var rule: Multicast.Rule = battle.multicast_rule(owner.id, fangs)
	assert_eq(rule.count, 3, "the passive's count")
	assert_true(Multicast.allows(rule, catalog.get_skill(BattleSkill.KIND_ABILITY, ARMOR_BREAK)), "the passive's list")
	assert_true(Multicast.allows(rule, catalog.get_skill(BattleSkill.KIND_ABILITY, SLASH)), "and the record's")
	assert_eq(battle.multicast_pick_problem(owner.id, fangs, _picks([_skill(SLASH)]), _skill(ARMOR_BREAK)), BattleEngine.OK)
	assert_eq(battle.can_execute(owner.id, _multicast(DUAL_FANGS, [_skill(SLASH), _skill(ARMOR_BREAK), _skill(SLASH)])), BattleEngine.OK)
	assert_eq(battle.multicast_rule(other.id, fangs).count, 2, "a unit without the passive reads the record")
	assert_eq(battle.multicast_pick_problem(other.id, fangs, _picks([]), _skill(ARMOR_BREAK)), BattleEngine.REJECT_NOT_MULTICASTABLE)


func test_abilities_that_grant_a_command_are_not_commands() -> void:
	assert_null(_rule(DELAY_ATTACK), "98 next to another effect grants")
	assert_null(_rule(SPEED_DRINK), "a single 98 with an MP cost grants")
	assert_null(_rule(SLASH))
	assert_null(Multicast.rule_for(catalog.get_skill(BattleSkill.KIND_MAGIC, FIRE_SPELL)))


# --- Picking: checks only ---

func test_picks_add_up_their_costs_without_paying_anything() -> void:
	var mage: Combatant = Fixtures.unit("Mage", {"mp": 25, "lb": 500, "max_lb": 2000})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([mage], [foe], null, catalog)
	battle.start()
	battle.debug_edit(mage.id, &"orbs", 3)
	var events_before: int = battle.events.size()
	var chainspell: BattleCommand = _multicast(CHAINSPELL, [])
	assert_eq(battle.multicast_rule(mage.id, chainspell).count, 3)
	assert_eq(battle.multicast_pick_problem(mage.id, chainspell, _picks([]), _spell(FIRE_SPELL)), BattleEngine.OK)
	assert_eq(battle.multicast_pick_problem(mage.id, chainspell, _picks([_spell(FIRE_SPELL)]), _spell(FIRE_SPELL)),
		BattleEngine.OK, "the same spell again: 20 of 25 MP")
	assert_eq(battle.multicast_pick_problem(mage.id, chainspell, _picks([_spell(FIRE_SPELL), _spell(FIRE_SPELL)]), _spell(FIRE_SPELL)),
		BattleEngine.REJECT_NOT_ENOUGH_MP, "a third would need 30")

	var blade: BattleCommand = _multicast(TRIPLE_BLADE, [])
	assert_eq(battle.multicast_pick_problem(mage.id, blade, _picks([_skill(ROUGH_DIVIDE)]), _skill(ROUGH_DIVIDE)),
		BattleEngine.REJECT_LIMIT_NOT_FULL, "8 crystals of LB gauge, the unit has 5")
	assert_eq(battle.multicast_pick_problem(mage.id, blade, _picks([_skill(ORB_STRIKE)]), _skill(ORB_STRIKE)),
		BattleEngine.REJECT_NOT_ENOUGH_ORBS, "4 orbs, the party has 3")
	assert_eq(battle.multicast_pick_problem(mage.id, blade, _picks([_skill(SLASH), _skill(SLASH)]), _skill(SLASH)),
		BattleEngine.OK, "an unlimited ability three times")
	assert_eq([mage.mp, mage.lb, battle.esper_orbs], [25, 500, 3], "nothing is paid")
	assert_eq(battle.events.size(), events_before, "nothing happens")
	assert_false(mage.acted)


func test_a_skill_with_a_cooldown_or_a_use_limit_is_picked_once() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	var blade: BattleCommand = _multicast(TRIPLE_BLADE, [])
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([]), _skill(STRIKE_CD)), BattleEngine.OK)
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([_skill(STRIKE_CD)]), _skill(STRIKE_CD)),
		BattleEngine.REJECT_SKILL_NOT_READY)
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([_skill(SLASH)]), _skill(STRIKE_TWICE)), BattleEngine.OK)
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([_skill(STRIKE_TWICE)]), _skill(STRIKE_TWICE)),
		BattleEngine.REJECT_NO_USES_LEFT, "two uses left, still once per multicast")

	assert_eq(battle.execute(hero.id, _multicast(TRIPLE_BLADE, [_skill(STRIKE_CD), _skill(STRIKE_TWICE), _skill(SLASH)], foe.id)), BattleEngine.OK)
	_finish_turn(battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [100, 100, 100], "both wrappers ran Slash")
	assert_eq(battle.skill_limits(hero.id, _skill(STRIKE_CD)), {"uses_left": -1, "ready_turn": 4}, "spent when cast")
	assert_eq(int(battle.skill_limits(hero.id, _skill(STRIKE_TWICE))["uses_left"]), 1)


func test_what_a_command_cannot_pick_is_refused() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"limit_burst_id": "1", "max_lb": 100})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	var dualcast: BattleCommand = _multicast(DUALCAST, [])
	var blade: BattleCommand = _multicast(TRIPLE_BLADE, [])
	assert_eq(battle.multicast_pick_problem(hero.id, dualcast, _picks([]), _skill(SLASH)), BattleEngine.REJECT_NOT_MULTICASTABLE)
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([]), _skill(TRIPLE_BLADE)), BattleEngine.REJECT_NOT_MULTICASTABLE)
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([]), _skill(DUALCAST)), BattleEngine.REJECT_NOT_MULTICASTABLE)
	assert_eq(battle.multicast_pick_problem(hero.id, blade, _picks([]), BattleCommand.limit_burst("1")), BattleEngine.REJECT_NOT_MULTICASTABLE)
	assert_eq(battle.multicast_pick_problem(hero.id, _skill(SLASH), _picks([]), _skill(SLASH)), BattleEngine.REJECT_NOT_MULTICASTABLE,
		"Slash is no command")
	assert_null(battle.multicast_rule(hero.id, _skill(SLASH)))

	assert_eq(battle.can_execute(hero.id, dualcast), BattleEngine.REJECT_MULTICAST_INCOMPLETE, "no picks")
	assert_eq(battle.can_execute(hero.id, _multicast(DUALCAST, [_spell(FIRE_SPELL)])), BattleEngine.REJECT_MULTICAST_INCOMPLETE)
	assert_eq(battle.can_execute(hero.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _spell(FIRE_SPELL), _spell(FIRE_SPELL)])),
		BattleEngine.REJECT_MULTICAST_INCOMPLETE, "too many")
	assert_eq(battle.can_execute(hero.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _skill(SLASH)])), BattleEngine.REJECT_NOT_MULTICASTABLE)
	assert_eq(battle.can_execute(hero.id, _multicast(SLASH, [_skill(SLASH)])), BattleEngine.REJECT_NOT_MULTICASTABLE,
		"picks on a skill that is no command")

	battle.debug_edit(hero.id, &"ailment", 1, "SILENCE")
	assert_eq(battle.multicast_pick_problem(hero.id, dualcast, _picks([]), _spell(FIRE_SPELL)), BattleEngine.REJECT_SILENCED)
	assert_eq(battle.can_execute(hero.id, _multicast(TRIPLE_BLADE, [_skill(SLASH), _skill(SLASH), _skill(SLASH)])), BattleEngine.OK,
		"silence leaves an ability multicast alone")
	assert_eq(battle.execute(hero.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _spell(BLIZZARD)])), BattleEngine.REJECT_SILENCED)
	assert_false(hero.acted)


# --- Casting ---

func test_each_pick_is_its_own_action_a_cast_gap_after_the_previous_start() -> void:
	var mage: Combatant = Fixtures.unit("Mage", {"mp": 100})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([mage], [foe], null, catalog)
	battle.start()
	var start: int = battle.frame
	assert_eq(battle.execute(mage.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _spell(BLIZZARD)], foe.id)), BattleEngine.OK)
	assert_true(mage.acted)
	assert_eq(mage.mp, 90, "only the first pick is paid so far")
	battle.advance(20)
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "the phase waits for the second pick")
	_finish_turn(battle)
	assert_eq(mage.mp, 80)

	var started: Array[Dictionary] = Fixtures.actions_by(battle, mage.id)
	assert_eq(started.size(), 2, "the command is not an action, its picks are")
	assert_eq(_frames(started), [start, start + 39])
	for i in range(started.size()):
		assert_eq([started[i]["skill_id"], started[i]["multicast_skill_id"], int(started[i]["multicast_index"]), int(started[i]["multicast_count"])],
			[[FIRE_SPELL, BLIZZARD][i], DUALCAST, i, 2])
		assert_eq(int(started[i]["origin"]), BattleAction.Origin.COMMAND)
		assert_eq(int(started[i]["target"]), foe.id, "picks without a target take the command's")
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(_frames(hits), [start + 10, start + 49])
	assert_eq([Array(hits[0]["elements"]), Array(hits[1]["elements"])], [[FIRE], [ICE]], "each pick keeps its elements")
	assert_eq(battle.events.count_of_type(BattleEventLog.COST_PAID), 2, "each pick pays when it is cast")
	assert_eq(mage.last_command.picks.size(), 2, "Repeat gets the picks back")
	assert_true(battle.format_event(started[1]).contains("multicast %s, 2 of 2" % DUALCAST))


func test_a_long_pick_overlaps_the_next_one() -> void:
	_magic("25", "Flare", "Black", [], "10:25-30:25-50:25-70:25")
	var mage: Combatant = Fixtures.unit("Mage")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([mage], [foe], null, catalog)
	battle.start()
	var start: int = battle.frame
	battle.execute(mage.id, _multicast(DUAL_BLACK_MAGIC, [_spell("25"), _spell("25")], foe.id))
	_finish_turn(battle)
	assert_eq(_frames(Fixtures.hits(battle, foe.id)), [10, 30, 49, 50, 69, 70, 89, 109].map(func(f: int) -> int: return start + f))


func test_a_later_pick_sees_what_an_earlier_pick_did() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _multicast(TRIPLE_BLADE, [_skill(ARMOR_BREAK), _skill(SLASH), _skill(SLASH)], foe.id))
	_finish_turn(battle)
	# Slash deals 100 against DEF 100; cast after the break lands, against DEF 50: 200.
	# The second Slash follows the unit's own hit, so it starts a new chain: no bonus.
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [200, 200])


func test_a_dual_wielders_picks_swing_once_with_the_right_hand() -> void:
	var hero: Combatant = Fixtures.unit("Dual", {"atk": 350, "hand_atk": [100, 50]})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _multicast(DUAL_FANGS, [_skill(SLASH), _skill(SLASH)], foe.id))
	_finish_turn(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [900, 900], "one swing each, with the right hand's 300 ATK")
	assert_eq([int(hits[0]["swing"]), int(hits[1]["swing"])], [DualWield.RIGHT, DualWield.RIGHT])
	for started in Fixtures.actions_by(battle, hero.id):
		assert_false(bool(started["dual_wield"]))


func test_a_pick_keeps_its_own_target() -> void:
	var mage: Combatant = Fixtures.unit("Mage")
	var near: Combatant = _idle("Near")
	var far: Combatant = _idle("Far")
	var battle: BattleEngine = Fixtures.engine([mage], [near, far], null, catalog)
	battle.start()
	battle.queue_command(mage.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _spell(BLIZZARD, near.id)]))
	battle.set_target(mage.id, far.id)
	battle.execute(mage.id)
	_finish_turn(battle)
	assert_eq(Fixtures.hits(battle, far.id).size(), 1, "Fire takes the command's target")
	assert_eq(Fixtures.hits(battle, near.id).size(), 1, "Blizzard keeps its own")


func test_a_caster_down_between_picks_drops_the_rest() -> void:
	var mage: Combatant = Fixtures.unit("Mage")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([mage, Fixtures.unit("Friend")], [foe], null, catalog)
	battle.start()
	battle.execute(mage.id, _multicast(CHAINSPELL, [_spell(FIRE_SPELL), _spell(FIRE_SPELL), _spell(FIRE_SPELL)], foe.id))
	battle.advance(20)
	battle.debug_edit(mage.id, &"hp", 0)
	battle.advance(40)
	assert_eq(Fixtures.actions_by(battle, mage.id).size(), 1)
	var dropped: Array[Dictionary] = battle.events.of_type(BattleEventLog.MULTICAST_CAST_DROPPED)
	assert_eq(dropped.size(), 2)
	for i in range(dropped.size()):
		assert_eq([int(dropped[i]["index"]), dropped[i]["reason"], dropped[i]["multicast_skill_id"]], [i + 1, &"caster_down", CHAINSPELL])
	assert_true(battle.is_idle(), "nothing is left on the timeline")


func test_a_pick_due_after_the_formation_fell_is_dropped() -> void:
	var mage: Combatant = Fixtures.unit("Mage")
	var foe: Combatant = _idle("Foe", {"hp": 50})
	var battle: BattleEngine = Fixtures.engine([mage], [foe], null, catalog)
	battle.start()
	battle.execute(mage.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _spell(FIRE_SPELL)], foe.id))
	assert_true(Fixtures.run_until_ended(battle))
	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)
	var dropped: Dictionary = battle.events.last_of_type(BattleEventLog.MULTICAST_CAST_DROPPED)
	assert_eq([int(dropped["index"]), dropped["reason"]], [1, &"no_opponents"])
	assert_eq(mage.mp, 90, "the dropped pick costs nothing")


func test_a_confused_caster_attacks_instead() -> void:
	var mage: Combatant = Fixtures.unit("Mage")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([mage], [foe], null, catalog)
	battle.start()
	battle.debug_edit(mage.id, &"ailment", 1, "CONFUSION")
	assert_eq(battle.execute(mage.id, _multicast(DUALCAST, [_spell(FIRE_SPELL), _spell(BLIZZARD)], foe.id)), BattleEngine.OK)
	var started: Array[Dictionary] = Fixtures.actions_by(battle, mage.id)
	assert_eq(started.size(), 1)
	assert_eq(str(started[0]["forced_by"]), "CONFUSION")
	assert_eq(mage.mp, 100, "nothing is paid")
