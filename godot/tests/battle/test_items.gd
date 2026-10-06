extends "res://tests/test_case.gd"

## Items: the party's shared stock, a queued item held for its unit (the others see one
## fewer and cannot queue or use it), spent only when its action starts, the hold ending
## when the unit acts, is KO'd, picks something else or the turn or wave ends; and the
## builder's stock and real items against the database. Writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const POTION: String = "101000100"  # casts 300210: 200 HP
const HI_POTION: String = "101000200"
const PHOENIX_DOWN: String = "101003100"  # casts 300270: revive at 20%
const ANTIDOTE: String = "102000100"  # useType 2
const BOMB_FRAGMENT: String = "104000100"  # useType 4, thrown at enemies
const TENT: String = "106000100"  # field only, casts nothing


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


## Fixture items: a Potion and a Hi-Potion that restore a flat 200 and 500 HP (opcode 16).
static func _catalog() -> SkillCatalog:
	var catalog: SkillCatalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_ITEM, POTION, Fixtures.record("Potion",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 16, [200]]]))
	catalog.add_record(BattleSkill.KIND_ITEM, HI_POTION, Fixtures.record("Hi-Potion",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 16, [500]]]))
	return catalog


static func _foe(foe_name: String = "Foe", spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(foe_name, full)


## A started battle against one idle foe, with `stock` as the party's items.
static func _battle(party: Array, stock: Dictionary, catalog: SkillCatalog = null) -> BattleEngine:
	var battle: BattleEngine = Fixtures.engine(party, [_foe()], null, catalog if catalog != null else _catalog())
	battle.item_stock = stock.duplicate()
	battle.start()
	return battle


func _inflict(battle: BattleEngine, fighter: Combatant, key: String) -> void:
	assert_eq(battle.debug_edit(fighter.id, &"ailment", 3, key), BattleEngine.OK, "inflict %s" % key)


# === Using an item ===

func test_an_item_runs_its_ability_and_spends_one() -> void:
	var hurt: Combatant = Fixtures.unit("Hurt")
	var battle: BattleEngine = _battle([hurt], {POTION: 2})
	battle.debug_edit(hurt.id, &"hp", 500)
	assert_eq(battle.items_available(POTION, hurt.id), 2)

	assert_eq(battle.execute(hurt.id, BattleCommand.item(POTION, hurt.id)), BattleEngine.OK)
	var started: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_STARTED)
	assert_eq(int(started["kind"]), BattleCommand.Kind.ITEM)
	assert_eq(started["skill_id"], POTION)
	assert_eq(started["skill_name"], "Potion")
	var used: Dictionary = battle.events.last_of_type(BattleEventLog.ITEM_USED)
	assert_eq([int(used["action"]), int(used["actor"]), used["item_id"], int(used["left"])],
		[int(started["action"]), hurt.id, POTION, 1])
	assert_eq(battle.item_stock[POTION], 1)
	assert_eq(battle.events.count_of_type(BattleEventLog.COST_PAID), 0, "an item costs no MP")
	assert_true(battle.format_event(used).contains("item %s, 1 left" % POTION), battle.format_event(used))

	battle.advance(10)
	assert_eq(hurt.hp, 700, "the Potion's 200 HP")


func test_an_item_outside_the_stock_cannot_be_used() -> void:
	var unit: Combatant = Fixtures.unit("Unit")
	var battle: BattleEngine = _battle([unit], {POTION: 1})
	assert_eq(battle.queue_command(unit.id, BattleCommand.item(HI_POTION, unit.id)), BattleEngine.REJECT_NO_ITEMS_LEFT)
	assert_null(unit.queued_command)
	assert_eq(battle.can_execute(unit.id, BattleCommand.item(HI_POTION, unit.id)), BattleEngine.REJECT_NO_ITEMS_LEFT)
	assert_eq(battle.items_available(HI_POTION, unit.id), 0)

	battle.item_stock["999"] = 1
	assert_eq(battle.can_execute(unit.id, BattleCommand.item("999", unit.id)), BattleEngine.REJECT_UNKNOWN_SKILL,
		"an item the catalog cannot cast")


func test_the_last_item_is_gone_once_used() -> void:
	var first: Combatant = Fixtures.unit("First")
	var second: Combatant = Fixtures.unit("Second")
	var battle: BattleEngine = _battle([first, second], {POTION: 1})
	assert_eq(battle.execute(first.id, BattleCommand.item(POTION, first.id)), BattleEngine.OK)
	assert_eq(battle.item_stock[POTION], 0)
	assert_eq(battle.items_available(POTION, second.id), 0)
	assert_eq(battle.execute(second.id, BattleCommand.item(POTION, second.id)), BattleEngine.REJECT_NO_ITEMS_LEFT)
	assert_eq(battle.events.count_of_type(BattleEventLog.ITEM_USED), 1)


