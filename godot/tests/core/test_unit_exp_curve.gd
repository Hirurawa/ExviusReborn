extends "res://tests/test_case.gd"

## Unit levels come from the unit's accumulated xp. unit_exp_pattern's needExp at level
## L is the xp from level L-1 to L, so the xp to reach a level is the sum of the rows up
## to it. Uses Elfreeda (exp pattern 30) and reads GameDatabase; writes nothing.

const ELFREEDA_6: String = "100009806"
const ELFREEDA_7: String = "100009807"
## Pattern 30 running totals: needExp[36] is 10390, levels 2-100 sum to 1,993,672 and
## levels 101-120 to exactly 45,000,000.
const XP_TO_LV35: int = 138242
const XP_TO_LV36: int = 148632
const XP_TO_LV100: int = 1993672
const XP_TO_LV101: int = 2340422


## Hydration computes final stats, which parse passives.
func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


func _unit(unit_id: String, rarity: int, xp: int) -> Dictionary:
	return {"unit_id": unit_id, "instance_id": "test_" + unit_id, "current_rarity": rarity, "xp": xp}


func test_level_35_needs_its_next_row_to_level_up() -> void:
	var unit: Dictionary = _unit(ELFREEDA_6, 6, XP_TO_LV35)
	unit["level"] = 35
	assert_eq(UnitService.calculate_next_xp_for_unit(unit), 10390)
	unit["xp"] = XP_TO_LV35 + 390
	assert_eq(UnitService.calculate_next_xp_for_unit(unit), 10000)


func test_level_progress_uses_running_totals() -> void:
	var unit: Dictionary = _unit(ELFREEDA_6, 6, 0)
	var progress: Dictionary = UnitService.level_progress_at_xp(unit, XP_TO_LV35 + 390)
	assert_eq(progress["level"], 35)
	assert_eq(progress["level_floor"], XP_TO_LV35)
	assert_eq(progress["next_floor"], XP_TO_LV36)
	assert_eq(UnitService.level_progress_at_xp(unit, XP_TO_LV36 - 1)["level"], 35, "one xp short of 36")
	assert_eq(UnitService.level_progress_at_xp(unit, XP_TO_LV36)["level"], 36)
	assert_eq(UnitService.level_progress_at_xp(unit, 0)["level"], 1)
	assert_eq(UnitService.level_progress_at_xp(unit, 20)["level"], 1)
	assert_eq(UnitService.level_progress_at_xp(unit, 21)["level"], 2)


func test_six_star_caps_at_level_100() -> void:
	var unit: Dictionary = _unit(ELFREEDA_6, 6, 0)
	assert_eq(UnitService.level_progress_at_xp(unit, XP_TO_LV100 - 1)["level"], 99)
	var progress: Dictionary = UnitService.level_progress_at_xp(unit, XP_TO_LV101 * 4)
	assert_eq(progress["level"], 100)
	assert_true(progress["at_max_level"])


func test_hydration_derives_level_from_accumulated_xp() -> void:
	var hydrated: Array = UnitService._hydrate_owned_units([_unit(ELFREEDA_6, 6, XP_TO_LV35 + 390)])
	assert_eq(hydrated[0]["level"], 35)
	assert_eq(hydrated[0]["next_xp"], 10000)


func test_seven_star_save_with_too_little_xp_loads_at_level_101() -> void:
	# 346750 is the old reading's "xp to reach 101" (needExp[101] alone).
	var hydrated: Array = UnitService._hydrate_owned_units([_unit(ELFREEDA_7, 7, 346750)])
	assert_eq(hydrated[0]["level"], 101)
	assert_eq(hydrated[0]["xp"], XP_TO_LV101)
	assert_eq(hydrated[0]["next_xp"], 378273, "needExp[102]")
