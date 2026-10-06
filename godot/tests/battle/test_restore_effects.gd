extends "res://tests/test_case.gd"

## Recovery effects: the heal formula, flat and percent restores, revive, sacrifice,
## limit gauge fills and transfers, and regens at the end of the turn.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()


func _cast(battle: BattleEngine, actor: Combatant, skill_id: String, target: Combatant = null) -> StringName:
	return battle.execute(actor.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, skill_id, target.id if target != null else -1))


func test_heal_uses_spr_and_mag_and_stops_at_max_hp() -> void:
	# 100 + (0.5 x 200 + 0.1 x 100) x 300% = 430
	catalog.add_record(BattleSkill.KIND_ABILITY, "2", Fixtures.record("Cure", [[1, 2, 2, [0, 0, 100, 300, 100]]]))
	var healer: Combatant = Fixtures.unit("Healer", {"spr": 200})
	var hurt: Combatant = Fixtures.unit("Hurt")
	var nearly_full: Combatant = Fixtures.unit("Nearly Full")
	hurt.hp = 400
	nearly_full.hp = 900
	var battle: BattleEngine = Fixtures.engine([healer, hurt, nearly_full], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, healer, "2", hurt)
	battle.advance(10)
	assert_eq(hurt.hp, 830)
	var restored: Dictionary = Fixtures.events_on(battle, BattleEventLog.RESTORED, hurt.id)[0]
	assert_eq(int(restored["hp"]), 430)
	assert_eq(Fixtures.hits(battle).size(), 0, "healing is not damage")

	battle.execute(hurt.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "2", nearly_full.id))
	battle.advance(10)
	assert_eq(nearly_full.hp, 1000)
	assert_eq(int(Fixtures.events_on(battle, BattleEventLog.RESTORED, nearly_full.id)[0]["hp"]), 100, "only what fit")


func test_flat_and_percent_restores() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "16", Fixtures.record("Potion", [[1, 2, 16, [250]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "17", Fixtures.record("Ether", [[1, 2, 17, [30]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "64", Fixtures.record("Chakra", [[0, 3, 64, [30, 50]]]))
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var c: Combatant = Fixtures.unit("C")
	for member in [a, b, c]:
		member.hp = 100
		member.mp = 0
	var battle: BattleEngine = Fixtures.engine([a, b, c], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, a, "16", b)
	_cast(battle, b, "17", c)
	_cast(battle, c, "64")
	battle.advance(10)
	assert_eq(b.hp, 350, "HP_RESTORE 250")
	assert_eq(c.mp, 80, "MP_RESTORE 30, then PCT_RESTORE 50% of 100")
	assert_eq(c.hp, 400, "PCT_RESTORE 30% of 1000")


func test_revive_brings_back_a_kod_ally_with_its_own_max_hp() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "4", Fixtures.record("Raise", [[1, 6, 4, [30]]], "10:100", {"targetType": 7}))
	var cleric: Combatant = Fixtures.unit("Cleric")
	var sturdy: Combatant = Fixtures.unit("Sturdy", {"hp": 3000})
	var fallen: Combatant = Fixtures.unit("Fallen", {"hp": 2000})
	sturdy.hp = 0
	fallen.hp = 0
	var battle: BattleEngine = Fixtures.engine([cleric, sturdy, fallen], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(_cast(battle, cleric, "4", fallen), BattleEngine.OK)
	battle.advance(10)
	assert_eq(fallen.hp, 600, "30% of its own 2000")
	assert_eq(sturdy.hp, 0, "only the picked ally")
	assert_eq(Fixtures.events_on(battle, BattleEventLog.REVIVED, fallen.id).size(), 1)


func test_mass_revive_skips_the_living() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "5", Fixtures.record("Full-Life II", [[2, 2, 4, [100]]]))
	var cleric: Combatant = Fixtures.unit("Cleric")
	var alive: Combatant = Fixtures.unit("Alive")
	var down_a: Combatant = Fixtures.unit("Down A")
	var down_b: Combatant = Fixtures.unit("Down B")
	alive.hp = 10
	down_a.hp = 0
	down_b.hp = 0
	var battle: BattleEngine = Fixtures.engine([cleric, alive, down_a, down_b], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, cleric, "5")
	battle.advance(10)
	assert_eq([down_a.hp, down_b.hp], [1000, 1000])
	assert_eq(alive.hp, 10, "revive does not heal the living")


func test_sacrifice_kos_the_caster_and_restores_the_others() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "11", Fixtures.record("Life Giver", [[2, 5, 11, [100, 100]]]))
	var martyr: Combatant = Fixtures.unit("Martyr")
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	a.hp = 1
	b.mp = 0
	var battle: BattleEngine = Fixtures.engine([martyr, a, b], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, martyr, "11")
	assert_false(martyr.is_alive())
	battle.advance(10)
	assert_eq(a.hp, 1000)
	assert_eq(b.mp, 100)


func test_limit_gauge_fill_and_transfer() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "125", Fixtures.record("Fill LB", [[0, 3, 125, [300, 300]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, "31", Fixtures.record("Entrust", [[1, 5, 31, []]]))
	var giver: Combatant = Fixtures.unit("Giver", {"max_lb": 1000, "lb": 600})
	var filler: Combatant = Fixtures.unit("Filler", {"max_lb": 1000})
	var taker: Combatant = Fixtures.unit("Taker", {"max_lb": 1000, "lb": 100})
	var battle: BattleEngine = Fixtures.engine([giver, filler, taker], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	_cast(battle, filler, "125")
	_cast(battle, giver, "31", taker)
	battle.advance(10)
	assert_eq(filler.lb, 300, "3 crystals, in hundredths")
	assert_eq(giver.lb, 0)
	assert_eq(taker.lb, 700)


func test_regen_restores_at_the_end_of_each_turn_until_it_expires() -> void:
	# 100 + (0.5 x 100 + 0.1 x 100) x 100% = 160 HP per turn, for two turns.
	catalog.add_record(BattleSkill.KIND_ABILITY, "8", Fixtures.record("Regen", [[1, 2, 8, [100, 1, 100, 2]]]))
	var healer: Combatant = Fixtures.unit("Healer", {"attack_frames": "4:100"})
	healer.hp = 100
	var foe: Combatant = Fixtures.monster("Foe", {"atk": 0})
	var battle: BattleEngine = Fixtures.engine([healer], [foe], null, catalog)
	battle.start()
	_cast(battle, healer, "8", healer)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(healer.hp, 260, "one regen tick at the end of turn 1")
	battle.execute(healer.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 3)
	assert_eq(healer.hp, 420, "the second and last")
	assert_null(healer.find_status(BattleStatus.REGEN), "expired")
	battle.execute(healer.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 4)
	assert_eq(healer.hp, 420)
