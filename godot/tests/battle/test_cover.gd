extends "res://tests/test_case.gd"

## Cover (CoverTracker, CoverHandler, passive covers): the FFBE wiki's rules and the
## user's (2026-10-01). Rule tests call CoverTracker.decide on a declared action
## directly; the rest run turns through the engine. Combatants come from specs.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog
var _next_action_id: int = 1000


## Plays `decisions` in order, one per action, `attacks_per_turn` actions a turn.
class ScriptBrain:
	extends EnemyBrain
	var decisions: Array = []
	var _played: int = 0

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _attacks_left <= 0 or decisions.is_empty():
			return turn_over("done")
		_attacks_left -= 1
		var decision: Dictionary = decisions[mini(_played, decisions.size() - 1)]
		_played += 1
		return decision


func before_each() -> void:
	catalog = Fixtures.catalog()
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	var magic: Dictionary = {"attack_type": BattleSkill.ATTACK_MAGIC}
	_monster_skill("701", [[2, 1, 1, Fixtures.physical_params(100)]], physical)
	_monster_skill("702", [[1, 1, 1, Fixtures.physical_params(100)]], physical)
	_monster_skill("703", [[1, 1, 15, Fixtures.magic_params(100)]], magic)
	# A magic attack dealing physical damage.
	_monster_skill("704", [[1, 1, 1, Fixtures.physical_params(100)]], magic)
	_monster_skill("705", [[1, 1, 40, [0, 0, 0, 0, 0, 0, 0, 0, 100, 100]]], {"attack_type": BattleSkill.ATTACK_HYBRID})
	# DEF piercing (21) and SPR piercing (70).
	_monster_skill("706", [[1, 1, 21, [0, 0, 100, -50]]], physical)
	_monster_skill("707", [[1, 1, 70, [0, 0, 100, 50]]], magic)
	# Physical damage plus a certain poison, on one target.
	_monster_skill("708", [[1, 1, 1, Fixtures.physical_params(100)], [1, 1, 6, [100, 0, 0, 0, 0, 0, 0, 0, 3]]], physical)
	_monster_skill("709", [[2, 1, 15, Fixtures.magic_params(100)]], magic)
	# Plain physical damage, then DEF-piercing damage, on one target.
	_monster_skill("710", [[1, 1, 1, Fixtures.physical_params(100)], [1, 1, 21, [0, 0, 100, -50]]], physical)


func _monster_skill(skill_id: String, effects_raw: Array, extra: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_MONSTER, skill_id, Fixtures.record("Skill " + skill_id, effects_raw, "20:100", extra))


## An AoE cover status, as opcode 96 puts it on its target.
static func _aoe_cover(chance: int, physical: bool = true, magic: bool = false, mit_min: int = 0, mit_max: int = -1) -> BattleStatus:
	return BattleStatus.make(BattleStatus.COVER, CoverTracker.KEY_AOE, chance, 3, {
		"mit_min": mit_min, "mit_max": mit_min if mit_max < 0 else mit_max,
		"physical": physical, "magic": magic, "protects": -1, "condition": CoverTracker.CONDITION_ANY,
	})


## A passive cover, as PassiveAggregator gives it for opcodes 8 and 59.
static func _passive_cover(chance: int, physical: bool = true, extra: Dictionary = {}) -> Dictionary:
	var cover: Dictionary = {
		"physical": physical, "magic": not physical, "chance": chance, "mit_min": 0, "mit_max": 0,
		"condition": CoverTracker.CONDITION_ANY, "hp_below_pct": 100,
	}
	cover.merge(extra, true)
	return cover


static func _with_covers(unit_name: String, covers: Array, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"passives": {"covers": covers}}
	full.merge(spec, true)
	return Fixtures.unit(unit_name, full)


