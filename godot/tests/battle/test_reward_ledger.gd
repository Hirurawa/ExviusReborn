extends "res://tests/test_case.gd"

## RewardLedger from scripted event lists: EXP, gil, the drop roll and the kills from
## defeated enemies (once each), nothing from party members, the items used, and drops
## that a seed replays. Fixture combatants; writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var _killed: Array[String] = []
var _dropped: Array = []


## An engine (not started) holding one party member and `foes`; enough for the ledger's
## lookups.
static func _engine(foes: Array) -> BattleEngine:
	return Fixtures.engine([Fixtures.unit("Hero")], foes)


static func _foe(template_id: String, exp_value: int, gil_value: int, loot: Array = []) -> Combatant:
	var foe: Combatant = Fixtures.monster("Foe %s" % template_id, {"template_id": template_id})
	foe.meta = {"exp": exp_value, "gil": gil_value, "loot": {"drops": loot}}
	return foe


static func _defeated(target: Combatant) -> Dictionary:
	return {"type": BattleEventLog.COMBATANT_DEFEATED, "target": target.id, "by": -1, "action": -1}


func _ledger(seed_value: int = 7) -> RewardLedger:
	var ledger := RewardLedger.new(seed_value)
	ledger.monster_killed.connect(func(template_id: String) -> void: _killed.append(template_id))
	ledger.item_dropped.connect(func(enemy_id: int, item_id: String) -> void: _dropped.append([enemy_id, item_id]))
	return ledger


func test_defeated_enemies_pay_exp_and_gil_and_count_as_kills() -> void:
	var goblin: Combatant = _foe("100", 30, 12)
	var bomb: Combatant = _foe("200", 50, 0)
	var battle: BattleEngine = _engine([goblin, bomb])
	var ledger: RewardLedger = _ledger()
	ledger.record(battle, [_defeated(goblin)])
	ledger.record(battle, [{"type": BattleEventLog.HIT_LANDED, "target": bomb.id}, _defeated(bomb)])
	assert_eq([ledger.unit_exp, ledger.gil], [80, 12])
	assert_eq(_killed, ["100", "200"], "the monster dictionary ids, as the old engine recorded")
	assert_true(ledger.drops.is_empty(), "no loot, no drop")


func test_party_members_and_repeated_defeats_pay_nothing() -> void:
	var goblin: Combatant = _foe("100", 30, 12)
	var battle: BattleEngine = _engine([goblin])
	var hero: Combatant = battle.party[0]
	var ledger: RewardLedger = _ledger()
	ledger.record(battle, [_defeated(hero), _defeated(goblin), _defeated(goblin)])
	assert_eq([ledger.unit_exp, ledger.gil], [30, 12], "an enemy pays once, even if it comes back")
	assert_eq(_killed, ["100"])


func test_items_used_are_counted_by_id() -> void:
	var battle: BattleEngine = _engine([_foe("100", 0, 0)])
	var ledger: RewardLedger = _ledger()
	ledger.record(battle, [
		{"type": BattleEventLog.ITEM_USED, "item_id": "101000100", "left": 2},
		{"type": BattleEventLog.ITEM_USED, "item_id": "101003100", "left": 0},
		{"type": BattleEventLog.ITEM_USED, "item_id": "101000100", "left": 1},
	])
	assert_eq(ledger.used_items, {"101000100": 2, "101003100": 1})


func test_drops_roll_half_the_time_and_a_seed_replays_them() -> void:
	var foes: Array = []
	for i in range(40):
		foes.append(_foe("100", 1, 1, ["1001", "1002", "1003"]))
	var battle: BattleEngine = _engine(foes)
	var events: Array = foes.map(func(foe: Combatant) -> Dictionary: return _defeated(foe))

	var ledger: RewardLedger = _ledger(11)
	ledger.record(battle, events)
	assert_true(ledger.drops.size() > 5 and ledger.drops.size() < 35, "about half drop: %d of 40" % ledger.drops.size())
	for item_id in ledger.drops:
		assert_has(["1001", "1002", "1003"], item_id)
	assert_eq(_dropped.size(), ledger.drops.size(), "one item_dropped per drop")
	assert_eq(_dropped[0][1], ledger.drops[0])
	assert_true(foes.any(func(foe: Combatant) -> bool: return foe.id == _dropped[0][0]), "names the enemy that dropped it")

	var replay := RewardLedger.new(11)
	replay.record(battle, events)
	assert_eq(replay.drops, ledger.drops, "the same seed drops the same items")
	var other := RewardLedger.new(12)
	other.record(battle, events)
	assert_ne(other.drops, ledger.drops, "another seed rolls differently")
