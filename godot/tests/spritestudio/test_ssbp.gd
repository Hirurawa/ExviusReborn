extends "res://tests/test_case.gd"

## SsbpData and SsbpPlayer against the game's two SpriteStudio files.

const OPENING: String = "res://assets/map_effect/ev_opening.ssbp"
const MAP_EFFECT: String = "res://assets/map_effect/map_effect.ssbp"


## True when a frame lists every part of its pack exactly once.
static func _lists_each_part_once(states: Array, part_count: int) -> bool:
	var seen: Array = []
	for state in states:
		seen.append(state["part"])
	seen.sort()
	return seen == range(part_count)


func test_both_files_parse() -> void:
	var opening: SsbpData = SsbpData.load_file(OPENING)
	assert_eq(opening.error, "")
	assert_eq(opening.version, 1)
	assert_eq(opening.cells.size(), 12)
	assert_eq(opening.packs.size(), 9)
	assert_eq(opening.cells[4].name, "sky")
	assert_eq(opening.cells[4].rect, Rect2(2, 368, 760, 560))
	var effects: SsbpData = SsbpData.load_file(MAP_EFFECT)
	assert_eq(effects.error, "")
	assert_eq(effects.cells.size(), 121)
	assert_eq(effects.packs.size(), 74)
	assert_false(effects.find("cosmos/anime").is_empty(), "the Farplane's backdrop")


func test_every_frame_of_the_opening_lists_every_part_once() -> void:
	var data: SsbpData = SsbpData.load_file(OPENING)
	var bad: Array = []
	for pack in data.packs.values():
		for animation in pack.animations.values():
			for f in animation.frame_count:
				if not _lists_each_part_once(data.frame_states(pack, animation, f), pack.parts.size()):
					bad.append("%s/%s %d" % [pack.name, animation.name, f])
	assert_eq(bad, [])


func test_map_effect_frames_decode() -> void:
	var data: SsbpData = SsbpData.load_file(MAP_EFFECT)
	var bad: Array = []
	for pack in data.packs.values():
		for animation in pack.animations.values():
			for f in [0, animation.frame_count / 2, animation.frame_count - 1]:
				if not _lists_each_part_once(data.frame_states(pack, animation, f), pack.parts.size()):
					bad.append("%s/%s %d" % [pack.name, animation.name, f])
	assert_eq(bad, [])


func test_the_opening_sky_hangs_from_the_top_of_a_640_wide_screen() -> void:
	var data: SsbpData = SsbpData.load_file(OPENING)
	var found: Array = data.find("opening_bg/anime")
	assert_eq(found[1].fps, 60)
	assert_eq(found[1].frame_count, 1200)
	var states: Array = data.frame_states(found[0], found[1], 0)
	var sky: Dictionary = states.filter(func(s: Dictionary) -> bool: return found[0].parts[s["part"]].name == "sky")[0]
	assert_almost_eq(sky["anchor"].x, 60.0 / 760.0, 0.0001, "60 px over each side of 640")
	assert_eq(sky["anchor"].y, 0.0)
	var mountains: Dictionary = states.filter(func(s: Dictionary) -> bool: return found[0].parts[s["part"]].name == "ins_mt:anime")[0]
	assert_eq(mountains["position"], Vector2(0, -468))
	assert_eq(mountains["instance"]["speed"], 0.5)


func test_instance_frames_follow_the_ss5_timing() -> void:
	var late: Dictionary = {"keyframe": 260, "start": 0, "end": 199, "speed": 1.0, "loops": 1, "loop_flags": SsbpData.INSTANCE_INFINITY}
	assert_eq(SsbpData.instance_frame(late, 100), -1, "not started")
	assert_eq(SsbpData.instance_frame(late, 300), 40)
	assert_eq(SsbpData.instance_frame(late, 460), 0, "loops forever")
	var once: Dictionary = {"keyframe": 0, "start": 0, "end": 99, "speed": 1.0, "loops": 1, "loop_flags": 0}
	assert_eq(SsbpData.instance_frame(once, 250), 99, "holds its last frame")
	var half: Dictionary = {"keyframe": 0, "start": 0, "end": 299, "speed": 0.5, "loops": 1, "loop_flags": SsbpData.INSTANCE_INFINITY}
	assert_eq(SsbpData.instance_frame(half, 100), 50)


