extends "res://tests/test_case.gd"

## Chain math: ChainTracker on hand-placed hits. Multipliers are percentages.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var rules: BattleRules
var target: Combatant
var a: Combatant
var b: Combatant


func before_each() -> void:
	rules = Fixtures.rules()
	target = Fixtures.monster("Target")
	target.id = 10
	a = Fixtures.unit("A")
	a.id = 1
	b = Fixtures.unit("B")
	b.id = 2


func _hit(source: Combatant, frame: int, elements: Array = []) -> int:
	return ChainTracker.register_hit(target, source, frame, PackedInt32Array(elements), rules)


func test_first_hit_starts_a_chain_at_one() -> void:
	assert_eq(_hit(a, 0), 100)
	assert_eq(target.chain_count, 0)


func test_alternating_sources_within_the_window_build_the_chain() -> void:
	_hit(a, 0)
	assert_eq(_hit(b, 10), 110, "second hit: a normal chain, +10")
	assert_eq(target.chain_count, 1)
	assert_eq(_hit(a, 30), 120, "third hit, exactly 20 frames later")
	assert_eq(target.chain_count, 2)
	assert_false(target.chain_spark)


func test_gap_longer_than_the_window_breaks_the_chain() -> void:
	_hit(a, 0)
	_hit(b, 10)
	assert_eq(_hit(a, 31), 100, "21 frames after the last hit")
	assert_eq(target.chain_count, 0)


func test_same_source_twice_in_a_row_breaks_the_chain() -> void:
	_hit(a, 0)
	_hit(b, 5)
	assert_eq(_hit(b, 8), 100)
	assert_eq(target.chain_count, 0)


func test_same_source_can_extend_when_the_rule_is_off() -> void:
	rules.chain_same_source_breaks = false
	_hit(a, 0)
	assert_eq(_hit(a, 5), 110)


func test_a_hit_on_the_same_frame_is_a_spark_chain() -> void:
	var c: Combatant = Fixtures.unit("C")
	c.id = 3
	_hit(a, 0)
	assert_eq(_hit(b, 0), 140, "no delay from the previous hit: +40 instead of +10")
	assert_true(target.chain_spark)
	assert_eq(_hit(a, 10), 150, "the first hit on a later frame is a normal chain")
	assert_false(target.chain_spark)
	assert_eq(_hit(c, 10), 190, "the next one on that frame sparks")
	assert_true(target.chain_spark)


func test_element_step_counts_shared_elements() -> void:
	_hit(a, 0, [1])
	assert_eq(_hit(b, 5, [1, 2]), 130, "one shared element: 10 + 20")
	assert_eq(target.chain_shared_elements, 1)
	assert_eq(_hit(a, 10, [1, 2]), 180, "two shared elements: 10 + 40")
	assert_eq(_hit(b, 15, [3]), 190, "no shared element: 10")
	assert_eq(target.chain_shared_elements, 0)
	assert_eq(_hit(a, 15, [3]), 250, "a spark with one shared element: 40 + 20")


func test_the_thirtieth_normal_chain_reaches_the_cap_exactly() -> void:
	var percent: int = 0
	for i in range(31):
		percent = _hit(a if i % 2 == 0 else b, i * 5)
		if i == 29:
			assert_eq(percent, 390, "chain 29")
	assert_eq(target.chain_count, 30)
	assert_eq(percent, 400)


func test_hits_stay_capped_while_the_chain_keeps_rising() -> void:
	var percent: int = 0
	for i in range(33):
		percent = _hit(a if i % 2 == 0 else b, i * 5)
	assert_eq(target.chain_count, 32)
	assert_eq(percent, 400, "without a cap passive a hit takes at most 4x")
	assert_eq(target.chain_percent, 420, "the chain itself grows toward the ceiling")
	for i in range(33, 60):
		_hit(a if i % 2 == 0 else b, i * 5)
	assert_eq(target.chain_percent, 600, "and stops at 6x")


## Two units chaining as in the wiki's tables, on a fresh target: they alternate 5
## frames apart, or, with `spark`, hit on the same frame in pairs 10 frames apart (the
## first of a pair is a normal chain, the second a spark). Returns the chain count on
## which the multiplier first reaches `cap` (default rules.chain_cap_pct).
func _chains_to_cap(spark: bool, elements: Array, cap: int = -1) -> int:
	var goal: int = cap if cap > 0 else rules.chain_cap_pct
	target.reset_chain()
	for i in range(200):
		var frame: int = floori(float(i) / 2.0) * 10 if spark else i * 5
		var percent: int = _hit(a if i % 2 == 0 else b, frame, elements)
		if percent >= goal:
			return target.chain_count
	return -1