## Declares an action of `actor` running `skill` on `target` and returns its cover map.
func _decide_skill(battle: BattleEngine, actor: Combatant, skill: BattleSkill, target: Combatant, origin: int = BattleAction.Origin.AI) -> Dictionary:
	var action := BattleAction.new()
	action.id = _next_action_id
	_next_action_id += 1
	action.actor_id = actor.id
	action.origin = origin
	action.skill = skill
	CoverTracker.decide(battle, action, actor, skill, target)
	return action.cover_map


func _decide(battle: BattleEngine, foe: Combatant, skill_id: String, target: Combatant) -> Dictionary:
	return _decide_skill(battle, foe, catalog.get_skill(BattleSkill.KIND_MONSTER, skill_id), target)


func _activations(battle: BattleEngine) -> Array[Dictionary]:
	return battle.events.of_type(BattleEventLog.COVER_ACTIVATED)


## Runs turn 1 (and more with `turns`): the party attacks, then the one enemy plays
## `decisions` (skill ids, each aimed at a party member or null for a random one).
func _run(party: Array, plays: Array, turns: int = 1, battle_rules: BattleRules = null) -> BattleEngine:
	var brain := ScriptBrain.new()
	brain.attacks_per_turn = plays.size()
	var foe: Combatant = Fixtures.monster("Foe", {"brain": brain})
	var battle: BattleEngine = Fixtures.engine(party, [foe], battle_rules, catalog)
	# Party slots exist once the engine holds the party.
	for play in plays:
		var target: Combatant = play[1]
		brain.decisions.append(EnemyBrain.action(EnemyBrain.KIND_SKILL, str(play[0]),
			"disp_order" if target != null else "random", target.slot if target != null else 0))
	for _turn in range(turns):
		if battle.phase == BattleEngine.Phase.SETUP:
			battle.start()
		var ids: Array = []
		for member in party:
			ids.append((member as Combatant).id)
		battle.execute_many(ids)
		var next_turn: int = battle.turn + 1
		Fixtures.run_until(battle, func() -> bool: return battle.turn == next_turn)
	return battle


# --- Which attacks are covered ---

func test_an_aoe_cover_takes_an_area_attack_for_every_ally_against_its_own_def() -> void:
	var tank: Combatant = Fixtures.unit("Tank", {"def": 200})
	var left: Combatant = Fixtures.unit("Left")
	var right: Combatant = Fixtures.unit("Right")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = _run([tank, left, right], [["701", null]])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, tank.id)), [50, 50, 50], "its own share and both allies': 100^2 / 200 each")
	assert_eq(Fixtures.hits(battle, left.id).size() + Fixtures.hits(battle, right.id).size(), 0)
	var activated: Array[Dictionary] = _activations(battle)
	assert_eq(activated.size(), 1)
	if not activated.is_empty():
		assert_eq([activated[0]["coverer"], activated[0]["mode"], activated[0]["protects"]], [tank.id, &"aoe", -1])
	var covered: Array = []
	for event in battle.events.of_type(BattleEventLog.COVERED):
		covered.append([event["target"], event["coverer"]])
	assert_eq(covered, [[left.id, tank.id], [right.id, tank.id]])


func test_cover_follows_the_attack_type_not_the_damage() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	tank.add_status(_aoe_cover(100, true, false))
	var battle: BattleEngine = Fixtures.engine([tank, ally], [foe], null, catalog)
	for case in [["702", true, "physical"], ["703", false, "magic"], ["704", false, "magic attack, physical damage"], ["705", true, "hybrid"]]:
		CoverTracker.reset(battle)
		assert_eq(not _decide(battle, foe, str(case[0]), ally).is_empty(), bool(case[1]), "physical cover against %s" % case[2])
	tank.add_status(_aoe_cover(100, false, true))
	for case in [["702", false, "physical"], ["704", true, "magic attack, physical damage"], ["705", true, "hybrid"]]:
		CoverTracker.reset(battle)
		assert_eq(not _decide(battle, foe, str(case[0]), ally).is_empty(), bool(case[1]), "magic cover against %s" % case[2])


