extends "res://tests/test_case.gd"

## Damage effects beyond plain physical and magic: percent and fixed damage (and how
## they chain), piercing, DEF- and SPR-based damage, HP costs, miss chances and drain.
## Fixture stats are 100 across the board unless a test says otherwise.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()


func _use(battle: BattleEngine, actor: Combatant, skill_id: String, target: Combatant = null) -> StringName:
	return battle.execute(actor.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, skill_id, target.id if target != null else -1))


func test_percent_damage_takes_a_share_of_current_hp() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "9", Fixtures.record("Gravity", [[1, 1, 9, [40, 40, 100, 0]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "90", Fixtures.record("Fire Gravity", [[1, 1, 9, [40, 40, 100, 0]]], "10:100", {"element_inflict": [1]}))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var plain: Combatant = Fixtures.monster("Plain", {"hp": 1000})
	var weak: Combatant = Fixtures.monster("Weak", {"hp": 1000, "element_resist": {"FIRE": -50}})
	var battle: BattleEngine = Fixtures.engine([a, b], [plain, weak], null, catalog)
	battle.start()
	_use(battle, a, "9", plain)
	_use(battle, b, "90", weak)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, plain.id)), [400], "40% of 1000")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, weak.id)), [600], "fire weakness applies")


func test_fixed_damage_builds_the_chain_without_its_bonus() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "41", Fixtures.record("Needles", [[1, 1, 41, [300]]], "6:100"))
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var b: Combatant = Fixtures.unit("B")
	var c: Combatant = Fixtures.unit("C", {"attack_frames": "16:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b, c], [foe], null, catalog)
	battle.start()
	battle.execute(a.id)
	_use(battle, b, "41", foe)
	battle.execute(c.id)
	battle.advance(16)
	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(landed), [100, 300, 120])
	assert_eq(int(landed[1]["chain"]), 1, "the fixed hit counts in the chain")
	assert_eq(int(landed[1]["chain_pct"]), 100, "but takes no chain bonus")
	assert_eq(int(landed[2]["chain"]), 2, "the next hit continues the chain it built")


func test_def_and_spr_piercing_lower_the_defending_stat() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "21", Fixtures.record("Pierce", [[1, 1, 21, [0, 0, 100, -50]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "70", Fixtures.record("Mind Pierce", [[1, 1, 70, [0, 0, 100, 50]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var foe: Combatant = Fixtures.monster("Foe")
	var other: Combatant = Fixtures.monster("Other")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe, other], null, catalog)
	battle.start()
	_use(battle, a, "21", foe)
	_use(battle, b, "70", other)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [200], "100^2 / (100 x 0.5)")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, other.id)), [200], "the same through SPR")


func test_def_and_spr_based_damage_use_the_casters_defenses() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "102", Fixtures.record("Shield Bash", [[1, 1, 102, [100, 99999, 150]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "103", Fixtures.record("Holy Strike", [[1, 1, 103, [100, 99999, 150]]]))
	var tank: Combatant = Fixtures.unit("Tank", {"def": 200})
	var sage: Combatant = Fixtures.unit("Sage", {"spr": 200})
	var foe: Combatant = Fixtures.monster("Foe")
	var other: Combatant = Fixtures.monster("Other")
	var battle: BattleEngine = Fixtures.engine([tank, sage], [foe, other], null, catalog)
	battle.start()
	_use(battle, tank, "102", foe)
	_use(battle, sage, "103", other)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [600], "200^2 / 100 x 1.5")
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, other.id)), [600])


func test_hp_sacrifice_costs_a_share_of_max_hp() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "81", Fixtures.record("Soul Eater", [[1, 1, 81, [0, 0, 0, 0, 0, 0, 100, 20, 0, 0]]]))
	var a: Combatant = Fixtures.unit("A")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a], [foe], null, catalog)
	battle.start()
	_use(battle, a, "81", foe)
	assert_eq(a.hp, 800)
	assert_eq(int(battle.events.last_of_type(BattleEventLog.COST_PAID)["hp_cost"]), 200)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [100])


func test_a_full_hp_sacrifice_kos_the_caster_but_still_hits() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "81", Fixtures.record("Final Sequence", [[1, 1, 81, [0, 0, 0, 0, 0, 0, 999, 100, 0, 0]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe], null, catalog)
	battle.start()
	_use(battle, a, "81", foe)
	assert_false(a.is_alive())
	assert_eq(Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, a.id).size(), 1)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [999])


func test_a_certain_miss_misses_every_hit() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "43", Fixtures.record("Wild Swing", [[1, 1, 43, [0, 0, 300, 100]]], "5:50-10:50"))
	var a: Combatant = Fixtures.unit("A")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a], [foe], null, catalog)
	battle.start()
	_use(battle, a, "43", foe)
	battle.advance(10)
	assert_eq(Fixtures.hits(battle, foe.id).size(), 0)
	var missed: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.HIT_MISSED, foe.id)
	assert_eq(missed.size(), 2)
	assert_eq(missed[0]["reason"], &"missed")


func test_drain_heals_the_caster_by_a_share_of_the_damage() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "25", Fixtures.record("Steal HP", [[1, 1, 25, [50, 100, 100]]], "10:100", {"attack_type": 1}))
	catalog.add_record(BattleSkill.KIND_ABILITY, "26", Fixtures.record("Drain", [[1, 1, 25, [50, 100, 100]]], "10:100", {"attack_type": 2}))
	var fighter: Combatant = Fixtures.unit("Fighter")
	var mage: Combatant = Fixtures.unit("Mage", {"mag": 200})
	fighter.hp = 500
	mage.hp = 500
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([fighter, mage], [foe], null, catalog)
	battle.start()
	_use(battle, fighter, "25", foe)
	_use(battle, mage, "26", foe)
	battle.advance(10)
	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(int(landed[0]["amount"]), 100, "physical attack type: ATK against DEF")
	assert_eq(int(landed[1]["amount"]), 560, "magic attack type: MAG against SPR, a spark chain x1.4")
	assert_eq(fighter.hp, 550)
	assert_eq(mage.hp, 780)
	var restored: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.RESTORED, fighter.id)
	assert_eq(restored[0]["reason"], &"drain")
