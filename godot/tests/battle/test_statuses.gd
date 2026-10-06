extends "res://tests/test_case.gd"

## Statuses: how they change stats and damage, how they stack, count down and get
## resisted or cleansed, and the ailments that stop a combatant from acting.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


## Returns the same decision once per turn.
class FixedBrain:
	extends EnemyBrain
	var decision: Dictionary = {}

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _attacks_left <= 0:
			return turn_over("done")
		_attacks_left -= 1
		return decision


func before_each() -> void:
	catalog = Fixtures.catalog()


func _status(kind: StringName, key: String, value: int, turns: int = 3) -> BattleStatus:
	return BattleStatus.make(kind, key, value, turns)


func _cast(battle: BattleEngine, actor: Combatant, skill_id: String, target: Combatant = null) -> StringName:
	return battle.execute(actor.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, skill_id, target.id if target != null else -1))


func _roll(attacker: Combatant, target: Combatant, kind: int, elements: Array = [], skill_ids: Array = [], limit_burst: bool = false) -> float:
	var req: DamageFormula.Request = DamageFormula.request(attacker, target, kind, 1.0, PackedInt32Array(elements))
	req.skill_ids = PackedStringArray(skill_ids)
	req.is_limit_burst = limit_burst
	return DamageFormula.compute(req, Fixtures.rules(), RandomNumberGenerator.new()).amount


# --- Stats ---

func test_buffs_and_breaks_scale_the_raw_stat() -> void:
	var unit: Combatant = Fixtures.unit("Unit", {"atk": 100, "raw_stats": {"ATK": 50}})
	unit.add_status(_status(BattleStatus.STAT, "ATK", 100))
	assert_eq(unit.stat("ATK"), 150, "+100% of the raw 50")
	unit.add_status(_status(BattleStatus.STAT, "ATK", -30))
	assert_eq(unit.stat("ATK"), 135, "a buff and a break add up: +70% of 50")
	unit.add_status(_status(BattleStatus.STAT, "ATK", 50))
	assert_eq(unit.stat("ATK"), 110, "the newer buff replaces the older one: +20%")


func test_a_stronger_status_can_be_kept() -> void:
	var unit: Combatant = Fixtures.unit("Unit")
	unit.add_status(_status(BattleStatus.STAT, "DEF", 100), true)
	assert_false(unit.add_status(_status(BattleStatus.STAT, "DEF", 50), true))
	assert_eq(unit.status_value(BattleStatus.STAT, "DEF"), 100)


func test_a_buff_skill_raises_later_damage() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "3", Fixtures.record("Bravery", [[1, 2, 3, [100, 0, 0, 0, 3, 1]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe], null, catalog)
	battle.start()
	_cast(battle, a, "3", b)
	battle.advance(10)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, b.id).size(), 1)
	battle.execute(b.id)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [400], "ATK 200: 200^2 / 100")


func test_breaks_land_unless_resisted() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "24", Fixtures.record("Armor Break", [[2, 1, 24, [0, -50, 0, 0, 3, 1]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var c: Combatant = Fixtures.unit("C")
	var breakable: Combatant = Fixtures.monster("Breakable")
	var sturdy: Combatant = Fixtures.monster("Sturdy", {"debuff_resist": {"DEF": 100}})
	var battle: BattleEngine = Fixtures.engine([a, b, c], [breakable, sturdy], null, catalog)
	battle.start()
	_cast(battle, a, "24")
	battle.advance(10)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.STATUS_RESISTED, sturdy.id).size(), 1)
	battle.execute(b.id, BattleCommand.attack(breakable.id))
	battle.execute(c.id, BattleCommand.attack(sturdy.id))
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, breakable.id)), [200], "DEF 50")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, sturdy.id)), [100])


func test_imperils_use_resistance_headroom() -> void:
	var target: Combatant = Fixtures.monster("Target", {"element_resist": {"FIRE": 120}})
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([1])), 0.0, 0.0001, "120 counts as 100")
	target.add_status(_status(BattleStatus.ELEMENT_RESIST, "FIRE", -70))
	assert_eq(target.element_resistance("FIRE"), 50)
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([1])), 0.5, 0.0001, "120 - 70 = 50")