func test_the_old_converter_build_reads_its_shorter_initial_states() -> void:
	# airship_sky comes from the Nov 2014 converter: 76-byte initial states.
	var data: SsbpData = SsbpData.load_file("res://assets/map_effect/airship_sky.ssbp")
	assert_eq(data.error, "")
	var found: Array = data.find("back/anime")
	var bad: Array = []
	for f in found[1].frame_count:
		var states: Array = data.frame_states(found[0], found[1], f)
		if not _lists_each_part_once(states, found[0].parts.size()):
			bad.append("parts %d" % f)
		for state in states:
			if int(state["cell"]) >= data.cells.size() or int(state["opacity"]) > 255:
				bad.append("state %d part %d" % [f, state["part"]])
	assert_eq(bad, [])
	for initial in found[1].initial:
		assert_eq(initial["anchor"], Vector2(0.5, 0.5), "SpriteStudio's default anchor")


func test_a_battle_background_stands_on_its_origin() -> void:
	var path: String = "res://assets/battleBg1/battle_bg_0005_01.ssbp"
	if not FileAccess.file_exists(path):
		return
	var player := SsbpPlayer.new()
	player.open(path, "back/anime")
	var bounds := Rect2(player.quads(0)[0]["points"][0], Vector2.ZERO)
	for quad in player.quads(0):
		for point in quad["points"]:
			bounds = bounds.expand(point)
	player.free()
	assert_eq(bounds.position.x, -480.0, "960 wide, centred on x = 0")
	assert_eq(bounds.end.x, 480.0)
	assert_true(bounds.position.y < -400.0 and bounds.end.y < 100.0, "drawn above the origin: %s" % bounds)


func test_the_viewer_lists_every_file_and_its_animations() -> void:
	var viewer: Node2D = load("res://features/spritestudio/SsbpViewer.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(viewer)
	var files: OptionButton = viewer.get("_files")
	var animations: OptionButton = viewer.get("_animations")
	var names: Array = range(files.item_count).map(func(i: int) -> String: return files.get_item_text(i))
	assert_eq(names.filter(func(name: String) -> bool: return name.begins_with("map_effect/")).size(), 121)
	assert_eq(files.get_item_text(files.selected), "map_effect/ev_opening.ssbp")
	assert_eq(animations.get_item_text(animations.selected), "opening_bg/anime")
	var player: SsbpPlayer = viewer.get("_player")
	assert_eq(player.frame_count(), 1200)
	var camera: Camera2D = viewer.get("_camera")
	var bounds: Rect2 = viewer.get("_bounds")
	assert_true(bounds.has_point(camera.position), "fitted on the sky: %s, camera at %s" % [bounds, camera.position])
	viewer.get_parent().remove_child(viewer)
	viewer.free()


func test_the_player_places_the_sky_quad() -> void:
	var player := SsbpPlayer.new()
	player.ssbp_path = OPENING
	player.animation = "opening_bg/anime"
	player.playing = false
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	var quads: Array = player.quads(0)
	assert_true(quads.size() > 10, "%d quads" % quads.size())
	var sky: Array = quads.filter(func(q: Dictionary) -> bool:
		var r: Rect2 = Rect2(q["points"][0], Vector2.ZERO)
		for p in q["points"]:
			r = r.expand(p)
		return r.size.is_equal_approx(Vector2(760, 560)))
	assert_eq(sky.size(), 1, "one opaque sky (sky_1 is at opacity 0)")
	var bounds := Rect2(sky[0]["points"][0], Vector2.ZERO)
	for p in sky[0]["points"]:
		bounds = bounds.expand(p)
	assert_almost_eq(bounds.position.x, -60.0, 0.01, "60 px over each side of 640")
	assert_almost_eq(bounds.position.y, 0.0, 0.01, "hanging from the top")
	player.get_parent().remove_child(player)
	player.free()
