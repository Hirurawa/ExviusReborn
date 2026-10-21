extends "res://tests/test_case.gd"

## StoryFlow and the database it reads (CUTSCENE-PLAN.md section 10): which scenes play
## on entering a dungeon, after a clear and in a town, under chapter 1's switches, and
## the cutscene screen playing one to its end. The player's switches are swapped for
## each test and put back; nothing here writes a save.

const SCREEN: PackedScene = preload("res://features/event/CutsceneScreen.tscn")

var _saved_switches: Array = []


func before_each() -> void:
	_saved_switches = SwitchService.opened_switches.duplicate()


func after_each() -> void:
	SwitchService.opened_switches = _saved_switches


func _switches(ids: Array) -> void:
	SwitchService.opened_switches = ids.map(func(id: Variant) -> String: return str(id))


# === The database ===

func test_a_story_event_finds_its_bin_through_its_map_event_row() -> void:
	var scene: Dictionary = GameDatabase.get_story_event_scene("1001006")
	assert_eq(scene["name"], "main1-2_ED")
	assert_eq(scene["bin_id"], "111010102", "map_event's resource 311101102")


func test_a_scene_filed_under_another_mission_finds_the_playing_missions_bin() -> void:
	assert_eq(GameDatabase.get_story_event_scene("1059001"), {}, "main5-5-1 is filed under 1310305, which has no package")
	var scene: Dictionary = GameDatabase.get_story_event_scene("1059001", "1310403")
	assert_eq(scene["bin_id"], "131010501", "mission 1310403 plays it")


func test_map_event_rows_carry_their_trigger() -> void:
	var rows: Array = GameDatabase.get_map_events(StoryFlow.LOCATION_DUNGEON, 11102, StoryFlow.ON_ENTERING)
	assert_eq(rows.size(), 1)
	assert_eq([int(rows[0]["storyEventId"]), int(rows[0]["switchInfo"]), int(rows[0]["openSwitch"])], [1002001, 10002200, 10003001], "Latius Woods' main1-2_OP")
	assert_eq(GameDatabase.get_map_events(StoryFlow.LOCATION_DUNGEON, 11102, StoryFlow.AFTER_CLEAR), [])


func test_a_towns_event_packages_and_their_gates() -> void:
	var packages: Array = GameDatabase.get_town_event_packages(1101)
	assert_eq(packages[0], {"switch_info": 0, "open_switch": 10004003, "bin_id": "111020101"}, "Mitra's story until 10004003")
	assert_eq(packages.size(), 9)


func test_switch_kinds() -> void:
	assert_eq(GameDatabase.get_switch_kind(19100010), {"type": 102, "scope": 2}, "a scene's page selector")
	assert_eq(GameDatabase.get_switch_kind(10002200), {"type": 101, "scope": 1}, "a saved story switch")
	assert_eq(GameDatabase.get_switch_kind(1), {"type": -1, "scope": -1})


# === Which scenes play ===

func test_a_row_plays_while_its_switch_is_on_and_its_open_switch_off() -> void:
	var on: Callable = func(id: String) -> bool: return id == "10"
	assert_true(StoryFlow.is_active("10", "20", on))
	assert_false(StoryFlow.is_active("11", "20", on), "not unlocked yet")
	assert_false(StoryFlow.is_active("0", "10", on), "already seen")
	assert_true(StoryFlow.is_active(0, null, on), "no gates at all")


func test_latius_woods_plays_its_opening_once_the_earth_shrine_is_cleared() -> void:
	_switches([])
	assert_eq(StoryFlow.dungeon_entry_scenes("11102"), [])
	_switches([10002200])
	var scenes: Array = StoryFlow.dungeon_entry_scenes("11102")
	assert_eq(scenes.size(), 1)
	assert_eq([scenes[0]["story_event_id"], scenes[0]["bin_id"], scenes[0]["done_switch"]], ["1002001", "111010203", 10003001])
	assert_true(StoryFlow.can_play(scenes[0]), "main1-2_OP starts in its bin")
	_switches([10002200, 10003001])
	assert_eq(StoryFlow.dungeon_entry_scenes("11102"), [], "seen")


func test_the_earth_shrine_exit_plays_its_ending_after_the_clear() -> void:
	_switches([10002100])
	assert_eq(StoryFlow.after_clear_scenes("1110103"), [], "not cleared yet")
	_switches([10002100, 10002200])
	var scenes: Array = StoryFlow.after_clear_scenes("1110103")
	assert_eq(scenes.map(func(scene: Dictionary) -> String: return scene["name"]), ["main1-2_ED"])
	assert_eq(scenes[0]["done_switch"], 10002002)
	assert_true(StoryFlow.can_play(scenes[0]))
	assert_eq(StoryFlow.after_clear_scenes(""), [], "the test battle")


func test_mitras_arrival_plays_its_package_one_page_at_a_time() -> void:
	_switches([10003300])
	var played: Dictionary = {}
	var arrival: Dictionary = StoryFlow.next_town_scene("1101", played)
	assert_eq([arrival["bin_id"], arrival["layer"]], ["111020101", 56], "the arrival on the start layer")
	assert_true(StoryFlow.can_play(arrival))
	assert_eq(StoryFlow.next_town_scene("1101", played), {}, "the same page does not play twice in a visit")
	# Back from the Farplane: the forge, the portal and the Farplane's switch are on.
	_switches([10003300, 10004001, 10004002, 10005001])
	var back: Dictionary = StoryFlow.next_town_scene("1101", played)
	assert_eq(back["bin_id"], "111020101", "the page that closes Mitra's chapter")
	_switches([10003300, 10004001, 10004002, 10005001, 10004003])
	assert_eq(StoryFlow.next_town_scene("1101", {}), {}, "the package is closed")