func test_statuses_count_down_at_the_end_of_each_turn() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "31", Fixtures.record("Quick Boost", [[0, 3, 3, [50, 0, 0, 0, 1, 1]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "32", Fixtures.record("Long Boost", [[0, 3, 3, [0, 50, 0, 0, 2, 1]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	a.add_status(_status(BattleStatus.STAT, "SPR", 30, -1))
	var foe: Combatant = Fixtures.monster("Foe", {"atk": 0})
	var battle: BattleEngine = Fixtures.engine([a, b], [foe], null, catalog)
	battle.start()
	_cast(battle, a, "31")
	_cast(battle, b, "32")
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(a.status_value(BattleStatus.STAT, "ATK"), 0, "the 1-turn buff expired")
	assert_eq(b.status_value(BattleStatus.STAT, "DEF"), 50, "the 2-turn buff has a turn left")
	battle.execute_many([a.id, b.id])
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 3)
	assert_eq(b.status_value(BattleStatus.STAT, "DEF"), 0)
	assert_eq(a.status_value(BattleStatus.STAT, "SPR"), 30, "a permanent status stays")
	var expired: Array = []
	for event in battle.events.of_type(BattleEventLog.STATUS_REMOVED):
		expired.append([int(event["target"]), event["key"], event["reason"], int(event["frame"]) > 0])
	assert_has(expired, [a.id, "ATK", &"expired", true])
	assert_has(expired, [b.id, "DEF", &"expired", true])


# --- Damage terms ---

func test_mitigation_layers_multiply_and_respect_attack_type() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	hero.add_status(_status(BattleStatus.MITIGATION, "all", 50))
	hero.add_status(_status(BattleStatus.MITIGATION, "physical", 50))
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [25], "100 x 0.5 x 0.5")

	var mage: Combatant = Fixtures.unit("Mage", {"attack_frames": "4:100"})
	mage.add_status(_status(BattleStatus.MITIGATION, "magic", 50))
	var second: BattleEngine = Fixtures.engine([mage], [Fixtures.monster("Foe")], null, catalog)
	second.start()
	second.execute(mage.id)
	Fixtures.run_until(second, func() -> bool: return second.turn == 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(second, mage.id)), [100], "magic mitigation leaves physical hits alone")


func test_killers_boost_damage_against_their_race() -> void:
	var attacker: Combatant = Fixtures.unit("Attacker")
	attacker.add_status(_status(BattleStatus.KILLER, "physical:2", 100))
	var avian: Combatant = Fixtures.monster("Avian", {"races": [2]})
	var human: Combatant = Fixtures.monster("Human", {"races": [5]})
	assert_almost_eq(_roll(attacker, avian, DamageFormula.Kind.PHYSICAL), 200.0, 0.001)
	assert_almost_eq(_roll(attacker, human, DamageFormula.Kind.PHYSICAL), 100.0, 0.001)
	assert_almost_eq(_roll(attacker, avian, DamageFormula.Kind.MAGIC), 100.0, 0.001, "physical killers only")


func test_killers_average_over_a_target_with_two_races() -> void:
	var attacker: Combatant = Fixtures.unit("Attacker")
	attacker.add_status(_status(BattleStatus.KILLER, "physical:4", 100))
	var demon_fairy: Combatant = Fixtures.monster("Demon fairy", {"races": [4, 8]})
	assert_almost_eq(_roll(attacker, demon_fairy, DamageFormula.Kind.PHYSICAL), 150.0, 0.001,
		"100% against one of two races counts half")


func test_innate_damage_resistance_cuts_its_own_side() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "900", Fixtures.skill_record("Blizzard", 15, Fixtures.magic_params(100), "10:100"))
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var foe: Combatant = Fixtures.monster("Foe", {"physical_resist": 50, "magic_resist": 100})
	foe.add_status(_status(BattleStatus.MITIGATION, "physical", 50))
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return not Fixtures.hits(battle, foe.id).is_empty())
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [25], "100 x 0.5 mitigation x 0.5 innate resistance")

	var mage: Combatant = Fixtures.unit("Mage")
	var immune: Combatant = Fixtures.monster("Immune", {"magic_resist": 100})
	var second: BattleEngine = Fixtures.engine([mage], [immune], null, catalog)
	second.start()
	_cast(second, mage, "900", immune)
	Fixtures.run_until(second, func() -> bool: return not Fixtures.hits(second, immune.id).is_empty())
	assert_eq(Fixtures.amounts(Fixtures.hits(second, immune.id)), [0], "magic resistance 100 stops magic damage")


