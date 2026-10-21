extends "res://tests/test_case.gd"

## EventInterpreter on small hand-built scripts: one opcode's rule per test, timed in
## frames (CUTSCENE-PLAN.md sections 5 and 8). The stage draws no map.

var _stage: EventStage


func before_each() -> void:
	_stage = EventStage.new()
	_stage.draw_map = false
	(Engine.get_main_loop() as SceneTree).root.add_child(_stage)
	var bin := EventBin.new()
	bin.version = 1045
	_stage.setup(bin, "test")


func after_each() -> void:
	_stage.get_parent().remove_child(_stage)
	_stage.free()


## Builds the page and runs it until it ends or `max_frames` pass. With `taps` the
## cinema window is tapped whenever its cursor shows.
func _run(script: PackedByteArray, labels: PackedInt32Array = PackedInt32Array(), max_frames: int = 2000, taps: bool = true) -> EventInterpreter:
	var interpreter: EventInterpreter = _start(script, labels)
	_frames(interpreter, max_frames, taps)
	return interpreter


func _start(script: PackedByteArray, labels: PackedInt32Array = PackedInt32Array()) -> EventInterpreter:
	var page := EventBin.Page.new()
	page.code = script
	page.labels = labels
	return EventInterpreter.new(_stage.bin, page, _stage, {})


func _frames(interpreter: EventInterpreter, count: int, taps: bool = true) -> void:
	for i in count:
		if interpreter.done:
			return
		_stage.tick()
		interpreter.step()
		if taps and _stage.dialogue.state == EventDialogue.State.CURSOR:
			_stage.tap()


static func _frame(op: int, payload: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray([op, payload.size() >> 8, payload.size() & 0xff])
	out.append_array(payload)
	return out


static func _u16(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 8) & 0xff, value & 0xff])


static func _u32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff])


static func _party(index: int) -> PackedByteArray:
	return PackedByteArray([0]) + _u32(index)


static func _move(ref: PackedByteArray, relative: bool, x: int, y: int, speed: int) -> PackedByteArray:
	var payload: PackedByteArray = ref + PackedByteArray([0, 1 if relative else 0]) + _u16(x & 0xffff) + _u16(y & 0xffff)
	payload.append_array(PackedByteArray([speed, 1, 1, 0]))
	return _frame(EventInterpreter.OP_MOVE, payload)


static func _camera(relative: bool, x: int, y: int, speed: int) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray([1 if relative else 0]) + _u16(x & 0xffff) + _u16(y & 0xffff)
	payload.append_array(PackedByteArray([0, speed]))
	return _frame(EventInterpreter.OP_CAMERA, payload)


static func _advance() -> PackedByteArray:
	return _frame(EventInterpreter.OP_ADVANCE)


static func _end() -> PackedByteArray:
	return _frame(EventInterpreter.OP_END)


func test_a_move_speed_is_tenths_of_a_pixel_per_frame() -> void:
	var script: PackedByteArray = _move(_party(1), false, 100, 100, 0) + _move(_party(1), true, 0, 58, 20) + _advance() + _end()
	var interpreter: EventInterpreter = _start(script)
	_frames(interpreter, 10)
	var rain: EventActor = _stage.actors["pc1"]
	assert_almost_eq(rain.position.y, 118.0, 0.01, "nine frames at 2 px")
	assert_eq(rain.facing, EventActor.DOWN, "turned to the move")
	_frames(interpreter, 100)
	assert_eq(rain.position, Vector2(100, 158))
	assert_eq(interpreter.frame, 30, "58 px at 2 px a frame: 29 frames after the start")


func test_a_diagonal_move_goes_straight() -> void:
	var script: PackedByteArray = _move(_party(1), false, 0, 0, 0) + _move(_party(1), true, 30, 40, 50) + _advance() + _end()
	var interpreter: EventInterpreter = _run(script)
	assert_eq(_stage.actors["pc1"].position, Vector2(30, 40))
	assert_eq(interpreter.frame, 11, "50 px at 5 px a frame")


func test_wait_resumes_n_frames_later() -> void:
	var interpreter: EventInterpreter = _run(_frame(EventInterpreter.OP_WAIT, _u16(90)) + _end())
	assert_eq(interpreter.frame, 91)
	assert_eq(interpreter.end_reason, "end")


func test_goto_jumps_to_its_label() -> void:
	var skipped: PackedByteArray = _frame(EventInterpreter.OP_TEXT, _u32(210806))
	var head: PackedByteArray = _frame(EventInterpreter.OP_GOTO, _u16(1))
	var script: PackedByteArray = head + skipped + _end()
	var interpreter: EventInterpreter = _run(script, PackedInt32Array([head.size() + skipped.size()]))
	assert_eq(_stage.lines_shown, [] as Array[int])
	assert_eq(interpreter.end_reason, "end")