func test_a_scene_keeps_its_story_switches_but_not_its_page_selectors() -> void:
	var before: Dictionary = {19100010: 1, 10003300: 1}
	var after: Dictionary = {19100010: 0, 10003300: 1, 10004001: 1, 10077600: 0}
	assert_eq(StoryFlow.switch_writes(before, after, GameDatabase.get_switch_kind), {10004001: 1})
	assert_eq(StoryFlow.switch_writes({10004001: 1}, {10004001: 0}, GameDatabase.get_switch_kind), {10004001: 0}, "turned off")


func test_a_story_event_scene_puts_its_own_switches_over_the_players() -> void:
	_switches([10002200, 19100010])
	var scene: Dictionary = StoryFlow.story_event_scene("1001002")
	assert_eq(scene["switches"][10002200], 1)
	assert_eq(scene["switches"][19100010], 0, "main1-1_OP1 sets 19100010:0")
	assert_eq(scene["switches"][19100011], 1)
	assert_eq(scene["layer"], 65)
	assert_eq(StoryFlow.story_event_scene("1")["bin_id"], "", "unknown: nothing to play, still counts as watched")


# === The screen ===

func test_the_cutscene_screen_plays_a_scene_to_its_next_location() -> void:
	var screen: CutsceneScreen = SCREEN.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_switches([])
	var scene: Dictionary = StoryFlow.story_event_scene("1001001")
	var results: Array = []
	var run: Callable = func() -> void: results.append(await screen.play(scene))
	run.call()
	for _i in range(20000):
		if not results.is_empty():
			break
		screen.player.stage.tap()
		screen.player.step_frame()
	assert_eq(results.size(), 1, "the prologue's crystal scene ends")
	assert_eq(results[0]["reason"], "end")
	assert_eq(results[0]["next_location"], {"type": 0, "id": 1110101}, "into the Earth Shrine")
	assert_eq(screen.player.stage.lines_shown.size(), 12)
	screen.get_parent().remove_child(screen)
	screen.free()


func test_the_cutscene_screen_ignores_the_back_button() -> void:
	var screen: CutsceneScreen = SCREEN.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_true(screen.get_meta("block_back_request", false), "no skip, and StoryFlow would lose its scene")
	screen.get_parent().remove_child(screen)
	screen.free()


func test_a_screen_closed_mid_scene_reports_it_instead_of_waiting_forever() -> void:
	var screen: CutsceneScreen = SCREEN.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_switches([])
	var results: Array = []
	var run: Callable = func() -> void: results.append(await screen.play(StoryFlow.story_event_scene("1001001")))
	run.call()
	for _i in range(120):
		screen.player.step_frame()
	assert_eq(results, [], "still playing")
	screen.get_parent().remove_child(screen)
	assert_eq(results.size(), 1)
	assert_eq(results[0]["reason"], "closed")
	screen.free()


# === Skipping ===

func test_fast_forward_runs_a_scene_to_its_end_with_everything_it_sets() -> void:
	var screen: CutsceneScreen = SCREEN.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_switches([])
	var scene: Dictionary = StoryFlow.story_event_scene("1001001")
	assert_true(screen.player.play(scene["bin_id"], scene["layer"], scene["switches"]))
	assert_false(screen.player.fast_forward(100000), "ended")
	assert_eq(screen.player.next_location, {"type": 0, "id": 1110101}, "still leads into the Earth Shrine")
	assert_eq(screen.player.stage.lines_shown.size(), 12, "every line went by")
	screen.get_parent().remove_child(screen)
	screen.free()


func test_fast_forward_stops_with_its_scene_when_the_next_starts_at_once() -> void:
	var screen: CutsceneScreen = SCREEN.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_switches([])
	var scene: Dictionary = StoryFlow.story_event_scene("1001001")
	var player: EventPlayer = screen.player
	player.play(scene["bin_id"], scene["layer"], scene["switches"])
	# As StoryFlow does in a town: the next scene starts from the finished signal.
	player.finished.connect(func(_reason: String) -> void: player.play(scene["bin_id"], scene["layer"], scene["switches"]), CONNECT_ONE_SHOT)
	assert_false(player.fast_forward(100000))
	assert_true(player.running, "the next scene plays")
	assert_true(player.stage.lines_shown.is_empty(), "from its start")
	screen.get_parent().remove_child(screen)
	screen.free()


func test_the_skip_button_ends_the_scene_out_of_sight() -> void:
	var screen: CutsceneScreen = SCREEN.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_switches([])
	var results: Array = []
	var run: Callable = func() -> void: results.append(await screen.play(StoryFlow.story_event_scene("1001001")))
	run.call()
	var button: TextureButton = screen.get_node("SkipButton")
	assert_true(button.visible)
	for _i in range(60):
		screen.player.step_frame()
	button.pressed.emit()
	assert_false(screen.get_node("Container").visible, "the stage goes dark")
	assert_false(button.visible)
	for _i in range(20):
		if not results.is_empty():
			break
		screen._process(0.0)
	assert_eq(results.size(), 1, "a few frames later")
	assert_eq(results[0]["reason"], "end")
	assert_eq(results[0]["next_location"], {"type": 0, "id": 1110101})
	screen.get_parent().remove_child(screen)
	screen.free()