func test_chains_to_the_cap_match_the_wiki_table() -> void:
	assert_eq(_chains_to_cap(false, []), 30, "normal, no element")
	assert_eq(_chains_to_cap(true, []), 12, "spark, no element")
	assert_eq(_chains_to_cap(false, [1]), 10, "normal, one element")
	assert_eq(_chains_to_cap(true, [1]), 7, "spark, one element")


func test_chains_to_a_raised_cap_match_the_wiki_table() -> void:
	# Cap passives raise the modifier cap by 200%, to 500% (6x), for both units.
	a.passives.chain_cap_raise = 200
	b.passives.chain_cap_raise = 200
	assert_eq(_chains_to_cap(false, [], 600), 50, "normal, no element")
	assert_eq(_chains_to_cap(true, [], 600), 20, "spark, no element")
	assert_eq(_chains_to_cap(false, [1], 600), 17, "normal, one element")
	assert_eq(_chains_to_cap(true, [1], 600), 11, "spark, one element")


func test_a_cap_passive_raises_only_its_own_hits() -> void:
	a.passives.chain_cap_raise = 200
	var last: Dictionary = {}
	for i in range(40):
		var source: Combatant = a if i % 2 == 0 else b
		last[source.name] = _hit(source, i * 5)
	assert_eq(last["A"], 480, "hit 38: A takes the chain as it stands")
	assert_eq(last["B"], 400, "hit 39: B stays at 4x")


func test_a_raised_unit_uses_a_chain_others_built() -> void:
	# Wiki: "This increased cap works even if the unit use an existing chain provided by
	# other units without these passives."
	var c: Combatant = Fixtures.unit("C", {"passives": {"chain_cap_raise": 200}})
	c.id = 3
	for i in range(45):
		_hit(a if i % 2 == 0 else b, i * 5)
	assert_eq(_hit(c, 45 * 5), 550, "the 46th hit")


func test_cap_raises_stop_at_the_ceiling() -> void:
	a.passives.chain_cap_raise = 400
	assert_eq(ChainTracker.attacker_cap(a, rules), 600)
	assert_eq(ChainTracker.attacker_cap(b, rules), 400)


func test_a_chain_boost_adds_to_the_units_own_chained_hits() -> void:
	a.passives.chain_boost_pct = 100
	assert_eq(_hit(a, 0), 100, "the first hit is not chained: no boost")
	assert_eq(_hit(b, 5), 110)
	assert_eq(_hit(a, 10), 220, "the chain's 120 plus 100")
	assert_eq(_hit(b, 15), 130, "B's hits and the chain itself are not boosted")


func test_a_chain_boost_stops_at_the_attackers_cap() -> void:
	a.passives.chain_boost_pct = 100
	for i in range(26):
		_hit(a if i % 2 == 0 else b, i * 5)
	assert_eq(target.chain_percent, 350)
	assert_eq(_hit(a, 26 * 5), 400, "360 + 100 capped at 4x")
	a.passives.chain_cap_raise = 200
	assert_eq(_hit(b, 27 * 5), 370)
	assert_eq(_hit(a, 28 * 5), 480, "380 + 100 under a raised cap")


func test_enemy_hits_chain_like_party_hits() -> void:
	var party_target: Combatant = Fixtures.unit("Victim")
	var e1: Combatant = Fixtures.monster("E1")
	e1.id = 21
	var e2: Combatant = Fixtures.monster("E2")
	e2.id = 22
	ChainTracker.register_hit(party_target, e1, 0, PackedInt32Array(), rules)
	assert_eq(ChainTracker.register_hit(party_target, e2, 5, PackedInt32Array(), rules), 110, "two enemies")
	assert_eq(ChainTracker.register_hit(party_target, e2, 9, PackedInt32Array(), rules), 100, "same enemy twice")


func test_enemy_hits_do_not_chain_when_the_rule_is_off() -> void:
	rules.enemy_hits_chain = false
	var party_target: Combatant = Fixtures.unit("Victim")
	var e1: Combatant = Fixtures.monster("E1")
	e1.id = 21
	var e2: Combatant = Fixtures.monster("E2")
	e2.id = 22
	assert_eq(ChainTracker.register_hit(party_target, e1, 0, PackedInt32Array(), rules), 100)
	assert_eq(ChainTracker.register_hit(party_target, e2, 5, PackedInt32Array(), rules), 100)
	assert_eq(party_target.chain_count, 0)


func test_sources_are_told_apart_by_id_not_slot() -> void:
	# The old engine compared slot indices without the team, so party slot 0 and enemy
	# slot 0 counted as the same attacker.
	var foe: Combatant = Fixtures.monster("Foe")
	foe.id = 30
	foe.slot = 0
	a.slot = 0
	_hit(a, 0)
	assert_eq(_hit(foe, 5), 110)
