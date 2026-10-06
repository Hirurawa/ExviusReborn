extends SceneTree

## Which passive effects PassiveAggregator consumes, over every passive a unit can get:
## traits, awakenings, equipment, materia and esper boards. Prints, per effect type,
## how many effects and skills carry it and whether a handler reads it, then the keys
## handled effects carry that no pool reads. Run it when a passives phase starts or
## ends (PASSIVES-HANDOVER.md):
##
##   Godot_v4.6.2-stable_win64_console.exe --headless --path <abs>/godot --quit-after 100000 --script res://tests/tools/passive_coverage.gd
##
## Redirect stdout to a file: output read through a pipe only shows up once the process
## exits. Not a test (the runner loads only test_*.gd). Like run_tests.gd it names no
## autoload or class_name script at compile time: the work waits for the first frame and
## loads PassiveAggregator then.

## Every id column that grants a unit a passive, as SQL returning one text column.
const SOURCES: Dictionary = {
	"trait": "SELECT abilityId FROM unit_series_lv_acquire WHERE abilityId IS NOT NULL",
	"awakening": "SELECT afterSkillId FROM sublimation_recipe",
	"equipment": "SELECT abilityId FROM equip_item WHERE abilityId IS NOT NULL",
	"materia": "SELECT abilityId FROM materia WHERE abilityId IS NOT NULL",
	"esper": "SELECT pieceParam FROM beast_board_piece WHERE pieceType = 21",
}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var aggregator: GDScript = load("res://core/passive_aggregator.gd")
	var db: Node = root.get_node("GameDatabase")
	var resolver: Node = root.get_node("SkillResolver")
	if not resolver.opcode_schemas_ready:
		resolver.load_schemas()

	var ids: Dictionary = {}
	for source in SOURCES:
		for row in db.query(SOURCES[source]):
			for token in str(row.values()[0]).split(",", false):
				var skill_id: String = token.strip_edges()
				if db.has_passive(skill_id):
					ids[skill_id] = true

	var by_type: Dictionary = {}  # type -> { opcode, effects, skills }
	var ignored: Dictionary = {}  # "TYPE.key" -> count
	var total_effects: int = 0
	var consumed_effects: int = 0
	for skill_id in ids:
		var effects: Array = resolver.parse_passive_effects(db.get_passive(skill_id)).get("effects", [])
		var seen: Dictionary = {}
		for effect in effects:
			var effect_type: String = str(effect["type"])
			var row: Dictionary = by_type.get(effect_type, {"opcode": effect["opcode"], "effects": 0, "skills": 0})
			row["effects"] += 1
			if not seen.has(effect_type):
				row["skills"] += 1
				seen[effect_type] = true
			by_type[effect_type] = row
			total_effects += 1
			if aggregator.handles(effect_type):
				consumed_effects += 1
				for key in aggregator.ignored_keys(effect_type, effect["effect"]):
					var name: String = "%s.%s" % [effect_type, key]
					ignored[name] = int(ignored.get(name, 0)) + 1

	print("passives a unit can get: %d; effects %d, consumed %d (%.1f%%)" % [
		ids.size(), total_effects, consumed_effects, 100.0 * consumed_effects / maxf(1.0, total_effects)])
	var types: Array = by_type.keys()
	types.sort_custom(func(a: String, b: String) -> bool: return by_type[a]["effects"] > by_type[b]["effects"])
	for label in ["consumed", "unconsumed"]:
		print("%s:" % label)
		for effect_type in types:
			if aggregator.handles(effect_type) == (label == "consumed"):
				var row: Dictionary = by_type[effect_type]
				print("  %6s  %-34s effects %5d  skills %5d" % [str(row["opcode"]), effect_type, row["effects"], row["skills"]])
	print("keys handled effects carry that no pool reads:")
	for name in ignored:
		print("  %-44s %d" % [name, ignored[name]])
	quit(0)