func test_advance_waits_for_the_line_to_be_tapped_away() -> void:
	var script: PackedByteArray = _frame(EventInterpreter.OP_TEXT, _u32(1)) + _advance() + _end()
	var interpreter: EventInterpreter = _start(script)
	_frames(interpreter, 300, false)
	assert_false(interpreter.done, "still waiting on the tap")
	assert_eq(_stage.dialogue.state, EventDialogue.State.CURSOR)
	assert_eq(_stage.dialogue.shown_text(), "[text 1]")
	assert_true(_stage.tap())
	_frames(interpreter, 1, false)
	assert_true(interpreter.done)


func test_a_tap_completes_a_line_that_is_still_appearing() -> void:
	_stage.dialogue.show_line(1, "Is that...<wait=20>a crystal!?<wait=90>")
	_stage.tick()
	assert_eq(_stage.dialogue.state, EventDialogue.State.REVEAL)
	assert_true(_stage.tap())
	assert_eq(_stage.dialogue.shown_text(), "Is that...a crystal!?")
	assert_eq(_stage.dialogue.state, EventDialogue.State.CURSOR, "the trailing wait is skipped too")


func test_waits_inside_a_line_pause_and_the_last_one_waits_for_the_tap() -> void:
	_stage.dialogue.show_line(1, "Is that...<wait=20>a crystal!?<wait=90>")
	var frames: int = 0
	while _stage.dialogue.state == EventDialogue.State.REVEAL and frames < 1000:
		_stage.tick()
		frames += 1
	# 21 characters at 2/3 a frame and the 20-frame pause; <wait=90> is the keypress.
	assert_almost_eq(float(frames), 21.0 * 1.5 + 20.0, 3.0)
	assert_eq(_stage.dialogue.state, EventDialogue.State.CURSOR)


func test_a_line_that_closes_by_itself_runs_its_last_wait() -> void:
	_stage.dialogue.show_line(1, "<invalid_touchwait>Charlotte!<wait=60>")
	var frames: int = 0
	while _stage.dialogue.is_busy() and frames < 1000:
		_stage.tick()
		frames += 1
	assert_almost_eq(float(frames), 10.0 * 1.5 + 60.0, 3.0)
	assert_eq(_stage.dialogue.state, EventDialogue.State.DONE, "no tap needed")


func test_op_67_shows_and_hides_the_cinema_window() -> void:
	_run(_frame(EventInterpreter.OP_PANEL, PackedByteArray([0])) + _end())
	assert_false(_stage.panel_visible())
	_run(_frame(EventInterpreter.OP_PANEL, PackedByteArray([1])) + _end())
	assert_true(_stage.panel_visible())


func test_a_scene_that_opens_on_a_fade_in_starts_black() -> void:
	var fade_in: PackedByteArray = PackedByteArray([0, 0, 0, 0, 3, 3]) + _u32(40)
	var interpreter: EventInterpreter = _start(_frame(EventInterpreter.OP_FADE, fade_in) + _advance() + _end())
	assert_eq(_stage.fade_alpha(), 1.0, "black before the first frame")
	_frames(interpreter, 21)
	assert_almost_eq(_stage.fade_alpha(), 0.5, 0.001, "halfway after 20 frames")
	_frames(interpreter, 100)
	assert_eq(_stage.fade_alpha(), 0.0)
	assert_eq(interpreter.frame, 41)


func test_a_fade_out_ends_on_its_colour() -> void:
	var fade_out: PackedByteArray = PackedByteArray([1, 255, 255, 255, 3, 3]) + _u32(40)
	_run(_frame(EventInterpreter.OP_FADE, fade_out) + _advance() + _end())
	assert_eq(_stage.fade_alpha(), 1.0)


func test_camera_targets_are_screen_centres_and_pans_move_at_the_speed() -> void:
	var interpreter: EventInterpreter = _run(_camera(false, 1392, 812, 0) + _camera(true, 0, -30, 10) + _advance() + _end())
	assert_eq(_stage.camera_position(), Vector2(1392, 782))
	assert_eq(interpreter.frame, 31, "30 px at 1 px a frame")


func test_set_switch_writes_the_shared_switches() -> void:
	var interpreter: EventInterpreter = _run(_frame(EventInterpreter.OP_SET_SWITCH, _u32(19100011) + PackedByteArray([1])) + _end())
	assert_eq(interpreter.switches, {19100011: 1})