func test_element_skill_and_lb_boosts() -> void:
	var attacker: Combatant = Fixtures.unit("Attacker")
	var target: Combatant = Fixtures.monster("Target")
	attacker.add_status(_status(BattleStatus.ELEMENT_BOOST, "FIRE", 50))
	attacker.add_status(BattleStatus.make(BattleStatus.SKILL_BOOST, "7", 100, 3, {
		"skill_ids": PackedStringArray(["777"]), "opcodes": [],
	}))
	attacker.add_status(_status(BattleStatus.LB_BOOST, "", 100))
	assert_almost_eq(_roll(attacker, target, DamageFormula.Kind.PHYSICAL, [1]), 150.0, 0.001, "fire boost")
	assert_almost_eq(_roll(attacker, target, DamageFormula.Kind.PHYSICAL, [], ["777"]), 200.0, 0.001, "boosted skill")
	assert_almost_eq(_roll(attacker, target, DamageFormula.Kind.PHYSICAL, [], ["778"]), 100.0, 0.001, "other skill")
	assert_almost_eq(_roll(attacker, target, DamageFormula.Kind.PHYSICAL, [], [], true), 200.0, 0.001, "limit burst")


func test_lb_boosts_from_different_sources_add_up() -> void:
	# Opcode 171 with no LB ids boosts every limit burst, alongside opcode 120's boost.
	catalog.add_record(BattleSkill.KIND_ABILITY, "171", Fixtures.record("LB Focus", [[0, 3, 171, [0, 0, 0, 50, 3, 9, 0]]]))
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, hero, "171")
	battle.advance(10)
	assert_eq(hero.status_value(BattleStatus.LB_BOOST, "171:9"), 50)
	hero.add_status(_status(BattleStatus.LB_BOOST, "", 50))
	var target: Combatant = Fixtures.monster("Target")
	assert_almost_eq(_roll(hero, target, DamageFormula.Kind.PHYSICAL, [], [], true), 200.0, 0.001, "+50% and +50%")
	assert_almost_eq(_roll(hero, target, DamageFormula.Kind.PHYSICAL), 100.0, 0.001, "not a limit burst")


func test_imbue_adds_elements_to_physical_attacks_only() -> void:
	catalog.add_record(BattleSkill.KIND_MAGIC, "15", Fixtures.skill_record("Blast", 15, Fixtures.magic_params(100), "10:100"))
	var knight: Combatant = Fixtures.unit("Knight")
	var mage: Combatant = Fixtures.unit("Mage")
	knight.add_status(_status(BattleStatus.IMBUE, "FIRE", 1))
	mage.add_status(_status(BattleStatus.IMBUE, "FIRE", 1))
	var foe: Combatant = Fixtures.monster("Foe", {"element_resist": {"FIRE": -50}})
	var other: Combatant = Fixtures.monster("Other", {"element_resist": {"FIRE": -50}})
	var battle: BattleEngine = Fixtures.engine([knight, mage], [foe, other], null, catalog)
	battle.start()
	battle.execute(knight.id, BattleCommand.attack(foe.id))
	battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "15", other.id))
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [150], "fire added to the attack")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, other.id)), [100], "magic is not imbued")


# --- Defensive statuses ---

func test_dodge_evades_physical_hits_until_used_up() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	hero.add_status(_status(BattleStatus.DODGE, "", 2))
	var foe: Combatant = Fixtures.monster("Foe", {"attack_frames": "10:33-20:33-30:34"})
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.HIT_MISSED, hero.id).size(), 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [34], "the third hit lands")
	assert_null(hero.find_status(BattleStatus.DODGE))