func test_def_piercing_physical_damage_goes_past_cover_and_spr_piercing_does_not() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	tank.add_status(_aoe_cover(100, true, true))
	var battle: BattleEngine = Fixtures.engine([tank, ally], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "706", ally), {}, "ignores DEF")
	assert_eq(_decide(battle, foe, "707", ally), {ally.id: tank.id}, "ignores SPR")


func test_the_def_piercing_part_of_a_covered_attack_still_reaches_its_target() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = _run([tank, ally], [["710", ally]])
	assert_eq(Fixtures.hits(battle, tank.id).size(), 1, "the plain damage")
	assert_eq(Fixtures.hits(battle, ally.id).size(), 1, "the DEF-piercing damage")


func test_only_opponents_attacks_are_covered() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var confused: Combatant = Fixtures.unit("Confused")
	var ally: Combatant = Fixtures.unit("Ally")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = Fixtures.engine([tank, confused, ally], [Fixtures.monster("Foe")], null, catalog)
	assert_eq(_decide_skill(battle, confused, confused.attack_skill, ally, BattleAction.Origin.FORCED), {}, "a confused ally's swing")


func test_enemies_cover_each_other_against_the_party() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var shield: Combatant = Fixtures.monster("Shield", {"brain": IdleEnemyBrain.new()})
	var other: Combatant = Fixtures.monster("Other", {"brain": IdleEnemyBrain.new()})
	shield.add_status(_aoe_cover(100))
	var battle: BattleEngine = Fixtures.engine([hero], [shield, other], null, catalog)
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(other.id))
	battle.advance(5)
	assert_eq(Fixtures.hits(battle, shield.id).size(), 1)
	assert_eq(Fixtures.hits(battle, other.id).size(), 0)


# --- Rolls ---

func test_an_aoe_cover_rolls_once_per_ally_the_attack_reaches() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var party: Array = [tank]
	for i in range(5):
		party.append(Fixtures.unit("Ally %d" % i))
	var foe: Combatant = Fixtures.monster("Foe")
	tank.add_status(_aoe_cover(50))
	var battle: BattleEngine = Fixtures.engine(party, [foe], null, catalog, 11)
	var area: int = 0
	var single: int = 0
	for _i in range(2000):
		CoverTracker.reset(battle)
		if not _decide(battle, foe, "701", party[1]).is_empty():
			area += 1
		CoverTracker.reset(battle)
		if not _decide(battle, foe, "702", party[1]).is_empty():
			single += 1
	# About four standard deviations either way (seed 11's stream runs a little high).
	assert_true(area >= 1905 and area <= 1970, "1 - 0.5^5 = 96.9%%: %d of 2000" % area)
	assert_true(single >= 910 and single <= 1090, "50%%: %d of 2000" % single)


func test_the_mitigation_is_rolled_once_in_whole_percents_and_holds_for_the_turn() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	tank.add_status(_aoe_cover(100, true, false, 50, 70))
	var battle: BattleEngine = _run([tank, ally], [["702", ally], ["702", ally]])
	var activated: Array[Dictionary] = _activations(battle)
	assert_eq(activated.size(), 1, "the second attack finds the cover already triggered")
	if activated.is_empty():
		return
	var mitigation: int = int(activated[0]["mitigation"])
	assert_true(mitigation >= 50 and mitigation <= 70, "rolled %d" % mitigation)
	var amounts: Array[int] = Fixtures.amounts(Fixtures.hits(battle, tank.id))
	assert_eq(amounts.size(), 2)
	for amount in amounts:
		assert_true(absi(amount - (100 - mitigation)) <= 1, "%d after -%d%%" % [amount, mitigation])


func test_the_mitigation_cuts_every_hit_the_coverer_takes_whatever_the_type() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	tank.add_status(_aoe_cover(100, true, false, 50))
	var battle: BattleEngine = _run([tank, ally], [["702", ally], ["703", tank]])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, tank.id)), [50, 50], "the covered physical hit, then a magic hit on itself")


