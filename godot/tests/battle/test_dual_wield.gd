extends "res://tests/test_case.gd"

## Dual wield in battle (DualWield): two swings, right hand first, each with its own
## weapon's ATK, both carrying both weapons' elements and ailments. Most cases follow the
## wiki's example: base ATK 200 with a 100 ATK weapon in the right hand and a 50 ATK one
## in the left shows 350 ATK, but the right hand swings with 300 and the left with 250.
## Against DEF 100 a 100% swing deals 900 (300^2 / 100) and 625 (250^2 / 100).

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const FIRE: int = 1
const ICE: int = 2
const LIGHTNING: int = 3

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	catalog.add_record(BattleSkill.KIND_ABILITY, "10", Fixtures.record("Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	catalog.add_record(BattleSkill.KIND_ABILITY, "11", Fixtures.record("Twin Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "42:50-62:50", physical))
	catalog.add_record(BattleSkill.KIND_ABILITY, "12", Fixtures.record("Hybrid Slash",
		[[1, 1, 40, [0, 0, 0, 0, 0, 0, 0, 0, 100, 100]]], "10:100", {"attack_type": BattleSkill.ATTACK_HYBRID}))
	# Sunbeam's shape: magic damage (opcode 15) with a physical attack type.
	catalog.add_record(BattleSkill.KIND_ABILITY, "13", Fixtures.record("Sunbeam", [[1, 1, 15, Fixtures.magic_params(100)]], "10:100", physical))
	catalog.add_record(BattleSkill.KIND_ABILITY, "14", Fixtures.record("Thunder Slash",
		[[1, 1, 1, Fixtures.physical_params(100)]], "10:100", {"attack_type": BattleSkill.ATTACK_PHYSICAL, "element_inflict": [LIGHTNING]}))
	# Damage, then a DEF break on the same target, for 10 MP.
	catalog.add_record(BattleSkill.KIND_ABILITY, "15", Fixtures.record("Armor Slash",
		[[1, 1, 1, Fixtures.physical_params(100)], [1, 1, 24, [0, -50, 0, 0, 3, 1]]], "10:100",
		{"attack_type": BattleSkill.ATTACK_PHYSICAL, "cost": {"MP": 10}}))
	# A physical attack type and no damage.
	catalog.add_record(BattleSkill.KIND_ABILITY, "16", Fixtures.record("Armor Break", [[1, 1, 24, [0, -50, 0, 0, 3, 1]]], "10:100", physical))
	catalog.add_record(BattleSkill.KIND_MAGIC, "20", Fixtures.skill_record("Fire", 15, Fixtures.magic_params(100), "10:100", 1, 1, 0, [FIRE]))
	catalog.add_record(BattleSkill.KIND_LIMIT_BURST, "30", {
		"name": "Blade Flash",
		"attack_type": BattleSkill.ATTACK_PHYSICAL,
		"levels": [[8, [[1, 1, 1, Fixtures.physical_params(100)]]]],
		"attack_frames": [[10]],
		"attack_damage": [[100]],
	})


func _engine(party: Array, foes: Array) -> BattleEngine:
	var rules: BattleRules = Fixtures.rules()
	rules.enemy_ailment_recovery_pct = 0
	return Fixtures.engine(party, foes, rules, catalog)


## The wiki's dual wielder: 350 ATK shown, a 100 ATK weapon right and a 50 ATK one left.
func _dual_wielder(unit_name: String = "Dual", spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"atk": 350, "hand_atk": [100, 50], "attack_frames": "10:100"}
	full.merge(spec, true)
	return Fixtures.unit(unit_name, full)