func test_dodge_does_not_evade_magic() -> void:
	catalog.add_record(BattleSkill.KIND_MONSTER, "700", Fixtures.record("Flare", [[1, 1, 15, Fixtures.magic_params(100)]], "20:100", {"attack_type": 2}))
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	hero.add_status(_status(BattleStatus.DODGE, "", 2))
	var brain := FixedBrain.new()
	brain.decision = EnemyBrain.action(EnemyBrain.KIND_SKILL, "700")
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Caster", {"brain": brain})], null, catalog)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [100])
	assert_eq(hero.status_value(BattleStatus.DODGE), 2)


func test_a_barrier_absorbs_damage_then_breaks() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	hero.add_status(_status(BattleStatus.SHIELD, "", 150))
	var foe: Combatant = Fixtures.monster("Foe", {"attack_frames": "10:50-40:50"})
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(hero.hp, 1000, "two hits of 50 are absorbed")
	assert_eq(hero.status_value(BattleStatus.SHIELD), 50)
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 3)
	assert_eq(hero.hp, 950, "50 absorbed, 50 through")
	assert_null(hero.find_status(BattleStatus.SHIELD))


func test_auto_revive_brings_a_kod_unit_back_and_ko_clears_statuses() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"hp": 1000, "attack_frames": "4:100"})
	hero.hp = 100
	hero.add_status(_status(BattleStatus.AUTO_REVIVE, "", 50))
	hero.add_status(_status(BattleStatus.STAT, "ATK", 100))
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Brute", {"atk": 1000})], null, catalog)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2 or battle.phase == BattleEngine.Phase.ENDED)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, hero.id).size(), 1)
	assert_eq(hero.hp, 500)
	assert_true(hero.statuses.is_empty(), "KO removed the buff and the used auto-revive")
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "the battle goes on")


# --- Ailments ---

func test_sleep_stops_an_enemy_from_acting_unless_resisted() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "6", Fixtures.record("Lullaby", [[2, 1, 6, [0, 0, 100, 0, 0, 0, 0, 0, 1]]], "4:100"))
	var singer: Combatant = Fixtures.unit("Singer")
	var drowsy: Combatant = Fixtures.monster("Drowsy")
	var alert: Combatant = Fixtures.monster("Alert", {"ailment_resist": {"SLEEP": 100}})
	var rules: BattleRules = Fixtures.rules()
	rules.enemy_ailment_recovery_pct = 0
	var battle: BattleEngine = Fixtures.engine([singer], [drowsy, alert], rules, catalog)
	battle.start()
	_cast(battle, singer, "6")
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_true(Fixtures.events_on(battle, BattleEventLog.STATUS_RESISTED, alert.id).size() == 1)
	var acting: Array = []
	for event in Fixtures.actions_by(battle):
		if int(event["actor"]) != singer.id:
			acting.append(int(event["actor"]))
	assert_eq(acting, [alert.id], "the sleeping enemy skipped its turn")
	assert_true(drowsy.has_ailment("SLEEP"), "enemies shake ailments off by a roll, not a countdown")