func test_advance_waits_for_an_emote_bubble() -> void:
	var bubble: PackedByteArray = _party(1) + _u32(1) + _u32(80) + _u32(0) + _u32(0xffffffff)
	var interpreter: EventInterpreter = _run(_frame(EventInterpreter.OP_BUBBLE, bubble) + _advance() + _end())
	assert_eq(interpreter.frame, 81)


func test_face_and_visibility() -> void:
	_run(_frame(EventInterpreter.OP_FACE, _party(2) + PackedByteArray([1])) + _frame(EventInterpreter.OP_VISIBLE, _party(2) + PackedByteArray([0])) + _end())
	var lasswell: EventActor = _stage.actors["pc2"]
	assert_eq(lasswell.facing, EventActor.UP)
	assert_false(lasswell.visible)


func test_a_warp_ends_the_script_with_its_target() -> void:
	var warp: PackedByteArray = _u32(61) + _u32(8) + _u32(4) + PackedByteArray([0, 1, 1])
	var interpreter: EventInterpreter = _run(_frame(EventInterpreter.OP_WARP, warp) + _frame(EventInterpreter.OP_TEXT, _u32(1)))
	assert_eq(interpreter.end_reason, "warp")
	assert_eq(interpreter.warp, {"layer": 61, "x": 8, "y": 4})
	assert_eq(_stage.lines_shown, [] as Array[int])


func test_a_flash_pulses_byte_four_times_with_byte_three_frame_halves() -> void:
	var interpreter: EventInterpreter = _run(_frame(EventInterpreter.OP_FLASH, PackedByteArray([255, 255, 255, 5, 3])) + _advance() + _end())
	assert_eq(interpreter.frame, 31, "3 pulses of 5 frames on and 5 off")


func test_the_banner_names_the_town_and_does_not_hold_the_script() -> void:
	var file_name: PackedByteArray = "townname_1101.png".to_ascii_buffer()
	var payload: PackedByteArray = _u16(file_name.size()) + file_name + _u32(60)
	var interpreter: EventInterpreter = _start(_frame(EventInterpreter.OP_BANNER, payload) + _advance() + _end())
	_frames(interpreter, 2)
	assert_true(interpreter.done, "advance does not wait for the banner")
	assert_true(_stage.banner.showing())
	assert_eq(_stage.banner.shown_name(), "Town of Mitra")
	for i in 300:
		_stage.tick()
	assert_false(_stage.banner.showing(), "gone after fading in, holding and fading out")


func test_op_59_names_where_the_game_goes_next() -> void:
	var interpreter: EventInterpreter = _run(_frame(EventInterpreter.OP_NEXT_LOCATION, PackedByteArray([1]) + _u32(9001)) + _end())
	assert_eq(interpreter.next_location, {"type": 1, "id": 9001})
	assert_eq(interpreter.end_reason, "end", "the script carries on after it")


func test_the_cursor_blinks_while_it_waits_for_a_tap() -> void:
	_stage.dialogue.show_line(1, "Hi.")
	while _stage.dialogue.state == EventDialogue.State.REVEAL:
		_stage.tick()
	var shown: Array = []
	for i in EventDialogue.CURSOR_DELAY_FRAMES - 1 + EventDialogue.CURSOR_ON_FRAMES + EventDialogue.CURSOR_OFF_FRAMES:
		_stage.tick()
		shown.append(_stage.dialogue.cursor_visible())
	assert_false(shown[0], "not at once")
	assert_true(shown[EventDialogue.CURSOR_DELAY_FRAMES - 1], "after half a second")
	assert_eq(shown.count(true), EventDialogue.CURSOR_ON_FRAMES, "then on 40 frames of every 90")
	assert_false(shown[EventDialogue.CURSOR_DELAY_FRAMES - 1 + EventDialogue.CURSOR_ON_FRAMES])
	assert_eq(_stage.dialogue.state, EventDialogue.State.CURSOR, "still waiting")


func test_unhandled_opcodes_are_skipped_and_counted() -> void:
	var interpreter: EventInterpreter = _run(_frame(0x69, _u32(0x37)) + _frame(0x69, _u32(0x6a)) + _end())
	assert_eq(interpreter.skipped_ops, {0x69: 2})
	assert_eq(interpreter.end_reason, "end")


func test_bins_before_1025_reference_actors_with_u16_ids() -> void:
	_stage.bin.version = 1020
	var ref := PackedByteArray([0, 0, 1])
	var payload: PackedByteArray = ref + PackedByteArray([0, 0]) + _u16(116) + _u16(58) + PackedByteArray([0, 1, 1, 0])
	_run(_frame(EventInterpreter.OP_MOVE, payload) + _end())
	assert_eq(_stage.actors["pc1"].position, Vector2(116, 58))