# --- What the coverer takes ---

func test_the_coverer_takes_the_whole_attack_with_its_ailments() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = _run([tank, ally], [["708", ally]])
	assert_eq(Fixtures.hits(battle, tank.id).size(), 1)
	assert_true(tank.has_ailment("POISON"), "the poison went to the coverer")
	assert_false(ally.has_ailment("POISON"))
	assert_eq(ally.hp, ally.max_hp)


# --- ST covers ---

func test_an_st_coverer_protects_one_ally_per_turn() -> void:
	var guard: Combatant = _with_covers("Guard", [_passive_cover(100)])
	var first: Combatant = Fixtures.unit("First")
	var second: Combatant = Fixtures.unit("Second")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([guard, first, second], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "701", first), {first.id: guard.id}, "an area attack: the first ally only")
	assert_eq(_decide(battle, foe, "702", second), {}, "not a second ally that turn")
	assert_eq(_decide(battle, foe, "702", first), {first.id: guard.id}, "the first one stays covered")
	assert_eq(_activations(battle).size(), 1)
	CoverTracker.reset(battle)
	assert_eq(_decide(battle, foe, "702", second), {second.id: guard.id}, "free again next turn")


func test_the_highest_rate_of_a_units_st_covers_is_used() -> void:
	var guard: Combatant = _with_covers("Guard", [
		_passive_cover(30, true, {"mit_min": 10, "mit_max": 10}),
		_passive_cover(75, true, {"mit_min": 50, "mit_max": 50}),
		_passive_cover(90, false),
	])
	var ally: Combatant = Fixtures.unit("Ally")
	var best: Dictionary = CoverTracker.best_st_cover(guard, ally, BattleSkill.ATTACK_PHYSICAL)
	assert_eq([int(best.get("chance", 0)), int(best.get("mit_min", 0))], [75, 50], "the magic one does not count")
	assert_eq(int(CoverTracker.best_st_cover(guard, ally, BattleSkill.ATTACK_HYBRID).get("chance", 0)), 90, "a hybrid attack: either")


func test_a_matching_aoe_cover_overrides_the_units_st_covers() -> void:
	var guard: Combatant = _with_covers("Guard", [_passive_cover(100)])
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	guard.add_status(_aoe_cover(1))
	var battle: BattleEngine = Fixtures.engine([guard, ally], [foe], null, catalog, 3)
	for _i in range(30):
		CoverTracker.reset(battle)
		_decide(battle, foe, "702", ally)
	for event in _activations(battle):
		assert_eq(event["mode"], &"aoe", "the 100% ST cover never rolls")
	guard.add_status(_aoe_cover(100, false, true))
	CoverTracker.reset(battle)
	assert_eq(_decide(battle, foe, "702", ally), {ally.id: guard.id}, "a magic AoE cover leaves physical attacks to the ST cover")
	assert_eq(_activations(battle).back()["mode"], &"st")


func test_an_st_cover_from_118_protects_the_chosen_ally() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "118", Fixtures.record("Royal Guard", [[1, 5, 118, [50, 50, 100, 2, 1, 0]]], "4:100"))
	var knight: Combatant = Fixtures.unit("Knight", {"attack_frames": "4:100"})
	var ward: Combatant = Fixtures.unit("Ward", {"attack_frames": "4:100"})
	var other: Combatant = Fixtures.unit("Other", {"attack_frames": "4:100"})
	var foe: Combatant = Fixtures.monster("Foe", {"brain": IdleEnemyBrain.new()})
	var battle: BattleEngine = Fixtures.engine([knight, ward, other], [foe], null, catalog)
	battle.start()
	battle.execute(knight.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "118", ward.id))
	battle.advance(5)
	var status: BattleStatus = knight.find_status(BattleStatus.COVER, CoverTracker.KEY_ST)
	assert_not_null(status, "the caster covers")
	if status == null:
		return
	assert_eq([status.value, status.turns_left, int(status.params["protects"])], [100, 2, ward.id])
	assert_true(bool(status.params["physical"]) and bool(status.params["magic"]))
	assert_eq(_decide(battle, foe, "702", other), {}, "another ally")
	assert_eq(_decide(battle, foe, "703", ward), {ward.id: knight.id}, "the chosen ally, magic too")