# === Holding a queued item ===

func test_a_queued_item_is_held_for_its_unit() -> void:
	var holder: Combatant = Fixtures.unit("Holder")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = _battle([holder, other], {POTION: 1, HI_POTION: 1})
	assert_eq(battle.queue_command(holder.id, BattleCommand.item(POTION, holder.id)), BattleEngine.OK)
	assert_eq(battle.item_stock[POTION], 1, "queueing spends nothing")
	assert_eq(battle.events.count_of_type(BattleEventLog.ITEM_USED), 0)
	assert_eq(battle.items_available(POTION, holder.id), 1, "the holder still sees it")
	assert_eq(battle.items_available(POTION, other.id), 0, "gone from the others' menu")
	assert_eq(battle.items_available(HI_POTION, other.id), 1, "other items are not held")

	assert_eq(battle.queue_command(other.id, BattleCommand.item(POTION, other.id)), BattleEngine.REJECT_NO_ITEMS_LEFT)
	assert_null(other.queued_command)
	assert_eq(battle.events.last_of_type(BattleEventLog.COMMAND_REJECTED)["reason"], BattleEngine.REJECT_NO_ITEMS_LEFT)
	assert_eq(battle.execute(other.id, BattleCommand.item(POTION, other.id)), BattleEngine.REJECT_NO_ITEMS_LEFT,
		"nor can it be used directly")
	assert_eq(battle.queue_command(holder.id, BattleCommand.item(POTION, other.id)), BattleEngine.OK,
		"the holder can queue it again, on another target")

	assert_eq(battle.execute(holder.id), BattleEngine.OK)
	assert_eq(battle.item_stock[POTION], 0)


func test_a_stack_is_held_one_per_unit() -> void:
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var c: Combatant = Fixtures.unit("C")
	var battle: BattleEngine = _battle([a, b, c], {POTION: 2})
	assert_eq(battle.queue_command(a.id, BattleCommand.item(POTION, a.id)), BattleEngine.OK)
	assert_eq(battle.items_available(POTION, b.id), 1)
	assert_eq(battle.queue_command(b.id, BattleCommand.item(POTION, b.id)), BattleEngine.OK)
	assert_eq(battle.items_available(POTION, c.id), 0)
	assert_eq(battle.items_available(POTION, a.id), 1)
	assert_eq(battle.queue_command(c.id, BattleCommand.item(POTION, c.id)), BattleEngine.REJECT_NO_ITEMS_LEFT)

	assert_eq(battle.execute_many([a.id, b.id]), {a.id: BattleEngine.OK, b.id: BattleEngine.OK})
	assert_eq(battle.item_stock[POTION], 0)
	assert_eq(battle.events.count_of_type(BattleEventLog.ITEM_USED), 2)


func test_picking_something_else_releases_the_item() -> void:
	var holder: Combatant = Fixtures.unit("Holder")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = _battle([holder, other], {POTION: 1})
	battle.queue_command(holder.id, BattleCommand.item(POTION, holder.id))
	assert_eq(battle.queue_command(holder.id, BattleCommand.attack()), BattleEngine.OK)
	assert_eq(battle.items_available(POTION, other.id), 1)
	assert_eq(battle.queue_command(other.id, BattleCommand.item(POTION, other.id)), BattleEngine.OK)


func test_a_confused_unit_attacks_and_keeps_the_item() -> void:
	var confused: Combatant = Fixtures.unit("Confused")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = _battle([confused, other], {POTION: 1})
	battle.queue_command(confused.id, BattleCommand.item(POTION, confused.id))
	_inflict(battle, confused, "CONFUSION")
	assert_eq(battle.items_available(POTION, other.id), 0, "held until the unit acts")

	assert_eq(battle.execute(confused.id), BattleEngine.OK)
	var started: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_STARTED)
	assert_eq(int(started["kind"]), BattleCommand.Kind.ATTACK)
	assert_eq(started["forced_by"], "CONFUSION")
	assert_eq(battle.events.count_of_type(BattleEventLog.ITEM_USED), 0, "the item never ran")
	assert_eq(battle.item_stock[POTION], 1)
	assert_eq(battle.items_available(POTION, other.id), 1, "the unit has acted, so the hold is over")