## An enemy that passes its turns.
func _idle(monster_name: String, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(monster_name, full)


## Runs until `actions` actions have ended (each ends after its last hit).
func _settle(battle: BattleEngine, actions: int = 1) -> void:
	assert_true(Fixtures.run_until(battle, func() -> bool:
		return battle.events.of_type(BattleEventLog.ACTION_ENDED).size() >= actions), "the actions finish")


func _swings(hits: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for hit in hits:
		out.append(int(hit["swing"]))
	return out


func _frames(hits: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for hit in hits:
		out.append(int(hit["frame"]))
	return out


## The ailment keys rolled on `target_id` (landed or resisted), sorted.
func _rolled(battle: BattleEngine, target_id: int) -> Array:
	var keys: Array = []
	for type in [BattleEventLog.STATUS_ADDED, BattleEventLog.STATUS_RESISTED]:
		for event in Fixtures.events_on(battle, type, target_id):
			if event["kind"] == BattleStatus.AILMENT:
				keys.append(str(event["key"]))
	keys.sort()
	return keys


# --- Swings and damage ---

func test_a_basic_attack_swings_twice_right_hand_first_with_each_weapons_atk() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [900, 625], "300 ATK, then 250 ATK")
	assert_eq(_swings(hits), [DualWield.RIGHT, DualWield.LEFT])
	var started: Array[Dictionary] = Fixtures.actions_by(battle, hero.id)
	assert_eq(started.size(), 1, "one action")
	if started.size() == 1:
		assert_true(bool(started[0]["dual_wield"]))


func test_the_atk_both_weapons_add_up_to_is_used_by_nothing() -> void:
	var single: Combatant = Fixtures.unit("Single", {"atk": 350, "hand_atk": [150], "attack_frames": "10:100"})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([single], [foe])
	battle.start()
	battle.execute(single.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_false(single.is_dual_wielding())
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [1225], "one weapon swings once with all 350 ATK")
	assert_false(bool(Fixtures.actions_by(battle, single.id)[0]["dual_wield"]))


func test_the_left_swing_starts_the_cast_gap_after_the_right_hands_start() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	var start: int = battle.frame
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "11", foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	# Right: 42 and 62. Left: the same frames counted from 39.
	assert_eq(_frames(hits), [start + 42, start + 62, start + 81, start + 101])
	assert_eq(_swings(hits), [DualWield.RIGHT, DualWield.RIGHT, DualWield.LEFT, DualWield.LEFT])
	assert_eq(Fixtures.amounts(hits), [450, 450, 312, 312], "each swing splits its own amount")
	var ended: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_ENDED)
	assert_eq(int(ended["frame"]), start + 101, "the action ends on the left hand's last hit")


func test_the_gap_is_a_rule() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var rules: BattleRules = Fixtures.rules()
	rules.cast_gap_frames = 0
	var battle: BattleEngine = Fixtures.engine([hero], [foe], rules, catalog)
	battle.start()
	var start: int = battle.frame
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(_frames(hits), [start + 10, start + 10], "both swings on the same frame")
	assert_eq(_swings(hits), [DualWield.RIGHT, DualWield.LEFT], "right hand first")


func test_a_physical_ability_runs_whole_twice_for_one_cost() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	var start: int = battle.frame
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "15", foe.id))
	_settle(battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [900, 625])
	var breaks: Array[Dictionary] = []
	for event in Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, foe.id):
		if event["kind"] == BattleStatus.STAT:
			breaks.append(event)
	assert_eq(_frames(breaks), [start + 10, start + 49], "the break runs with each swing")
	assert_eq(battle.events.count_of_type(BattleEventLog.COST_PAID), 1, "the cost is paid once")
	assert_eq(hero.mp, 90)


func test_hybrid_abilities_swing_twice() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "12", foe.id))
	_settle(battle)
	# (ATK^2 / DEF + MAG^2 / SPR) / 2: (900 + 100) / 2, then (625 + 100) / 2.
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [500, 362])


func test_magic_damage_with_a_physical_attack_type_swings_twice() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "13", foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [100, 100], "Sunbeam: MAG^2 / SPR each time, whatever the hand")
	assert_eq(_swings(hits), [DualWield.RIGHT, DualWield.LEFT])


func test_magic_swings_once() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "20", foe.id))
	_settle(battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [100])
	assert_false(bool(Fixtures.actions_by(battle, hero.id)[0]["dual_wield"]))


func test_a_physical_skill_without_damage_runs_once() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "16", foe.id))
	_settle(battle)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, foe.id).size(), 1)
	assert_false(bool(Fixtures.actions_by(battle, hero.id)[0]["dual_wield"]))