func test_a_cover_condition_reads_the_allys_sex() -> void:
	var gallant: Combatant = _with_covers("Gallant", [_passive_cover(100, true, {"condition": CoverTracker.CONDITION_FEMALE})])
	var her: Combatant = Fixtures.unit("Her", {"sex": Combatant.SEX_FEMALE})
	var him: Combatant = Fixtures.unit("Him", {"sex": Combatant.SEX_MALE})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([gallant, her, him], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "702", him), {})
	assert_eq(_decide(battle, foe, "702", her), {her.id: gallant.id})


func test_an_hp_gated_cover_works_only_while_the_coverers_hp_is_low() -> void:
	var scapegoat: Combatant = _with_covers("Scapegoat", [_passive_cover(100, true, {"hp_below_pct": 30})])
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([scapegoat, ally], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "702", ally), {}, "full HP")
	scapegoat.hp = 300
	assert_eq(_decide(battle, foe, "702", ally), {ally.id: scapegoat.id}, "30% HP")


# --- Who can cover ---

func test_once_an_aoe_cover_triggers_no_other_cover_triggers_that_turn() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var mage: Combatant = _with_covers("Mage", [_passive_cover(100, false)])
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = Fixtures.engine([tank, mage, ally], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "702", ally), {ally.id: tank.id})
	assert_eq(_decide(battle, foe, "703", ally), {}, "the physical cover lets magic through, and the mage is covered")


func test_an_st_coverer_can_be_covered_by_an_aoe_cover_only() -> void:
	var guard: Combatant = _with_covers("Guard", [_passive_cover(100)])
	var squire: Combatant = _with_covers("Squire", [_passive_cover(100)])
	var ward: Combatant = Fixtures.unit("Ward")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([guard, squire, ward], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "702", ward), {ward.id: guard.id})
	assert_eq(_decide(battle, foe, "702", guard), {}, "no ST cover for an ST coverer")
	squire.add_status(_aoe_cover(100))
	assert_eq(_decide(battle, foe, "702", guard), {guard.id: squire.id}, "an AoE cover takes it")


func test_a_disabled_unit_does_not_cover() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = Fixtures.engine([tank, ally], [foe], null, catalog)
	assert_eq(battle.debug_edit(tank.id, &"ailment", 3, "PARALYSIS"), BattleEngine.OK)
	assert_eq(_decide(battle, foe, "702", ally), {})
	battle.rules.disabled_units_cover = true
	assert_eq(_decide(battle, foe, "702", ally), {ally.id: tank.id}, "with the rule switched")


func test_a_ko_ends_the_cover_and_a_reraised_coverer_cannot_cover_again_that_turn() -> void:
	var tank: Combatant = _with_covers("Tank", [_passive_cover(100)])
	var ally: Combatant = Fixtures.unit("Ally")
	var foe: Combatant = Fixtures.monster("Foe")
	tank.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 50, 3))
	var battle: BattleEngine = Fixtures.engine([tank, ally], [foe], null, catalog)
	assert_eq(_decide(battle, foe, "702", ally), {ally.id: tank.id})
	battle.kill(tank, foe.id, null)
	assert_true(tank.is_alive(), "reraised")
	assert_eq(tank.cover_mode, Combatant.COVER_NONE)
	assert_eq(str(battle.events.last_of_type(BattleEventLog.COVER_ENDED).get("reason", "")), "ko")
	assert_eq(_decide(battle, foe, "702", ally), {}, "not again this turn")
	CoverTracker.reset(battle)
	assert_eq(_decide(battle, foe, "702", ally), {ally.id: tank.id}, "next turn")