func test_a_ko_releases_the_item() -> void:
	var holder: Combatant = Fixtures.unit("Holder")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = _battle([holder, other], {POTION: 1})
	battle.queue_command(holder.id, BattleCommand.item(POTION, holder.id))
	battle.kill(holder, -1, null)
	assert_eq(battle.items_available(POTION, other.id), 1)
	assert_eq(battle.execute(other.id, BattleCommand.item(POTION, other.id)), BattleEngine.OK)

	# Revived later in the turn, the unit still has the item queued, but none is left.
	battle.revive(holder, 50.0, null, other.id)
	assert_eq(battle.can_execute(holder.id), BattleEngine.REJECT_NO_ITEMS_LEFT)


func test_the_hold_ends_with_the_turn() -> void:
	var sleeper: Combatant = Fixtures.unit("Sleeper")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = _battle([sleeper, other], {POTION: 1})
	battle.queue_command(sleeper.id, BattleCommand.item(POTION, sleeper.id))
	_inflict(battle, sleeper, "SLEEP")
	assert_eq(battle.items_available(POTION, other.id), 0, "a sleeper still holds it this turn")

	battle.execute(other.id)
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.turn == 2), "turn 2")
	assert_null(sleeper.queued_command)
	assert_eq(battle.items_available(POTION, other.id), 1)
	assert_eq(battle.item_stock[POTION], 1)


func test_the_stock_carries_across_waves_and_holds_end() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"atk": 1000, "attack_frames": "4:100"})
	var medic: Combatant = Fixtures.unit("Medic")
	var holder: Combatant = Fixtures.unit("Holder")
	var battle: BattleEngine = Fixtures.engine([hero, medic, holder], [_foe("First", {"hp": 10})], null, _catalog())
	var second: Array[Combatant] = [_foe("Second")]
	battle.queue_wave(func() -> Array[Combatant]: return second)
	battle.item_stock = {POTION: 3}
	battle.start()

	battle.execute(medic.id, BattleCommand.item(POTION, medic.id))
	battle.queue_command(holder.id, BattleCommand.item(POTION, holder.id))
	battle.execute(hero.id)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED), "wave 1 cleared")
	assert_null(holder.queued_command)
	assert_eq(battle.items_available(POTION, medic.id), 2, "the hold ended with the wave")

	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	assert_eq(battle.item_stock[POTION], 2, "what was used stays used")
	assert_eq(battle.execute(holder.id, BattleCommand.item(POTION, holder.id)), BattleEngine.OK)
	assert_eq(int(battle.events.last_of_type(BattleEventLog.ITEM_USED)["left"]), 1)


# === Real data ===

func test_the_builder_stocks_the_combat_item_bar() -> void:
	var builder := BattleBuilder.new(Fixtures.rules(), null, 42)
	var slots: Array = [POTION, "", PHOENIX_DOWN, ANTIDOTE, BOMB_FRAGMENT, TENT, POTION, HI_POTION]
	var owned: Dictionary = {POTION: 50, PHOENIX_DOWN: 3, ANTIDOTE: 2, BOMB_FRAGMENT: 1, TENT: 4}
	assert_eq(builder.item_stock(slots, owned), {POTION: 10, PHOENIX_DOWN: 3, ANTIDOTE: 2, BOMB_FRAGMENT: 1},
		"Potions capped at their carry limit of 10, the Tent casts nothing, the Hi-Potion is not owned")


func test_a_real_potion_and_phoenix_down() -> void:
	var medic: Combatant = Fixtures.unit("Medic")
	var fallen: Combatant = Fixtures.unit("Fallen")
	var battle: BattleEngine = _battle([medic, fallen], {POTION: 1, PHOENIX_DOWN: 1}, DatabaseSkillCatalog.new())
	battle.debug_edit(medic.id, &"hp", 100)
	battle.kill(fallen, -1, null)

	assert_eq(battle.execute(medic.id, BattleCommand.item(POTION, medic.id)), BattleEngine.OK)
	assert_eq(battle.events.last_of_type(BattleEventLog.ACTION_STARTED)["skill_name"], "Potion")
	assert_true(Fixtures.run_until(battle, func() -> bool: return medic.hp > 100, 300), "the Potion lands")
	assert_eq(medic.hp, 300)

	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.turn == 2), "turn 2")
	assert_eq(battle.execute(medic.id, BattleCommand.item(PHOENIX_DOWN, fallen.id)), BattleEngine.OK)
	assert_true(Fixtures.run_until(battle, func() -> bool: return fallen.is_alive(), 300), "the Phoenix Down lands")
	assert_eq(fallen.hp, 200, "20% of 1000 HP")
	assert_eq(battle.item_stock, {POTION: 0, PHOENIX_DOWN: 0})