func test_a_limit_burst_swings_once_with_the_higher_atk_weapon() -> void:
	# The stronger weapon is in the left hand this time.
	var hero: Combatant = _dual_wielder("Dual", {"hand_atk": [50, 100], "limit_burst_id": "30", "max_lb": 800, "lb": 800})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	assert_eq(battle.execute(hero.id, BattleCommand.limit_burst("30", foe.id)), BattleEngine.OK)
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [900], "one swing with 350 - 50 = 300 ATK")
	assert_eq(_swings(hits), [DualWield.RIGHT])
	assert_false(bool(Fixtures.actions_by(battle, hero.id)[0]["dual_wield"]))


func test_both_swings_and_a_limit_burst_use_the_right_hand_weapons_variance() -> void:
	# Combatant.weapon_variance_min/max hold the right hand's range (wiki: "only the right
	# hand weapon variance is used for both hits"); 150 .. 150 keeps the numbers exact.
	var spec: Dictionary = {"weapon_variance": [150, 150], "limit_burst_id": "30", "max_lb": 800, "lb": 800}
	var rules: BattleRules = Fixtures.rules()
	rules.enemy_ailment_recovery_pct = 0
	rules.weapon_variance = true
	var hero: Combatant = _dual_wielder("Dual", spec)
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], rules, catalog)
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [1350, 937], "900 and 625, each x 1.5")

	var lb_hero: Combatant = _dual_wielder("Dual", spec)
	var lb_foe: Combatant = _idle("Foe")
	var lb_battle: BattleEngine = Fixtures.engine([lb_hero], [lb_foe], rules, catalog)
	lb_battle.start()
	assert_eq(lb_battle.execute(lb_hero.id, BattleCommand.limit_burst("30", lb_foe.id)), BattleEngine.OK)
	_settle(lb_battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(lb_battle, lb_foe.id)), [1350], "one swing with 300 ATK, x 1.5")


func test_a_forced_attack_swings_twice() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	assert_eq(battle.debug_edit(hero.id, &"ailment", 3, "BERSERK"), BattleEngine.OK)
	battle.start()
	_settle(battle)
	var started: Array[Dictionary] = Fixtures.actions_by(battle, hero.id)
	assert_true(not started.is_empty() and started[0]["forced_by"] == "BERSERK", "the berserk unit attacked on its own")
	if not started.is_empty():
		assert_true(bool(started[0]["dual_wield"]))
	assert_eq(_swings(Fixtures.hits(battle, foe.id)), [DualWield.RIGHT, DualWield.LEFT])


func test_the_left_swing_misses_a_target_the_right_swing_kod() -> void:
	var hero: Combatant = _dual_wielder()
	var foe: Combatant = _idle("Foe", {"hp": 500})
	var bystander: Combatant = _idle("Bystander")
	var battle: BattleEngine = _engine([hero], [foe, bystander])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_false(foe.is_alive())
	assert_eq(Fixtures.hits(battle, bystander.id), [], "no new target")
	var missed: Array[Dictionary] = battle.events.of_type(BattleEventLog.HIT_MISSED)
	assert_eq(missed.size(), 1)
	if missed.size() == 1:
		assert_eq([int(missed[0]["target"]), int(missed[0]["swing"]), missed[0]["reason"]], [foe.id, DualWield.LEFT, &"target_down"])


# --- Elements ---

func test_a_weapon_element_reaches_the_basic_attack() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"hand_atk": [50], "weapon_elements": [FIRE]})
	var foe: Combatant = _idle("Foe", {"element_resist": {"FIRE": -50}})
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [150], "fire weakness")
	assert_eq(Array(hits[0]["elements"]), [FIRE])


func test_both_weapons_elements_average_with_the_abilitys_against_resistance() -> void:
	# The wiki's example: fire and ice weapons, a lightning ability, against +50% fire,
	# +50% ice and +100% lightning resistance: (50 + 50 + 100) / 3 = 66.67% for both swings.
	var hero: Combatant = _dual_wielder("Dual", {"weapon_elements": [FIRE, ICE]})
	var foe: Combatant = _idle("Foe", {"element_resist": {"FIRE": 50, "ICE": 50, "LIGHTNING": 100}})
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "14", foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	var survives: float = 1.0 - 200.0 / 3.0 / 100.0
	assert_eq(Fixtures.amounts(hits), [floori(900.0 * survives), floori(625.0 * survives)])
	for hit in hits:
		var elements: Array = Array(hit["elements"])
		elements.sort()
		assert_eq(elements, [FIRE, ICE, LIGHTNING], "swing %d carries both weapons' elements" % int(hit["swing"]))