func test_a_disabled_unit_cannot_act_and_does_not_hold_up_the_turn() -> void:
	var awake: Combatant = Fixtures.unit("Awake", {"attack_frames": "4:100"})
	var asleep: Combatant = Fixtures.unit("Asleep")
	asleep.add_status(_status(BattleStatus.AILMENT, "SLEEP", 0))
	var battle: BattleEngine = Fixtures.engine([awake, asleep], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(battle.execute(asleep.id), BattleEngine.REJECT_CANNOT_ACT)
	assert_eq(battle.units_to_act(), [awake])
	battle.execute(awake.id)
	battle.advance(4)
	assert_eq(battle.phase, BattleEngine.Phase.ENEMY)


func test_silence_blocks_magic_but_not_abilities() -> void:
	catalog.add_record(BattleSkill.KIND_MAGIC, "15", Fixtures.skill_record("Fire", 15, Fixtures.magic_params(100), "10:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "1", Fixtures.skill_record("Slash", 1, Fixtures.physical_params(100), "10:100"))
	var mute: Combatant = Fixtures.unit("Mute")
	mute.add_status(_status(BattleStatus.AILMENT, "SILENCE", 0))
	var battle: BattleEngine = Fixtures.engine([mute], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(battle.execute(mute.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "15")), BattleEngine.REJECT_SILENCED)
	assert_eq(battle.execute(mute.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "1")), BattleEngine.OK)


func test_stop_rolls_against_debuff_resistance() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "88", Fixtures.record("Stop", [[2, 1, 88, [100, 2]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var stoppable: Combatant = Fixtures.monster("Stoppable")
	var boss: Combatant = Fixtures.monster("Boss", {"debuff_resist": {"STOP": 100}})
	var battle: BattleEngine = Fixtures.engine([caster], [stoppable, boss], null, catalog)
	battle.start()
	_cast(battle, caster, "88")
	battle.advance(4)
	assert_true(stoppable.has_ailment("STOP"))
	assert_false(stoppable.can_act())
	assert_false(boss.has_ailment("STOP"))


# --- Cleansing ---

func test_cure_and_debuff_removal_take_only_what_they_list() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "5", Fixtures.record("Wake", [[1, 2, 5, [3, 0, 0, 0, 0, 0, 0, 0]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "111", Fixtures.record("Attack Detach", [[1, 2, 111, [1, 0, 0, 0, 0, 0]]]))
	var cleric: Combatant = Fixtures.unit("Cleric")
	var patient: Combatant = Fixtures.unit("Patient")
	var other: Combatant = Fixtures.unit("Other")
	patient.add_status(_status(BattleStatus.AILMENT, "SLEEP", 0))
	patient.add_status(_status(BattleStatus.AILMENT, "POISON", 0))
	other.add_status(_status(BattleStatus.STAT, "ATK", -40))
	other.add_status(_status(BattleStatus.STAT, "DEF", -40))
	var battle: BattleEngine = Fixtures.engine([cleric, patient, other], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, cleric, "5", patient)
	battle.execute(other.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "111", other.id))
	battle.advance(10)
	assert_false(patient.has_ailment("SLEEP"))
	assert_true(patient.has_ailment("POISON"))
	assert_eq(other.status_value(BattleStatus.STAT, "ATK"), 0)
	assert_eq(other.status_value(BattleStatus.STAT, "DEF"), -40)


func test_remove_buffs_and_dispel() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "141", Fixtures.record("Shatter", [[1, 1, 141, [[1, 2, 3, 4], 0]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "59", Fixtures.record("Purify", [[1, 1, 59, [2, 0]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "60", Fixtures.record("Dispel", [[1, 1, 59, ["none"]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var c: Combatant = Fixtures.unit("C")
	var buffed: Combatant = Fixtures.monster("Buffed")
	var mixed: Combatant = Fixtures.monster("Mixed")
	var everything: Combatant = Fixtures.monster("Everything")
	buffed.add_status(_status(BattleStatus.STAT, "ATK", 50))
	buffed.add_status(_status(BattleStatus.ELEMENT_RESIST, "FIRE", 50))
	for foe in [mixed, everything]:
		foe.add_status(_status(BattleStatus.STAT, "ATK", 50))
		foe.add_status(_status(BattleStatus.STAT, "DEF", -50))
		foe.add_status(_status(BattleStatus.AILMENT, "POISON", 0))
	var battle: BattleEngine = Fixtures.engine([a, b, c], [buffed, mixed, everything], null, catalog)
	battle.start()
	_cast(battle, a, "141", buffed)
	_cast(battle, b, "59", mixed)
	_cast(battle, c, "60", everything)
	battle.advance(10)
	assert_eq(buffed.status_value(BattleStatus.STAT, "ATK"), 0, "stat boosts removed")
	assert_eq(buffed.element_resistance("FIRE"), 50, "resistance boosts are other buff types")
	assert_eq(mixed.status_value(BattleStatus.STAT, "DEF"), 0, "mode 2 removes debuffs")
	assert_eq(mixed.status_value(BattleStatus.STAT, "ATK"), 50, "and keeps buffs")
	assert_eq(everything.status_value(BattleStatus.STAT, "ATK") + everything.status_value(BattleStatus.STAT, "DEF"), 0, "both go")
	assert_true(everything.has_ailment("POISON"), "ailments stay")


func test_the_ai_sees_ailments() -> void:
	var foe: Combatant = Fixtures.monster("Foe")
	foe.add_status(_status(BattleStatus.AILMENT, "BLIND", 0))
	assert_eq(BattleEngine.ai_view(foe)["statuses"], ["BLIND"])