# --- Turns ---

func test_a_triggered_cover_ends_when_the_next_phase_starts() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var ally: Combatant = Fixtures.unit("Ally")
	tank.add_status(_aoe_cover(100))
	var battle: BattleEngine = _run([tank, ally], [["702", ally]], 2)
	assert_eq(_activations(battle).size(), 2, "it triggers again in the second enemy phase")
	var reasons: Array = []
	for event in battle.events.of_type(BattleEventLog.COVER_ENDED):
		reasons.append(event["reason"])
	assert_eq(reasons, [&"turn_over", &"turn_over"])
	assert_eq(tank.cover_mode, Combatant.COVER_NONE, "turn 3's player phase")


# --- Statuses from opcodes 96 and 118 ---

func test_96_puts_an_aoe_cover_on_its_target_and_the_newest_replaces_the_last() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "96", Fixtures.record("Dawn Guard", [[0, 3, 96, [1, 0, 50, 70, 75, 100, 3, 1, 1]]], "4:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "961", Fixtures.record("Redirect", [[1, 2, 96, [1, 0, 30, 30, 20, 100, 2, 1, 2]]], "4:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "962", Fixtures.record("Old Shield", [[0, 3, 96, [1, 0, 55, 55, 50, 100, 3, 1]]], "4:100"))
	var rules: BattleRules = Fixtures.rules()
	rules.keep_stronger_status = true
	var knight: Combatant = Fixtures.unit("Knight", {"attack_frames": "4:100"})
	var bard: Combatant = Fixtures.unit("Bard", {"attack_frames": "4:100"})
	var other: Combatant = Fixtures.unit("Other", {"attack_frames": "4:100"})
	var battle: BattleEngine = Fixtures.engine([knight, bard, other], [Fixtures.monster("Foe", {"brain": IdleEnemyBrain.new()})], rules, catalog)
	battle.start()
	battle.execute(knight.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "96", knight.id))
	battle.execute(other.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "962", other.id))
	battle.advance(5)
	var cover: BattleStatus = knight.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE)
	assert_not_null(cover)
	if cover != null:
		assert_eq([cover.value, cover.turns_left, cover.params["mit_min"], cover.params["mit_max"]], [75, 3, 50, 70])
		assert_eq([cover.params["physical"], cover.params["magic"]], [true, false])
	var old: BattleStatus = other.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE)
	assert_true(old != null and bool(old.params["physical"]) and not bool(old.params["magic"]), "no phys_mag slot: physical")
	battle.execute(bard.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "961", knight.id))
	battle.advance(5)
	var covers: Array[BattleStatus] = knight.statuses_of(BattleStatus.COVER)
	assert_eq(covers.size(), 1, "one AoE cover at a time")
	if covers.size() == 1:
		assert_eq([covers[0].value, covers[0].params["physical"], covers[0].params["magic"]], [20, false, true],
			"the newer magic cover, though weaker")


func test_118_with_physical_only_takes_physical_attacks_only() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "1181", Fixtures.record("Cover", [[1, 5, 118, [60, 80, 100, 1, 1, 1]]], "4:100"))
	var galuf: Combatant = Fixtures.unit("Galuf", {"attack_frames": "4:100"})
	var ward: Combatant = Fixtures.unit("Ward", {"attack_frames": "4:100"})
	var foe: Combatant = Fixtures.monster("Foe", {"brain": IdleEnemyBrain.new()})
	var battle: BattleEngine = Fixtures.engine([galuf, ward], [foe], null, catalog)
	battle.start()
	battle.execute(galuf.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "1181", ward.id))
	battle.advance(5)
	assert_eq(_decide(battle, foe, "703", ward), {}, "magic")
	assert_eq(_decide(battle, foe, "702", ward), {ward.id: galuf.id}, "physical")
	var mitigation: int = galuf.cover_mitigation
	assert_true(mitigation >= 60 and mitigation <= 80, "rolled %d" % mitigation)