func test_magic_takes_only_its_own_elements() -> void:
	var hero: Combatant = _dual_wielder("Dual", {"weapon_elements": [ICE]})
	var foe: Combatant = _idle("Foe", {"element_resist": {"ICE": 100}})
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "20", foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [100], "ice resistance does not matter to Fire")
	assert_eq(Array(hits[0]["elements"]), [FIRE])


func test_hybrid_and_physical_type_magic_damage_take_weapon_elements() -> void:
	var lancer: Combatant = _dual_wielder("Lancer", {"weapon_elements": [ICE]})
	var sunbeam: Combatant = _dual_wielder("Sunbeam", {"weapon_elements": [ICE]})
	var hybrid_foe: Combatant = _idle("Hybrid Foe", {"element_resist": {"ICE": 50}})
	var sunbeam_foe: Combatant = _idle("Sunbeam Foe", {"element_resist": {"ICE": 50}})
	var battle: BattleEngine = _engine([lancer, sunbeam], [hybrid_foe, sunbeam_foe])
	battle.start()
	battle.execute(lancer.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "12", hybrid_foe.id))
	battle.execute(sunbeam.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "13", sunbeam_foe.id))
	_settle(battle, 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hybrid_foe.id)), [250, 181], "(500, 362.5) x 0.5")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, sunbeam_foe.id)), [50, 50], "100 x 0.5 each swing")


func test_imbues_follow_the_attack_type() -> void:
	var lancer: Combatant = Fixtures.unit("Lancer")
	var mage: Combatant = Fixtures.unit("Mage")
	for caster: Combatant in [lancer, mage]:
		caster.add_status(BattleStatus.make(BattleStatus.IMBUE, "ICE", 1, 3))
	var hybrid_foe: Combatant = _idle("Hybrid Foe", {"element_resist": {"ICE": -50}})
	var magic_foe: Combatant = _idle("Magic Foe", {"element_resist": {"ICE": -50}})
	var battle: BattleEngine = _engine([lancer, mage], [hybrid_foe, magic_foe])
	battle.start()
	battle.execute(lancer.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "12", hybrid_foe.id))
	battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "20", magic_foe.id))
	_settle(battle, 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hybrid_foe.id)), [150], "a hybrid attack is imbued")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, magic_foe.id)), [100], "magic is not")


# --- Ailments ---

func test_both_swings_roll_the_weapon_ailments() -> void:
	var hero: Combatant = _dual_wielder("Dual", {"attack_frames": "4:50-12:50", "weapon_inflicts": {"POISON": 100, "BLIND": 100}})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(hits.size(), 4)
	assert_eq(_rolled(battle, foe.id), ["BLIND", "BLIND", "POISON", "POISON"], "once per swing, not once per hit")
	var added: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, foe.id)
	if added.size() == 4 and hits.size() == 4:
		assert_eq([int(added[0]["frame"]), int(added[2]["frame"])], [int(hits[1]["frame"]), int(hits[3]["frame"])],
			"each after its swing's last hit")


func test_the_left_swing_wakes_the_sleep_the_right_one_put_on_and_rolls_it_again() -> void:
	var hero: Combatant = _dual_wielder("Dual", {"weapon_inflicts": {"SLEEP": 100}})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(_frames(Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, foe.id)), _frames(hits), "slept after each swing")
	var woke: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_REMOVED, foe.id)
	assert_eq(woke.size(), 1)
	if woke.size() == 1:
		assert_eq([woke[0]["reason"], int(woke[0]["frame"])], [&"damaged", int(hits[1]["frame"])], "the left hand's hit woke it")
	assert_not_null(foe.find_status(BattleStatus.AILMENT, "SLEEP"), "asleep at the end")


func test_a_magic_spell_from_a_dual_wielder_inflicts_nothing() -> void:
	var hero: Combatant = _dual_wielder("Dual", {"weapon_inflicts": {"POISON": 100}})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "20", foe.id))
	_settle(battle)
	assert_eq(_rolled(battle, foe.id), [])


func test_enemies_never_dual_wield() -> void:
	var foe: Combatant = Fixtures.monster("Foe")
	assert_false(foe.is_dual_wielding())
	assert_eq(foe.weapon_elements, PackedInt32Array())
