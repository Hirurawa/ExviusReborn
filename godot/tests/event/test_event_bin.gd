extends "res://tests/test_case.gd"

## EventBin against the whole dump (CUTSCENE-PLAN.md section 2): every bin parses to its
## exact size, every script frames exactly, and the prologue bin 111010105 has the
## scenes the story events select.

const ROOT: String = "res://assets/town_data"


func _all_bin_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var dir: DirAccess = DirAccess.open(ROOT)
	for folder in dir.get_directories():
		for file in DirAccess.get_files_at(ROOT.path_join(folder)):
			if file.ends_with("_event.bin"):
				paths.append(ROOT.path_join(folder).path_join(file))
	return paths


## True when `code` is a whole number of <op> <u16 length> <payload> frames.
static func _frames_exactly(code: PackedByteArray) -> bool:
	var at: int = 0
	while at < code.size():
		if at + 3 > code.size():
			return false
		at += 3 + EventBin.u16(code, at + 1)
	return at == code.size()


func test_every_bin_in_the_dump_parses_to_its_exact_size() -> void:
	var paths: PackedStringArray = _all_bin_paths()
	assert_eq(paths.size(), 502, "event bins in the dump")
	var records: int = 0
	var scripts: int = 0
	var unframed: int = 0
	var errors := PackedStringArray()
	var mismatches: Dictionary = {}
	for path in paths:
		var bin: EventBin = EventBin.load_file(path)
		if bin.error != "":
			errors.append(bin.error)
			continue
		if not bin.size_mismatches.is_empty():
			mismatches[path.get_file()] = bin.size_mismatches
		for layer in bin.layers.values():
			records += layer.records.size()
			for record in layer.records:
				for page in record.pages:
					if page.code.is_empty():
						continue
					scripts += 1
					if not _frames_exactly(page.code):
						unframed += 1
	assert_eq(errors, PackedStringArray(), "parse errors")
	assert_eq(records, 5668, "records")
	assert_eq(scripts, 875, "scripts")
	assert_eq(unframed, 0, "scripts that do not frame exactly")
	assert_eq(mismatches, {"183030102_event.bin": [[3, 6]]}, "the one layer whose records outrun its size")


func test_the_prologue_bin_holds_the_scenes_its_story_events_select() -> void:
	var bin: EventBin = EventBin.load_file(EventBin.find_path("111010105"))
	assert_eq(bin.error, "")
	assert_eq(bin.version, 1045)
	assert_eq(bin.start_layer, 65)
	assert_eq(bin.assets, {0x7919: "npc900101100.png"})
	var crystal: EventBin.Page = bin.get_layer(61).record_by_slot(9).pages[0]
	assert_eq(crystal.conditions, [[19100010, 1]])
	assert_eq(crystal.trigger, EventBin.TRIGGER_AUTORUN)
	assert_eq(crystal.labels, PackedInt32Array([1335, 1338]))
	assert_eq(crystal.code.size(), 1338)
	assert_eq(bin.get_layer(61).record_by_slot(0).pages.size(), 2, "the night-sky record has two pages")

	assert_eq(bin.autorun_pages(61, {19100010: 1}), [crystal], "main0-0_OP")
	assert_eq(bin.autorun_pages(65, {19100010: 0, 19100011: 1}), [bin.get_layer(65).record_by_slot(6).pages[0]], "main1-1_OP1")
	assert_eq(bin.autorun_pages(67, {19100012: 1}), [bin.get_layer(67).record_by_slot(3).pages[0]], "main1-1_OP2")
	assert_eq(bin.autorun_pages(61, {}), [], "nothing runs with no switch set")


func test_record_graphics_name_their_sheets() -> void:
	var bin: EventBin = EventBin.load_file(EventBin.find_path("111010105"))
	var layer: EventBin.Layer = bin.get_layer(65)
	assert_eq(layer.record_by_slot(2).pages[0].graphic, {"character": 200100120}, "a Grandshelt soldier")
	assert_eq(layer.record_by_slot(1).pages[0].graphic, {"character": 13})
	var deck: EventBin.Layer = bin.get_layer(61)
	assert_eq(deck.record_by_slot(2).pages[0].graphic, {"image": 11001, "src_x": 58, "src_y": 232})
	assert_eq(deck.record_by_slot(9).pages[0].graphic, {}, "the script holder draws nothing")


func test_bins_before_version_1025_use_u16_record_ids() -> void:
	# An older build of 112010101, packed in the next event's folder.
	var bin: EventBin = EventBin.load_file(ROOT.path_join("112010102/112010101_event.bin"))
	assert_eq(bin.error, "")
	assert_eq(bin.version, 1019)
	assert_eq(bin.actor_ref_size(), 3)
	var layer: EventBin.Layer = bin.get_layer(77)
	assert_eq(layer.records.size(), 1)
	assert_eq(layer.records[0].slot, 0)
	assert_eq(layer.records[0].x, 580)


func test_an_image_id_of_zero_is_an_effect_file() -> void:
	var bin: EventBin = EventBin.load_file(EventBin.find_path("141010803"))
	assert_eq(bin.error, "")
	var effects: Array = []
	for layer in bin.layers.values():
		for record in layer.records:
			for page in record.pages:
				if page.graphic.has("effect"):
					effects.append(page.graphic["effect"])
	assert_eq(effects, ["map_bahamut_awakening.bmb"])


func test_a_truncated_bin_reports_an_error_instead_of_crashing() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(EventBin.find_path("111010105"))
	var bin := EventBin.new()
	bin.parse(bytes.slice(0, 5000))
	assert_ne(bin.error, "")
